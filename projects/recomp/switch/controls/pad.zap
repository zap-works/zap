# The Pro Controller a game sees, from what the player holds: a game pad through the engine
# (Bluetooth or USB on Android), its buttons by place as a Switch names them (South is B), its
# sticks scaled to the Switch's range with y up, and each stick's lean as the direction bits
# games read in menus.

import engine
import recomp.switch.horizon

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
