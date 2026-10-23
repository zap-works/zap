# Pictures as grids of RGBA pixels: read and written as PNG, cut, scaled and compared. Every PNG
# kind that is not interlaced is read: grayscale, gray and alpha, RGB, RGBA, palette (1, 2, 4 or 8
# bits, with tRNS transparency), 8 or 16 bits a channel (16 keeps the high byte). A module of the
# standard library: `import image`, then `img = image.loadPng("a.png")`, `img[x, y].r`,
# `img.compare(other.resize(img.width, img.height)).pixels`.

import deflate
import digest
import fs

# a pixel: red, green, blue and alpha, 0..255 each (p[0] is p.r)
pub type Rgba8:
	r u8
	g u8
	b u8
	a u8

# A picture, rows from the top: img[x, y] its pixel, img.cells.bytes() its RGBA bytes as a
# texture takes them (no copy).
pub type Image = Grid<Rgba8>

# the image of width by height pixels whose RGBA bytes, rows from the top, are rgba
pub fn fromBytes(width i64, height i64, rgba u8[]) Image:
	if rgba.len != width * height * 4:
		fail("a {width}x{height} image needs {width * height * 4} bytes, got {rgba.len}")
	cells Rgba8[] = []
	cells.reserve(width * height)
	for at in (0..rgba.len step 4):
		cells.push((rgba[at], rgba[at + 1], rgba[at + 2], rgba[at + 3]))
	Image(rt.gridOfCells(width, height, move cells))

# a channel of 0..1 as a pixel's byte: clamped to 0..1, then the nearest of 0..255
pub fn unitToByte(v f32) u8:
	u8(i64((v.clamp(0.0, 1.0) * 255.0).round()))

# ---------- PNG ----------

# the image in a PNG file; stops with the reason when it cannot be read or decoded
pub fn loadPng(path str) Image:
	text = fs.readFile(path) ?? ""
	if text == "":
		fail("cannot read the image {path}")
	decodePng(text.bytes()) ?? fail("{path} is not a PNG this decoder reads: {error}")

# the image a PNG holds, or why it cannot be read. No file stops the program (`use noStops`): the
# chunks are read through a Reader, the rows of the image data through another, each filter undone
# over a row and the one above it.
pub fn decodePng(d u8[]) Image ? str:
	use noStops
	signature u8[] = [137, 80, 78, 71, 13, 10, 26, 10]
	if d.len < 8: return "too short"
	if d[..8] != signature: return "no PNG signature"
	header = []
	palette = []
	alphas = []
	packed = []
	file = Reader(d, at = 8, big = true)
	loop:
		n = i64(file.u32())
		tag = str(file.bytes(4))
		if file.short: break
		data = file.bytes(n)
		if file.short: return "a chunk runs past the end"
		file.skip(4)   # its CRC
		if tag == "IHDR":
			header = data
		elif tag == "PLTE":
			palette = data
		elif tag == "tRNS":
			alphas = data
		elif tag == "IDAT":
			packed.extend(data)
		elif tag == "IEND":
			break
	h = Reader(d = header, big = true)
	width = i64(h.u32())
	height = i64(h.u32())
	depth = i64(h.u8())
	kind = i64(h.u8())
	h.skip(2)   # the compression and the filtering, deflate's and PNG's
	interlaced = h.u8() != 0
	if h.short or width <= 0 or height <= 0: return "no image header"
	if width > 16_777_216 or height > 16_777_216: return "{width}x{height} pixels are too many"
	if interlaced: return "interlaced images are not read"
	channels = 1 if kind == 0 or kind == 3
		else 2 if kind == 4
		else 3 if kind == 2
		else 4 if kind == 6
		else 0
	if channels == 0 or
		(
			depth != 8 and depth != 16 and not (kind == 3 and depth < 8) and
				not (kind == 0 and depth < 8)
		):
		return "color type {kind} at {depth} bits"
	bits = channels.clamp(1, 4) * depth
	stride = (width * bits + 7) / 8
	raw = try deflate.inflateZlib(packed, height * (stride + 1))
	if raw.len < height * (stride + 1): return "the image data is short"
	bpp = (bits / 8).clamp(1, 8)
	rows = Reader(d = raw)
	above u8[] = zeros(stride)   # the row above the first: zeros
	cells Rgba8[] = []
	cells.reserve(width * height)
	loop height:
		filter = rows.u8()
		line = rows.bytes(stride)
		if rows.short or line.len != above.len: return "the image data is short"
		line.unfilter(above, filter, bpp)
		cells.appendRow(line, width, kind, depth, palette, alphas)
		above = move line
	grid = rt.gridMade(width, height, move cells) ?? return "the image data is short"
	Image(grid)

