# The controls drawn over the frame: a stick for the cross on the left, the face buttons on the
# right as a SNES pad has them, the shoulders above, Select and Start below, and beside those the
# overlay's own two, PAD (shows or hides the rest) and MENU. Placed by the frame's height, in the
# margins beside the picture when they are wide enough, else over the picture's edges.

import engine
import image

# a control's kind beyond engine.PadButton's indexes
stickControl = 100
toggleControl = 101
menuControl = 102

type Control:
	shape Capsule
	label str
	kind i64   # an engine.PadButton's index, or one of the kinds above

# long: a table of the controls' places
fn controls(fw f64, fh f64, margin f64):
	left = (margin / 2.0).max(fh * 0.24)
	right = fw - left
	middle = fh * 0.58
	d = fh * 0.12
	r = fh * 0.062
	pill = fh * 0.07
	low = fh * 0.92
	top = fh * 0.14
	[
		Control(Capsule(x = left, y = middle, r = fh * 0.2), "", stickControl),
		Control(Capsule(x = right, y = middle + d, r), "B", engine.PadButton.South.index()),
		Control(Capsule(x = right + d, y = middle, r), "A", engine.PadButton.East.index()),
		Control(Capsule(x = right - d, y = middle, r), "Y", engine.PadButton.West.index()),
		Control(Capsule(x = right, y = middle - d, r), "X", engine.PadButton.North.index()),
		Control(Capsule(x = left, y = top, half = pill, r = r * 0.7), "L", engine.PadButton.LeftShoulder.index()),
		Control(Capsule(x = right, y = top, half = pill, r = r * 0.7), "R", engine.PadButton.RightShoulder.index()),
		Control(Capsule(x = left - pill * 0.9, y = low, half = pill * 0.8, r = r * 0.5), "SELECT", engine.PadButton.Select.index()),
		Control(Capsule(x = right + pill * 0.9, y = low, half = pill * 0.8, r = r * 0.5), "START", engine.PadButton.Start.index()),
		Control(Capsule(x = left + pill * 1.3, y = low, half = pill * 0.4, r = r * 0.5), "PAD", toggleControl),
		Control(
			Capsule(x = right - pill * 1.3, y = low, half = pill * 0.4, r = r * 0.5),
			"MENU",
			menuControl
		)
	]

# whether a finger at (x, y) is on the control: within its shape or a little past it
fn reaches(c Control, x f64, y f64):
	c.shape.edgeDistance(x, y) < c.shape.r * (0.6 if c.kind == stickControl else 0.25)

# The stick pushed by a finger at (dx, dy) from its centre: the knob there (kept within its
# reach), and past a dead middle the cross's directions it leans toward, diagonals too.
fn pushStick(mut o Overlay, dx f64, dy f64, reach f64):
	d = (dx * dx + dy * dy).sqrt()
	scale = reach / d if d > reach else 1.0
	o.stickX = dx * scale
	o.stickY = dy * scale
	if d < reach * 0.3: return
	lean = d * 0.38   # sin of 22.5 degrees: eight directions
	if dx < -lean: o.held[engine.PadButton.Left.index()] = true
	if dx > lean: o.held[engine.PadButton.Right.index()] = true
	if dy < -lean: o.held[engine.PadButton.Up.index()] = true
	if dy > lean: o.held[engine.PadButton.Down.index()] = true

# The controls laid over the frame, faint, a held one lit; only PAD and MENU while the pad is hidden.
# The stick's knob, which moves with the finger, is left to paintKnob.
fn paintControls(o Overlay, mut frame image.Image, cs Control[]):
	for c in cs:
		if not o.shown and c.kind < toggleControl: continue
		if c.kind == stickControl:
			frame.paintCapsule(c.shape, 0.12, 0.3, c.shape.r * 0.05, false)
			continue
		lit = c.kind < o.held.len and o.held[c.kind]
		frame.paintCapsule(c.shape, 0.18, 0.35, c.shape.r * 0.1, lit)
		size = c.shape.r * (0.75 if c.label.len == 1 else 0.6)
		frame.paintText(c.label, c.shape.x, c.shape.y, size, 0.6)

# the stick's knob where the finger pushed it, lit while pushed
fn paintKnob(mut o Overlay, cs Control[]):
	if not o.shown: return
	for c in cs:
		if c.kind != stickControl: continue
		knob = Capsule(x = c.shape.x + o.stickX, y = c.shape.y + o.stickY, r = c.shape.r * 0.42)
		o.frame.paintCapsule(knob, 0.3, 0.45, knob.r * 0.12, o.isStickPushed())

# what the painted controls depend on besides the knob: the frame's size, the pad shown, the
# buttons held
fn controlsKey(o Overlay, cs Control[]) str:
	lit = cs.map(it.kind < o.held.len and o.held[it.kind] and it.kind != stickControl)
	"{o.frame.width}x{o.frame.height} {o.shown} {lit}"

fn isStickPushed(o Overlay):
	o.stickX != 0.0 or o.stickY != 0.0
