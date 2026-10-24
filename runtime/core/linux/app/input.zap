# An app's input beside its keys (runtime/core/linux/app/): a game pad's buttons as the input
# queue gives them, its sticks and hat as the cross, and the fingers on the screen, which a program
# draws its own controls for (projects/recomp/touch/). The buttons are engine.PadButton's, in its
# order.

extern "libandroid.so" fn AMotionEvent_getAction(event i64) i32
extern "libandroid.so" fn AMotionEvent_getPointerCount(event i64) i64
extern "libandroid.so" fn AMotionEvent_getX(event i64, index i64) f32
extern "libandroid.so" fn AMotionEvent_getY(event i64, index i64) f32
extern "libandroid.so" fn AMotionEvent_getAxisValue(event i64, axis i32, index i64) f32
extern "libandroid.so" fn AInputEvent_getSource(event i64) i32

padButtons = 12
padSouth = 0
padEast = 1
padWest = 2
padNorth = 3
padLeftShoulder = 4
padRightShoulder = 5
padStart = 6
padSelect = 7
padUp = 8
padDown = 9
padLeft = 10
padRight = 11

# a game pad's key codes (KEYCODE_BUTTON_A...) and the pad's buttons they are
padKeys = [
	(96, padSouth),
	(97, padEast),
	(99, padWest),
	(100, padNorth),
	(102, padLeftShoulder),
	(103, padRightShoulder),
	(104, padLeftShoulder),   # L2 and R2
	(105, padRightShoulder),
	(108, padStart),
	(109, padSelect),
	(19, padUp),
	(20, padDown),
	(21, padLeft),
	(22, padRight)
]

motionUp = 1   # AMOTION_EVENT_ACTION_UP
motionCancel = 3
motionPointerUp = 6

mut touches f64[] = []   # the fingers' places on the window, 0..1 across and down: x, y pairs
mut stickHeld bool[] = []   # the cross's directions a game pad's stick or hat holds, by button

# AINPUT_SOURCE_CLASS_JOYSTICK: a motion event of a game pad's sticks, not of fingers
sourceJoystick = 0x10

# the axes that lean the cross (AXIS_X, AXIS_Y, AXIS_HAT_X, AXIS_HAT_Y), the triggers that hold the
# shoulders (AXIS_LTRIGGER, AXIS_RTRIGGER), and how far an axis leans before it counts
axisX = 0
axisY = 1
axisHatX = 15
axisHatY = 16
axisLeftTrigger = 17
axisRightTrigger = 18
axisLean = 0.5

# whether the pad's button (engine.PadButton's index) is held
pub fn isAppPadDown(button i64) bool:
	if button < 0 or button >= padButtons: return false
	for (code, b) in padKeys:
		if b == button and isAppKeyDown(code): return true
	button < stickHeld.len and stickHeld[button]

# whether the motion event is a game pad's (its sticks, hat and triggers) rather than fingers'
fn isPadMotion(event i64) bool:
	i64(AInputEvent_getSource(event)) & sourceJoystick == sourceJoystick

# The cross and the shoulders as a game pad's motion event leaves them: a stick or the hat leaned
# past half way, a trigger pressed past half way.
fn notePadMotion(event i64):
	if stickHeld.isEmpty: stickHeld = fill(padButtons, false)
	x = event.axis(axisX) + event.axis(axisHatX)
	y = event.axis(axisY) + event.axis(axisHatY)
	stickHeld[padLeft] = x < -axisLean
	stickHeld[padRight] = x > axisLean
	stickHeld[padUp] = y < -axisLean
	stickHeld[padDown] = y > axisLean
	stickHeld[padLeftShoulder] = event.axis(axisLeftTrigger) > axisLean
	stickHeld[padRightShoulder] = event.axis(axisRightTrigger) > axisLean

fn axis(event i64, which i64) f64:
	f64(AMotionEvent_getAxisValue(event, i32(which), 0))

# The places of the fingers a motion event leaves on the window (ww x wh), the one lifted by it gone.
fn noteTouches(event i64, ww i64, wh i64):
	action = i64(AMotionEvent_getAction(event))
	kind = action & 0xFF
	lifted = (action >> 8) & 0xFF if kind == motionPointerUp else -1
	touches.clear()
	if kind == motionUp or kind == motionCancel or ww <= 0 or wh <= 0: return
	for i in 0..AMotionEvent_getPointerCount(event):
		if i == lifted: continue
		touches.push(f64(AMotionEvent_getX(event, i)) / f64(ww))
		touches.push(f64(AMotionEvent_getY(event, i)) / f64(wh))

# the fingers on the screen, 0..1 across and down from its top left: x, y pairs
pub fn appTouches() f64[]:
	touches.copy()