# The filter a row was written with undone in place: each byte was predicted from the one bpp
# before it (a), the one above it (b) and the one above that (c). The bytes bpp back are kept in a
# ring of 8 by their index's last three bits, so no index reaches before the row (a ring's slot
# not written yet is the 0 before the row's first pixel).
fn unfilter(mut line u8[], above u8[], filter u8, bpp i64 in 1..=8):
	if filter == 0: return
	if filter == 2:
		for i in 0..line.len.min(above.len):
			line[i] = u8.wrap(i64(line[i]) + above[i])
		return
	ring u8[8]
	if filter == 1:
		for i in 0..line.len:
			v = u8.wrap(i64(line[i]) + ring[(i - bpp) & 7])
			line[i] = v
			ring[i & 7] = v
	elif filter == 3:
		for i in 0..line.len.min(above.len):
			v = u8.wrap(line[i] + (i64(ring[(i - bpp) & 7]) + above[i]) / 2)
			line[i] = v
			ring[i & 7] = v
	elif filter == 4:
		upRing u8[8]
		for i in 0..line.len.min(above.len):
			back = (i - bpp) & 7
			v = u8.wrap(line[i] + paeth(i64(ring[back]), i64(above[i]), i64(upRing[back])))
			line[i] = v
			ring[i & 7] = v
			upRing[i & 7] = above[i]

# a byte of a row, or one of the values a byte packs (depth below 8, the highest first) or the
# high byte of a 16-bit one: the i-th; 0 past the row
fn sample(line u8[], i i64 in 0..=1_073_741_824, depth i64) Byte:
	if depth >= 8:
		at = i * 2 if depth == 16 else i
		return i64(line[at]) if at < line.len else 0
	bitsEach = depth.clamp(1, 8)
	perByte = 8 / bitsEach
	at = i / perByte
	byte = i64(line[at]) if at < line.len else 0
	shift = (8 - bitsEach * (i % perByte + 1)).clamp(0, 7)
	(byte >> shift) & ((1 << bitsEach) - 1)

# the pixels of a row of width pixels of PNG color type kind, appended to cells
fn appendRow(
	mut cells Rgba8[],
	line u8[],
	width i64 in 1..=16_777_216,
	kind i64,
	depth i64,
	palette u8[],
	alphas u8[]
):
	if kind == 6 and depth == 8:
		i n64 = 0
		while line.len - i >= 4:
			cells.push((line[i], line[i + 1], line[i + 2], line[i + 3]))   # RGBA as it is
			i += 4
		return
	if kind == 2 and depth == 8:
		i n64 = 0
		while line.len - i >= 3:
			cells.push((line[i], line[i + 1], line[i + 2], 255))
			i += 3
		return
	for x in 0..width:
		if kind == 3:
			k = sample(line, x, depth)
			at = k * 3
			alpha = alphas[k] if k < alphas.len else 255
			if at + 2 < palette.len:
				cells.push((palette[at], palette[at + 1], palette[at + 2], alpha))
			else:
				cells.push((0, 0, 0, alpha))
		elif kind == 0:
			cells.push(gray(sample(line, x, depth), 255, depth))
		elif kind == 4:
			cells.push(gray(sample(line, x * 2, depth), sample(line, x * 2 + 1, depth), depth))
		elif kind == 2:
			cells.push(color(line, x * 3, 255, depth))
		else:
			cells.push(color(line, x * 4, sample(line, x * 4 + 3, depth), depth))

# a gray pixel of fewer than 8 bits widened to 0..255
fn gray(value Byte, alpha Byte, depth i64):
	g = value * 255 / ((1 << depth.clamp(1, 8)) - 1) if depth < 8 else value
	Rgba8(g & 255, g & 255, g & 255, alpha)

# a pixel of the three samples from i on
fn color(line u8[], i i64 in 0..=67_108_864, alpha Byte, depth i64):
	Rgba8(
		sample(line, i, depth),
		sample(line, i + 1, depth),
		sample(line, i + 2, depth),
		alpha
	)

# a byte's value
type Byte = i64 in 0..=255

