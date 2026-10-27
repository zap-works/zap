# The Pro Controller a game sees, from what the player holds: the touch overlay's fingers
# (the layout of its controls below), or a game pad through the engine
# (Bluetooth or USB on Android), its buttons by place as a Switch names them (South is B), its
# sticks scaled to the Switch's range with y up, and each stick's lean as the direction bits
# games read in menus.

import engine
import recomp.switch.horizon
import recomp.touch

# NpadButton's bits (libnx's HidNpadButton)
pub buttonA = 0
pub buttonB = 1
pub buttonX = 2
pub buttonY = 3
pub buttonStickL = 4
pub buttonStickR = 5
pub buttonL = 6
pub buttonR = 7
pub buttonZL = 8
pub buttonZR = 9
pub buttonPlus = 10
pub buttonMinus = 11
pub buttonLeft = 12
pub buttonUp = 13
pub buttonRight = 14
pub buttonDown = 15
stickLeftLeft = 16
stickRightLeft = 20

# the Switch's stick range
stickRange = 32767.0

# engine.PadButton's buttons and the Switch's bits they are
padBits = [
	(engine.PadButton.South, buttonB),
	(engine.PadButton.East, buttonA),
	(engine.PadButton.West, buttonY),
	(engine.PadButton.North, buttonX),
	(engine.PadButton.LeftShoulder, buttonL),
	(engine.PadButton.RightShoulder, buttonR),
	(engine.PadButton.LeftTrigger, buttonZL),
	(engine.PadButton.RightTrigger, buttonZR),
	(engine.PadButton.LeftStick, buttonStickL),
	(engine.PadButton.RightStick, buttonStickR),
	(engine.PadButton.Start, buttonPlus),
	(engine.PadButton.Select, buttonMinus),
	(engine.PadButton.Left, buttonLeft),
	(engine.PadButton.Up, buttonUp),
	(engine.PadButton.Right, buttonRight),
	(engine.PadButton.Down, buttonDown)
]

# a stick's lean (-1..1 each way, y down as screens count) as the Switch's numbers, y up
pub fn stickOf(v Vec2) (i64, i64):
	x = f64(v.x).clamp(-1.0, 1.0)
	y = f64(v.y).clamp(-1.0, 1.0)
	(i64((x * stickRange).round()), i64((-y * stickRange).round()))

# the direction bits of a stick leaning past half its range: left, up, right, down from `first`
fn leanBits(x i64, y i64, first i64):
	half = i64(stickRange / 2.0)
	bits = u64(0)
	if x < -half: bits |= u64(1) << first
	if y > half: bits |= u64(1) << (first + 1)
	if x > half: bits |= u64(1) << (first + 2)
	if y < -half: bits |= u64(1) << (first + 3)
	bits

# The pad state from buttons held (NpadButton bits) and two sticks (-1..1, y down).
pub fn padState(buttons u64, left Vec2, right Vec2) horizon.PadState:
	lx, ly = left.stickOf()
	rx, ry = right.stickOf()
	horizon.PadState(
		buttons = buttons | leanBits(lx, ly, stickLeftLeft) | leanBits(rx, ry, stickRightLeft),
		leftX = lx,
		leftY = ly,
		rightX = rx,
		rightY = ry
	)

# The pad state a game pad gives now.
pub fn fromGamePad() horizon.PadState:
	held = u64(0)
	for (b, bit) in padBits:
		if b.isPadDown(): held |= u64(1) << bit
	left = Vec2(engine.padAxis(.LeftX), engine.padAxis(.LeftY))
	right = Vec2(engine.padAxis(.RightX), engine.padAxis(.RightY))
	padState(held, left, right)

test "a stick's lean is the Switch's range with y up, and its direction bits":
	s = padState(u64(1) << buttonA, Vec2(1.0, 0.0), Vec2(0.0, -1.0))
	expect s.leftX == 32_767 and s.leftY == 0
	expect s.rightY == 32_767
	expect s.buttons ==
		(u64(1) << buttonA) | (u64(1) << (stickLeftLeft + 2)) | (u64(1) << (stickRightLeft + 1))

# the Switch's touch screen
screenWidth = 1280
screenHeight = 720

pub fn proLayout() touch.Layout:
	touch.Layout(buttons = 16, sticks = 2, cameraStick = 1, place = proControls)

# a button's control: a circle of the radius at (x, y), the slot of NpadButton's bit
fn round(x f64, y f64, r f64, label str, slot i64):
	touch.Control(touch.Capsule(x, y, r = r), label.copy(), slot)

# a shoulder's control: a pill
fn pill(x f64, y f64, half f64, r f64, label str, slot i64):
	touch.Control(touch.Capsule(x, y, half, r), label.copy(), slot)

