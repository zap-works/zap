# The picture, a line at a time as the hardware draws it at each horizontal blank: the four
# backgrounds (text, affine or bitmap as the mode says), the sprites, the windows that choose
# what shows where, and the blending of the two top layers. A pixel is BGR555 (15 bits).

pub screenWidth = 240
pub screenHeight = 160
transparent u32 = 0x8000

pub mut screen u16[] = zeros(240 * 160)

# each layer's colors on the line being drawn (transparent where it has none)
mut layers u32[4, 240] = [zeros(240), zeros(240), zeros(240), zeros(240)]
mut objColor u32[] = zeros(240)
mut objPriority i64[] = zeros(240)
mut objSemi bool[] = zeros(240)
mut objWindow bool[] = zeros(240)

# the affine backgrounds' reference points as the hardware steps them down the lines
mut affineX i64[2] = [0, 0]
mut affineY i64[2] = [0, 0]

fn color(index i64):
	u32(palette.u16le(2 * index)) & 0x7FFF

fn dispcnt():
	ioHalf(regDispcnt)

# Draws the line into screen.
pub fn drawLine(y i64):
	control = dispcnt()
	row = y * screenWidth
	if control & 0x80 != 0:
		for x in 0..screenWidth:
			screen[row + x] = 0x7FFF
		return
	if y == 0: latchAffine()
	mode = control & 7
	for bg in 0..4:
		visible = control & (u32(0x100) << u32(bg)) != 0
		kind = layerKind(mode, bg)
		if not visible or kind == 0:
			fillTransparent(bg)
		elif kind == 1:
			drawText(bg, y)
		elif kind == 2:
			drawAffine(bg, y)
		else:
			drawBitmap(mode, y)
	drawSprites(y, control)
	compose(y, control)
	stepAffine()

# what the background is in the mode: 0 none, 1 text, 2 affine, 3 bitmap
fn layerKind(mode u32, bg i64):
	match mode:
		0: 1
		1: 1 if bg < 2 else 2 if bg == 2 else 0
		2: 2 if bg >= 2 else 0
		3, 4, 5: 3 if bg == 2 else 0
		_: 0

fn fillTransparent(bg i64):
	for x in 0..screenWidth:
		layers[bg, x] = transparent

fn drawText(bg i64, y i64):
	cnt = ioHalf(0x08 + 2 * bg)
	charBase = i64((cnt >> 2) & 3) * 0x4000
	screenBase = i64((cnt >> 8) & 31) * 0x800
	wide = 512 if (cnt >> 14) & 1 == 1 else 256
	tall = 512 if (cnt >> 14) & 2 == 2 else 256
	colors256 = cnt & 0x80 != 0
	hofs = i64(ioHalf(0x10 + 4 * bg) & 0x1FF)
	py = (y + (ioHalf(0x12 + 4 * bg) & 0x1FF)) & (tall - 1)
	for x in 0..screenWidth:
		px = (x + hofs) & (wide - 1)
		block = (px >> 8) + (py >> 8) * (wide >> 8)
		entry = i64(
			vram.u16le(
				screenBase + block * 0x800 + (((py & 255) >> 3) * 32 + ((px & 255) >> 3)) * 2
			)
		)
		tx = (px & 7) ^ (7 if entry & 0x400 != 0 else 0)
		ty = (py & 7) ^ (7 if entry & 0x800 != 0 else 0)
		tile = entry & 0x3FF
		if colors256:
			at = charBase + tile * 64 + ty * 8 + tx
			index = i64(vram[at]) if at < 0x1_0000 else 0
			layers[bg, x] = transparent if index == 0 else color(index)
		else:
			at = charBase + tile * 32 + ty * 4 + (tx >> 1)
			b = i64(vram[at]) if at < 0x1_0000 else 0
			nibble = (b >> 4) if tx & 1 == 1 else b & 15
			layers[bg, x] = transparent if nibble == 0 else color((entry >> 12) * 16 + nibble)

fn affineParam(bg i64, k i64) i64:
	i16.wrap(ioHalf(0x20 + 0x10 * (bg - 2) + 2 * k))

fn reference(off i64):
	v = ioHalf(off) | (ioHalf(off + 2) << 16)
	i64(i32(v << 4)) >> 4

# the reference points taken again from their registers: at the frame's start, and when written
pub fn latchAffine():
	for k in 0..2:
		affineX[k] = reference(0x28 + 0x10 * k)
		affineY[k] = reference(0x2C + 0x10 * k)

pub fn affineWritten(off i64):
	k = (off - 0x28) / 0x10
	if off & 0xF < 4:
		affineX[k] = reference(0x28 + 0x10 * k)
	else:
		affineY[k] = reference(0x2C + 0x10 * k)

fn stepAffine():
	for k in 0..2:
		affineX[k] += affineParam(k + 2, 1)
		affineY[k] += affineParam(k + 2, 3)

fn drawAffine(bg i64, y i64):
	cnt = ioHalf(0x08 + 2 * bg)
	charBase = i64((cnt >> 2) & 3) * 0x4000
	screenBase = i64((cnt >> 8) & 31) * 0x800
	size = 128 << ((cnt >> 14) & 3)
	wraps = cnt & 0x2000 != 0
	pa = affineParam(bg, 0)
	pc = affineParam(bg, 2)
	ix = affineX[bg - 2]
	iy = affineY[bg - 2]
	for x in 0..screenWidth:
		tx = ix >> 8
		ty = iy >> 8
		ix += pa
		iy += pc
		if wraps:
			tx &= size - 1
			ty &= size - 1
		elif tx < 0 or ty < 0 or tx >= size or ty >= size:
			layers[bg, x] = transparent
			continue
		tile = i64(vram[screenBase + (ty >> 3) * (size >> 3) + (tx >> 3)])
		index = i64(vram[charBase + tile * 64 + (ty & 7) * 8 + (tx & 7)])
		layers[bg, x] = transparent if index == 0 else color(index)

fn drawBitmap(mode u32, y i64):
	page = 0xA000 if dispcnt() & 0x10 != 0 else 0
	for x in 0..screenWidth:
		layers[2, x] = match mode:
			3: u32(vram.u16le((y * 240 + x) * 2)) & 0x7FFF
			4:
				index = i64(vram[page + y * 240 + x])
				transparent if index == 0 else color(index)
			_: u32(vram.u16le(page + (y * 160 + x) * 2)) & 0x7FFF if x < 160 and y < 128
				else transparent