fn paeth(a Byte, b Byte, c Byte) Byte:
	p = a + b - c
	pa = (p - a).abs()
	pb = (p - b).abs()
	pc = (p - c).abs()
	if pa <= pb and pa <= pc: a
	elif pb <= pc: b
	else: c

# ---------- writing PNG ----------

# The image as a PNG file's bytes: RGBA, 8 bits, each row with the filter that leaves it the
# smallest numbers (the usual rule), compressed (std/deflate).
pub fn encodePng(img Image) u8[]:
	out u8[] = [137, 80, 78, 71, 13, 10, 26, 10]
	header = []
	header.pushU32be(img.width)
	header.pushU32be(img.height)
	for b in [8, 6, 0, 0, 0]:   # 8 bits, RGBA, deflate, filters by row, no interlace
		header.push(u8(b))
	chunk(out, "IHDR", header)
	stride = img.width * 4
	raw u8[] = []
	raw.reserve((stride + 1) * img.height)
	best u8[] = []
	trial = []
	for y in 0..img.height:
		bestScore = -1
		bestKind = 0
		for kind in 0..5:
			filterRow(img.cells.bytes(), y, stride, kind, trial)
			score = 0
			for v in trial:
				x = i64(v)
				score += x if x < 128 else 256 - x
			if bestScore < 0 or score < bestScore:
				bestScore = score
				bestKind = kind
				best.clear()
				best.extend(trial)
		raw.push(u8(bestKind))
		raw.extend(best)
	chunk(out, "IDAT", deflate.deflateZlib(raw))
	chunk(out, "IEND", [])
	out

# row y filtered by PNG filter `kind` (0 none, 1 left, 2 up, 3 average, 4 Paeth) into `into`
fn filterRow(px u8[], y i64, stride i64, kind i64, mut into u8[]):
	into.clear()
	at = y * stride
	for i in 0..stride:
		x = i64(px[at + i])
		a = i64(px[at + i - 4]) if i >= 4 else 0
		b = i64(px[at - stride + i]) if y > 0 else 0
		c = i64(px[at - stride + i - 4]) if i >= 4 and y > 0 else 0
		predicted = 0 if kind == 0
			else a if kind == 1
			else b if kind == 2
			else (a + b) / 2 if kind == 3
			else paeth(a, b, c)
		into.push((x - predicted) & 255)

# writes the image as a PNG file
pub fn savePng(img Image, path str) ? fs.Error:
	try fs.writeBytes(path, img.encodePng())

fn chunk(mut out u8[], name str, data u8[]):
	out.pushU32be(data.len)
	out.extend(name.bytes())
	out.extend(data)
	out.pushU32be(digest.crcOver(digest.crcOver(0xFFFF_FFFF, name.bytes()), data) ^ 0xFFFF_FFFF)

# ---------- cut, scale, compare ----------

# the part width by height whose top left corner is (x, y), clipped to the image
pub fn crop(img Image, x i64, y i64, width i64, height i64) Image:
	left = x.clamp(0, img.width)
	top = y.clamp(0, img.height)
	right = (x + width).clamp(left, img.width)
	bottom = (y + height).clamp(top, img.height)
	Image(img[left..right, top..bottom].grid())

# the pixels of `from` copied in, its top left corner at (x, y); one past the edge stops the program
# (a defined type takes a Grid's operations, not its arguments: `Grid.paste` takes a Grid)
pub fn paste(mut img Image, from Image, x i64, y i64):
	for j in 0..from.height:
		for i in 0..from.width:
			img[x + i, y + j] = from[i, j]

# the rectangle width by height whose top left corner is (x, y) filled with one color, clipped to
# the image
pub fn fillRect(mut img Image, x i64, y i64, width i64, height i64, color Rgba8):
	for j in y.max(0)..(y + height).min(img.height):
		for i in x.max(0)..(x + width).min(img.width):
			img[i, j] = color

# the two images side by side, `left` at the left, on black below the shorter one
pub fn sideBySide(left Image, right Image) Image:
	out = Image(
		left.width + right.width,
		left.height.max(right.height),
		fill = Rgba8(0, 0, 0, 255)
	)
	out.paste(left, 0, 0)
	out.paste(right, left.width, 0)
	out

