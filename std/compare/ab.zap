# The A/B race (`--ab zap`): each problem's Zap program built by that zap (one from before a
# change, say build/base/zap.exe) and by this one (the PATH's: zap test's own), the two
# executables run one after the other, rounds times, then the median of each and their ratio, new
# over base: where the processor counts them (std/perf) of the instructions, the cycles, the cache
# and the branch misses, which a program running beside it moves little, so any number of A/Bs
# run side by side; else of the processor cycles (Windows' count) or the wall time. Where the
# processor also samples, each problem's hot functions follow: the instructions spent in each in
# either build, and where their code differs.
# `--ab-for target` builds the two executables for the target and races nothing; `--ab-built`
# races those, built elsewhere (zap test builds on its host, races where the target runs).
# No rival is built or run: the way a change is measured while it is studied; the full run stays
# the record.

import fs
import perf

abDir = "{benchDir}/ab"

# the instructions between two samples of a hot function's: a few thousand samples a second, under
# the kernel's limit (perf_event_max_sample_rate, which it lowers on a busy machine) past which it
# drops them
samplePeriod = 1_000_003

# the hot functions listed a problem
hotCount = 6

pub fn abSuite(problems Problem[], inputFor fn(str) str, request SuiteRequest):
	rounds = request.runs.max(4)
	_ = fs.createDir(abDir)
	if request.abFor == "":
		print("problem         instructions        cycles  cache misses branch misses   (M; base, new / base; {rounds} rounds alternated)")
	for p in problems:
		if request.name not in p.name: continue
		suffix = "" if request.abFor != "" or request.abBuilt else exeSuffix()
		base = "{abDir}/{fs.stem(p.zap)}.base{suffix}"
		new = "{abDir}/{fs.stem(p.zap)}.new{suffix}"
		if not request.abBuilt:
			if not abBuild(request.ab, p.zap, base, request.abFor): continue
			if not abBuild(zapExePath(), p.zap, new, request.abFor): continue
		if request.abFor != "": continue
		arg = p.arg if request.full else p.quickArg
		input = inputFor("full" if request.full else "quick") if p.stdin else ""
		out = "{benchDir}/{p.name}.ab.out"
		baseRuns = []
		newRuns = []
		failed = false
		loop rounds:
			b = runMeasured("{base} {arg}", input, out, memoryLimitMb())
			n = runMeasured("{new} {arg}", input, out, memoryLimitMb())
			failed = failed or b.code != 0 or n.code != 0
			baseRuns.push(b)
			newRuns.push(n)
		if failed:
			print("{p.name:<14} a run failed")
			continue
		print("{p.name:<14}{medianRun(baseRuns).abCells(medianRun(newRuns))}")
		hotFunctions(base, new, arg, input, out)

# The cells of a problem's medians: each count's base (millions) and new / base; without the
# counts, the processor cycles' (or the wall time's, in ms)
fn abCells(b Run, n Run):
	if b.instructions == 0:
		bt = b.cycles / 1e6 if b.cycles > 0 else b.seconds * 1000.0
		nt = n.cycles / 1e6 if n.cycles > 0 else n.seconds * 1000.0
		return "{bt:>10.0}{nt / bt:>8.3}"
	pairs = [
		(b.instructions, n.instructions),
		(b.cycles, n.cycles),
		(b.cacheMisses, n.cacheMisses),
		(b.branchMisses, n.branchMisses)
	]
	cells = ""
	for (bv, nv) in pairs:
		cells += "{bv / 1e6:>8.1}{f64(nv) / f64(bv.max(1)):>6.3}"
	cells

