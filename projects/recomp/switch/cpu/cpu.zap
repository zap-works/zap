# A guest thread's registers and the guest's memory, which every thread shares. The registers
# are x0-x30, then 31 the zero register (a write to it is undone) and 32 the stack pointer;
# the FP/SIMD registers are 32 of 128 bits, each two words (low, high).

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
	fn get(r i64, sf bool) u64:
		x[r] if sf else x[r] & 0xFFFF_FFFF

	# register r set (zero-extended from 32 bits when not sf); a write to zr is dropped
	mut fn set(r i64, v u64, sf bool):
		x[r] = v if sf else v & 0xFFFF_FFFF
		x[arm64.zr] = 0

	# the flags as NZCV's four bits (bit 3 is N)
	fn nzcv() u64:
		flagBit(flagN) << 3 | flagBit(flagZ) << 2 | flagBit(flagC) << 1 | flagBit(flagV)

	mut fn setNzcv(f u64):
		flagN = f & 8 != 0
		flagZ = f & 4 != 0
		flagC = f & 2 != 0
		flagV = f & 1 != 0

	# whether the condition's four bits hold (ConditionHolds)
	fn holds(cond i64) bool:
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

# The guest's memory: one span of bytes from address `base`, where the loader and the kernel
# place everything. An access outside it is a fault: noted (the thread halts after its
# instruction, saying where) and served by the span's first bytes.
pub type Memory:
	bytes u8[] = []
	base i64 = 0
	faultAt i64 = -1   # the first access outside since the last look, and its bytes: numbers,
	faultBytes i64 = 0   # so that the check every translated access holds stays a few instructions

	mut fn index(at i64, n i64) i64:
		i = at - base
		if i >= 0 and i + n <= bytes.len: return i
		if faultAt < 0:
			faultAt = at
			faultBytes = n
		0

	# what the first access outside was, "" when none was; the note cleared
	mut fn takeFault() str:
		if faultAt < 0: return ""
		said = "{faultBytes} bytes at {faultAt:x}, outside {base:x}-{base + bytes.len:x}"
		faultAt = -1
		said

	# the size's bytes (log2: 0-3) at `at`, zero-extended
	mut fn load(at i64, size i64) u64:
		i = index(at, 1 << size)
		match size:
			0: u64(bytes[i])
			1: u64(bytes.u16le(i))
			2: u64(bytes.u32le(i))
			_: bytes.u64le(i)

	# size bytes moved from `from` to `to`, zeros left behind
	mut fn moveBytes(from i64, to i64, size i64):
		f = index(from, size)
		t = index(to, size)
		for k in 0..size:
			bytes[t + k] = bytes[f + k]
			bytes[f + k] = 0

	# n bytes at `at`
	mut fn read(at i64, n i64) u8[]:
		if n <= 0: return []
		i = index(at, n)
		bytes[i..i + n].copy()

	# the bytes stored at `at`
	mut fn write(at i64, src u8[]):
		if src.isEmpty: return
		i = index(at, src.len)
		for k, b in src:
			bytes[i + k] = b

	mut fn store(at i64, size i64, v u64):
		i = index(at, 1 << size)
		match size:
			0: bytes[i] = u8(v & 0xFF)
			1: bytes.setU16le(i, u16(v & 0xFFFF))
			2: bytes.setU32le(i, u32(v & 0xFFFF_FFFF))
			_: bytes.setU64le(i, v)

pub mut memory = Memory()
