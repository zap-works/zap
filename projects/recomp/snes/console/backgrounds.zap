# The tile backgrounds of modes 0-6 (and mode 7's plane, mode7.zap): a pixel of a layer read from its tilemap and its
# characters (2, 4 or 8 bits a pixel, tiles of 8 or 16), scrolled, with the mosaic's blocks.
# A layer's line is its scroll plus the PPU's line counted from 0, as the hardware fetches it:
# the first line drawn (1) shows the background's row vscroll + 1.

# A background as a mode uses it: its bits a pixel, its priority values with the tile's priority
# bit clear and set (the composition draws the highest), the CGRAM index of its palette 0.
pub type Layer:
	bg i64
	bpp i64
	low i64
	high i64
	palettes i64
	mode7 bool = false   # BG1 of mode 7 (mode7.zap)

# the mode's layers now, made once for each mode and BG3 priority bit (2105) they are drawn in
mut layersKey = -1
mut layersNow Layer[] = []

fn currentLayers() ref Layer[]:
	key = i64(ppuRegs[5] & 0xF)
	if key != layersKey:
		layersNow = modeLayers(key & 7)
		layersKey = key
	layersNow

fn modeLayers(mode i64) Layer[]:
	match mode:
		0:
			[
				Layer(bg = 0, bpp = 2, low = 8, high = 11, palettes = 0),
				Layer(bg = 1, bpp = 2, low = 7, high = 10, palettes = 32),
				Layer(bg = 2, bpp = 2, low = 2, high = 5, palettes = 64),
				Layer(bg = 3, bpp = 2, low = 1, high = 4, palettes = 96)
			]
		1:
			[
				Layer(bg = 0, bpp = 4, low = 6, high = 9, palettes = 0),
				Layer(bg = 1, bpp = 4, low = 5, high = 8, palettes = 0),
				Layer(
					bg = 2,
					bpp = 2,
					low = 1,
					high = 11 if ppuRegs[5] & 8 != 0 else 3,
					palettes = 0
				)
			]
		2:
			[
				Layer(bg = 0, bpp = 4, low = 3, high = 7, palettes = 0),
				Layer(bg = 1, bpp = 4, low = 1, high = 5, palettes = 0)
			]
		3:
			[
				Layer(bg = 0, bpp = 8, low = 3, high = 7, palettes = 0),
				Layer(bg = 1, bpp = 4, low = 1, high = 5, palettes = 0)
			]
		4:
			[
				Layer(bg = 0, bpp = 8, low = 3, high = 7, palettes = 0),
				Layer(bg = 1, bpp = 2, low = 1, high = 5, palettes = 0)
			]
		5:
			[
				Layer(bg = 0, bpp = 4, low = 3, high = 7, palettes = 0),
				Layer(bg = 1, bpp = 2, low = 1, high = 5, palettes = 0)
			]
		6: [Layer(bg = 0, bpp = 4, low = 1, high = 5, palettes = 0)]
		7: [Layer(bg = 0, bpp = 8, low = 3, high = 3, palettes = 0, mode7 = true)]
		_: []

# the sprites' priority values in the mode, by their priority 0-3
fn spritePriorities(mode i64) i64[4]:
	match mode:
		0: [3, 6, 9, 12]
		1: [2, 4, 7, 10]
		6: [2, 3, 4, 6]
		7: [2, 4, 6, 7]
		_: [2, 4, 6, 8]

# ---------- the mosaic ----------

# Lines left in the mosaic's block (0 with the mosaic off): a block's lines all show its first.
mut mosaicCounter = 0
mut mosaicHeld i64[4] = [0, 0, 0, 0]

fn mosaicSize():
	i64(ppuRegs[6] >> 4) + 1

fn hasMosaic(bg i64):
	ppuRegs[6] & (u8(1) << u8(bg)) != 0

# turned on from off mid-frame: its block starts on this line
fn restartMosaic(v u8):
	mosaicCounter = i64(v >> 4) + 2

# a line before the vertical blank ended: the block counted down, a new one begun
fn stepMosaic():
	on = ppuRegs[6] & 0x0F != 0
	if line == 0: mosaicCounter = mosaicSize() + 1 if on else 0
	if mosaicCounter > 0:
		mosaicCounter -= 1
		if on and mosaicCounter == 0: mosaicCounter = mosaicSize()

# ---------- a layer's pixel ----------

# The layer's pixel at x on the line: its colour (0 transparent) | palette << 8 | priority bit
# << 11; under the mosaic the first pixel of its block.
# In high resolution (modes 5 and 6) `half` picks the even (0) or the odd (1) of the line's 512
# pixels at x, the tiles 16 wide and the scroll doubled; -1 in the other modes.
pub fn layerPixel(layer Layer, x i64, half i64) i64:
	if layer.mode7: return mode7MosaicPixel(x) if hasMode7Mosaic() else mode7Pixel(x)
	if x < 0 or x > 255: return wideHooks.marginPixel(layer, x)
	if half >= 0: return layer.fetchedPixel(x, half)
	if not hasMosaic(layer.bg): return layer.fetchedPixel(x, -1)
	if x % mosaicSize() == 0: mosaicHeld[layer.bg] = layer.fetchedPixel(x, -1)   # its line the fetch's
	mosaicHeld[layer.bg]

