# The window and the input: a Win32 window the GPU draws into (through the RHI's Vulkan surface),
# its messages turned into the state a frame reads (keys held and pressed, the mouse, the wheel,
# the size). One window per program; the engine's other parts draw into it. A scripted run is
# headless (isHeadless): no window at all, the frames drawn offscreen at the window's size, the
# real mouse and keyboard never read, the cursor never taken; its input is the program's script.

import rhi
import win

pub type Window:
	handle i64   # 0 headless
	width i64
	height i64

	# closed where it is dropped, after waiting for the GPU and saving the pipelines
	mut fn drop():
		gpu.waitIdle()
		gpu.savePipelineCache()
		if handle != 0:
			DestroyWindow(handle)

# the C structures the system reads and writes, laid out as C lays them out
extern type WndClassEx:
	size u32 = 80
	style u32 = 32   # CS_OWNDC
	proc i64   # the window procedure's address (DefWindowProcA's until the window exists)
	classExtra i32 = 0
	windowExtra i32 = 0
	instance i64
	icon i64 = 0
	cursor i64
	background i64 = 0
	menuName i64 = 0
	className i64
	iconSmall i64 = 0

extern type Msg:
	window i64 = 0
	message u32 = 0
	wparam i64 = 0
	lparam i64 = 0
	time u32 = 0
	x i32 = 0
	y i32 = 0
	extra u32 = 0

extern type Point:
	x i32
	y i32

extern type Rect:
	left i32
	top i32
	right i32
	bottom i32

extern fn GetModuleHandleA(name i64) i64

extern "user32.dll" fn RegisterClassExA(class WndClassEx) u16
extern "user32.dll" fn SetProcessDpiAwarenessContext(context i64) bool
extern "user32.dll" fn CreateWindowExA(
	exStyle i64,
	className str,
	title str,
	style i64,
	x i64,
	y i64,
	w i64,
	h i64,
	parent i64,
	menu i64,
	instance i64,
	param i64
) i64
extern "user32.dll" fn SetWindowLongPtrA(window i64, index i64, proc fn(i64, i64, i64, i64) i64) i64
extern "user32.dll" fn DefWindowProcA(window i64, message i64, wparam i64, lparam i64) i64
extern "user32.dll" fn ShowWindow(window i64, how i64) bool
extern "user32.dll" fn DestroyWindow(window i64) bool
extern "user32.dll" fn PeekMessageA(mut msg Msg, window i64, first i64, last i64, remove i64) bool
extern "user32.dll" fn TranslateMessage(msg Msg) bool
extern "user32.dll" fn DispatchMessageA(msg Msg) i64
extern "user32.dll" fn AdjustWindowRect(mut rect Rect, style i64, menu bool) bool
extern "user32.dll" fn LoadCursorA(instance i64, name i64) i64
extern "user32.dll" fn SetWindowTextA(window i64, text str) bool
extern "user32.dll" fn GetCursorPos(mut p Point) bool
extern "user32.dll" fn SetCursorPos(x i64, y i64) bool
extern "user32.dll" fn ClientToScreen(window i64, mut p Point) bool
extern "user32.dll" fn ShowCursor(show bool) i32
extern "user32.dll" fn GetForegroundWindow() i64

extern "user32.dll" fn SetCapture(window i64) i64
extern "user32.dll" fn ReleaseCapture() bool
extern "user32.dll" fn SetCursor(cursor i64) i64
extern "user32.dll" fn ClipCursor(rect Rect) bool
extern loaded "ClipCursor" fn unclipCursor(nothing i64) bool
extern "user32.dll" fn RegisterRawInputDevices(devices RawInputDevice, count u32, size u32) bool
extern "user32.dll" fn GetRawInputData(
	input i64,
	command u32,
	mut data RawMouse,
	mut size RawSize,
	headerSize u32
) u32