# the triangle a, b, c (in pixels, either winding) filled with one color: every pixel whose center
# is inside it or on its edge, clipped to the image
pub fn fillTriangle(mut img Image, a Vec2, b Vec2, c Vec2, color Rgba8):
	area = a.edge(b, c)
	if area == 0.0: return
	left = i64(a.x.min(b.x).min(c.x).floor()).max(0)
	right = i64(a.x.max(b.x).max(c.x).ceil()).min(img.width - 1)
	top = i64(a.y.min(b.y).min(c.y).floor()).max(0)
	bottom = i64(a.y.max(b.y).max(c.y).ceil()).min(img.height - 1)
	for y in top..=bottom:
		for x in left..=right:
			p = Vec2(f32(x) + 0.5, f32(y) + 0.5)
			u = b.edge(c, p) * area
			v = c.edge(a, p) * area
			w = a.edge(b, p) * area
			if u >= 0.0 and v >= 0.0 and w >= 0.0: img[x, y] = color

# twice the signed area of a, b, p: which side of the line a b the point p is on
fn edge(a Vec2, b Vec2, p Vec2):
	(b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)

# the image k times larger, each pixel a k by k square (pixel art kept sharp)
pub fn enlarge(img Image, k i64) Image:
	out = Image(img.width * k, img.height * k, fill = Rgba8(0, 0, 0, 0))
	for y in 0..out.height:
		for x in 0..out.width:
			out[x, y] = img[x / k, y / k]
	out

# The picture enlarged k times (2, 3 or 4; 4 is 2 twice) with its edges smoothed, as the EPX
# family does (Scale2x, Scale3x): each pixel a k by k block whose corners take a neighbour's colour
# where two neighbours of the same colour meet across it, so a diagonal steps in finer stairs, no
# colour made that the picture does not have, a flat area or a straight edge as enlarge draws it.
# Written into `out` with its top left corner at (left, top); a part past its edges stops the
# program.
pub fn smoothInto(mut out Image, img Image, k i64, left i64, top i64):
	if left < 0 or top < 0 or left + img.width * k > out.width or top + img.height * k > out.height:
		fail("the picture enlarged {k} times does not fit at ({left}, {top})")
	if k == 3:
		out.scale3x(img, left, top)
	elif k == 4:
		twice = Image(img.width * 2, img.height * 2, fill = Rgba8(0, 0, 0, 0))
		twice.scale2x(img, 0, 0)
		out.scale2x(twice, left, top)
	elif k == 2:
		out.scale2x(img, left, top)
	else:
		out.paste(img.enlarge(k.max(1)), left, top)

# The rows above, at and below y as the places of their first pixel, the edge's own past the edge.
fn rowsAround(img Image, y i64) (i64, i64, i64):
	((y - 1).max(0) * img.width, y * img.width, (y + 1).min(img.height - 1) * img.width)

fn scale2x(mut out Image, img Image, left i64, top i64):
	ow = out.width
	last = img.width - 1
	for y in 0..img.height:
		up, at, down = img.rowsAround(y)
		q = (top + 2 * y) * ow + left
		for x in 0..img.width:
			e = img.cells[at + x]
			b = img.cells[up + x]
			h = img.cells[down + x]
			d = img.cells[at + (x - 1).max(0)]
			f = img.cells[at + (x + 1).min(last)]
			edge = b != h and d != f
			out.cells[q] = d if edge and d == b else e
			out.cells[q + 1] = f if edge and b == f else e
			out.cells[q + ow] = d if edge and d == h else e
			out.cells[q + ow + 1] = f if edge and h == f else e
			q += 2

fn scale3x(mut out Image, img Image, left i64, top i64):
	ow = out.width
	last = img.width - 1
	for y in 0..img.height:
		up, at, down = img.rowsAround(y)
		q = (top + 3 * y) * ow + left
		for x in 0..img.width:
			e = img.cells[at + x]
			b = img.cells[up + x]
			h = img.cells[down + x]
			d = img.cells[at + (x - 1).max(0)]
			f = img.cells[at + (x + 1).min(last)]
			if b == h or d == f:
				for row in [q, q + ow, q + 2 * ow]:
					out.cells[row] = e
					out.cells[row + 1] = e
					out.cells[row + 2] = e
				q += 3
				continue
			l = (x - 1).max(0)
			r = (x + 1).min(last)
			a = img.cells[up + l]
			c = img.cells[up + r]
			g = img.cells[down + l]
			i = img.cells[down + r]
			out.cells[q] = d if d == b else e
			out.cells[q + 1] = b if (d == b and e != c) or (b == f and e != a) else e
			out.cells[q + 2] = f if b == f else e
			out.cells[q + ow] = d if (d == b and e != g) or (d == h and e != a) else e
			out.cells[q + ow + 1] = e
			out.cells[q + ow + 2] = f if (b == f and e != i) or (h == f and e != c) else e
			out.cells[q + 2 * ow] = d if d == h else e
			out.cells[q + 2 * ow + 1] = h if (d == h and e != i) or (h == f and e != g) else e
			out.cells[q + 2 * ow + 2] = f if h == f else e
			q += 3

