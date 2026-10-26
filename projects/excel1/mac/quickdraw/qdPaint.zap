# QuickDraw's painting: a shape as a region (rectangles, ovals, rounded rectangles, the pen's
# lines), clipped by the port's visRgn, clipRgn and bitmap, its pixels set from a pattern in a
# transfer mode (copy, or, xor or bic, of the pattern or its inverse), a pattern's row and column
# taken from the port's local coordinates.

import cpu

pub type Canvas:
	base u32
	rowBytes i64
	bounds Rect

pub fn canvasOf(port u32) Canvas:
	Canvas(
		base = address(cpu.read32(port + portBits)),
		rowBytes = word(port + portBits + 4) & 0x3FFF,
		bounds = readRect(port + portBounds)
	)

# the area drawing in the port may touch, in its local coordinates
pub fn clipOf(port u32) Area:
	vis = areaOfHandle(cpu.read32(port + portVisRgn))
	clip = areaOfHandle(cpu.read32(port + portClipRgn))
	vis.combine(clip, 1).combine(readRect(port + portBounds).rectToArea(), 1)

pub fn readPattern(at u32) u8[]:
	(0..8).map(u8(cpu.read8(at + u32(it))))

# one pixel of a canvas set by a transfer mode (0 copy, 1 or, 2 xor, 3 bic) from a bit
pub fn transfer(c Canvas, x i64, y i64, bit bool, mode i64):
	at = c.base + (y - c.bounds.top) * c.rowBytes + ((x - c.bounds.left) >> 3)
	mask = u8(0x80 >> ((x - c.bounds.left) & 7))
	old = cpu.mem[at]
	cpu.mem[at] = match mode & 3:
		0: old | mask if bit else old & ~mask
		1: old | mask if bit else old
		2: old ^ mask if bit else old
		_: old & ~mask if bit else old

pub fn isPixelSet(c Canvas, x i64, y i64) bool:
	at = c.base + (y - c.bounds.top) * c.rowBytes + ((x - c.bounds.left) >> 3)
	cpu.mem[at] & u8(0x80 >> ((x - c.bounds.left) & 7)) != 0

# the point patterns are aligned to (QuickDraw's global PatAlign, below thePort): a pattern's row
# and column are taken from the coordinates less it
patAlignOffset u32 = 0xA8

fn patternAlign():
	if thePortVar() < patAlignOffset: return (0, 0)   # before InitGraf
	at = thePortVar() - patAlignOffset
	(word(at), word(at + 2))

# Paints the area in the port with the pattern at `pattern` in a pattern mode (8-15).
pub fn paintArea(port u32, a Area, pattern u32, mode i64):
	if a.isEmpty: return
	c = canvasOf(port)
	pat = readPattern(pattern)
	isInverted = mode & 4 != 0
	clipped = a.combine(clipOf(port), 1)
	alignV, alignH = patternAlign()
	for band in clipped.bands:
		for y in band.top..band.bottom:
			row = pat[(y - alignV) & 7]
			i = 0
			while i < band.xs.len:
				for x in band.xs[i]..band.xs[i + 1]:
					bit = (row >> (7 - ((x - alignH) & 7)) & 1 != 0) != isInverted
					c.transfer(x, y, bit, mode)
				i += 2

# a BitMap record (baseAddr, rowBytes, bounds) as a canvas
pub fn canvasAt(bitMap u32) Canvas:
	Canvas(
		base = address(cpu.read32(bitMap)),
		rowBytes = word(bitMap + 4) & 0x3FFF,
		bounds = readRect(bitMap + 6)
	)

# CopyBits: the source bitmap's rectangle into the destination's, scaled to fit, each pixel set
# by a source mode (0 copy, 1 or, 2 xor, 3 bic; 4-7 the same of the inverted source), within the
# destination rectangle, its bounds and the mask region, and the port's clip and visible regions
# when the destination is the port's own bitmap
pub fn copyBits(source u32, dest u32, from Rect, to Rect, mode i64, mask u32):
	if from.isEmptyRect() or to.isEmptyRect(): return
	s = canvasAt(source)
	d = canvasAt(dest)
	area = to.rectToArea().combine(d.bounds.rectToArea(), 1)
	if mask != 0: area = area.combine(areaOfHandle(mask), 1)
	port = thePort()
	if d.base == address(cpu.read32(port + portBits)): area = area.combine(clipOf(port), 1)
	width = to.right - to.left
	height = to.bottom - to.top
	# the source's pixels read before any is written: the two bitmaps may be one; a destination
	# pixel takes the source pixel under its center
	bits = fill(width * height, false)
	for y in 0..height:
		sy = from.top + (2 * y + 1) * (from.bottom - from.top) / (2 * height)
		for x in 0..width:
			sx = from.left + (2 * x + 1) * (from.right - from.left) / (2 * width)
			isInside = sx >= s.bounds.left and sx < s.bounds.right and sy >= s.bounds.top and
				sy < s.bounds.bottom
			bits[y * width + x] = isInside and s.isPixelSet(sx, sy)
	isInverted = mode & 4 != 0
	for band in area.bands:
		for y in band.top..band.bottom:
			i = 0
			while i < band.xs.len:
				for x in band.xs[i]..band.xs[i + 1]:
					d.transfer(x, y, bits[(y - to.top) * width + x - to.left] != isInverted, mode)
				i += 2

