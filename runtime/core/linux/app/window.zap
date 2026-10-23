# An app's window and keys (runtime/core/linux/app/): the window and the input queue the system
# hands the activity, kept by the entry's callbacks in slots 15 and 16 (compiler/targets/android/
# entry.zap) and held while used (slot 17, which the callbacks wait on before the system takes
# them back). A picture is copied into the window's buffer, the buffer sized to the window's shape
# with the picture in its middle on black, so the system's scaling keeps its proportions; the
# keys are read from the queue, each held while it is down, and the fingers' places and a game
# pad's sticks (input.zap).

extern "libandroid.so" fn ANativeWindow_getWidth(window i64) i32
extern "libandroid.so" fn ANativeWindow_getHeight(window i64) i32
extern "libandroid.so" fn ANativeWindow_setBuffersGeometry(
	window i64, width i64, height i64, format i64
) i32
extern "libandroid.so" fn ANativeWindow_lock(window i64, buffer u8[], dirty i64) i32
extern "libandroid.so" fn ANativeWindow_unlockAndPost(window i64) i32
extern "libandroid.so" fn AInputQueue_getEvent(queue i64, event u8[]) i32
extern "libandroid.so" fn AInputQueue_preDispatchEvent(queue i64, event i64) i32
extern "libandroid.so" fn AInputQueue_finishEvent(queue i64, event i64, handled i64)
extern "libandroid.so" fn AInputEvent_getType(event i64) i32
extern "libandroid.so" fn AKeyEvent_getAction(event i64) i32
extern "libandroid.so" fn AKeyEvent_getKeyCode(event i64) i32
extern "libandroid.so" fn ANativeActivity_finish(activity i64)
extern "libandroid.so" fn ANativeWindow_setFrameRate(window i64, rate f32, compatibility i8) i32
extern "libc.so" "__system_property_get" fn systemProperty(name str, value u8[]) i32

slotWindow = 15
slotQueue = 16
slotHeld = 17
slotEnded = 18
slotResized = 19
backKey = 4   # AKEYCODE_BACK: the activity ends

# the keys the system acts on, left to it: volume up, down and mute, power, camera, the headset's
# button, play and pause, the microphone's mute, brightness down and up
systemKeys = [24, 25, 164, 26, 27, 79, 85, 91, 220, 221]

windowFormatRgbx = 2   # WINDOW_FORMAT_RGBX_8888: a pixel's red, green, blue bytes, then one unused
inputKey = 1   # AINPUT_EVENT_TYPE_KEY
inputMotion = 2   # AINPUT_EVENT_TYPE_MOTION: a finger on the screen
keyDownAction = 0   # AKEY_EVENT_ACTION_DOWN

mut keysHeld bool[] = []   # by Android's key code
mut shownWidth = 0   # the buffer's size last set, for the window last shown in
mut shownHeight = 0
mut shownWindow = 0
mut shownPicture = 0, 0   # the picture's size the buffer was last set for
mut windowWidth = 0   # the window's own size
mut windowHeight = 0

# Shows the picture (RGBA bytes, rows from the top) in the app's window and reads the keys; waits
# while the app has no window (it is away from the screen), and ends the program once the activity
# has ended.
pub fn appShowPixels(rgba u8[], width i64, height i64):
	while gv(slotWindow) == 0 and gv(slotEnded) == 0:
		sleepMs(50)
	if gv(slotEnded) != 0: exit(0)
	gset(slotHeld, 1)
	readAppKeys()
	window = gv(slotWindow)
	if window != 0: drawInto(window, rgba, width, height)
	gset(slotHeld, 0)

mut framesPerSecond = 0.0   # the rate the program shows pictures at, 0 when it did not say

# ANativeWindow_setFrameRate's first Android, and its FIXED_SOURCE: the pictures come at that rate
frameRateSdk = 30
fixedSource = 1

# The rate the program shows pictures at, which the screen is asked to match (so each picture stays
# up as long as the next) on an Android that can.
pub fn appSetFrameRate(perSecond f64):
	framesPerSecond = perSecond
	shownWindow = 0   # (given to the window as it is set up again)

# the system's Android version (its SDK level), 0 when it cannot be read
fn androidSdk() i64:
	value = zeroBytes(92)   # PROP_VALUE_MAX
	length = systemProperty("ro.build.version.sdk", value)
	i64.parse(value[..i64(length).clamp(0, len)].text()) ?? 0

# the window's size in pixels, 0 by 0 before it is first shown
pub fn appScreenSize() (i64, i64):
	(windowWidth, windowHeight)

# whether the key (Android's key code) is down
pub fn isAppKeyDown(code i64) bool:
	code >= 0 and code < keysHeld.len and keysHeld[code]

fn drawInto(window i64, rgba u8[], width i64, height i64):
	if window != shownWindow or gv(slotResized) != 0 or shownPicture != (width, height):
		gset(slotResized, 0)
		shownPicture = width, height
		_ = ANativeWindow_setBuffersGeometry(window, 0, 0, windowFormatRgbx)   # the window's own size
		ww = i64(ANativeWindow_getWidth(window))
		wh = i64(ANativeWindow_getHeight(window))
		if ww <= 0 or wh <= 0: return
		windowWidth = ww
		windowHeight = wh
		shownWidth = width.max((height * ww + wh - 1) / wh)
		shownHeight = height.max((width * wh + ww - 1) / ww)
		_ = ANativeWindow_setBuffersGeometry(window, shownWidth, shownHeight, windowFormatRgbx)
		if framesPerSecond > 0.0 and androidSdk() >= frameRateSdk:
			_ = ANativeWindow_setFrameRate(window, f32(framesPerSecond), i8(fixedSource))
		shownWindow = window
	bw = shownWidth
	bh = shownHeight
	buffer = zeroBytes(48)   # ANativeWindow_Buffer: width, height, stride, format, bits, reserved
	if ANativeWindow_lock(window, buffer, 0) < 0: return
	stride = i64(buffer.u32le(8))
	bits = buffer.i64le(16)
	rows = i64(buffer.u32le(4)).min(bh)
	columns = i64(buffer.u32le(0)).min(bw)
	left = (columns - width) / 2
	top = (rows - height) / 2
	__memset(bits, 0, stride * rows * 4)
	from = __ld64(hdr(rgba))
	for y in 0..height.min(rows - top):
		__memcpy(
			bits + ((top + y) * stride + left) * 4,
			from + y * width * 4,
			width.min(columns) * 4
		)
	_ = ANativeWindow_unlockAndPost(window)

# the queue's events taken: a key's down or up noted, every event finished
fn readAppKeys():
	queue = gv(slotQueue)
	if queue == 0: return
	if keysHeld.isEmpty: keysHeld = fill(512, false)
	slot = zeroBytes(8)
	while AInputQueue_getEvent(queue, slot) >= 0:
		event = slot.i64le(0)
		if AInputQueue_preDispatchEvent(queue, event) != 0: continue
		handled = 0
		kind = AInputEvent_getType(event)
		if kind == inputMotion:
			if isPadMotion(event):
				notePadMotion(event)
			else:
				noteTouches(event, windowWidth, windowHeight)
			handled = 1
		if kind == inputKey:
			code = i64(AKeyEvent_getKeyCode(event))
			if code == backKey: ANativeActivity_finish(gv(slotActivity))
			if code >= 0 and code < keysHeld.len and not (code in systemKeys):
				keysHeld[code] = AKeyEvent_getAction(event) == keyDownAction
				handled = 1
		AInputQueue_finishEvent(queue, event, handled)