# the pixel at the layer's column px (scrolled) on line y: its tile's 8 pixels of the line decoded
# once and kept for the rest of the drawing (tileRows)
fn tilePixel(layer Layer, px i64, y i64, wideTiles bool):
	key = (drawings << 42) | ((px >> 3) & 0x1F_FFFF) << 20 | ((y & 0x7_FFFF) << 1) |
		(1 if wideTiles else 0)
	at = layer.bg * 8
	if tileRowKeys[layer.bg] != key:
		tileRowKeys[layer.bg] = key
		large = ppuRegs[5] & (u8(0x10) << u8(layer.bg)) != 0
		py = y + vScroll[layer.bg]
		column = px >> (4 if large or wideTiles else 3)
		entry = mapEntry(layer.bg, column, py >> (4 if large else 3))
		layer.entryRow(entry, px & ~7, py, wideTiles, at)
	tileRows[at + (px & 7)]

# tilePixel's tile rows, by layer: the 8 pixels and what they were decoded for, which counts the
# drawings, so a row is never kept past the drawing (composeScreens) it was made in
mut tileRows i64[] = zeros(5 * 8)   # the fifth: entryPixel's own
mut tileRowKeys i64[] = [-1, -1, -1, -1]
mut drawings = 0

# the tilemap's entry at a tile's column and row (the map 32 or 64 tiles wide and high, wrapping)
pub fn mapEntry(bg i64, column i64, row i64) i64:
	sc = i64(ppuRegs[7 + bg])
	wide = sc & 1 != 0
	map = ((sc & 0x7C) << 8) + ((row & 0x20) << (6 if wide else 5) if sc & 2 != 0 else 0) +
		((row & 0x1F) << 5) + (column & 0x1F) + ((column & 0x20) << 5 if wide else 0)
	vram[map & 0x7FFF]

# the pixel at column px, row py (both scrolled) of a tilemap entry's tile
pub fn entryPixel(layer Layer, entry i64, px i64, py i64, wideTiles bool) i64:
	layer.entryRow(entry, px & ~7, py, wideTiles, 32)
	tileRows[32 + (px & 7)]

# The 8 pixels from column px (a multiple of 8) on row py (both scrolled) of a tilemap entry's
# tile, each its colour | palette << 8 | priority bit << 11, into tileRows from `at`.
fn entryRow(layer Layer, entry i64, px i64, py i64, wideTiles bool, at i64):
	chrBits = i64(ppuRegs[0x0B + layer.bg / 2]) >> (4 * (layer.bg & 1))
	chr = (chrBits & 7) << 12
	large = ppuRegs[5] & (u8(0x10) << u8(layer.bg)) != 0
	flipX = entry & 0x4000 != 0
	flipY = entry & 0x8000 != 0
	tile = entry & 0x3FF
	if large: tile += 16 if (py & 8 != 0) != flipY else 0
	if large or wideTiles: tile += 1 if (px & 8 != 0) != flipX else 0
	ty = 7 - (py & 7) if flipY else py & 7
	base = chr + (tile & 0x3FF) * 4 * layer.bpp + ty
	attributes = (((entry >> 10) & 7) << 8) | (((entry >> 13) & 1) << 11)
	for tx in 0..8:
		tileRows[at + tx] = attributes
	for plane in 0..layer.bpp / 2:
		word = i64(vram[(base + plane * 8) & 0x7FFF])
		for tx in 0..8:
			bitAt = tx if flipX else 7 - tx
			bits = ((word >> bitAt) & 1) | (((word >> (8 + bitAt)) & 1) << 1)
			tileRows[at + tx] |= bits << (2 * plane)

# a pixel's BGR555 colour: from CGRAM, or in direct colour (2130 bit 0, 8 bits a pixel) from its
# bits and its palette's
fn layerColor(layer Layer, pixel i64):
	color = pixel & 0xFF
	palette = (pixel >> 8) & 7
	if layer.bpp == 8 and ppuRegs[0x30] & 1 != 0:
		return ((((color & 7) << 1) | (palette & 1)) << 1) |
			(((color & 0x38) | ((palette & 2) << 1)) << 4) | (
				((color & 0xC0) | ((palette & 4) << 3)) << 7
			)
	if layer.bpp == 8: return paletteColor(layer.palettes + color)
	paletteColor(layer.palettes + palette * (1 << layer.bpp) + color)

fn paletteColor(index i64) i64:
	cgramRead = index
	cgram[index]
