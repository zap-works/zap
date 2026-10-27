# What the fingers do to the overlay: the buttons they hold, the sticks they lean, the camera
# stick a drag on the right half moves, the fingers on no control passed on as touches, PAD's and
# MENU's tap as it lands, and in editing a control dragged to a new place.

import engine

# how far a camera drag goes before the stick is at its end, in frame heights
cameraReach = 0.15

# Reads the fingers (in the frame's pixels), told apart by their place in the list: the state
# they give, and whether a game pad is in use, which hides the controls.
pub fn read(mut o Overlay, fingers Vec2[], padDown bool):
	o.readFingers((0..fingers.len).map(engine.Finger(it, fingers[it])), padDown)

# Reads the fingers (in the frame's pixels), each kept by its id from one frame to the next.
pub fn readFingers(mut o Overlay, fingers engine.Finger[], padDown bool):
	cs = o.controls()
	if o.menuOpen:
		o.readMenu(fingers.map(.at))
	else:
		o.readControls(cs, fingers, padDown)
	o.fingers = fingers.len

fn readControls(mut o Overlay, cs Control[], fingers engine.Finger[], padDown bool):
	for b in 0..o.held.len:
		o.held[b] = false
	for s in 0..o.push.len:
		o.push[s] = Vec2(0.0, 0.0)
	o.passed = []
	if not o.gamePadSeen and padDown:
		o.gamePadSeen = true
		o.shown = false
	touching = fill(cs.len, false)
	free = []
	for f in fingers:
		x = f64(f.at.x)
		y = f64(f.at.y)
		hit = false
		for i, c in cs:
			if not o.shown and c.kind < toggleControl: continue
			if not c.reaches(x, y): continue
			hit = true
			touching[i] = true
			if o.editing and c.kind < toggleControl: continue
			if c.isStick():
				o.pushStick(c.kind - stickControl, x - c.shape.x, y - c.shape.y, c.stickReach())
			elif c.kind < o.held.len:
				o.held[c.kind] = true
		if not hit: free.push(f)
	if o.editing:
		o.dragControls(cs, fingers.map(.at))
	else:
		o.readFree(free)
	for i, c in cs:
		if not touching[i] or (i < o.touched.len and o.touched[i]): continue
		if c.kind == toggleControl: o.shown = not o.shown
		if c.kind == menuControl: o.menuOpen = true
	o.touched = touching

# The stick pushed by a finger at (dx, dy) from its centre: the lean (kept within its reach), and
# for a layout whose first stick leans onto buttons, past a dead middle the directions it leans
# toward, diagonals too.
fn pushStick(mut o Overlay, stick i64, dx f64, dy f64, reach f64):
	d = (dx * dx + dy * dy).sqrt()
	scale = reach / d if d > reach else 1.0
	o.push[stick] = Vec2(f32(dx * scale / reach), f32(dy * scale / reach))
	if stick != 0 or o.layout.lean.len != 4 or d < reach * 0.3: return
	lean = d * 0.38   # sin of 22.5 degrees: eight directions
	if dx < -lean: o.held[o.layout.lean[0]] = true
	if dx > lean: o.held[o.layout.lean[1]] = true
	if dy < -lean: o.held[o.layout.lean[2]] = true
	if dy > lean: o.held[o.layout.lean[3]] = true

# The fingers on no control: passed on in the picture's own 0..1, and the one dragging on the right
# half of the screen leans the camera stick by how far it was dragged from where it landed. The
# camera finger stays the same one while it is down; when it lifts, the next on that half takes over.
fn readFree(mut o Overlay, free engine.Finger[]):
	p = o.placement
	for f in free:
		u = (f64(f.at.x) - f64(p.margin)) / (p.k * p.pictureWidth)
		v = f64(f.at.y) / f64(p.k * p.pictureHeight)
		if u >= 0.0 and u < 1.0 and v >= 0.0 and v < 1.0:
			o.passed.push(engine.Finger(f.id, Vec2(f32(u), f32(v))))
	stick = o.layout.cameraStick
	camera = free.filter(f64(.at.x) > p.fw / 2.0)
	if stick < 0 or not o.shown or camera.isEmpty:
		o.cameraFinger = -1
		return
	f = camera.find(.id == o.cameraFinger) ?? camera[0]
	if f.id != o.cameraFinger:
		o.cameraFinger = f.id
		o.dragX = f64(f.at.x)
		o.dragY = f64(f.at.y)
	if o.push[stick].x != 0.0 or o.push[stick].y != 0.0: return   # the stick itself is in use
	reach = p.fh * cameraReach
	o.push[stick] = Vec2(
		f32(((f64(f.at.x) - o.dragX) / reach).clamp(-1.0, 1.0)),
		f32(((f64(f.at.y) - o.dragY) / reach).clamp(-1.0, 1.0))
	)

# A control dragged: the one a finger lands on follows it, and the settings are kept when it lets go.
fn dragControls(mut o Overlay, cs Control[], fingers Vec2[]):
	if fingers.isEmpty:
		if o.grabbed >= 0: o.settings.saveSettings(o.settingsPath)
		o.grabbed = -1
		return
	f = fingers[0]
	x = f64(f.x)
	y = f64(f.y)
	if o.grabbed < 0:
		for i, c in cs:
			if c.kind < toggleControl and c.reaches(x, y):
				o.grabbed = i
				o.picked = c.controlName().copy()
				break
	elif o.grabbed < cs.len:
		fh = f64(o.placement.fh)
		o.settings.moveBy(cs[o.grabbed].controlName(), (x - o.editX) / fh, (y - o.editY) / fh)
	o.editX = x
	o.editY = y
