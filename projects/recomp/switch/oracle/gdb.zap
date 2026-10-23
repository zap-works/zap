# The arm64 machine as the oracle: gdb stops /bin/true at its first instruction, then for each
# case writes the word there, sets the registers (and the scratch's pattern for an access),
# steps one instruction and prints the registers (and the scratch after a store). A case that
# raises SIGILL is kept as one the decoder must refuse; one that faults on memory is dropped.

regNames = (0..31).map("$x{it}")

# this run's files on the machine, apart from another run's
pub run = "/tmp/zap-oracle-{clockMs()}"

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
		"dump binary memory {run}.bin $mem $mem + {scratchSize}",
		"printf \"A %lx %lx\\n\", $code, $mem"
	]
	lines.join("\n")

# one case's commands
pub fn scriptCase(index i64, word i64, regs u64[], c Class) str:
	lines = ["echo C {index}\\n"]
	if c.access: lines.push("restore {run}.bin binary $mem")
	lines.push("set \{int\}$code = 0x{word:x}")
	for r in 0..31:
		lines.push("set $x{r} = 0x{regs[r]:x}")
	lines.push("set $sp = 0x{regs[atSp]:x}")
	lines.push("set $cpsr = 0x{regs[atNzcv] << 28:x}")
	for v in 0..32:
		lines.push("set $v{v}.d.u[0] = 0x{regs[atQ + 2 * v]:x}")
		lines.push("set $v{v}.d.u[1] = 0x{regs[atQ + 2 * v + 1]:x}")
	lines.push("set $fpcr = 0x{regs[atFpcr]:x}")
	lines.push("set $fpsr = 0x{regs[atFpsr]:x}")
	lines.push("set $pc = $code")
	lines.push("stepi")
	general = "%lx{" %lx".repeat(33)}"
	lines.push("printf \"R {general}\\n\",{regNames.join(", ")}, $sp, ((unsigned long)(int)$cpsr >> 28) & 15, $pc")
	vectors = (0..32).map("$v{it}.d.u[0], $v{it}.d.u[1]").join(", ")
	words = "%lx{" %lx".repeat(65)}"
	lines.push("printf \"V {words}\\n\",{vectors}, (unsigned long)(int)$fpcr & 0xffffffff, (unsigned long)(int)$fpsr & 0xffffffff")
	if c.store: lines.push("x/{scratchSize / 8}gx $mem")
	lines.join("\n")

# What gdb printed for a case: the state after (stateSize words), whether the machine refused
# the word (SIGILL) or faulted on memory, and the scratch's words after (empty when not dumped).
pub type Outcome:
	state u64[] = []
	refused bool = false
	faulted bool = false
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
			outcomes[current].refused = true
		elif "SIGSEGV" in line or "SIGBUS" in line:
			outcomes[current].faulted = true
		elif line.startsWith("R ") or line.startsWith("V "):
			outcomes[current].state.extend(numbers(line[2..]))
		elif line.startsWith("0x") and ":" in line:
			at = line.indexOf(":") ?? continue
			outcomes[current].scratch.extend(numbers(line[at + 1..].replace("0x", "")))
	(code, mem, outcomes)