# the rows of an oval in the rectangle, as a region
pub fn ovalArea(r Rect) Area:
	if r.isEmptyRect(): return emptyArea()
	bands = []
	height = f64(r.bottom - r.top)
	width = f64(r.right - r.left)
	for y in r.top..r.bottom:
		dy = ((y - r.top) + 0.5) / height * 2.0 - 1.0
		half = (1.0 - dy * dy).max(0.0).sqrt() * width / 2.0
		center = r.left + width / 2.0
		left = i64((center - half).round())
		right = i64((center + half).round())
		if right > left: bands.push(Band(top = y, bottom = y + 1, xs = [left, right]))
	merged(bands)

fn merged(bands Band[]):
	out Band[] = []
	for b in bands:
		if not out.isEmpty:
			last = out.len - 1
			if out[last].bottom == b.top and out[last].xs == b.xs:
				out[last].bottom = b.bottom
				continue
		out.push(b.copy())
	Area(bands = out)

# a rounded rectangle: the rectangle with its corners cut by an oval of the given size
pub fn roundRectArea(r Rect, ovalWidth i64, ovalHeight i64) Area:
	if r.isEmptyRect(): return emptyArea()
	w = ovalWidth.min(r.right - r.left)
	h = ovalHeight.min(r.bottom - r.top)
	if w <= 0 or h <= 0: return r.rectToArea()
	corners = ovalArea(Rect(..r, bottom = r.top + h, right = r.left + w))
	bands = []
	for y in r.top..r.bottom:
		fromTop = y - r.top
		fromBottom = r.bottom - 1 - y
		cornerRow = -1
		if fromTop < h / 2:
			cornerRow = fromTop
		elif fromBottom < h / 2:
			cornerRow = h - 1 - fromBottom
		inset = 0
		if cornerRow >= 0:
			match corners.spansAt(r.top + cornerRow):
				xs: inset = xs[0] - r.left
				none: inset = w / 2
		bands.push(Band(top = y, bottom = y + 1, xs = [r.left + inset, r.right - inset]))
	merged(bands)

# the frame of an area with the pen's size: the area less itself moved in by the pen
pub fn frameOf(outer Area, inner Area) Area:
	outer.combine(inner, 2)

pub fn penSize(port u32) (i64, i64):
	(word(port + portPnSize), word(port + portPnSize + 2))

pub fn isPenVisible(port u32) bool:
	word(port + portPnVis) >= 0

# the pen's pattern and mode painting an area, when the pen is visible
pub fn penPaint(port u32, a Area):
	if isPenVisible(port): paintArea(port, a, port + portPnPat, word(port + portPnMode))

# the area a line of the pen covers from (h0, v0) to (h1, v1): the pen's rectangle at each point
pub fn lineArea(port u32, h0 i64, v0 i64, h1 i64, v1 i64) Area:
	pv, ph = penSize(port)
	if pv <= 0 or ph <= 0: return emptyArea()
	if h0 == h1 or v0 == v1:
		return rectArea(v0.min(v1), h0.min(h1), v0.max(v1) + pv, h0.max(h1) + ph)
	dx = (h1 - h0).abs()
	dy = (v1 - v0).abs()
	sx = 1 if h1 > h0 else -1
	sy = 1 if v1 > v0 else -1
	out = emptyArea()
	x = h0
	y = v0
	e = dx - dy
	while true:
		out = out.combine(rectArea(y, x, y + pv, x + ph), 0)
		if x == h1 and y == v1: break
		e2 = 2 * e
		if e2 > -dy:
			e -= dy
			x += sx
		if e2 < dx:
			e += dx
			y += sy
	out
