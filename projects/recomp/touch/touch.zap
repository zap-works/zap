# A console's picture with touch controls over it, for a phone: the picture scaled up by a whole
# number into a frame of the screen's shape (at its height, the margins beside it; look.zap), the
# controls (controls.zap) laid over it, and a menu of the program's choices (save, load...) that
# MENU opens. The program shows the frame and reads the held buttons and the choice made.

import engine
import image

pub type Overlay:
	items str[]   # the menu's choices
	frame image.Image
	held bool[]   # by engine.PadButton's index
	shown bool = true   # the pad's controls (PAD hides them, a game pad's first press too)
	menuOpen bool = false
	touched bool[] = []   # the controls fingers were on at the frame before: a tap acts as it lands
	fingers i64 = 0   # how many were on the screen then
	stickX f64 = 0.0   # the knob from the stick's centre
	stickY f64 = 0.0
	chosen i64 = -1
	gamePadSeen bool = false
	levelName str = ""   # the menu's level row (the volume, say), none when ""
	level f64 = 1.0   # 0..1
	levelChanged bool = false
	dragging bool = false   # a finger on the level's bar, which it follows
	look Look = Look()   # how the picture is drawn (look.zap)

# an overlay whose menu offers the items
pub fn newOverlay(items str[]) Overlay:
	Overlay(
		items = items.copy(),
		frame = image.fromBytes(1, 1, fill(4, 0)),
		held = fill(engine.padButtons().len, false)
	)

# Makes the frame for the picture on a screen of that size (0 by 0 when not yet known): the
# picture scaled, the touches read, the controls or the menu drawn.
pub fn compose(mut o Overlay, picture image.Image, screen IVec2):
	k = (screen.y / picture.height).clamp(1, 3)
	fh = picture.height * k
	fw = picture.width * k
	if screen.y > 0: fw = fw.max(fh * screen.x / screen.y)
	if o.frame.width != fw or o.frame.height != fh:
		o.frame = image.fromBytes(fw, fh, fill(fw * fh * 4, 255))
	margin = (fw - picture.width * k) / 2
	o.drawPicture(picture, k, margin)
	cs = controls(fw, fh, margin)
	fingers = engine.touches().map(Vec2(.x * f32(fw), .y * f32(fh)))
	if o.menuOpen:
		o.readMenu(fingers)
	else:
		o.readControls(cs, fingers)
	if o.menuOpen:
		o.paintMenu()
	else:
		o.paintControls(cs)
	o.fingers = fingers.len

# whether the button is held on the controls
pub fn isDown(o Overlay, b engine.PadButton) bool:
	not o.menuOpen and o.held[b.index()]

# whether the menu is open (the program waits while it is)
pub fn isMenuOpen(o Overlay) bool:
	o.menuOpen

# the menu's level row, named, at value (0..1): a bar a finger sets
pub fn setLevel(mut o Overlay, name str, value f64):
	o.levelName = name.copy()
	o.level = value.clamp(0.0, 1.0)

# the level the menu's bar was set to since the last call, if it changed
pub fn takeLevel(mut o Overlay) f64?:
	if not o.levelChanged: return none
	o.levelChanged = false
	o.level

# the menu's item at i named anew (a choice that shows its state, say)
pub fn setItem(mut o Overlay, i i64, name str):
	o.items[i] = name.copy()

# the picture's look from now on
pub fn setLook(mut o Overlay, look Look):
	o.look = look

# the menu's item chosen since the last call, if any
pub fn takeChoice(mut o Overlay) i64?:
	if o.chosen < 0: return none
	at = o.chosen
	o.chosen = -1
	at

# The picture into the frame at (margin, 0), each pixel k by k: a row made, then copied below.
fn scalePicture(mut o Overlay, picture image.Image, k i64, margin i64):
	fw = o.frame.width
	for y in 0..picture.height:
		row = y * k * fw
		for x in 0..picture.width:
			p = picture.cells[y * picture.width + x]
			at = row + margin + x * k
			for j in 0..k:
				o.frame.cells[at + j] = p
		for r in 1..k:
			for x in 0..fw:
				o.frame.cells[row + r * fw + x] = o.frame.cells[row + x]

# The buttons the fingers hold and the stick, and PAD's or MENU's tap as it lands.
fn readControls(mut o Overlay, cs Control[], fingers Vec2[]):
	for b in 0..o.held.len:
		o.held[b] = false
	o.stickX = 0.0
	o.stickY = 0.0
	if not o.gamePadSeen and engine.padButtons().any(.isPadDown()):
		o.gamePadSeen = true
		o.shown = false
	touching = fill(cs.len, false)
	for f in fingers:
		x = f64(f.x)
		y = f64(f.y)
		for i, c in cs:
			if not o.shown and c.kind < toggleControl: continue
			if not c.reaches(x, y): continue
			touching[i] = true
			if c.kind == stickControl:
				o.pushStick(x - c.shape.x, y - c.shape.y, c.shape.r * 0.6)
			elif c.kind < o.held.len:
				o.held[c.kind] = true
	for i, c in cs:
		if not touching[i] or (i < o.touched.len and o.touched[i]): continue
		if c.kind == toggleControl: o.shown = not o.shown
		if c.kind == menuControl: o.menuOpen = true
	o.touched = touching
