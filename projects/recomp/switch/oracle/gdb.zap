# The arm64 machine as the oracle: gdb stops /bin/true at its first instruction, then for each
# case writes the word there, sets the registers (and the scratch's pattern for an access),
# steps one instruction and prints the registers (and the scratch after a store). A case that
# raises SIGILL is kept as one the decoder must refuse; one that faults on memory is dropped.

regNames = (0..31).map("$x{it}")

# the script's head: signals noted and passed over, the code and scratch addresses printed,
# the pattern written once and dumped to a file each access restores
pub fn scriptHead() str:
	lines = [
		"set pagination off",
		"set confirm off",
		"handle SIGILL stop print nopass",
		"handle SIGSEGV stop print nopass",
		"handle SIGBUS stop print nopass",
		"starti",
		"set $code = (long)$pc",
		"set $mem = ((long)$sp - 0x8000) & ~0xfff",
		"set $i = 0",
		"while $i < {scratchSize}",
		r"set {unsigned char}($mem + $i) = ($i * 29 + 0x5a) & 0xff",
		"set $i = $i + 1",
		"end",
		"dump binary memory /tmp/zap-oracle-pattern.bin $mem $mem + {scratchSize}",
		"printf \"A %lx %lx\\n\", $code, $mem"
	]
	lines.join("\n")

# one case's commands
pub fn scriptCase(index i64, word i64, regs u64[], c Class) str:
	lines = ["echo C {index}\\n"]
	if c.access: lines.push("restore /tmp/zap-oracle-pattern.bin binary $mem")
	lines.push("set \{int\}$code = 0x{word:x}")
	for r in 0..31:
		lines.push("set $x{r} = 0x{regs[r]:x}")
	lines.push("set $sp = 0x{regs[31]:x}")
	lines.push("set $cpsr = 0x{regs[32] << 28:x}")
	lines.push("set $pc = $code")
	lines.push("stepi")
	formats = "%lx{" %lx".repeat(33)}"
	lines.push("printf \"R {formats}\\n\", {regNames.join(", ")}, $sp, ((unsigned long)(int)$cpsr >> 28) & 15, $pc")
	if c.store: lines.push("x/{scratchSize / 8}gx $mem")
	lines.join("\n")

# What gdb printed for each case: its registers after (none when it faulted on memory, an empty
# list when it raised SIGILL) and the scratch's words after (empty when not dumped).
pub type Outcome:
	regs u64[]? = none
	scratch u64[] = []

# The code and scratch addresses, then each case's outcome, from gdb's output.
pub fn parseOutput(out str) (i64, i64, {i64: Outcome}):
	code = 0
	mem = 0
	outcomes {i64: Outcome} = {}
	current = -1
	for line in out.lines():
		if line.startsWith("A "):
			nums = numbers(line[2..])
			code = i64(nums[0])
			mem = i64(nums[1])
		elif line.startsWith("C "):
			current = i64.parse(line[2..].trimmed()) ?? -1
			outcomes[current] = Outcome()
		elif current < 0:
			continue
		elif "SIGILL" in line:
			raised u64[] = []
			outcomes[current].regs = raised
		elif "SIGSEGV" in line or "SIGBUS" in line:
			outcomes[current].regs = none
			current = -1
		elif line.startsWith("R "):
			if outcomes[current].regs == none: outcomes[current].regs = numbers(line[2..])
		elif line.startsWith("0x") and ":" in line:
			at = line.indexOf(":") ?? continue
			outcomes[current].scratch.extend(numbers(line[at + 1..].replace("0x", "")))
	(code, mem, outcomes)