# The program at src built by the zap at zap (for the target: "" the host's) with its map, kept
# at kept (and kept.map); whether it built
fn abBuild(zap str, src str, kept str, target str):
	option = "" if target == "" else " --target {target}"
	if Process.output("{quoteArg(zap)} build{option} {src}", vars = [runAssignment("map")]).code !=
		0:
		eprint("{zap} cannot build {src}")
		return false
	built = "{buildsDir()}{fs.stem(src)}{"" if target != "" else exeSuffix()}"
	bytes = fs.readBytes(built) ?? return false
	_ = fs.writeBytes(kept, bytes) ?? return false
	_ = fs.writeFile("{kept}.map", fs.readFile("{built}.map") ?? "") ?? return false
	fs.canRun(kept)

# A build's functions (by its map) and the samples of its run in each, and its bytes
type Sampled:
	fns perf.MapFunction[]
	counts i64[]
	image u8[]

# the build at exe run once sampled every samplePeriod instructions; none without its map, or
# when it failed
fn sampled(exe str, arg str, input str, out str) Sampled?:
	fns = try perf.readMap(exe)
	stdin = "/dev/null" if input == "" else input.copy()
	run = perf.runCounted("{exe} {arg}", stdin, out, memoryLimitMb(), 0.0, samplePeriod)
	if run.code != 0: return none
	Sampled(
		counts = perf.samplesByFunction(fns, run.addresses),
		fns,
		image = fs.readBytes(exe) ?? []
	)

# The functions most instructions were sampled in, in either build: each one's millions of
# instructions in base and in new, and where their code differs (where the processor samples)
fn hotFunctions(base str, new str, arg str, input str, out str):
	if not perf.canCount(): return
	b = sampled(base, arg, input, out) ?? return
	n = sampled(new, arg, input, out) ?? return
	names str[] = []
	names.addSampled(b)
	names.addSampled(n)
	hottest = names.sortedBy(-(b.samplesOf(it).max(n.samplesOf(it))))
	for name in hottest[..hotCount.min(len)]:
		bm = b.samplesOf(name) * samplePeriod / 1e6
		nm = n.samplesOf(name) * samplePeriod / 1e6
		shown = name[..len.min(40)]
		print("    {shown:<40}{bm:>9.1}{nm:>9.1}  {b.codeDifference(n, name)}")

# the names of the build's functions with samples added to names, once each
fn addSampled(mut names str[], s Sampled):
	for i, count in s.counts:
		if count > 0 and s.fns[i].name not in names:
			names.push(s.fns[i].name.copy())

# the samples in the function of that name (0 when the build has none)
fn samplesOf(s Sampled, name str):
	i = s.fns.findIndex(.name == name) ?? return 0
	s.counts[i]

# the code of the function of that name: its bytes up to the next function's start
fn codeOf(s Sampled, name str):
	i = s.fns.findIndex(.name == name) ?? return []
	if i + 1 >= s.fns.len: return []
	at = fileOffset(s.image, s.fns[i].start)
	end = at + s.fns[i + 1].start - s.fns[i].start
	if at < 0 or end > s.image.len: return []
	s.image[at..end].copy()

# where the byte at an RVA lies in an executable's file: a PE's by its sections, an ELF's at the
# RVA itself (its first segment maps the file from where it is loaded); -1 when nowhere
fn fileOffset(image u8[], rva i64):
	for s in sections(image):
		if rva >= s.va and rva < s.va + s.size: return s.raw + rva - s.va
	isElf = image.len > 4 and image[0] == 0x7F and image[1] == 'E' and image[2] == 'L'
	rva if isElf else -1

# where the two builds' code of the function differs: "same code", or the first differing byte's
# offset and their sizes
fn codeDifference(b Sampled, n Sampled, name str):
	if b.samplesOf(name) == 0 and n.samplesOf(name) == 0: return ""
	bc = b.codeOf(name)
	nc = n.codeOf(name)
	if bc.isEmpty or nc.isEmpty: return "in one build only" if bc.isEmpty != nc.isEmpty else ""
	if bc == nc: return "same code"
	at = 0
	while at < bc.len and at < nc.len and bc[at] == nc[at]:
		at += 1
	"differs from +{at:x} ({bc.len} -> {nc.len} bytes)"