# a device whose raw input the window asks for (the mouse: usage page 1, usage 2)
extern type RawInputDevice:
	usagePage u16 = 1
	usage u16 = 2
	flags u32 = 0
	target i64

# a RAWINPUT holding a mouse's motion: its header (24 bytes), then RAWMOUSE
extern type RawMouse:
	kind u32 = 0
	size u32 = 0
	device i64 = 0
	wparam i64 = 0
	flags u16 = 0   # 1: absolute positions (a tablet, a remote desktop)
	pad u16 = 0
	buttonFlags u16 = 0
	buttonData u16 = 0
	rawButtons u32 = 0
	lastX i32 = 0
	lastY i32 = 0
	extra u32 = 0

extern type RawSize:
	bytes u32

# ---------- the input, as the window procedure leaves it ----------

mut keysDown bool[] = []
mut keysPressed bool[] = []   # went down since the last frame began
mut mouseX = 0
mut mouseY = 0
mut mouseButtons bool[] = []   # left, right, middle
mut buttonsPressed bool[] = []
mut wheelRaw = 0   # the wheel's turn since the last frame began, 120 a notch
mut wheelFrame = 0   # the same, as the frame reads it
mut cursorHidden = false   # the system's cursor hidden over the window's drawing
mut headless = false   # no window: the system's input and cursor never touched
mut locked = false   # the window holds the mouse still
mut lockedAt = Point(x = 0, y = 0)   # where the cursor stays while it is held (screen pixels)
mut rawX = 0   # the mouse's own motion since the last frame began (counts)
mut rawY = 0
mut rawSeen = false   # the mouse sends raw motion (else held by moving it back)
mut closing = false
mut resizedW = 0
mut resizedH = 0
mut captured = false   # the window holds the mouse
mut lookX = 0   # the mouse's motion over the last frame while captured
mut lookY = 0

# a key of the keyboard
pub type Key:
	Char(code i64)   # a letter or a digit of the main row, by its character: .Char('W'), .Char('1')
	F(n i64)   # a function key, F1 to F12: .F(1)
	Left
	Up
	Right
	Down
	Space
	Escape
	Enter
	Shift   # either Shift
	Ctrl   # either Ctrl
	Raw(code i64)   # a key by its virtual-key code, any key of the keyboard
	Backspace
	Tab

	# its virtual-key code (a letter's is its capital's)
	fn code():
		match self:
			Char(c): c - 32 if c >= 'a' and c <= 'z' else c
			F(n): 111 + n
			Left: 37
			Up: 38
			Right: 39
			Down: 40
			Space: 32
			Escape: 27
			Enter: 13
			Shift: 16
			Ctrl: 17
			Raw(c): c
			Backspace: 8
			Tab: 9

fn engineWindowProc(window i64, message i64, wparam i64, lparam i64):
	if message == 16:   # WM_CLOSE: the program decides
		closing = true
		return 0
	if message == 256 or message == 260:   # WM_KEYDOWN, WM_SYSKEYDOWN
		k = wparam & 255
		if not keysDown[k]:
			keysPressed[k] = true
		keysDown[k] = true
		return 0
	if message == 257 or message == 261:   # WM_KEYUP, WM_SYSKEYUP
		keysDown[wparam & 255] = false
		return 0
	if message == 512:   # WM_MOUSEMOVE
		mouseX = lowWord(lparam)
		mouseY = highWord(lparam)
		return 0
	if message >= 513 and message <= 520:   # the buttons, down and up
		b = 0 if message <= 514 else 1 if message <= 517 else 2
		down = message in [513, 516, 519]
		if down and not mouseButtons[b]:
			buttonsPressed[b] = true
		mouseButtons[b] = down
		# the window keeps the mouse while a button is held, so a drag that leaves it still
		# moves, and its release is not lost
		if down:
			SetCapture(window)
		elif not mouseButtons[0] and not mouseButtons[1] and not mouseButtons[2]:
			ReleaseCapture()
		return 0
	if message == 522:   # WM_MOUSEWHEEL: 120 per notch
		wheelRaw += highWord(wparam)
		return 0
	if message == 255:   # WM_INPUT: the mouse's own motion
		m = RawMouse()
		size = RawSize(bytes = 48)
		if GetRawInputData(lparam, 0x1000_0003, m, size, 24) != 0xFFFF_FFFF and m.kind == 0 and
			(m.flags & 1) == 0:
			rawX += m.lastX
			rawY += m.lastY
			rawSeen = true
		return DefWindowProcA(window, message, wparam, lparam)
	if message == 32 and cursorHidden and (lparam & 65_535) == 1:   # WM_SETCURSOR over the drawing
		SetCursor(0)
		return 1
	if message == 8:   # WM_KILLFOCUS: the held mouse let go
		if locked:
			unclipCursor(0)
		for b in 0..3:
			mouseButtons[b] = false
		return DefWindowProcA(window, message, wparam, lparam)
	if message == 5:   # WM_SIZE
		resizedW = lparam & 65_535
		resizedH = lparam.bits(16, 16)
		return 0
	DefWindowProcA(window, message, wparam, lparam)

