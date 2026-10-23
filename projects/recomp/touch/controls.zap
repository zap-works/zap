# The controls a layout places over the frame, and the SNES pad's layout: a stick for the cross on
# the left, the face buttons on the right as a SNES pad has them, the shoulders above, Select and
# Start below, and beside those the overlay's own two, PAD (shows or hides the rest) and MENU.
# Placed by the frame's height, in the margins beside the picture when they are wide enough, else
# over the picture's edges.

import engine

# a control's kind beyond a layout's button slots: the sticks (stickControl + the stick's number),
# then the overlay's own two
pub stickControl = 100
pub toggleControl = 110
pub menuControl = 111

pub type Control:
	shape Capsule
	label str
	kind i64   # a button slot of the layout, or one of the kinds above

# What a console's pad is: how many button slots and sticks it has, where its controls go, and
# which slots the first stick leans onto (left, right, up, down; none when it is only analog).
pub type Layout:
	buttons i64
	sticks i64
	lean i64[] = []
	cameraStick i64 = -1   # the stick a drag on the right half of the screen moves, if any
	place fn(f64, f64, f64) Control[]   # the controls for a frame's width, height and margin

fn isStick(c Control):
	c.kind >= stickControl and c.kind < toggleControl

# the layout of a SNES pad, its slots engine.PadButton's indexes
pub fn snesLayout() Layout:
	Layout(
		buttons = engine.padButtons().len,
		sticks = 1,
		lean = [
			engine.PadButton.Left.index(),
			engine.PadButton.Right.index(),
			engine.PadButton.Up.index(),
			engine.PadButton.Down.index()
		],
		place = snesControls
	)

# long: a table of the controls' places
fn snesControls(fw f64, fh f64, margin f64):
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
	c.shape.edgeDistance(x, y) < c.shape.r * (0.6 if c.isStick() else 0.25)

# how far from a stick's centre its knob goes
fn stickReach(c Control):
	c.shape.r * 0.6
