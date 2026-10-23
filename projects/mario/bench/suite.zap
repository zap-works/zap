# Super Mario 64: the Zap rewrite against the PC port (sm64ex built with the harness in
# projects/mario/bench/pc, see projects/mario/README.md), the same frames measured the same way: a fixed
# camera over Castle Grounds, Mario standing, frames as fast as they go after a 60-frame warm-up.
# Each case is the processor cycles a frame of the rewrite (without and with 4x multisampling)
# over the port's, the median of the runs. Nothing is measured, and the check passes with a line
# saying so, without the cartridge dump (projects/mario/rom/sm64.us.z64) or the port built.
#
#   zap test --only bench
#   zap run projects/mario/bench/suite.zap --pc <the port's build dir>   (default: pc/sm64ex/build/us_pc)
import compare
import fs
import sm64ex

# a case: the rewrite's multisampling
type Case:
	name str
	samples str

cases = [Case(name = "mario-1x", samples = "1"), Case(name = "mario-4x", samples = "4")]
eye = "0,2500,9000"
focus = "0,500,0"
out = "build/mario-bench"

# the processor cycles a frame a run printed (its "bench: cycles N a frame" line), 0 when none
fn cyclesOf(file str):
	for line in (fs.readFile(file) ?? "").lines():
		words = line.words()
		if line.startsWith("bench: cycles ") and words.len >= 3: return i64.parse(words[2]) ?? 0
	0

fn median(values i64[]):
	values.sorted()[values.len / 2]

request = compare.timedSuiteRequest(args)
frames = 2000 if request.full else 300
chosen = cases.filter(request.name in .name)
if not fs.exists("projects/mario/rom/sm64.us.z64"):
	print("bench: skipped, mario needs the user's cartridge dump at projects/mario/rom/sm64.us.z64")
elif not fs.exists(sm64ex.exe()):
	print("bench: skipped, the PC port is not built at {sm64ex.exe()} (projects/mario/README.md)")
elif not chosen.isEmpty:
	_ = fs.createDir(out)
	if Process.output("zap build projects/mario/main.zap").code != 0:
		exit(1)
	zapMario = "{out}/zap-mario{exeSuffix()}"
	_ = fs.writeFile(
		zapMario,
		fs.readFile(builtExe("main")) ?? fail("suite.zap: no {builtExe("main")}")
	)
	env["BENCH_FRAMES"] = "{frames}"
	env["BENCH_UNCAPPED"] = "1"
	env["BENCH_EYE"] = eye
	env["BENCH_FOCUS"] = focus
	ours {str: i64[]} = {}
	for c in chosen:
		ours[c.name.copy()] = []
	theirs = []
	loop request.runs:
		for c in chosen:
			file = "{out}/zap-{c.name}.txt"
			ran = Process.output(
				"{zapMario} --bench {frames} --samples {c.samples} --eye {eye} --focus {focus}"
			)
			_ = fs.writeFile(file, ran.out)
			ours[c.name].push(cyclesOf(file))
		file = fs.join(currentDir(), "{out}/port.txt")
		env["BENCH_OUT"] = file
		Process.output("{sm64ex.exe()} --skip-intro", dir = sm64ex.dir())
		theirs.push(cyclesOf(file))
	rival = median(theirs)
	if rival == 0:
		print(
			"bench: the port prints no cycles; rebuild it with the harness (projects/mario/README.md)"
		)
		exit(1)
	for c in chosen:
		zapCycles = median(ours[c.name])
		if zapCycles == 0:
			print("bench: {c.name} printed no cycles")
			exit(1)
		compare.benchLine(
			c.name,
			"time",
			zapCycles,
			rival,
			"sm64ex",
			"projects/mario/main.zap",
			"--bench {frames} --samples {c.samples} --eye {eye} --focus {focus}",
			""
		)
