# Two fields on target 0: `color` by its place, `target0` by its name.

pub type Targets:
	color Vec4
	target0 Vec4

pub fn pixel(uv Vec2) Targets:
	Targets(color = Vec4(uv.x, uv.y, 0.0, 1.0), target0 = Vec4(1.0, 1.0, 1.0, 1.0))
