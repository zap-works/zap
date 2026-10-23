# recomp.switch: a Switch executable recompiled into a native Zap program. Its AArch64 code is
# translated ahead of time into Zap functions (translate/), which run on the guest CPU and the
# HLE kernel written in Zap (cpu/, horizon/); code the translation did not see runs on the
# interpreter. Run from the repository root:
#
#   zap run projects/recomp/switch/main.zap <homebrew.nro | exefs dir> [--name n] [--out <dir>]
#       [--profile f] [--part n] [--build] [--jobs n]
#
# writes <dir>/<name>.zap and its module game/ (projects/recomp/switch/out/<name> by default);
# `zap run <dir>/<name>.zap` runs it. A translation of more than --part instructions (60,000 by
# default, a build of about 2 GB) is written as parts the program loads, each built on its own
# (translate/write.zap). --build builds them, --jobs at once (2 by default), then the program.
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
if "--build" in args:
	jobs = i64.parse(args.option("--jobs") ?? "2") ?? fail("--jobs takes a count")
	parts = files[..files.len - 1]
	for at in (0..(parts.len + jobs - 1) / jobs).map(it * jobs):
		started = parts[at..(at + jobs).min(parts.len)]
			.map(Process.start("{zapPath()} build --loadable {it}"))
		for mut p in started:
			if p.wait() != 0: fail("a part did not build")
	if Process.run("{zapPath()} build {files.last ?? ""}") != 0: fail("the program did not build")
