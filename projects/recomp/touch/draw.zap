# The controls painted at the settings' opacity, a held one lit; only PAD and MENU while the pad is
# hidden. The sticks' knobs, which move with the fingers, are painted over each frame apart from
# the rest, which ink.zap lays.

import image

# the controls but the knobs, onto the frame (the overlay's, or ink.zap's black and white)
fn paintControls(o Overlay, mut frame image.Image, cs Control[]):
	a = o.settings.opacity
	for c in cs:
		if not o.shown and c.kind < toggleControl: continue
		if c.isStick():
			frame.paintCapsule(c.shape, 0.12 * a, 0.3 * a, c.shape.r * 0.05, false)
			continue
		frame.paintCapsule(c.shape, 0.18 * a, 0.35 * a, c.shape.r * 0.1, o.isLit(c))
		size = c.shape.r * (0.75 if c.label.len == 1 else 0.6)
		frame.paintText(c.label, c.shape.x, c.shape.y, size, 0.6 * a)

# each stick's knob where its lean put it, lit while leaning
fn paintKnobs(mut o Overlay, cs Control[]):
	if not o.shown: return
	a = o.settings.opacity
	for c in cs:
		if not c.isStick(): continue
		lean = o.push[c.kind - stickControl]
		reach = c.stickReach()
		knob = Capsule(
			x = c.shape.x + f64(lean.x) * reach,
			y = c.shape.y + f64(lean.y) * reach,
			r = c.shape.r * 0.42
		)
		leaning = lean.x != 0.0 or lean.y != 0.0
		o.frame.paintCapsule(knob, 0.3 * a, 0.45 * a, knob.r * 0.12, leaning)

fn isLit(o Overlay, c Control):
	c.kind < o.held.len and o.held[c.kind]

# what the painted controls depend on besides the knobs: the frame's size, the pad shown, the
# settings (size, opacity, places), the buttons held
fn controlsKey(o Overlay, cs Control[]):
	"{o.frame.width}x{o.frame.height} {o.shown} {o.settings.formatSettings()} {cs.map(o.isLit(it))}"