# long: a table of the controls' places
fn proControls(fw f64, fh f64, margin f64):
	left = (margin / 2.0).max(fh * 0.2)
	right = fw - left
	d = fh * 0.085
	r = fh * 0.05
	shoulder = fh * 0.05
	low = fh * 0.93
	centre = fw / 2.0
	[
		touch.Control(
			touch.Capsule(x = left, y = fh * 0.76, r = fh * 0.15),
			"",
			touch.stickControl
		),
		touch.Control(
			touch.Capsule(x = right, y = fh * 0.76, r = fh * 0.15),
			"",
			touch.stickControl + 1
		),
		round(right, fh * 0.32 + d, r, "B", buttonB),
		round(right + d, fh * 0.32, r, "A", buttonA),
		round(right - d, fh * 0.32, r, "Y", buttonY),
		round(right, fh * 0.32 - d, r, "X", buttonX),
		round(left, fh * 0.32 - d, r, "^", buttonUp),
		round(left, fh * 0.32 + d, r, "V", buttonDown),
		round(left - d, fh * 0.32, r, "<", buttonLeft),
		round(left + d, fh * 0.32, r, ">", buttonRight),
		pill(left, fh * 0.05, shoulder, r * 0.7, "ZL", buttonZL),
		pill(left, fh * 0.12, shoulder, r * 0.7, "L", buttonL),
		pill(right, fh * 0.05, shoulder, r * 0.7, "ZR", buttonZR),
		pill(right, fh * 0.12, shoulder, r * 0.7, "R", buttonR),
		round(centre - fh * 0.22, low, r * 0.7, "-", buttonMinus),
		round(centre + fh * 0.22, low, r * 0.7, "+", buttonPlus),
		pill(centre - fh * 0.08, low, shoulder * 0.4, r * 0.5, "PAD", touch.toggleControl),
		pill(centre + fh * 0.08, low, shoulder * 0.4, r * 0.5, "MENU", touch.menuControl)
	]

# The pad state the overlay's fingers give.
pub fn fromOverlay(o touch.Overlay) horizon.PadState:
	held = u64(0)
	for slot in 0..16:
		if o.isHeld(slot): held |= u64(1) << slot
	padState(held, o.stickLean(0), o.stickLean(1))

# The fingers on no control as the Switch's touch screen points (1280 by 720), each finger keeping
# its id while it is down.
pub fn touchPoints(o touch.Overlay) horizon.Touch[]:
	o.passedFingers().map(
		horizon.Touch(
			i64((f64(.at.x) * screenWidth).round()),
			i64((f64(.at.y) * screenHeight).round()),
			.id
		)
	)

fn placed():
	o = touch.newOverlay(proLayout(), ["resume"])
	o.placement = touch.Placement(1280, 720, 0, 1, 1280, 720)
	o

# the centre of the control labelled so in the 1280 by 720 frame
fn centreOf(label str):
	for c in proControls(1280.0, 720.0, 0.0):
		if c.label == label: return Vec2(f32(c.shape.x), f32(c.shape.y))
	Vec2(-1.0, -1.0)   # no such control: a test then fails

test "ABXY, the cross, the shoulders and +/- hold their Switch buttons":
	o = placed()
	pairs = [
		("A", buttonA),
		("B", buttonB),
		("X", buttonX),
		("Y", buttonY),
		("^", buttonUp),
		("V", buttonDown),
		("<", buttonLeft),
		(">", buttonRight),
		("L", buttonL),
		("R", buttonR),
		("ZL", buttonZL),
		("ZR", buttonZR),
		("+", buttonPlus),
		("-", buttonMinus)
	]
	for (label, bit) in pairs:
		o.read([], false)
		o.read([centreOf(label)], false)
		expect o.fromOverlay().buttons == u64(1) << bit
		expect o.touchPoints().isEmpty

test "the left stick at its edge reads the Switch's full range, y up, with the lean bits":
	o = placed()
	c = centreOf("")
	o.read([Vec2(c.x + 100.0, c.y)], false)   # past the reach, still on the stick: the edge
	s = o.fromOverlay()
	expect s.leftX == 32_767 and s.leftY == 0 and s.rightX == 0
	expect s.buttons == u64(1) << 18
	o.read([Vec2(c.x, c.y - 30.0)], false)
	expect o.fromOverlay().leftY > 0

test "a drag on the right half moves the right stick, and the fingers on no control are touches":
	o = placed()
	o.read([Vec2(900.0, 300.0)], false)
	o.read([Vec2(900.0 + 54.0, 300.0)], false)   # the reach is 0.15 of 720
	s = o.fromOverlay()
	expect s.rightX == 16_384 and s.rightY == 0 and s.leftX == 0
	points = o.touchPoints()
	expect points.len == 1 and points[0].x == 954 and points[0].y == 300

test "with a game pad in use the controls are hidden and a finger is only a touch":
	o = placed()
	o.read([], true)
	o.read([centreOf("A")], false)
	expect o.fromOverlay().buttons == 0
	expect o.touchPoints().len == 1

test "a touch point keeps its finger's id while another finger lifts":
	o = placed()
	o.readFingers([engine.Finger(4, Vec2(300.0, 300.0)), engine.Finger(9, Vec2(400.0, 300.0))], false)
	expect o.touchPoints().map(.finger) == [4, 9]
	o.readFingers([engine.Finger(9, Vec2(410.0, 300.0))], false)
	points = o.touchPoints()
	expect points.len == 1 and points[0].finger == 9 and points[0].x == 410
