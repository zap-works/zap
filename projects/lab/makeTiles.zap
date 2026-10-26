# Draws the tileset of the lab's isometric scene in code and writes it to assets/tiles.png (the
# scene then loads it like any image). The atlas, 256 x 224:
#   row 0 (y 0..32):   four ground tiles, 64 x 32 diamonds: grass, dark grass, dirt, sand
#   row 1 (y 32..64):  water, stone, a highlight outline, a shadow
#   y 64..160:         a tree (64 x 96), a pine (64 x 96), a rock (64 x 48), a bush (64 x 48)
#   y 176..224:        the character, 32 x 48 in two frames (x 0 and 32)
#
#   zap run projects/lab/makeTiles.zap

import engine
import fs
import image

atlasW = 256
atlasH = 224

fn put(mut c image.Image, x i64, y i64, r i64, g i64, b i64, a i64):
	if x < 0 or y < 0 or x >= atlasW or y >= atlasH: return
	c[x, y] = image.Rgba8(
		r.clamp(0, 255),
		g.clamp(0, 255),
		b.clamp(0, 255),
		a.clamp(0, 255)
	)

# a small, repeatable noise in -1..1 for the texture of a pixel
fn noise(x i64, y i64, seed i64):
	f64(engine.random01(x, y, seed)) * 2.0 - 1.0

# whether the pixel (x, y) of a 64 x 32 cell lies on its diamond
fn inDiamond(x i64, y i64):
	dx = (x + 0.5 - 32.0).abs() / 32.0
	dy = (y + 0.5 - 16.0).abs() / 16.0
	dx + dy <= 1.04   # a little past the edge: neighbors overlap, no seams

# a ground tile at cell (cx, cy): its base color with grain, the lit top edges lighter
fn tile(mut c image.Image, cx i64, cy i64, r i64, g i64, b i64, grain f64, seed i64):
	for y in 0..32:
		for x in 0..64:
			if not inDiamond(x, y): continue
			n = noise(x, y, seed) * grain
			edge = 18 if y < 16 and
				((x + 0.5 - 32.0).abs() / 32.0 + (y + 0.5 - 16.0).abs() / 16.0) > 0.92
				else 0
			put(
				c,
				cx * 64 + x,
				cy * 32 + y,
				r + i64(n) + edge,
				g + i64(n) + edge,
				b + i64(n) + edge,
				255
			)

# a filled ellipse centered at (x0, y0), shaded from its top-left
fn blob(mut c image.Image, x0 f64, y0 f64, rx f64, ry f64, r i64, g i64, b i64, seed i64):
	for y in i64(y0 - ry)..i64(y0 + ry + 1.0):
		for x in i64(x0 - rx)..i64(x0 + rx + 1.0):
			dx = (x + 0.5 - x0) / rx
			dy = (y + 0.5 - y0) / ry
			d = dx * dx + dy * dy
			if d > 1.0: continue
			light = 1.15 - 0.45 * ((dx + 0.6) * (dx + 0.6) + (dy + 0.6) * (dy + 0.6)).sqrt()
			n = noise(x, y, seed) * 14.0
			put(
				c,
				x,
				y,
				i64(r * light + n),
				i64(g * light + n),
				i64(b * light + n),
				255
			)

fn rect(mut c image.Image, x0 i64, y0 i64, w i64, h i64, r i64, g i64, b i64):
	for y in y0..y0 + h:
		for x in x0..x0 + w:
			n = noise(x, y, 9) * 10.0
			c.put(x, y, r + i64(n), g + i64(n), b + i64(n), 255)

mut c = image.Image(atlasW, atlasH, fill = image.Rgba8(0, 0, 0, 0))
c.tile(0, 0, 92, 160, 70, 18.0, 1)   # grass
c.tile(1, 0, 70, 132, 58, 18.0, 2)   # dark grass
c.tile(2, 0, 150, 112, 74, 20.0, 3)   # dirt
c.tile(3, 0, 214, 196, 140, 12.0, 4)   # sand
c.tile(0, 1, 52, 108, 170, 10.0, 5)   # water
c.tile(1, 1, 128, 128, 136, 24.0, 6)   # stone
# the highlight: the diamond's outline only
for y in 0..32:
	for x in 0..64:
		inner = (x + 0.5 - 32.0).abs() / 32.0 + (y + 0.5 - 16.0).abs() / 16.0
		if inner <= 1.0 and inner > 0.9:
			c.put(128 + x, 32 + y, 255, 240, 120, 255)
# the shadow: a soft dark ellipse
for y in 0..32:
	for x in 0..64:
		dx = (x + 0.5 - 32.0) / 26.0
		dy = (y + 0.5 - 16.0) / 11.0
		d = dx * dx + dy * dy
		if d < 1.0:
			c.put(192 + x, 32 + y, 0, 0, 0, i64((1.0 - d) * 110.0))
# a broadleaf tree: the trunk, then the crown in overlapping blobs
c.rect(28, 120, 8, 36, 96, 64, 40)
c.blob(32.0, 100.0, 26.0, 22.0, 54, 120, 50, 11)
c.blob(22.0, 88.0, 16.0, 14.0, 64, 138, 58, 12)
c.blob(40.0, 82.0, 18.0, 15.0, 70, 146, 62, 13)
# a pine: the trunk, then three tiers
c.rect(92, 128, 8, 28, 90, 60, 38)
c.blob(96.0, 122.0, 24.0, 12.0, 36, 98, 62, 21)
c.blob(96.0, 104.0, 18.0, 11.0, 42, 110, 68, 22)
c.blob(96.0, 88.0, 12.0, 10.0, 48, 122, 74, 23)
# a rock and a bush
c.blob(160.0, 140.0, 20.0, 13.0, 132, 130, 138, 31)
c.blob(224.0, 142.0, 22.0, 14.0, 60, 132, 54, 41)
c.blob(214.0, 136.0, 12.0, 9.0, 74, 150, 64, 42)
# the character, two frames: legs apart and together
for f in 0..2:
	x0 = f * 32
	legOffset = 3 if f == 0 else 1
	c.rect(x0 + 16 - 3 - legOffset, 210, 4, 12, 52, 56, 90)   # legs
	c.rect(x0 + 16 + legOffset - 1, 210, 4, 12, 52, 56, 90)
	c.blob(x0 + 16, 202.0, 8.0, 11.0, 190, 60, 54, 51)   # body, a red tunic
	c.blob(x0 + 16, 186.0, 6.5, 6.5, 236, 196, 160, 52)   # head
	c.blob(x0 + 16, 182.0, 7.0, 4.0, 86, 52, 30, 53)   # hair
path = "projects/lab/assets/tiles.png"
_ = fs.createDir("projects/lab/assets")
c.savePng(path) ?? fail("cannot write {path}")
print("wrote {path}")
