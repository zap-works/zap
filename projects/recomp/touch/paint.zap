# Drawing over the frame: capsules (a circle, or a pill when stretched) whose edges are smoothed by
# how much of a pixel they cover, laid over the picture by their opacity, and text in the letters
# (letters.zap).

import image

# a segment from (x - half, y) to (x + half, y) widened by r: a circle when half is 0
pub type Capsule:
	x f64
	y f64
	half f64 = 0.0
	r f64

# how far (x, y) is from the capsule's edge, negative inside
fn edgeDistance(c Capsule, x f64, y f64):
	dx = ((x - c.x).abs() - c.half).max(0.0)
	dy = y - c.y
	(dx * dx + dy * dy).sqrt() - c.r

# The capsule laid over the frame: its inside dark at opacity `inside`, or light when lit, and a
# light rim `rim` pixels wide at opacity `edge`.
fn paintCapsule(mut frame image.Image, c Capsule, inside f64, edge f64, rim f64, lit bool):
	x0 = i64((c.x - c.half - c.r - 1.0).max(0.0))
	x1 = i64((c.x + c.half + c.r + 2.0).min(f64(frame.width)))
	y0 = i64((c.y - c.r - 1.0).max(0.0))
	y1 = i64((c.y + c.r + 2.0).min(f64(frame.height)))
	for y in y0..y1:
		for x in x0..x1:
			d = c.edgeDistance(x + 0.5, y + 0.5)
			cover = (0.5 - d).clamp(0.0, 1.0)
			if cover <= 0.0: continue
			onRim = (d + rim + 0.5).clamp(0.0, 1.0)
			frame.blend(x, y, 230.0 if lit else 0.0, cover * inside * (1.0 - onRim))
			frame.blend(x, y, 255.0, cover * edge * onRim)

# the pixel moved toward the grey `level` (0..255) by opacity a
fn blend(mut frame image.Image, x i64, y i64, level f64, a f64):
	if a <= 0.0: return
	p = frame[x, y]
	frame[x, y] = mix(p.r, level, a), mix(p.g, level, a), mix(p.b, level, a), 255

fn mix(v u8, level f64, a f64) u8:
	u8(v + (level - v) * a)

# The text, light at opacity a, its letters `height` pixels tall centred on (cx, cy); each pixel
# covered as the share of nine points in it that fall on a letter's cells.
fn paintText(mut frame image.Image, text str, cx f64, cy f64, height f64, a f64):
	cell = height / letterRows
	width = (text.len * (letterColumns + 1) - 1) * cell
	left = cx - width / 2.0
	top = cy - height / 2.0
	x0 = i64(left.max(0.0))
	x1 = i64((left + width + 1.0).min(f64(frame.width)))
	y0 = i64(top.max(0.0))
	y1 = i64((top + height + 1.0).min(f64(frame.height)))
	for y in y0..y1:
		for x in x0..x1:
			hits = 0
			for k in 0..9:
				u = (f64(x) + ((k % 3) + 0.5) / 3.0 - left) / cell
				v = (f64(y) + ((k / 3) + 0.5) / 3.0 - top) / cell
				if u < 0.0 or v < 0.0: continue
				column = i64(u)
				row = i64(v)
				at = column / (letterColumns + 1)
				column %= letterColumns + 1
				if at < text.len and column < letterColumns and row < letterRows and
					letterCell(text[at], column, row):
					hits += 1
			frame.blend(x, y, 255.0, a * hits / 9.0)
