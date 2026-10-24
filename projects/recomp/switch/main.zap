# recomp.switch: a Switch executable recompiled into a native Zap program. Its AArch64 code is
# translated ahead of time into Zap functions (translate/), which run on the guest CPU and the
# HLE kernel written in Zap (cpu/, horizon/); code the translation did not see runs on the
# interpreter. Run from the repository root:
#
#   zap run projects/recomp/switch/main.zap <homebrew.nro | exefs dir> [--name n] [--out <dir>]
#       [--profile f] [--part n] [--build] [--jobs n] [--target t] [--android <dir>]
#
# writes <dir>/<name>.zap and its module game/ (projects/recomp/switch/out/<name> by default);
# `zap run <dir>/<name>.zap` runs it. A translation of more than --part instructions (60,000 by
# default, a build of about 2 GB) is written as parts the program loads, each built on its own
# (translate/write.zap). --build builds them, --jobs at once (half the processors by default: a
# part's build uses about four of them and 0.7 GB, and more at once only contend), then the program,
# for --target's system (Windows by default; linux-arm64, linux). --android dir: the program as an
# Android app, <dir>/<name>.apk (a phone's arm64, or with --target android-x64 the emulator's
# x86-64), a homebrew NRO carried inside it (the app finds it beside itself), and its parts beside
# it in dir; a game's ExeFS and RomFS, and the parts, go to the app's files by adb (too big for an
# APK).
# --profile translates only the functions a run entered (tools/run.zap --profile). Nothing of the
# executable is in what is written but its code's translation, and the executable stays where it
# is (.gitignore: out/).

import fs
import recomp.switch.horizon
import recomp.switch.translate

path = args.positional().first ??
	fail("usage: zap run projects/recomp/switch/main.zap <homebrew.nro | exefs dir> [--out <dir>] [--build]")
name = args.option("--name") ?? fs.stem(path)
out = args.option("--out") ?? "projects/recomp/switch/out/{name}"
k = horizon.loadCode(path) ?? fail
functions = []
for m in k.modules:
	functions.extend(translate.findFunctions(m.at, m.at + m.textSize))
if args.option("--profile") is profile:
	ran = (fs.readFile(profile) ?? fail("cannot read {profile}"))
		.lines()
		.map(i64.parse("0x{it}") ?? -1)
	functions = translate.ranIn(functions, ran)
# the first n functions only (a measure of the build's scale)
if args.option("--first") is first:
	functions.truncate(i64.parse(first) ?? fail("--first takes a count"))
each = i64.parse(args.option("--part") ?? "60000") ?? fail("--part takes a count of instructions")
files = translate.writeProgram(out, name, fs.normalize(path), functions, each)
print("{functions.len} functions into {files.last ?? ""}, {files.len} builds")
parts = files[..files.len - 1]
if "--build" in args:
	target = args.option("--target") ?? ""
	option = "" if target == "" else " --target {target}"
	buildParts(parts, option)
	if Process.run("{zapPath()} build{option} {files.last ?? ""}") != 0: fail("the program did not build")
if args.option("--android") is dir:
	buildParts(parts, " --target {appTarget()}")
	if Process.run(appBuild(files.last ?? "", path, name)) != 0: fail("the app did not build")
	fs.createDir(dir) ?? fail("cannot make {dir}: {error}")
	apk = fs.readBytes("build/{fs.stem(files.last ?? "")}.apk") ?? fail("no app built: {error}")
	fs.writeBytes(fs.join(dir, "{name}.apk"), apk) ?? fail("cannot write into {dir}: {error}")
	for part in parts:
		for file in ["{fs.stem(part)}", "{fs.stem(part)}.load"]:
			bytes = fs.readBytes("build/{file}") ?? fail("no part built: {error}")
			fs.writeBytes(fs.join(dir, file), bytes) ?? fail("cannot write into {dir}: {error}")
	print("released into {dir}: {name}.apk and {parts.len} parts")

# the parts built with the option (a target), --jobs at once
fn buildParts(parts str[], option str):
	jobs = i64.parse(args.option("--jobs") ?? "{(cpuCount() / 2).max(1)}") ??
		fail("--jobs takes a count")
	for at in (0..(parts.len + jobs - 1) / jobs).map(it * jobs):
		started = parts[at..(at + jobs).min(len)]
			.map(Process.start("{zapPath()} build --loadable{option} {it}"))
		for mut p in started:
			if p.wait() != 0: fail("a part did not build")

# the app's target: a phone's by default
fn appTarget():
	args.option("--target") ?? "android"

# zap build of the program as an app: a homebrew NRO carried among its assets
fn appBuild(program str, executable str, name str):
	options = " --target {appTarget()} --label {quoteArg(name)}"
	if not fs.isDir(executable):
		assets = "build/{name}-assets"
		_ = fs.deleteTree(assets)
		fs.createDir(assets) ?? fail("cannot make {assets}: {error}")
		bytes = fs.readBytes(executable) ?? fail("cannot read {executable}: {error}")
		fs.writeBytes(fs.join(assets, fs.fileName(executable)), bytes) ??
			fail("cannot write into {assets}: {error}")
		options = "{options} --assets {assets}"
	"{zapPath()} build{options} {program}"
