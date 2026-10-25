# Storage images by integer coordinates in a compute stage: a color image read and written, an
# image of unsigned integers counted into by atomics, one of signed integers kept the least of.

import shaders.vecs

pub type Canvas:
	colors vecs.Image
	counts vecs.UintImage
	lows vecs.IntImage

pub fn paint(c Canvas):
	at = IVec2(globalId.x, globalId.y)
	size = c.colors.size()
	if at.x >= size.x or at.y >= size.y: return
	c.colors.store(at, c.colors.load(at) * 0.5 + Vec4(0.25, 0.0, 0.0, 1.0))
	before = c.counts.atomicAdd(IVec2(0, 0), 1)
	_ = c.counts.atomicMax(at, before) + c.counts.atomicCompareExchange(at.yx, 0, 7)
	c.counts.store(at + IVec2(0, 1), UVec4(before, 0, 0, 0) + c.counts.load(at))
	_ = c.lows.atomicMin(IVec2(0, 0), at.x - at.y) + c.lows.atomicExchange(at, -1)
