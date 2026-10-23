# recomp.switch: a Switch executable recompiled into a native Zap program. Its AArch64 code is
# translated ahead of time into Zap functions (translate/), which run on the guest CPU and the
# HLE kernel written in Zap (cpu/, horizon/); code the translation did not see runs on the
# interpreter. Run from the repository root:
#
#   zap run projects/recomp/switch/main.zap <homebrew.nro | exefs dir> [--name n] [--out <dir>] [--build]
#
# writes <dir>/<name>.zap and its module game/ (projects/recomp/switch/out/<name> by default);
# `zap run <dir>/<name>.zap` runs it. --build builds it too. Nothing of the executable is in what
# is written but its code's translation, and the executable stays where it is (.gitignore: out/).

import fs
import recomp.switch.horizon
import recomp.switch.translate

path = args.positional().first ??
	fail("usage: zap run projects/recomp/switch/main.zap <homebrew.nro | exefs dir> [--out <dir>] [--build]")
name = args.option("--name") ?? fs.stem(path)
out = args.option("--out") ?? "projects/recomp/switch/out/{name}"
k = horizon.launch(path) ?? fail
functions = []
for m in k.modules:
	functions.extend(translate.findFunctions(m.at, m.at + m.textSize))
if args.option("--profile") is profile:
	ran = (fs.readFile(profile) ?? fail("cannot read {profile}"))
		.lines()
		.map(i64.parse("0x{it}") ?? -1)
	functions = translate.ranIn(functions, ran)
program = translate.writeProgram(out, name, fs.normalize(path), functions)
print("{functions.len} functions into {program}")
if "--build" in args:
	built = Process.output("{zapPath()} build {program}")
	if built.code != 0: fail(built.out)
	print(built.out.trimmed())
