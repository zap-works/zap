# Two kernels on storage images: the first changes each texel of a color image (read, then
# written), counts into an image of unsigned integers by atomics and keeps the least of a value in
# one of signed integers; the second reads what the first wrote into a storage buffer.

import engine

pub type Canvas:
	colors engine.Image   # 16x16 RGBA8
	counts engine.UintImage   # 8x2 R32Uint
	lows engine.IntImage   # 1x1 R32Int

pub fn paint(c Canvas):
	at = IVec2(globalId.x, globalId.y)
	c.colors.store(at, c.colors.load(at) * 0.5 + Vec4(0.25, 0.0, 0.0, 1.0))
	_ = c.counts.atomicAdd(IVec2(at.x % 4, 0), 1)
	_ = c.lows.atomicMin(IVec2(0, 0), at.x - at.y)
	if at.x == 0 and at.y == 0:
		_ = c.counts.atomicCompareExchange(IVec2(5, 1), 0, 9)
		_ = c.counts.atomicCompareExchange(IVec2(6, 1), 1, 9)
		c.counts.store(IVec2(7, 1), UVec4(u32(c.colors.size().x), 0, 0, 0))

pub type Reading:
	colors engine.Image
	counts engine.UintImage
	lows engine.IntImage
	out u32[]

# a color's bytes, r in the lowest
fn packed(c Vec4) u32:
	b = (c * 255.0 + 0.5).floor()
	u32(b.x) | u32(b.y) << 8 | u32(b.z) << 16 | u32(b.w) << 24

pub fn read(mut p Reading):
	at = IVec2(globalId.x, globalId.y)
	i = at.y * 16 + at.x
	p.out[i] = packed(p.colors.load(at))
	if i < 16:
		p.out[256 + i] = p.counts.load(IVec2(i % 8, i / 8)).x
	if i == 0:
		p.out[272] = u32(p.lows.load(IVec2(0, 0)).x + 1000)
