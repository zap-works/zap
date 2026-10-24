# A guest thread's registers: x0-x30, then 31 the zero register (a write to it is undone) and 32
# the stack pointer; the FP/SIMD registers are 32 of 128 bits, each two words (low, high).

import recomp.switch.arm64

pub type Cpu:
	x u64[33] = fill(33, u64(0))
	pc i64 = 0
	flagN bool = false
	flagZ bool = false
	flagC bool = false
	flagV bool = false
	q u64[] = zeros(64)
	fpcr u64 = 0
	fpsr u64 = 0
	tpidr u64 = 0   # TPIDR_EL0, the thread's own
	tpidrro u64 = 0   # TPIDRRO_EL0, the thread's TLS, set by the kernel
	exclusiveAt i64 = -1   # the address a load-exclusive marked, -1 when none
	exclusiveValue u64 = 0
	halted str = ""   # why the thread stopped, "" while it runs
	isHalted bool = false   # halted's "" or not, read once an instruction
	budget i64 = 0   # instructions left in the thread's slice; translated code yields at 0
	trail i64[] = zeros(16)   # the last blocks entered, oldest first from trailAt (a diagnostic)
	trailAt i64 = 0

	# register r, a w register's 32 bits when not sf
	fn get(r i64, sf bool):
		x[r] if sf else x[r] & 0xFFFF_FFFF

	# register r set (zero-extended from 32 bits when not sf); a write to zr is dropped
	fn set(r i64, v u64, sf bool):
		x[r] = v if sf else v & 0xFFFF_FFFF
		x[arm64.zr] = 0

	# the flags as NZCV's four bits (bit 3 is N)
	fn nzcv():
		flagBit(flagN) << 3 | flagBit(flagZ) << 2 | flagBit(flagC) << 1 | flagBit(flagV)

	fn setNzcv(f u64):
		flagN = f & 8 != 0
		flagZ = f & 4 != 0
		flagC = f & 2 != 0
		flagV = f & 1 != 0

	# whether the condition's four bits hold (ConditionHolds)
	fn holds(cond i64):
		result = match cond >> 1:
			0: flagZ
			1: flagC
			2: flagN
			3: flagV
			4: flagC and not flagZ
			5: flagN == flagV
			6: flagN == flagV and not flagZ
			_: true
		not result if cond & 1 != 0 and cond != 15 else result

# 1 for true, 0 for false
pub fn flagBit(b bool) u64:
	1 if b else 0

# the thread halted at pc with the reason
pub fn stop(mut c Cpu, pc i64, move why str):
	c.pc = pc
	c.halted = why
	c.isHalted = true