# The image scaled to width by height, bilinear: each pixel the blend of the four source pixels
# around its center (the nearest one at the edges).
pub fn resize(img Image, width i64, height i64) Image:
	if img.width == 0 or img.height == 0:
		fail("an empty image cannot be resized")
	out = Image(width, height, fill = Rgba8(0, 0, 0, 0))
	for y in 0..height:
		sy = sourceAt(y, height, img.height)
		y0 = i64(sy.floor())
		y1 = (y0 + 1).min(img.height - 1)
		fy = sy - y0
		for x in 0..width:
			sx = sourceAt(x, width, img.width)
			x0 = i64(sx.floor())
			x1 = (x0 + 1).min(img.width - 1)
			fx = sx - x0
			for c in 0..4:
				top = blend(img[x0, y0][c], img[x1, y0][c], fx)
				bottom = blend(img[x0, y1][c], img[x1, y1][c], fx)
				out[x, y][c] = u8(i64(blend(top, bottom, fy).round()))
	out

# the source coordinate of pixel i's center, of `size` pixels scaled from `sourceSize`
fn sourceAt(i i64, size i64, sourceSize i64):
	((i + 0.5) * sourceSize / size - 0.5).clamp(
		0.0,
		f64(sourceSize - 1)
	)

fn blend(a f64, b f64, t f64):
	a + (b - a) * t

# how two images differ
pub type Difference:
	pixels i64   # the pixels a channel of which differs by more than the tolerance
	largest i64   # the largest difference of a channel, 0..255
	mean Vec3   # the mean difference of red, green and blue over the pixels, 0..255

# How two images differ, over the larger of their sizes: a pixel only one of them has differs by
# 255.
pub fn compare(a Image, b Image, tolerance i64 = 0) Difference:
	out = Difference(pixels = 0, largest = 0, mean = Vec3(0.0, 0.0, 0.0))
	sums = [0, 0, 0]
	width = a.width.max(b.width)
	height = a.height.max(b.height)
	for y in 0..height:
		for x in 0..width:
			d = a.pixelDifference(b, x, y)
			if d > tolerance:
				out.pixels += 1
			out.largest = out.largest.max(d)
			for c in 0..3:
				sums[c] += a.channelDifference(b, x, y, c)
	count = f32((width * height).max(1))
	out.mean = Vec3(f32(sums[0]) / count, f32(sums[1]) / count, f32(sums[2]) / count)
	out

# A picture of where two images differ, the larger of their sizes, for whoever looks: a pixel that
# differs by more than the tolerance is red, brighter the more it differs; the others are the
# first image in gray, dimmed so the red stands out.
pub fn diff(a Image, b Image, tolerance i64 = 0) Image:
	out = Image(a.width.max(b.width), a.height.max(b.height), fill = Rgba8(0, 0, 0, 255))
	for y in 0..out.height:
		for x in 0..out.width:
			d = a.pixelDifference(b, x, y)
			if d > tolerance:
				out[x, y].r = u8(128 + d / 2)
			elif x < a.width and y < a.height:
				gray = u8(a[x, y].dimmedGray())
				out[x, y] = Rgba8(gray, gray, gray, 255)
	out

# the pixel's brightness (the eye's weights of red, green and blue), a third of it
fn dimmedGray(p Rgba8):
	(i64(p.r) * 299 + i64(p.g) * 587 + i64(p.b) * 114) / 3000

# the largest difference of a channel at (x, y); 255 where only one image has the pixel
fn pixelDifference(a Image, b Image, x i64, y i64):
	d = 0
	for c in 0..4:
		d = d.max(a.channelDifference(b, x, y, c))
	d

# the difference of channel c at (x, y); 255 where only one image has the pixel
fn channelDifference(a Image, b Image, x i64, y i64, c i64):
	if x >= a.width or y >= a.height or x >= b.width or y >= b.height: return 255
	(i64(a[x, y][c]) - i64(b[x, y][c])).abs()

