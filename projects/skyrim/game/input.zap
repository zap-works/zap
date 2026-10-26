# The player's input of a frame: the keys and the mouse as the window reads them, or, for a run
# that needs no one at the screen, replayed from a script (engine/replay.zap: `--replay
# "10:down w;40:down shift;60:drag 300 0;90:up w"`): at frame N, `down k` and `up k` press and
# release a key (a letter, shift, tab, esc, enter, up, down, left or right) or a mouse button
# (`lmb`, `rmb`), `drag dx dy` moves the mouse that frame (pixels), `move x y` puts the pointer at
# a window's pixel for the menus and `click` presses its left button there for that frame.

import engine

pub type Input:
	forward f32   # 1 while W alone is held, -1 while S alone is
	right f32   # 1 while D alone is held, -1 while A alone is
	run bool   # Shift held
	look IVec2   # the mouse's motion this frame (pixels, x right, y down)
	draw bool = false   # R went down this frame: draw or sheathe the weapon
	sneak bool = false   # the Sneak key went down this frame: start or stop sneaking
	attack bool = false   # the left button is held
	block bool = false   # the right button is held
	pressed engine.Key[] = []   # the keys that went down this frame
	pointer IVec2 = IVec2(-1, -1)   # where the pointer is over the window (pixels), for the menus
	clicking bool = false   # the left button held
	rightPressed bool = false   # the right button went down this frame
	leftPressed bool = false   # the left button went down this frame

pub type InputSource:
	steps engine.ReplayStep[]
	held engine.Key[] = []   # the keys the script holds
	buttons str[] = []   # the mouse buttons it holds, "lmb" and "rmb"
	pointer IVec2 = IVec2(-1, -1)   # where the script put the pointer

pub fn newInputSource() InputSource:
	InputSource(steps = engine.replaySteps())

pub fn isScripted(s InputSource) bool:
	not s.steps.isEmpty

# the keys a menu or the game's commands read as they go down
menuKeys engine.Key[] = [.Tab, .Escape, .Enter, .Up, .Down, .Left, .Right, .Char('E'), .Char('I'),
	.Char('T'), .Char('R'), .Char('F'), .Char('Q'), .Char('W'), .Char('A'), .Char('S'), .Char('D'),
	.Char('1'), .Char('2'), .Char('3'), .Char('4'), .Char('5'), .Char('6'), .Char('7'), .Char('8'),
	.F(5), .F(9)]

# The keys of the player's own controls and the keys whose press the menus and commands watch: the
# defaults (WASD, Shift, R), or the player's remapped map (interface/inputMap.zap).
pub type PlayerKeys:
	forward engine.Key = .Char('W')
	back engine.Key = .Char('S')
	left engine.Key = .Char('A')
	right engine.Key = .Char('D')
	run engine.Key = .Shift
	draw engine.Key = .Char('R')
	sneak engine.Key = .Ctrl   # controlmap.txt's Sneak, the left Ctrl
	watch engine.Key[] = menuKeys

fn keyNamed(name str) engine.Key:
	match name.lower():
		"shift": .Shift
		"ctrl": .Ctrl
		"tab": .Tab
		"esc", "escape": .Escape
		"enter": .Enter
		"up": .Up
		"down": .Down
		"left": .Left
		"right": .Right
		"f5": .F(5)
		"f9": .F(9)
		_: .Char(name.upper()[0])

fn isButton(name str):
	name == "lmb" or name == "rmb"

fn axisOf(held engine.Key[], positive engine.Key, negative engine.Key) f32:
	(1.0 if positive in held else 0.0) - (1.0 if negative in held else 0.0)

# the mouse's motion over the frame while it looks: captured after a click, or held by a right
# drag (not while a weapon is drawn: the right button blocks then)
pub fn lookMotion(win engine.Window, armed bool) IVec2:
	if engine.isMouseCaptured(): return engine.mouseMotion()
	if engine.isMousePressed(1) and not armed: win.lockMouse(true)
	if engine.isMouseLocked():
		if not engine.isMouseDown(1):
			win.lockMouse(false)
			return IVec2(0, 0)
		return engine.mouseMotion()
	if engine.isMousePressed(0): win.captureMouse(true)
	IVec2(0, 0)

fn scriptedInput(mut s InputSource, frame i64, keys PlayerKeys):
	look = IVec2(0, 0)
	draw = false
	sneak = false
	rightPressed = false
	leftPressed = false
	pressed = []
	for st in s.steps:
		if st.frame != frame: continue
		word = st.words[0] if not st.words.isEmpty else " "
		key = keyNamed(word)
		if st.verb == "down": pressed.push(key)
		if isButton(word):
			if st.verb == "down" and word == "rmb": rightPressed = true
			if st.verb == "down" and word == "lmb": leftPressed = true
			if st.verb == "down" and word not in s.buttons:
				s.buttons.push(word.copy())
			elif st.verb == "up":
				s.buttons = s.buttons.filter(it != word)
		elif st.verb == "down" and key not in s.held:
			s.held.push(key)
			draw = draw or key == keys.draw
			sneak = sneak or key == keys.sneak
		elif st.verb == "up":
			s.held = s.held.filter(it != key)
		elif st.verb == "drag":
			look += IVec2(i32(st.number(0)), i32(st.number(1)))
		elif st.verb == "move":
			s.pointer = IVec2(i32(st.number(0)), i32(st.number(1)))
	Input(
		forward = axisOf(s.held, keys.forward, keys.back),
		right = axisOf(s.held, keys.right, keys.left),
		run = keys.run in s.held,
		look,
		draw,
		sneak,
		attack = "lmb" in s.buttons,
		block = "rmb" in s.buttons,
		pressed,
		pointer = s.pointer,
		clicking = s.steps.any(.frame == frame and .verb == "click"),
		rightPressed,
		leftPressed
	)

# the input of frame `frame`: the script's when there is one, else the window's; `armed` while a
# weapon is drawn; the mouse moves the pointer rather than the view while a menu is open
pub fn readInput(
	mut s InputSource,
	frame i64,
	win engine.Window,
	armed bool,
	menuOpen bool,
	keys PlayerKeys
) Input:
	if s.isScripted(): return s.scriptedInput(frame, keys)
	if menuOpen and engine.isMouseCaptured(): win.captureMouse(false)
	Input(
		forward = keys.forward.keyAxis(keys.back),
		right = keys.right.keyAxis(keys.left),
		run = keys.run.isKeyDown(),
		look = IVec2(0, 0) if menuOpen else win.lookMotion(armed),
		draw = keys.draw.isKeyPressed(),
		sneak = keys.sneak.isKeyPressed(),
		attack = engine.isMouseDown(0),
		block = armed and engine.isMouseDown(1),
		pressed = keys.watch.filter(.isKeyPressed()),
		pointer = engine.mousePosition(),
		clicking = engine.isMouseDown(0),
		rightPressed = engine.isMousePressed(1),
		leftPressed = engine.isMousePressed(0)
	)
