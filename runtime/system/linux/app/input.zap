# An app's input beside its keys (runtime/system/linux/app/): a game pad's buttons as the input
# queue gives them, and the fingers on the screen, which a program draws its own controls for
# (projects/recomp/touch/). The buttons are engine.PadButton's, in its order.

extern "libandroid.so" fn AMotionEvent_getAction(event i64) i32
extern "libandroid.so" fn AMotionEvent_getPointerCount(event i64) i64
extern "libandroid.so" fn AMotionEvent_getX(event i64, index i64) f32
extern "libandroid.so" fn AMotionEvent_getY(event i64, index i64) f32
extern "libandroid.so" fn AMotionEvent_getAxisValue(event i64, axis i32, index i64) f32
extern "libandroid.so" fn AInputEvent_getSource(event i64) i32

padButtons = 16
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
padLeftTrigger = 12
padRightTrigger = 13
padLeftStick = 14
padRightStick = 15

# a game pad's key codes (KEYCODE_BUTTON_A...) and the pad's buttons they are
padKeys = [
	(96, padSouth),
	(97, padEast),
	(99, padWest),
	(100, padNorth),
	(102, padLeftShoulder),
	(103, padRightShoulder),
	(108, padStart),
	(109, padSelect),
	(19, padUp),
	(20, padDown),
	(21, padLeft),
	(22, padRight),
	(104, padLeftTrigger),
	(105, padRightTrigger),
	(106, padLeftStick),
	(107, padRightStick)
]

# a joystick's motion (AINPUT_SOURCE_JOYSTICK), apart from the screen's
sourceJoystick = 0x0100_0010

# the axes read, by engine.PadAxis's index, and the hat (the cross as axes): MotionEvent's
# AXIS_X, Y, Z, RZ, LTRIGGER, RTRIGGER, then HAT_X, HAT_Y
axisIds i32[] = [0, 1, 11, 14, 17, 18, 15, 16]
mut axes f64[] = zeros(8)

motionUp = 1   # AMOTION_EVENT_ACTION_UP
motionCancel = 3
motionPointerUp = 6

mut touches f64[] = []   # the fingers' places on the window, 0..1 across and down: x, y pairs

# whether the pad's button (engine.PadButton's index) is held: its key, or for the cross the hat
# leaning its way, for a trigger its axis pulled past half
pub fn isAppPadDown(button i64) bool:
	if button < 0 or button >= padButtons: return false
	for (code, b) in padKeys:
		if b == button and isAppKeyDown(code): return true
	if button == padLeft: return axes[6] < -0.5
	if button == padRight: return axes[6] > 0.5
	if button == padUp: return axes[7] < -0.5
	if button == padDown: return axes[7] > 0.5
	if button == padLeftTrigger: return axes[4] > 0.5
	button == padRightTrigger and axes[5] > 0.5

# where the pad's axis (engine.PadAxis's index) stands
pub fn appPadAxis(axis i64) f64:
	axes[axis] if axis >= 0 and axis < 6 else 0.0

# whether a motion event comes from a game pad's sticks rather than the screen
fn isJoystick(event i64) bool:
	i64(AInputEvent_getSource(event)) & sourceJoystick == sourceJoystick

# the axes a game pad's motion event holds
fn notePadAxes(event i64):
	for k, id in axisIds:
		axes[k] = f64(AMotionEvent_getAxisValue(event, id, 0))

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
