# Each case of vectors.txt (the arm64 machine's, tools/armOracle.zap) run by decode and execute
# from the same registers and scratch: the registers, flags, pc and stored words must be the
# machine's; a word the machine refused (SIGILL) must decode as unknown.

import fs
import recomp.switch.arm64
import recomp.switch.cpu
import recomp.switch.cpu.core
import recomp.switch.oracle

# a thread's registers as the oracle's state (oracle/case.zap's places)
fn stateOf(c core.Cpu):
	out u64[] = (0..31).map(c.x[it])
	out.push(c.x[arm64.sp])
	out.push(c.nzcv())
	out.push(u64(c.pc))
	out.extend(c.q)
	out.push(c.fpcr)
	out.push(c.fpsr)
	out

# the name of a state's place
fn placeName(at i64):
	if at < 31: return "x{at}"
	if at == oracle.atSp: return "sp"
	if at == oracle.atNzcv: return "nzcv"
	if at == oracle.atPc: return "pc"
	if at == oracle.atFpcr: return "fpcr"
	if at == oracle.atFpsr: return "fpsr"
	q = at - oracle.atQ
	"v{q / 2}.{"hi" if q % 2 == 1 else "lo"}"

# the cases to run instead of vectors.txt (a file tools/armOracle.zap wrote)
fn vectorsWord():
	RunWord(
		"vectors",
		"vectors=<file>: the arm64 cases recomp.switch's cpu test runs instead of its vectors.txt"
	)

# what differs between the case's outcome and ours, "" when nothing
fn difference(k oracle.Case):
	core.memory = core.committedMemory(k.mem, oracle.scratchSize)
	core.memory.write(k.mem, oracle.pattern())
	c = core.Cpu()
	for r in 0..31:
		c.x[r] = k.before[r]
	c.x[arm64.sp] = k.before[oracle.atSp]
	c.setNzcv(k.before[oracle.atNzcv])
	for v in 0..64:
		c.q[v] = k.before[oracle.atQ + v]
	c.fpcr = k.before[oracle.atFpcr]
	c.fpsr = k.before[oracle.atFpsr]
	i = arm64.decode(k.word, k.pc)
	if k.after.isEmpty:
		return "" if i.op == .Unknown else "the machine refused it; decoded as {i.op}"
	if i.op == .Unknown: return "decoded as unknown"
	c.execute(i, k.pc)
	diffs = []
	ours = c.stateOf()
	for at in 0..oracle.stateSize:
		if ours[at] != k.after[at]: diffs.push("{placeName(at)} {ours[at]:x} != {k.after[at]:x}")
	pattern = oracle.pattern()
	for at in (0..oracle.scratchSize / 8).map(it * 8):
		mine = core.memory.load(k.mem + at, 3)
		theirs = pattern.u64le(at)
		for s in k.stores:
			if s.at == at: theirs = s.value
		if mine != theirs: diffs.push("[{at:x}] {mine:x} != {theirs:x}")
	if diffs.isEmpty: return ""
	"{i.op}: {diffs[..diffs.len.min(4)].join(", ")}"

test "the interpreter runs each instruction as the arm64 machine did":
	text = fs.readFile(
		vectorsWord().value() ?? "projects/recomp/switch/cpu/tests/vectors.txt"
	) ??
		""
	failed = 0
	total = 0
	for line in text.lines():
		k = oracle.parse(line) ?? continue
		total += 1
		d = k.difference()
		if d == "": continue
		failed += 1
		if failed <= 40: print("{k.word:08x}: {d}")
	print("{total - failed} of {total} cases as the machine")
	expect failed == 0
