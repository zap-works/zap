# An app's window and keys (runtime/core/linux/app/): the window and the input queue the system
# hands the activity, kept by the entry's callbacks in slots 15 and 16 (compiler/targets/android/
# entry.zap) and held while used (slot 17, which the callbacks wait on before the system takes
# them back). The engine's GPU draws into the window (engine/linux/app/window.zap), holding it
# until the system takes it back; the keys are read from the queue, each held while it is down, and the fingers'
# places and a game pad's sticks (input.zap). A thread of its own reads the queue, so that the app
# answers the system while a frame of the program takes seconds; the program reads what it noted.

extern "libandroid.so" fn ANativeWindow_getWidth(window i64) i32
extern "libandroid.so" fn ANativeWindow_getHeight(window i64) i32
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
slotReading = 20   # 1 while the input thread uses the queue (the entry's callback waits on it)
backKey = 4   # AKEYCODE_BACK: the activity ends

# the keys the system acts on, left to it: volume up, down and mute, power, camera, the headset's
# button, play and pause, the microphone's mute, brightness down and up
systemKeys = [24, 25, 164, 26, 27, 79, 85, 91, 220, 221]

inputKey = 1   # AINPUT_EVENT_TYPE_KEY
inputMotion = 2   # AINPUT_EVENT_TYPE_MOTION: a finger on the screen
keyDownAction = 0   # AKEY_EVENT_ACTION_DOWN

mut keysHeld bool[] = []   # by Android's key code
mut windowHeld = 0   # the window the program holds, 0 none
mut windowWidth = 0   # the window's own size
mut windowHeight = 0

# The app's window, held from here until the system takes it back (its callback waits on the
# hold, so the program stops drawing into it first) or appReleaseWindow: while it is being taken
# back, or the app has none (it is away from the screen), the hold is let go and the program waits
# for the next; the program ends once the activity has ended. The window, and whether it is
# another than the one held before (the system may hand the same address again); its size noted,
# the keys read. (The input queue is taken back after the window, when the hold is let go.)
pub fn appHoldWindow() (i64, bool):
	window = gv(slotWindow)
	fresh = window == 0 or window != windowHeld
	while window == 0 or window != windowHeld:
		gset(slotHeld, 0)
		while gv(slotWindow) == 0 and gv(slotEnded) == 0:
			sleepMs(50)
		if gv(slotEnded) != 0: exit(0)
		gset(slotHeld, 1)
		window = gv(slotWindow)
		windowHeld = window
	if fresh or gv(slotResized) != 0:
		gset(slotResized, 0)
		windowWidth = i64(ANativeWindow_getWidth(window))
		windowHeight = i64(ANativeWindow_getHeight(window))
		if framesPerSecond > 0.0 and androidSdk() >= frameRateSdk:
			_ = ANativeWindow_setFrameRate(window, f32(framesPerSecond), i8(fixedSource))
	startAppInput()
	(window, fresh)

# the window held let go, for the system to take back (the program draws into it no more)
pub fn appReleaseWindow():
	windowHeld = 0
	gset(slotHeld, 0)

mut framesPerSecond = 0.0   # the rate the program shows pictures at, 0 when it did not say

# ANativeWindow_setFrameRate's first Android, and its FIXED_SOURCE: the pictures come at that rate
frameRateSdk = 30
fixedSource = 1

# The rate the program shows pictures at, which the screen is asked to match (so each picture stays
# up as long as the next) on an Android that can.
pub fn appSetFrameRate(perSecond f64):
	framesPerSecond = perSecond
	if windowHeld != 0 and androidSdk() >= frameRateSdk:
		_ = ANativeWindow_setFrameRate(windowHeld, f32(perSecond), i8(fixedSource))

# the system's Android version (its SDK level), 0 when it cannot be read
fn androidSdk() i64:
	value = zeroBytes(92)   # PROP_VALUE_MAX
	length = systemProperty("ro.build.version.sdk", value)
	i64.parse(value[..i64(length).clamp(0, len)].text()) ?? 0

# the window's size in pixels, 0 by 0 before it is first held
pub fn appWindowSize() (i64, i64):
	(windowWidth, windowHeight)

# whether the key (Android's key code) is down
pub fn isAppKeyDown(code i64) bool:
	code >= 0 and code < keysHeld.len and keysHeld[code]

mut inputStarted = false
inputPollMs = 4

# the input thread started, once
fn startAppInput():
	if inputStarted: return
	inputStarted = true
	keysHeld = fill(512, false)
	if not startThread(():
		readAppInput()
	):
		fail("cannot create the input thread")

# The input thread's life: the queue's events taken as they come. The queue is in use from the
# mark in slot 20 until the events are read: its callback, taking it back, waits for the mark to
# go, and the queue read after the mark is the one the callback has not taken.
fn readAppInput():
	loop:
		gset(slotReading, 1)
		queue = fenced(gv(slotQueue))
		if queue != 0: readAppKeys(queue)
		gset(slotReading, fenced(0))
		sleepMs(inputPollMs)

# the queue's events taken: a key's down or up noted, every event finished
fn readAppKeys(queue i64):
	slot = zeroBytes(8)
	while AInputQueue_getEvent(queue, slot) >= 0:
		event = slot.i64le(0)
		if AInputQueue_preDispatchEvent(queue, event) != 0: continue
		handled = 0
		kind = AInputEvent_getType(event)
		if kind == inputMotion:
			if isPadMotion(event): notePadMotion(event)
			else: noteTouches(event, windowWidth, windowHeight)
			handled = 1
		if kind == inputKey:
			code = i64(AKeyEvent_getKeyCode(event))
			if code == backKey: ANativeActivity_finish(gv(slotActivity))
			if code >= 0 and code < keysHeld.len and not (code in systemKeys):
				keysHeld[code] = AKeyEvent_getAction(event) == keyDownAction
				handled = 1
		AInputQueue_finishEvent(queue, event, handled)
