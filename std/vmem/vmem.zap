# Address space reserved at a fixed address: a window whose pages are committed when the program
# asks, or as it first touches them where it asks for that (zeroed when new), and loads and stores of 1, 2, 4, 8 and 16 bytes at an address, each a
# plain host access. An emulator keeps a guest's memory in one: a guest address is then a host
# address as it is (the window at the guest's addresses) or with the window's base or'd in. A
# module of the standard library: `import vmem`, then
# `w = vmem.reserve(0x8_0000_0000, 1 << 35) ?? fail`, `w.commit(at, n)`, `w.store32(at, v)`.
# A guest's heap of gigabytes is `w.commitOnTouch(at, n)`: it costs the memory it touches.
#
# The window's length is a power of two and its base a multiple of it, and an access takes its
# address modulo the length: whatever the address, it lands inside the window, on a committed page
# (read or written) or an uncommitted one (a crash, reported as any is). Nothing outside the
# window is touched, so an address computed by foreign code (a guest's) needs no check.

# commits and decommits round to this, a multiple of every host's page (4 KB, 16 KB on Android)
granule = 65_536

pub type Window:
	base i64
	mask i64   # the length less one

	fn len():
		mask + 1

	fn end():
		base + mask + 1

	# whether the n bytes from `at` (taken modulo the length) stop before the window's end
	fn holds(at i64, n i64):
		n >= 0 and at & mask <= mask + 1 - n

	# the host address an access at `at` reaches
	fn place(at i64):
		base | (at & mask)

	# the pages under [at, at + n) readable and writable, zero when new; false when the system
	# has no memory for them
	fn commit(at i64, n i64):
		if n <= 0: return true
		from, to = granules(at, n)
		rt.commitPages(from, to - from)

	# the pages under [at, at + n) committed as the program first touches them, zero when new;
	# a touch the system has no memory for crashes
	fn commitOnTouch(at i64, n i64):
		if n <= 0: return
		from, to = granules(at, n)
		_ = rt.touchPages(from, to - from)

	# the host addresses of the granules under [at, at + n)
	fn granules(at i64, n i64):
		(place(at) & ~(granule - 1), (place(at) + n).alignUp(granule).min(end()))

	# the pages wholly inside [at, at + n) given back, reserved again (and committed on a touch
	# only when asked again)
	fn decommit(at i64, n i64):
		from = place(at).alignUp(granule)
		to = (place(at) + n).min(end()) & ~(granule - 1)
		if to > from: rt.untouchPages(from, to - from)

	fn load8(at i64):
		rt.u8AtAddress(base | (at & mask))

	fn load16(at i64):
		rt.u16AtAddress(base | (at & mask))

	fn load32(at i64):
		rt.u32AtAddress(base | (at & mask))

	fn load64(at i64):
		rt.u64AtAddress(base | (at & mask))

	# 16 bytes as their low and high words
	fn load128(at i64):
		(load64(at), load64(at + 8))

	fn store8(at i64, v u8):
		rt.setU8AtAddress(base | (at & mask), v)

	fn store16(at i64, v u16):
		rt.setU16AtAddress(base | (at & mask), v)

	fn store32(at i64, v u32):
		rt.setU32AtAddress(base | (at & mask), v)

	fn store64(at i64, v u64):
		rt.setU64AtAddress(base | (at & mask), v)

	fn store128(at i64, low u64, high u64):
		store64(at, low)
		store64(at + 8, high)

	# the values' bytes written from `at`, which they must not carry past the window's end (else
	# the program stops, as at an index out of bounds)
	fn write<T Copy>(at i64, values T[]):
		if not holds(at, values.byteSize): rt.boundsFail()
		rt.copyToAddress(place(at), values)

	# `into` filled with the bytes from `at`, as many as it holds; within the window as for write
	fn read<T Copy>(at i64, mut into T[]):
		if not holds(at, into.byteSize): rt.boundsFail()
		rt.copyFromAddress(into, place(at))

	# the n bytes from `at` copied to `to` (apart from them), both within the window as for write
	fn copyWithin(to i64, at i64, n i64):
		if not holds(at, n) or not holds(to, n): rt.boundsFail()
		rt.copyBetweenAddresses(place(to), place(at), n)

# The window of `len` bytes (a power of two) at `base` (a multiple of it), nothing committed;
# none when some of that address space is taken.
pub fn reserve(base i64, len i64) Window?:
	if len < granule or len & (len - 1) != 0 or base & (len - 1) != 0:
		fail("a window's length is a power of two of 64 KB or more, and its base a multiple of it")
	if not rt.reserveTouchedPagesAt(base, len): return none
	Window(base, mask = len - 1)
