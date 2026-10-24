# Pixel stages' outputs: one target named past those before it, two of them by name and by place,
# a depth beside a color.

pub type Fifth:
	target5 Vec4

pub type Pair:
	color Vec4
	target3 Vec4

pub type Deep:
	color Vec4
	depth f32

pub fn fifth(uv Vec2) Fifth:
	Fifth(target5 = Vec4(uv.x, uv.y, 0.0, 1.0))

pub fn pair(uv Vec2) Pair:
	Pair(color = Vec4(uv.x, 0.0, 0.0, 1.0), target3 = Vec4(0.0, uv.y, 0.0, 1.0))

pub fn deep(uv Vec2) Deep:
	Deep(color = Vec4(uv.x, uv.y, 0.0, 1.0), depth = uv.x * 0.5)
