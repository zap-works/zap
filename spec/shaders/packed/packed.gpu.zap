# A pixel stage that unpacks a word the CPU packed: a struct of ranges and bools read back by
# fromBits, packed again by toBits, and a foreign word's bits read with bits(from, count).

pub type Shade = i32 in 0..=16

pub type Texel:
	shade Shade
	lit bool
	layer i32 in 0..32

pub fn pixel(uv Vec2) Vec4:
	word = u32(uv.x * 65536.0)
	t = Texel.fromBits(word)
	again = t.toBits()
	g = f32(t.shade) / 16.0 + f32(word.bits(6, 5)) / 31.0
	Vec4(g, 1.0 if t.lit else 0.0, f32(again & 31) / 31.0, 1.0)