# the signed 16 bits of a word's low and high halves (coordinates may be negative)
fn lowWord(v i64):
	w = v & 65_535
	if w >= 32_768: w - 65_536
	else: w

fn highWord(v i64):
	lowWord(v >> 16)

# ---------- the window ----------

# Whether the program runs headless, with no one at the screen: a scripted run (`--frames`,
# `--shot`, `--replay` or `--bench`) or ZAP_RUN has headless. It draws the same pictures as windowed.
pub fn isHeadless() bool:
	headlessWord().on() or ["--frames", "--shot", "--replay", "--bench"].any(it in args)

# Opens a window whose drawing area is width x height, and the GPU that draws into it (vsync
# on); headless, only the GPU, drawing offscreen at that size. Stops the program with a message
# when the system or the driver refuses.
pub fn openWindow(title str, width i64, height i64) Window:
	keysDown = zeros(256)
	keysPressed = zeros(256)
	mouseButtons = [false, false, false]
	buttonsPressed = [false, false, false]
	resizedW = width
	resizedH = height
	headless = isHeadless()
	w = Window(handle = 0 if headless else newWindow(title, width, height), width, height)
	w.openGpu()
	w

# the system's window, shown, its drawing area width x height
fn newWindow(title str, width i64, height i64):
	# the window's pixels are the screen's: without this, Windows scaled to 125% or more draws
	# the window at its size and stretches the picture, blurring every edge and letter
	SetProcessDpiAwarenessContext(-4)   # DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
	instance = GetModuleHandleA(0)
	className = "ZapEngineWindow\0"
	cls = WndClassEx(
		proc = win.loadFunction("user32.dll", "DefWindowProcA"),
		instance,
		cursor = LoadCursorA(0, 32_512),
		className = sPtr(className))
	if RegisterClassExA(cls) == 0:
		fail("the window class could not be registered")
	style = 0x00CF_0000   # WS_OVERLAPPEDWINDOW
	rect = Rect(left = 0, top = 0, right = i32(width), bottom = i32(height))
	AdjustWindowRect(rect, style, false)
	handle = CreateWindowExA(
		0,
		className,
		"{title}\0",
		style,
		100,
		100,
		rect.right - rect.left,
		rect.bottom - rect.top,
		0,
		0,
		instance,
		0
	)
	if handle == 0:
		fail("the window could not be created")
	SetWindowLongPtrA(handle, -4, engineWindowProc)   # GWLP_WNDPROC: the engine's procedure
	# the mouse's own motion as WM_INPUT, for a mouse held still (lockMouse)
	RegisterRawInputDevices(RawInputDevice(target = handle), 1, 16)
	bindExtern(unclipCursor, win.loadFunction("user32.dll", "ClipCursor"))
	ShowWindow(handle, 5)
	handle

