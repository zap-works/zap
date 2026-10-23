# An Android app's window (engine/window.zap's, in an app): the app's own, which the system hands
# it and takes back while the app is away from the screen (runtime/system/linux/app/window.zap),
# held while the GPU draws into it through the RHI's Android surface, which is made again on the
# window the app comes back with. It fills the screen, so its size is the screen's whatever the
# program asks. Headless, only the GPU, drawing offscreen.

pub fn openWindow(title str, width i64, height i64) Window:
	_ = title
	headless = isHeadless()
	w = Window(handle = 0, width, height)
	if not headless:
		window, _ = appHoldWindow()
		w.handle = window
		w.takeWindowSize()
	w.openGpu()
	w

# The window held (waiting while the app is away from the screen), the frames moved to the one
# the app came back with, its size now; the program ends with the activity.
pub fn pollEvents(mut w Window) bool:
	if headless: return true
	window, fresh = appHoldWindow()
	if fresh:
		gpu.setWindow(window, 0)
		w.handle = window
	w.takeWindowSize()
	true

fn takeWindowSize(mut w Window):
	width, height = appWindowSize()
	w.width = width
	w.height = height

# (an app's window has no title, cursor or mouse)
pub fn setTitle(w Window, title str):
	_ = w
	_ = title

pub fn hideCursor(hidden bool):
	cursorHidden = hidden

pub fn lockMouse(w Window, on bool):
	_ = w
	locked = on

pub fn captureMouse(w Window, on bool):
	_ = w
	captured = on

# the window is the system's, let go and never destroyed by the app
fn destroyWindow(window i64) bool:
	_ = window
	appReleaseWindow()
	true

# (the RHI's Android surface needs no module)
pub fn moduleHandle() i64:
	0
