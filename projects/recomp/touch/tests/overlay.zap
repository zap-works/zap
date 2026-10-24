# The overlay without a window: the fingers it is given, the state it reads from them.

import recomp.touch

# two buttons, two sticks (the second the camera's), on a frame 1000 by 500
fn twoSticks(fw f64, fh f64, margin f64):
	[
		touch.Control(touch.Capsule(x = 100.0, y = 300.0, r = 80.0), "", touch.stickControl),
		touch.Control(touch.Capsule(x = 800.0, y = 400.0, r = 60.0), "", touch.stickControl + 1),
		touch.Control(touch.Capsule(x = 900.0, y = 100.0, r = 40.0), "A", 0),
		touch.Control(
			touch.Capsule(x = 300.0, y = 450.0, half = 20.0, r = 20.0),
			"PAD",
			touch.toggleControl
		)
	]

fn overlay():
	layout = touch.Layout(buttons = 2, sticks = 2, cameraStick = 1, place = twoSticks)
	o = touch.newOverlay(layout, ["resume"])
	o.placement = touch.Placement(1000, 500, 0, 1, 1000, 500)
	o

test "a finger on a button holds it, and one off every control is passed on":
	o = overlay()
	o.read([Vec2(900.0, 100.0), Vec2(500.0, 250.0)], false)
	expect o.isHeld(0) and not o.isHeld(1)
	expect o.passedFingers().len == 1
	expect o.passedFingers()[0].x == 0.5 and o.passedFingers()[0].y == 0.5

test "a finger on a stick leans it, within its reach":
	o = overlay()
	o.read([Vec2(100.0 + 48.0, 300.0)], false)   # half way: the reach is 0.6 of the radius, 48
	expect o.stickLean(0).x == 1.0 and o.stickLean(0).y == 0.0
	o.read([Vec2(100.0, 300.0 - 24.0)], false)
	expect o.stickLean(0).y == -0.5

test "a drag on the right half outside the controls leans the camera stick":
	o = overlay()
	o.read([Vec2(600.0, 200.0)], false)
	expect o.stickLean(1).x == 0.0
	o.read([Vec2(600.0 + 37.5, 200.0 - 100.0)], false)   # the reach is 0.15 of the height, 75
	expect o.stickLean(1).x == 0.5 and o.stickLean(1).y == -1.0
	o.read([], false)
	o.read([Vec2(200.0, 200.0)], false)   # the left half: no camera
	o.read([Vec2(300.0, 200.0)], false)
	expect o.stickLean(1).x == 0.0

test "a game pad hides the controls, which then hold nothing; PAD brings them back":
	o = overlay()
	o.read([], true)
	expect o.gamePadSeen and not o.shown
	o.read([Vec2(900.0, 100.0)], false)
	expect not o.isHeld(0) and o.passedFingers().len == 1
	o.read([], false)
	o.read([Vec2(300.0, 450.0)], false)
	expect o.shown

test "settings move and scale the controls a finger finds":
	o = overlay()
	o.settings.moveBy("A", 0.0, 0.2)   # 100 pixels down
	o.read([Vec2(900.0, 100.0)], false)
	expect not o.isHeld(0)
	o.read([Vec2(900.0, 200.0)], false)
	expect o.isHeld(0)

test "dragging in editing moves a control and keeps it out of play":
	o = overlay()
	o.toggleEditing()
	o.read([Vec2(900.0, 100.0)], false)
	o.read([Vec2(900.0, 150.0)], false)
	expect not o.isHeld(0) and o.settings.moves.len == 1
	expect (o.settings.moves[0].dy - 0.1).abs() < 1e-9

test "settings are written and read back, and move and scale the controls":
	s = touch.Settings(scale = 1.5, opacity = 0.5)
	s.moveBy("A", 0.125, -0.0625)
	s.moveBy("A", 0.125, 0.0)
	back = touch.parseSettings(s.formatSettings())
	expect back.scale == 1.5 and back.opacity == 0.5 and back.moves.len == 1
	cs = back.adjusted(
		[touch.Control(touch.Capsule(x = 100.0, y = 100.0, half = 10.0, r = 20.0), "A", 0)],
		1000.0
	)
	expect cs[0].shape.x == 350.0 and cs[0].shape.y == 37.5 and cs[0].shape.r == 30.0
	expect cs[0].shape.half == 15.0