# The messages that arrived since the last call, then the state a frame reads: whether the
# window should go on (false once it was asked to close), its size now.
pub fn pollEvents(mut w Window) bool:
	for k in 0..256:
		keysPressed[k] = false
	for b in 0..3:
		buttonsPressed[b] = false
	wheelRaw = 0
	rawX = 0
	rawY = 0
	msg = Msg()
	while not headless and PeekMessageA(msg, 0, 0, 0, 1):
		TranslateMessage(msg)
		DispatchMessageA(msg)
	w.width = resizedW
	w.height = resizedH
	wheelFrame = wheelRaw
	w.readCapturedMouse()
	w.readLockedMouse()
	not closing

# shows the frame drawn (waits for the screen's refresh when vsync is on)
pub fn present(w Window):
	_ = w
	endGpuFrame()

pub fn setTitle(w Window, title str):
	if w.handle != 0:
		SetWindowTextA(w.handle, "{title}\0")

# ---------- the input a frame reads ----------

# whether the key is held now
pub fn isKeyDown(k Key) bool:
	c = k.code()
	c >= 0 and c < 256 and keysDown.len == 256 and keysDown[c]

# -1, 0 or 1 from a pair of opposed keys: 1 while only `positive` is held, -1 while only
# `negative` is (keyAxis(.Char('D'), .Char('A')) for a step to the right)
pub fn keyAxis(positive Key, negative Key) f32:
	(1.0 if positive.isKeyDown() else 0.0) - (1.0 if negative.isKeyDown() else 0.0)

# whether the key went down since the frame began (once per press)
pub fn isKeyPressed(k Key) bool:
	c = k.code()
	c >= 0 and c < 256 and keysPressed.len == 256 and keysPressed[c]

# pixels from the window's top left
pub fn mousePosition() IVec2:
	IVec2(i32(mouseX), i32(mouseY))

# a game pad's button, a console's: the face buttons by their place (South is Nintendo's B,
# Xbox's A), the shoulders, the two in the middle, the cross, the triggers (ZL and ZR as buttons)
# and the sticks pressed in
pub type PadButton:
	South
	East
	West
	North
	LeftShoulder
	RightShoulder
	Start
	Select
	Up
	Down
	Left
	Right
	LeftTrigger
	RightTrigger
	LeftStick
	RightStick

	# its place in the order above
	fn index():
		match self:
			South: 0
			East: 1
			West: 2
			North: 3
			LeftShoulder: 4
			RightShoulder: 5
			Start: 6
			Select: 7
			Up: 8
			Down: 9
			Left: 10
			Right: 11
			LeftTrigger: 12
			RightTrigger: 13
			LeftStick: 14
			RightStick: 15

# every pad button, in their order
pub fn padButtons() PadButton[]:
	[
		.South,
		.East,
		.West,
		.North,
		.LeftShoulder,
		.RightShoulder,
		.Start,
		.Select,
		.Up,
		.Down,
		.Left,
		.Right,
		.LeftTrigger,
		.RightTrigger,
		.LeftStick,
		.RightStick
	]

# a game pad's analog input: the sticks' directions (-1..1, y down) and the triggers' pull (0..1)
pub type PadAxis:
	LeftX
	LeftY
	RightX
	RightY
	LeftTrigger
	RightTrigger

	# its place in the order above
	fn index():
		match self:
			LeftX: 0
			LeftY: 1
			RightX: 2
			RightY: 3
			LeftTrigger: 4
			RightTrigger: 5

# whether a game pad's button is held now (a pad an app is given; a window of Windows reads none
# yet)
pub fn isPadDown(b PadButton) bool:
	b.index() < 0

# where a game pad's axis stands now (0 without a pad: a window of Windows reads none yet)
pub fn padAxis(a PadAxis) f32:
	f32(a.index()) * 0.0

# whether the program's screen is touched rather than clicked (an app's)
pub fn hasTouchScreen() bool:
	false