# ---------- tests ----------

# an image whose pixel (x, y) is (x * 10, y * 10, x + y, 255)
fn ramp(width i64, height i64):
	img = Image(width, height, fill = Rgba8(0, 0, 0, 255))
	for (x, y), _ in img:
		img[x, y] = Rgba8(u8.wrap(x * 10), u8.wrap(y * 10), u8.wrap(x + y), 255)
	img

test "a channel of 0..1 as a byte: rounded, clamped":
	out = []
	for v in [-0.5, 0.0, 0.5, 1.0, 3.0]:
		out.push(unitToByte(f32(v)))
	expect out == [0, 0, 128, 255, 255]

test "a crop keeps the pixels under it, clipped to the image" for (x, y, w, h, want) in [
	(1, 2, 2, 2, "2x2 [10, 20, 3, 255, 20, 20, 4, 255, 10, 30, 4, 255, 20, 30, 5, 255]"),
	(3, 3, 5, 5, "1x1 [30, 30, 6, 255]"),
	(-3, 1, 2, 9, "0x3 []")
]:
	part = ramp(4, 4).crop(x, y, w, h)
	expect "{part.width}x{part.height} {part.cells.bytes()}" == want

test "an image pasted into another":
	img = Image(3, 3, fill = Rgba8(0, 0, 0, 255))
	img.paste(ramp(2, 2), 1, 1)
	expect img.cells.bytes() ==
		[
			0,
			0,
			0,
			255,
			0,
			0,
			0,
			255,
			0,
			0,
			0,
			255,
			0,
			0,
			0,
			255,
			0,
			0,
			0,
			255,
			10,
			0,
			1,
			255,
			0,
			0,
			0,
			255,
			0,
			10,
			1,
			255,
			10,
			10,
			2,
			255
		]

test "a rectangle fills the pixels under it, clipped to the image":
	img = Image(3, 2, fill = Rgba8(0, 0, 0, 255))
	img.fillRect(-1, 1, 3, 5, Rgba8(9, 9, 9, 255))
	expect img.cells.map(.r) == [0, 0, 0, 9, 9, 0]

test "two images side by side, the shorter on black":
	left Image = Image(1, 2, fill = Rgba8(5, 5, 5, 255))
	right Image = Image(2, 1, fill = Rgba8(7, 7, 7, 255))
	both = left.sideBySide(right)
	expect "{both.width}x{both.height} {both.cells.map(.r)}" == "3x2 [5, 7, 7, 5, 0, 0]"

test "a triangle fills the pixels whose centers it covers, either winding, clipped":
	for corners in [
		[Vec2(1.0, 1.0), Vec2(9.0, 1.0), Vec2(1.0, 9.0)],
		[Vec2(1.0, 1.0), Vec2(1.0, 9.0), Vec2(9.0, 1.0)]
	]:
		img = Image(8, 8, fill = Rgba8(0, 0, 0, 0))
		img.fillTriangle(corners[0], corners[1], corners[2], Rgba8(255, 0, 0, 255))
		expect img[1, 1].r == 255 and img[6, 1].r == 255 and img[1, 6].r == 255
		expect img[0, 0].r == 0 and img[7, 7].r == 0 and img[5, 5].r == 0

test "a resize to the same size changes nothing; halved, it blends pairs":
	img = ramp(4, 2)
	print(img.resize(4, 2).cells == img.cells)
	half = ramp(4, 1).resize(2, 1)
	print("{half.width}x{half.height} {half.cells.bytes()}")
	prints """
		true
		2x1 [5, 0, 1, 255, 25, 0, 3, 255]
		"""

test "a resize up repeats the edge and blends between":
	expect ramp(2, 1).resize(4, 1).cells.bytes() ==
		[0, 0, 0, 255, 3, 0, 0, 255, 8, 0, 1, 255, 10, 0, 1, 255]

test "compare counts the pixels that differ, the largest difference and the mean of each channel":
	a = ramp(2, 2)
	b = ramp(2, 2)
	b[0, 0].r = 40
	b[1, 0].b = 5
	for d in [a.compare(a), a.compare(b), a.compare(b, tolerance = 5), a.compare(ramp(1, 4))]:
		print("{d.pixels} {d.largest} {d.mean.x:.2} {d.mean.y:.2} {d.mean.z:.2}")
	prints """
		0 0 0.00 0.00 0.00
		2 40 10.00 0.00 1.00
		1 40 10.00 0.00 1.00
		6 255 191.25 191.25 191.25
		"""

