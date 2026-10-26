# Vectors of A64 instructions as the arm64 machine runs them (oracle/: gdb on the host named by
# --host, arm64 in ZAP_SETUP by default, reached by ssh), written for the interpreter's test to run
# the same:
#
#   zap run projects/recomp/switch/tools/armOracle.zap [--count n] [--seed n] [--host h]
#     [--only prefix] [--out file]
#
# n random cases of each encoding class of oracle/generate.zap (100 by default; --only keeps the
# classes whose name starts with the prefix) into projects/recomp/switch/cpu/tests/vectors.txt by
# default.

import fs
import recomp.switch.oracle

host = args.option("--host") ?? benchHost()
if host == "": fail("no arm64 host: arm64 in ZAP_SETUP, or --host")
count = i64.parse(args.option("--count") ?? "100") ?? 100
seed = i64.parse(args.option("--seed") ?? "1") ?? 1
only = args.option("--only") ?? ""
out = args.option("--out") ?? "projects/recomp/switch/cpu/tests/vectors.txt"
run = "/tmp/zap-oracle-{clockMs()}"

# gdb's output for the script, run on the host over /bin/true
fn runGdb(script str):
	got = Process.output(
		"ssh {host} \"cat > {run}.gdb && gdb -q -batch -x {run}.gdb /bin/true; rm -f {run}.gdb {run}.bin\"",
		input = "{script}\n"
	)
	if got.code != 0 and not ("A " in got.out): fail("gdb on {host} failed: {got.out}")
	got.out

code, mem, _ = oracle.parseOutput(runGdb(oracle.scriptHead(run)))
if mem == 0: fail("gdb on {host} printed no addresses")
base = mem + oracle.scratchMiddle
rng = Random(seed)
drawn = []
script = [oracle.scriptHead(run)]
for c in oracle.classes.filter(.name.startsWith(only)):
	loop count:
		word, regs = rng.draw(c, base)
		script.push(oracle.scriptCase(run, drawn.len, word, regs, c))
		drawn.push((word, regs, c.copy()))
code2, mem2, outcomes = oracle.parseOutput(runGdb(script.join("\n")))
if code2 != code or mem2 != mem:
	fail("the addresses moved between runs: {code:x} {mem:x}, {code2:x} {mem2:x}")
pattern = oracle.pattern()
lines = ["# A64 on an arm64 machine, seed {seed}, {count} a class: tools/armOracle.zap"]
dropped = 0
for k, (word, regs, _) in drawn:
	outcome = outcomes.get(k) ?? continue
	if outcome.faulted or (not outcome.refused and outcome.state.len != oracle.stateSize):
		dropped += 1
		continue
	after u64[] = [] if outcome.refused else outcome.state.copy()
	stores = []
	for w, v in outcome.scratch:
		if v != pattern.u64le(w * 8): stores.push(oracle.Stored(at = w * 8, value = v))
	lines.push(
		oracle.format(
			oracle.Case(
				word,
				pc = code,
				mem,
				before = regs.copy(),
				after,
				stores
			)
		)
	)
fs.writeFile(out, "{lines.join("\n")}\n") ?? fail("cannot write {out}: {error}")
print("{lines.len - 1} cases into {out}, {dropped} dropped (a memory fault)")
