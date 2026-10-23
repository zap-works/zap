# Two values a pixel, one per target of a set, and a pass that reads one of those targets back.

import engine

pub type Split:
	color Vec4
	pair Vec4

# what the two targets are given
pub type Values:
	color Vec4
	pair Vec4

pub fn pixel(uv Vec2, p Values) Split:
	Split(color = p.color, pair = p.pair)

# the green of a picture, in every channel
pub type Source:
	picture engine.Texture

pub fn green(uv Vec2, p Source) Vec4:
	g = p.picture.sample(uv).g
	Vec4(g, g, g, g)
