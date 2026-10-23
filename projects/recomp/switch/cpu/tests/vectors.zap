# Each case of vectors.txt (the arm64 machine's, tools/armoracle.zap) run by decode and execute
# from the same registers and scratch: the registers, flags, pc and stored words must be the
# machine's; a word the machine refused (SIGILL) must decode as unknown.

import fs
import recomp.switch.arm64
import recomp.switch.cpu
import recomp.switch.oracle

# what differs between the case's outcome and ours, "" when nothing
fn difference(k oracle.Case):
	cpu.memory = cpu.Memory(bytes = oracle.pattern(), base = k.mem)
	c = cpu.Cpu()
	for r in 0..31:
		c.x[r] = k.before[r]
	c.x[arm64.sp] = k.before[31]
	c.setNzcv(k.before[32])
	i = arm64.decode(k.word, k.pc)
	if k.after.isEmpty:
		return "" if i.op == .Unknown else "the machine refused it; decoded as {i.op}"
	if i.op == .Unknown: return "decoded as unknown"
	c.execute(i, k.pc)
	diffs = []
	for r in 0..32:
		ours = c.x[arm64.sp if r == 31 else r]
		if ours != k.after[r]:
			diffs.push("{"sp" if r == 31 else "x{r}"} {ours:x} != {k.after[r]:x}")
	if c.nzcv() != k.after[32]: diffs.push("nzcv {c.nzcv():x} != {k.after[32]:x}")
	if u64(c.pc) != k.after[33]: diffs.push("pc {c.pc:x} != {k.after[33]:x}")
	pattern = oracle.pattern()
	for at in (0..oracle.scratchSize / 8).map(it * 8):
		ours = cpu.memory.bytes.u64le(at)
		theirs = pattern.u64le(at)
		for s in k.stores:
			if s.at == at: theirs = s.value
		if ours != theirs: diffs.push("[{at:x}] {ours:x} != {theirs:x}")
	diffs[..diffs.len.min(4)].join(", ")

test "the interpreter runs each instruction as the arm64 machine did":
	text = fs.readFile("projects/recomp/switch/cpu/tests/vectors.txt") ?? ""
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
