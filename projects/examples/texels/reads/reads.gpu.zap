# A kernel that fetches the texels of textures by integer coordinates, with no sampler: a color
# texture's at two levels, unsigned and signed integer textures' numbers as they are, texels past
# a level's edge and past its levels (0), and writes what it read as numbers.

import engine

pub type Reads:
	colors engine.Texture   # 4x4, two levels
	counts engine.UintTexture   # 4x4 R32Uint
	signs engine.IntTexture   # 4x4 R32Int
	pairs engine.UintTexture   # 2x2 Rg32Uint
	out u32[]

# a color's bytes, r in the lowest
fn packed(c Vec4) u32:
	b = (c * 255.0 + 0.5).floor()
	u32(b.x) | u32(b.y) << 8 | u32(b.z) << 16 | u32(b.w) << 24

pub fn read(mut p Reads):
	i = globalId.x
	at = IVec2(i % 4, i / 4)
	k = i * 8
	p.out[k] = packed(p.colors.fetch(at, 0))
	p.out[k + 1] = packed(p.colors.fetch(at / 2, 1))
	p.out[k + 2] = p.counts.fetch(at, 0).x
	p.out[k + 3] = u32(p.signs.fetch(at.yx, 0).x + 1000)
	pair = p.pairs.fetch(IVec2(at.x % 2, at.y % 2), 0)
	p.out[k + 4] = pair.x + pair.y * 65536
	# past the right edge, past the levels, left of the first column (by the offset)
	outside = p.counts.fetch(at + IVec2(4, 0), 0).x + p.counts.fetch(at, 3).x +
		p.counts.fetch(at, 0, IVec2(-1, 0)).x * u32(1 if at.x == 0 else 0)
	p.out[k + 5] = outside
	p.out[k + 6] = packed(p.colors.fetch(at, 0, IVec2(1, -1)))
	p.out[k + 7] = u32(p.counts.size(0).x * 10 + p.colors.size(1).y)
