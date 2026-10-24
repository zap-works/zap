# Maxwell programs translated into Zap GPU code (recomp.switch.shaders): deko3d's DKSH files, or
# the programs a run recorded (each named by its code's hash), given as files or dirs of them.
# Run from the repository root:
#
#   zap run projects/recomp/switch/tools/shaders.zap <files | dirs> [--out <dir>]
#
# writes the module <dir>/translated/ (projects/recomp/switch/out/shaders by default) and
# <dir>/programs.zap, which names every entry (`zap build` it: it builds when each translation
# compiles), and prints what each program could not have translated.

import fs
import recomp.switch.maxwell
import recomp.switch.shaders

out = args.option("--out") ?? "projects/recomp/switch/out/shaders"
paths = []
pairsDir = ""
for path in args.positional():
	if path == out: continue
	if fs.isDir(path):
		if fs.exists(fs.join(path, maxwell.pairsFile)): pairsDir = path
		for name in fs.list(path) ?? []:
			if name != maxwell.pairsFile: paths.push(fs.join(path, name))
	else:
		paths.push(path.copy())
if paths.isEmpty:
	fail("usage: zap run projects/recomp/switch/tools/shaders.zap <files | dirs> [--out <dir>]")
sources = []
for path in paths:
	sources.push(shaders.readSource(path) ?? fail)
done = shaders.writeModule(sources, out) ?? fail
sets = shaders.translatedSets(
	(fs.readFile(fs.join(pairsDir, maxwell.pairsFile)) ?? "").lines(),
	done.shaders
)
done.writePrograms(sets, out) ?? fail
for s in done.shaders:
	print("{s.entry}: {"translated" if s.missing.isEmpty else s.missing.join("; ")}")
for why in done.skipped:
	print("left out {why}")
print("{done.shaders.len} programs into {out}/{shaders.module}, named by {out}/programs.zap")
