# The drop shadows of a placed text (PlaceObject3's filters, as the game's menus put on their
# text fields): the text drawn again under itself in the shadow's color, at its distance and angle
# in the stage's pixels. The blur is two more copies offset by half the blur either way, the
# alphas of the copies stacking to the shadow's strength: not the player's box blurs (a text's
# strokes are thin, so a blurred shadow stays faint). Glows, blurs and inner or knockout shadows
# are not drawn yet.

import engine

# the most opaque a stack of shadow copies gets, so that the blur's copies still show apart
shadowCeiling f32 = 0.9
# how much of the filter's strength the thin strokes of text keep after the blur
shadowKeep f32 = 0.6

# the shadows the placed object asks for drawn, under the object itself
fn drawShadows(
	scene Scene,
	st Stage,
	mut cache DrawCache,
	mut r engine.Renderer,
	p Placed,
	ctx Context
):
	if scene.movie.editTexts.get(p.character) == none: return
	for f in p.filters:
		if f.kind != 0 or f.inner or f.knockout: continue
		scene.drawShadow(st, cache, r, p, f, ctx)

fn drawShadow(
	scene Scene,
	st Stage,
	mut cache DrawCache,
	mut r engine.Renderer,
	p Placed,
	f Filter,
	ctx Context
):
	t = scene.movie.editTexts.get(p.character) ?? return
	node = ctx.node ?? return
	# the stage's pixel in the window's
	sx = ctx.matrix.a * 20.0
	sy = ctx.matrix.d * 20.0
	spread = Vec2(f.blurX * 0.5 * sx, f.blurY * 0.5 * sy)
	taps = [Vec2(0.0, 0.0)]
	if f.blurX > 1.0 or f.blurY > 1.0:
		taps.extend([spread, spread * -1.0])
	target = (f.strength * f.color.w * shadowKeep).min(shadowCeiling)
	each = 1.0 - (1.0 - target).pow(1.0 / f32(taps.len))
	shift = Vec2(f.angle.cos() * f.distance * sx, f.angle.sin() * f.distance * sy)
	for tap in taps:
		moved = ctx.matrix
		moved.tx += shift.x + tap.x
		moved.ty += shift.y + tap.y
		color = ColorTransform(mul = Vec4(0.0, 0.0, 0.0, ctx.color.mul.w * each),
			add = Vec4(f.color.x, f.color.y, f.color.z, 0.0))
		shadow = Context(matrix = moved, color, clip = ctx.clip, clipped = ctx.clipped,
			node)
		scene.drawEditText(cache, r, t, st.nodes[node], shadow)