test "diff marks the pixels that differ in red over a dimmed gray":
	a = ramp(2, 1)
	b = ramp(2, 1)
	b[0, 0].r = 40
	marked = a.diff(b)
	print("{marked.width}x{marked.height} {marked.cells.bytes()}")
	prints """
		2x1 [148, 0, 0, 255, 1, 1, 1, 255]
		"""

# PNG files another encoder wrote (Python's zlib: stored, fixed and dynamic Huffman blocks, every
# row filter, the data split over two IDAT chunks), each kind read, and this encoder's read back

# a sum and a running hash of the RGBA bytes, the checks the fixtures were made with
fn digest(img Image):
	sum = 0
	h = 0
	bytes = img.cells.bytes()
	for b in bytes:
		sum += b
		h = (h * 31 + i64(b)) % 1_000_000_007
	"{img.width}x{img.height} {sum} {h} {bytes[..8]}"

fn decoded(name str):
	path = "std/image/png/{name}.png"
	text = fs.readFile(path) ?? ""
	match decodePng(text.bytes()):
		error: "error"
		img: img.digest()

test "every kind of PNG decodes to the pixels written":
	expect decoded == {
		"rgba8": "13x9 54710 489952954 [0, 0, 0, 128, 19, 3, 0, 129]",
		"rgb8": "13x9 69243 596875773 [0, 0, 0, 255, 40, 0, 20, 255]",
		"stored": "13x9 69243 596875773 [0, 0, 0, 255, 40, 0, 20, 255]",
		"gray8": "13x9 75705 366981212 [0, 0, 0, 255, 17, 17, 17, 255]",
		"graya16": "13x9 55098 653933771 [0, 0, 0, 0, 23, 23, 23, 0]",
		"pal4": "13x9 62708 196501211 [0, 255, 0, 255, 16, 239, 37, 245]",
		"gray1": "13x9 59670 238418019 [255, 255, 255, 255, 0, 0, 0, 255]"
	}

test "the encoder's file decodes to the same image":
	pixels u8[] = []
	for i in 0..(70 * 3 * 4):
		pixels.push((i * 37) % 256)
	img = fromBytes(70, 3, pixels)
	bytes = img.encodePng()
	match decodePng(bytes):
		error: print("error")
		back: print(back.width == 70 and back.height == 3 and back.cells == img.cells)
	prints "true"

test "a damaged file is refused":
	bytes u8[] = [137, 80, 78, 71, 13, 10, 26, 10, 0, 0].map(u8(it))
	match decodePng(bytes):
		error: print(error)
		img: print("decoded {img.width}")
	prints "no image header"

test "a saved image compresses and reads back the same":
	pixels = []
	for y in 0..64:
		for x in 0..64:
			for v in [x * 4, y * 4, (x * y) % 256, 255]:
				pixels.push(u8(v))
	img = fromBytes(64, 64, pixels)
	file = img.encodePng()
	back = decodePng(file) ?? Image(0, 0, fill = Rgba8(0, 0, 0, 0))
	expect back.cells == img.cells
	expect file.len < img.cells.len * 4 / 3

test "a flat picture and a straight edge enlarge as enlarge does" for k in [2, 3, 4]:
	img = Image(3, 2, fill = Rgba8(10, 20, 30, 255))
	img[2, 0] = Rgba8(200, 0, 0, 255)
	img[2, 1] = Rgba8(200, 0, 0, 255)
	out = Image(3 * k, 2 * k, fill = Rgba8(0, 0, 0, 0))
	out.smoothInto(img, k, 0, 0)
	expect out.compare(img.enlarge(k)).pixels == 0

test "a diagonal's corner takes its neighbours' colour" for k in [2, 3]:
	dark = Rgba8(0, 0, 0, 255)
	light = Rgba8(255, 255, 255, 255)
	img = Image(2, 2, fill = light)
	img[0, 0] = dark
	img[1, 0] = dark
	img[0, 1] = dark
	out Image = Image(2 * k, 2 * k, fill = Rgba8(0, 0, 0, 0))
	out.smoothInto(img, k, 0, 0)
	expect out[2 * k - 1, 2 * k - 1] == light and out[k, k] == dark
