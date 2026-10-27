# What the player adjusts in a layout, kept in a small text file: the controls' scale and opacity,
# how far each was moved (in frame heights) and its own size beside the others', one line each:
# "scale 1.2", "opacity 0.8", "move A 0.02 -0.01", "size A 1.3".

import fs

pub type Move:
	name str
	dx f64
	dy f64

# a control's own size, as a factor of the scale
pub type Size:
	name str
	factor f64

pub type Settings:
	scale f64 = 1.0
	opacity f64 = 1.0
	moves Move[] = []
	sizes Size[] = []

pub fn parseSettings(text str) Settings:
	s = Settings()
	for row in text.lines():
		words = row.trimmed().split(" ").filter(not .isEmpty)
		if words.isEmpty: continue
		if words[0] == "scale" and words.len == 2: s.scale = f64.parse(words[1]) ?? 1.0
		if words[0] == "opacity" and words.len == 2: s.opacity = f64.parse(words[1]) ?? 1.0
		if words[0] == "move" and words.len == 4:
			s.moves.push(
				Move(words[1].copy(), f64.parse(words[2]) ?? 0.0, f64.parse(words[3]) ?? 0.0)
			)
		if words[0] == "size" and words.len == 3:
			s.sizes.push(Size(words[1].copy(), f64.parse(words[2]) ?? 1.0))
	s

pub fn formatSettings(s Settings) str:
	rows = ["scale {s.scale}", "opacity {s.opacity}"]
	for m in s.moves:
		rows.push("move {m.name} {m.dx} {m.dy}")
	for z in s.sizes:
		rows.push("size {z.name} {z.factor}")
	"{rows.join("\n")}\n"

# the settings in the file; the defaults when there is none
pub fn loadSettings(path str) Settings:
	if path.isEmpty: return Settings()
	parseSettings(fs.readFile(path) ?? "")

pub fn saveSettings(s Settings, path str):
	if path.isEmpty: return
	fs.writeFile(path, s.formatSettings()) ?? eprint("cannot write {path}: {error}")

# the control's name in the file: its label, or its stick's number
pub fn controlName(c Control) str:
	"stick{c.kind - stickControl}" if c.label.isEmpty else c.label

# the control moved by (dx, dy) frame heights more
pub fn moveBy(mut s Settings, name str, dx f64, dy f64):
	for i in 0..s.moves.len:
		if s.moves[i].name == name:
			s.moves[i] = Move(name.copy(), s.moves[i].dx + dx, s.moves[i].dy + dy)
			return
	s.moves.push(Move(name.copy(), dx, dy))

# the control's own size multiplied by the factor, within a third and three times the scale
pub fn resizeBy(mut s Settings, name str, factor f64):
	for i in 0..s.sizes.len:
		if s.sizes[i].name == name:
			s.sizes[i] = Size(name.copy(), (s.sizes[i].factor * factor).clamp(0.33, 3.0))
			return
	s.sizes.push(Size(name.copy(), factor.clamp(0.33, 3.0)))

fn sizeOf(s Settings, name str):
	(s.sizes.find(.name == name) ?? return 1.0).factor

# The controls as the settings change them: each one's size scaled and moved to where it was put.
pub fn adjusted(s Settings, cs Control[], fh f64) Control[]:
	out = []
	for c in cs:
		x = c.shape.x
		y = c.shape.y
		for m in s.moves:
			if m.name == c.controlName():
				x += m.dx * fh
				y += m.dy * fh
		size = s.scale * s.sizeOf(c.controlName())
		shape = Capsule(x, y, c.shape.half * size, c.shape.r * size)
		out.push(Control(shape, c.label.copy(), c.kind))
	out