# the fingers on a touch screen, 0..1 across and down from its top left (a window of Windows has
# none)
pub fn touches() Vec2[]:
	[]

# whether the button is held now: 0 left, 1 right, 2 middle
pub fn isMouseDown(b i64) bool:
	b >= 0 and b < 3 and mouseButtons.len == 3 and mouseButtons[b]

# whether the button went down since the frame began (once per press)
pub fn isMousePressed(b i64) bool:
	b >= 0 and b < 3 and buttonsPressed.len == 3 and buttonsPressed[b]

# How far the wheel turned since the last frame began, in notches and their fractions (a smooth
# wheel or a touchpad turns by fractions); up is positive.
pub fn wheelTurn() f32:
	f32(wheelFrame) / 120.0

# The system's cursor hidden (or shown again) over the window's drawing, for a program that
# draws a cursor of its own at mousePosition.
pub fn hideCursor(hidden bool):
	cursorHidden = hidden
	if hidden and not headless:
		SetCursor(0)

# ---------- the mouse held still (a third-person camera's drag) ----------

# Holds the cursor where it is (hidden, unable to move, its motion still read with mouseMotion,
# from the mouse itself, so a drag never meets the screen's edge) or lets it go, where it was.
pub fn lockMouse(w Window, on bool):
	_ = w
	if on == locked: return
	locked = on
	lookX = 0
	lookY = 0
	if headless: return
	if on:
		p = Point(x = 0, y = 0)
		GetCursorPos(p)
		lockedAt = p
		ShowCursor(false)
		if rawSeen:
			clipToLock()
	else:
		unclipCursor(0)
		SetCursorPos(lockedAt.x, lockedAt.y)
		ShowCursor(true)

pub fn isMouseLocked() bool:
	locked

fn clipToLock():
	ClipCursor(
		Rect(left = lockedAt.x, top = lockedAt.y, right = lockedAt.x + 1, bottom = lockedAt.y + 1)
	)

# the held mouse's motion over the last frame: its own counts when it sends them, else how far
# the cursor went before it was put back
fn readLockedMouse(w Window):
	if not locked: return
	if headless or GetForegroundWindow() != w.handle:
		lookX = 0
		lookY = 0
		return
	if rawSeen:
		clipToLock()
		lookX = rawX
		lookY = rawY
		return
	p = Point(x = 0, y = 0)
	GetCursorPos(p)
	lookX = p.x - lockedAt.x
	lookY = p.y - lockedAt.y
	SetCursorPos(lockedAt.x, lockedAt.y)

# ---------- the captured mouse (a first-person camera's look) ----------

# Takes the mouse (hidden, held at the window's center, its motion read with mouseMotion) or
# lets it go. While the window is not in front the mouse stays free.
pub fn captureMouse(w Window, on bool):
	if on == captured: return
	captured = on
	lookX = 0
	lookY = 0
	if headless: return
	ShowCursor(not on)
	if on:
		w.centerCursor()

pub fn isMouseCaptured() bool:
	captured

# how far the captured or held mouse moved over the last frame, in pixels (x right, y down)
pub fn mouseMotion() IVec2:
	IVec2(i32(lookX), i32(lookY))

fn windowCenter(w Window):
	p = Point(x = i32(w.width / 2), y = i32(w.height / 2))
	ClientToScreen(w.handle, p)
	p

fn centerCursor(w Window):
	c = w.windowCenter()
	SetCursorPos(c.x, c.y)

fn readCapturedMouse(w Window):
	lookX = 0
	lookY = 0
	if not captured or headless or GetForegroundWindow() != w.handle: return
	p = Point(x = 0, y = 0)
	GetCursorPos(p)
	c = w.windowCenter()
	lookX = p.x - c.x
	lookY = p.y - c.y
	w.centerCursor()

# the program's module (its HINSTANCE), for the system calls that want it
pub fn moduleHandle() i64:
	GetModuleHandleA(0)
