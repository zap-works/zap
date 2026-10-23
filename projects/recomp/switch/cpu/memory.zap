# The guest's memory, which every thread shares: one window of the host's address space (std/vmem)
# holding the guest's whole 36-bit space, the guest's address its offset, so a load is one host
# load at the window's base or'd with the address. A 36-bit game expects its code at 128 MiB and
# its stacks below 2 GiB, which the host cannot leave free at the same addresses (Windows puts the
# executable at 5 GiB and its own allocations low), so the window is 64 GiB at 64 GiB: free on
# Windows, on Linux and on Android (whose libraries and mappings lie near the top of a 39- or
# 48-bit space, ART's heap in the low 4 GiB). Its pages are committed as the kernel maps them
# (horizon/space.zap): an access to one never mapped is a crash, the first 128 MiB catching null
# pointers. A 39-bit game would need 512 GiB at 512 GiB, more than a 39-bit host has.
# `guestfaults` in ZAP_RUN checks each access against the process's span, noting a fault the
# thread halts on.

import vmem

windowBase = 0x10_0000_0000
windowLen = 0x10_0000_0000

# (mut: set once; TODO B.1 25)
mut window = vmem.reserve(windowBase, windowLen) ??
	fail("the guest memory's address space ({windowBase:x}, {windowLen:x} bytes) is taken")

fn guestFaultsWord():
	TraceWord(
		"guestfaults",
		"recomp.switch halts a guest thread at an access outside its process's memory"
	)

# with `guestfaults` (or while a translation tries code ahead of time) an access outside the span
# is noted and skipped: a load reads 0
pub mut checking = guestFaultsWord().on()

# The process's memory: its span from `base` to `end`, where the loader and the kernel place
# everything, and the first fault noted (with `guestfaults`, or by a copy outside the span).
pub type Memory:
	base i64 = 0
	end i64 = 0
	faultAt i64 = -1   # the first access outside since the last look, and its bytes: numbers,
	faultBytes i64 = 0   # so that the check a translated access holds stays a few instructions

	# the fault noted since the last look, "" when none; the note cleared
	fn takeFault():
		if faultAt < 0: return ""
		said = "{faultBytes} bytes at {faultAt:x}, outside {base:x}-{end:x}"
		faultAt = -1
		said

	# whether the n bytes at `at` lie in the span, a fault noted when not
	fn inside(at i64, n i64):
		if at >= base and n >= 0 and at <= end - n: return true
		if faultAt < 0:
			faultAt = at
			faultBytes = n
		false

	# the size's bytes (log2: 0-3) at `at`, zero-extended
	mut fn load(at i64, size i64) u64:
		if checking and not inside(at, 1 << size): return 0
		match size:
			0: window.load8(at)
			1: window.load16(at)
			2: window.load32(at)
			_: window.load64(at)

	mut fn store(at i64, size i64, v u64):
		if checking and not inside(at, 1 << size): return
		match size:
			0: window.store8(at, v & 0xFF)
			1: window.store16(at, v & 0xFFFF)
			2: window.store32(at, v & 0xFFFF_FFFF)
			_: window.store64(at, v)

	# size bytes moved from `from` to `to`, zeros left behind
	mut fn moveBytes(from i64, to i64, size i64):
		if not inside(from, size) or not inside(to, size): return
		window.copyWithin(to, from, size)
		blank u8[] = zeros(size)
		window.write(from, blank)

	# n bytes at `at` (zeros outside the span)
	mut fn read(at i64, n i64):
		out u8[] = zeros(n.max(0))
		if n > 0 and inside(at, n): window.read(at, out)
		out

	# the bytes stored at `at`
	mut fn write(at i64, src u8[]):
		if not src.isEmpty and inside(at, src.len): window.write(at, src)

	# [at, at + n) given memory (zero when new); false when the host has none
	fn commit(at i64, n i64):
		window.commit(at, n)

pub mut memory = Memory()

# A process's memory of n bytes from `base`, nothing committed yet: the last process's given back.
pub fn newMemory(base i64, n i64) Memory:
	window.decommit(window.base, window.len)
	Memory(base, end = base + n)

# a memory of n bytes from base, all of it committed: a test's
pub fn committedMemory(base i64, n i64) Memory:
	m = newMemory(base, n)
	m.commit(base, n)
	m
