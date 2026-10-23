# A console's picture with touch controls over it, for a phone: the picture scaled up by a whole
# number into a frame of the screen's shape (sharp at its height, the margins beside it), the
# controls of a layout (controls.zap) laid over it, and a menu of the program's choices (save, load...) that
# MENU opens. The program shows the frame and reads the held buttons and the choice made.

import engine
import image

# where the picture lies in the frame, in the frame's pixels
pub type Placement:
	fw i64 = 1
	fh i64 = 1
	margin i64 = 0
	k i64 = 1   # the picture's scale
	pictureWidth i64 = 1
	pictureHeight i64 = 1

pub type Overlay:
	layout Layout
	settings Settings = Settings()
	settingsPath str = ""
	items str[]   # the menu's choices
	frame image.Image
	placement Placement = Placement()
	held bool[]   # by the layout's button slots
	push Vec2[]   # each stick's lean, -1..1 each way, y down
	passed Vec2[] = []   # the fingers on no control, 0..1 across and down the picture
	dragging bool = false   # a finger on the right half is moving the camera stick, from here
	dragX f64 = 0.0
	dragY f64 = 0.0
	shown bool = true   # the pad's controls (PAD hides them, a game pad's first press too)
	menuOpen bool = false
	editing bool = false   # a finger drags a control to a new place
	grabbed i64 = -1   # the control being dragged
	editX f64 = 0.0
	editY f64 = 0.0
	touched bool[] = []   # the controls fingers were on at the frame before: a tap acts as it lands
	fingers i64 = 0   # how many were on the screen then
	chosen i64 = -1
	gamePadSeen bool = false

# an overlay of the layout whose menu offers the items
pub fn newOverlay(move layout Layout, items str[]) Overlay:
	Overlay(
		layout,
		items = items.copy(),
		frame = image.fromBytes(1, 1, fill(4, 0)),
		held = fill(layout.buttons, false),
		push = fill(layout.sticks, Vec2(0.0, 0.0))
	)

# the overlay with the settings kept in the file (and saved there when they change)
pub fn withSettings(mut o Overlay, path str):
	o.settingsPath = path.copy()
	o.settings = loadSettings(path)

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
	o.placement = Placement(fw, fh, margin, k, picture.width, picture.height)
	o.scalePicture(picture, k, margin)
	fingers = engine.touches().map(Vec2(.x * f32(fw), .y * f32(fh)))
	o.read(fingers, engine.padButtons().any(.isPadDown()))
	if o.menuOpen:
		o.paintMenu()
	else:
		o.paintControls(o.controls())
	o.fingers = fingers.len

# the layout's controls in this frame, as the settings place them
fn controls(o Overlay):
	p = o.placement
	o.settings.adjusted((o.layout.place)(f64(p.fw), f64(p.fh), f64(p.margin)), p.fh)

# whether the layout's button slot is held on the controls
pub fn isHeld(o Overlay, slot i64) bool:
	not o.menuOpen and slot >= 0 and slot < o.held.len and o.held[slot]

# how far the stick leans (-1..1 each way, y down): a finger on it, or for the camera stick a drag
pub fn stickLean(o Overlay, stick i64) Vec2:
	Vec2(0.0, 0.0) if o.menuOpen or stick < 0 or stick >= o.push.len else o.push[stick]

# the fingers on no control, 0..1 across and down the picture (the console's own touch screen)
pub fn passedFingers(o Overlay) Vec2[]:
	[] if o.menuOpen else o.passed

# whether a game pad has been used (the controls hide then)
pub fn hasGamePad(o Overlay) bool:
	o.gamePadSeen

# the controls grown or shrunk by the factor, kept in the settings file
pub fn resize(mut o Overlay, factor f64):
	o.settings.scale = (o.settings.scale * factor).clamp(0.4, 2.5)
	o.settings.saveSettings(o.settingsPath)

# whether a finger's drag moves the controls (and the settings kept when it ends)
pub fn toggleEditing(mut o Overlay):
	o.editing = not o.editing
	o.grabbed = -1

# whether the button is held on the controls
pub fn isDown(o Overlay, b engine.PadButton) bool:
	o.isHeld(b.index())

# whether the menu is open (the program waits while it is)
pub fn isMenuOpen(o Overlay) bool:
	o.menuOpen

# the menu's item chosen since the last call, if any
pub fn takeChoice(mut o Overlay) i64?:
	if o.chosen < 0: return none
	at = o.chosen
	o.chosen = -1
	at

# The picture into the frame, each pixel k by k, the margins black: a row made, then copied below.
fn scalePicture(mut o Overlay, picture image.Image, k i64, margin i64):
	fw = o.frame.width
	black = image.Rgba8(0, 0, 0, 255)
	right = margin + picture.width * k
	for y in 0..picture.height:
		row = y * k * fw
		for x in 0..margin:
			o.frame.cells[row + x] = black
		for x in right..fw:
			o.frame.cells[row + x] = black
		for x in 0..picture.width:
			p = picture.cells[y * picture.width + x]
			at = row + margin + x * k
			for j in 0..k:
				o.frame.cells[at + j] = p
		for r in 1..k:
			for x in 0..fw:
				o.frame.cells[row + r * fw + x] = o.frame.cells[row + x]
