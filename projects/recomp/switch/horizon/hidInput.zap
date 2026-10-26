# The input hid's shared memory carries (libnx's hid.h lays it out): a Pro Controller as player 1
# (npad 0, the FullKey style) and the touch screen, each a ring of 17 entries that the system
# writes 60 times a second and the game reads the newest of. Whoever runs the game sets
# Kernel.pad and Kernel.touches (the engine's pad, the touch overlay, a script); the kernel's
# clock writes them (runProcess).

import recomp.switch.cpu.core

touchAt = 0x400
npadAt = 0x9A00
ringEntries = 17
ringHeader = 0x20
npadEntry = 0x30   # a sampling number, then the state: sampling number, buttons, two sticks, attributes
touchEntry = 0x298   # a sampling number, then the state: sampling number, count, 16 touches of 0x28
npadFullKeyRing = 0x28
npadDeviceType = 0x4188
styleFullKey = 1
attributeConnected = 1
attributeWired = 2

# the counter's ticks between two of hid's samples (60 a second)
pub hidPeriod = 19_200_000 / 60

# A Pro Controller's state: its buttons (NpadButton's bits: A 0, B 1, X 2, Y 3, StickL 4, StickR 5,
# L 6, R 7, ZL 8, ZR 9, Plus 10, Minus 11, Left 12, Up 13, Right 14, Down 15) and its sticks
# (-32767..32767, y up).
pub type PadState:
	buttons u64 = 0
	leftX i64 = 0
	leftY i64 = 0
	rightX i64 = 0
	rightY i64 = 0

# A finger on the touch screen, in its 1280x720 pixels.
pub type Touch:
	x i64
	y i64
	finger i64

# where the ring at `ring` (in the shared memory mapped at `base`) takes its next entry: the
# header moved on
fn nextEntry(base i64, ring i64, entryBytes i64):
	tail = (i64(core.memory.load(base + ring + 0x10, 3)) + 1) % ringEntries
	count = (i64(core.memory.load(base + ring + 0x18, 3)) + 1).min(ringEntries)
	core.memory.store(base + ring + 0x8, 3, u64(ringEntries))
	core.memory.store(base + ring + 0x10, 3, u64(tail))
	core.memory.store(base + ring + 0x18, 3, u64(count))
	base + ring + ringHeader + tail * entryBytes

# player 1 as a wired Pro Controller: its style and device type
fn connectPad(base i64):
	npad = base + npadAt
	core.memory.store(npad, 2, styleFullKey)
	core.memory.store(npad + npadDeviceType, 2, 1)

# One of hid's samples written into its shared memory, when the game has mapped it.
pub fn sampleHid(mut k Kernel):
	if k.hidMemory < 0: return
	base = k.sharedMemory[k.hidMemory].mappedAt
	if base < 0: return
	k.hidSamples += 1
	n = u64(k.hidSamples)
	connectPad(base)
	at = nextEntry(base, npadAt + npadFullKeyRing, npadEntry)
	p = k.pad
	core.memory.store(at, 3, n)
	core.memory.store(at + 8, 3, n)
	core.memory.store(at + 0x10, 3, p.buttons)
	for o, v in [p.leftX, p.leftY, p.rightX, p.rightY]:
		core.memory.store(at + 0x18 + 4 * o, 2, u64(v) & 0xFFFF_FFFF)
	core.memory.store(at + 0x28, 2, attributeConnected | attributeWired)
	at = nextEntry(base, touchAt, touchEntry)
	core.memory.store(at, 3, n)
	core.memory.store(at + 8, 3, n)
	core.memory.store(at + 0x10, 2, k.touches.len.min(16))
	for j in 0..k.touches.len.min(16):
		t = k.touches[j]
		e = at + 0x18 + j * 0x28
		core.memory.store(e, 3, 0)
		core.memory.store(e + 8, 2, 0)
		core.memory.store(e + 0xC, 2, u64(t.finger))
		core.memory.store(e + 0x10, 2, u64(t.x))
		core.memory.store(e + 0x14, 2, u64(t.y))
		core.memory.store(e + 0x18, 2, 15)
		core.memory.store(e + 0x1C, 2, 15)
