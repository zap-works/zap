# The backgrounds' tiles fetched ahead of the drawing, as the PPU fetches them and Mesen 2 times
# it: through a line, dot by dot up to dot 263, each 8 dots fetch a column of every layer, its
# tilemap entry first (the scroll and line it is taken with kept), then its character's planes;
# the drawing, 22 dots behind, reads what was fetched. A scroll or a tilemap written mid-line so
# changes the columns fetched after it, not those already fetched (the pixels between). Modes
# 2, 4 and 6 also fetch BG3's offset-per-tile words, which move BG1's and BG2's columns.

columns = 33   # 0-32: the 256 pixels and the column the fine scroll reaches into

mut fetchedTo = 0    # the next dot to fetch on this line
mut offsetH = 0      # the column's offset-per-tile words (modes 2, 4, 6)
mut offsetV = 0
mut tileEntry i64[] = zeros(4 * columns)   # by layer and column: the tilemap entry
mut tileScroll i64[] = zeros(4 * columns)  # and the vertical scroll it was fetched with
mut tileChr i64[] = zeros(4 * columns * 4) # and its character's words (plane pairs; hires: both tiles)

# the line begins: nothing of it fetched
fn startFetch():
	fetchedTo = 0

# Fetches the dots up to `dot` (0-263) not yet fetched; nothing under the forced blank, the dots
# passing all the same.
fn fetchTo(dot i64):
	end = dot.min(263)
	if end < fetchedTo: return
	if not isBlanked():
		if fetchedTo == 0:
			offsetH = 0
			offsetV = 0
		mode = i64(ppuRegs[5] & 7)
		for x in fetchedTo..=end:
			fetchStep(mode, x)
	fetchedTo = end + 1

# what the dot's slot of the 8 fetches in the mode (Mesen's order)
fn fetchStep(mode i64, x i64):
	c = x >> 3
	match mode:
		0:
			match x & 7:
				0, 1, 2, 3: fetchEntry(3 - (x & 7), c, false)
				_: fetchChr(7 - (x & 7), c, 2, 0, false, false)
		1:
			match x & 7:
				0, 1, 2: fetchEntry(2 - (x & 7), c, false)
				3: fetchChr(2, c, 2, 0, false, false)
				4, 5: fetchChr(1, c, 4, (x & 7) - 4, false, false)
				_: fetchChr(0, c, 4, (x & 7) - 6, false, false)
		2, 6:
			hires = mode == 6
			match x & 7:
				0: if mode == 2: fetchEntry(1, c, false)
				1: fetchEntry(0, c, hires)
				2: offsetH = offsetWord(c, false)
				3: offsetV = offsetWord(c, true)
				4, 5:
					if mode == 2:
						fetchChr(1, c, 4, (x & 7) - 4, false, false)
					else:
						fetchChr(0, c, 4, (x & 7) - 4, true, false)
				_:
					if mode == 2:
						fetchChr(0, c, 4, (x & 7) - 6, false, false)
					else:
						fetchChr(0, c, 4, (x & 7) - 6, true, true)
		3:
			match x & 7:
				0, 1: fetchEntry(1 - (x & 7), c, false)
				2, 3: fetchChr(1, c, 4, (x & 7) - 2, false, false)
				_: fetchChr(0, c, 8, (x & 7) - 4, false, false)
		4:
			match x & 7:
				0, 1: fetchEntry(1 - (x & 7), c, false)
				2: offsetH = offsetWord(c, false)
				3: fetchChr(1, c, 2, 0, false, false)
				_: fetchChr(0, c, 8, (x & 7) - 4, false, false)
		5:
			match x & 7:
				0, 1: fetchEntry(1 - (x & 7), c, true)
				2: fetchChr(1, c, 2, 0, true, false)
				3: fetchChr(1, c, 2, 0, true, true)
				4, 5: fetchChr(0, c, 4, (x & 7) - 4, true, false)
				_: fetchChr(0, c, 4, (x & 7) - 6, true, true)
		_: pass

fn isLargeTiles(bg i64):
	ppuRegs[5] & (u8(0x10) << u8(bg)) != 0

# the line a layer is fetched for: under the mosaic its block's first
fn fetchLine(bg i64):
	if ppuRegs[6] & (u8(1) << u8(bg)) != 0: return line - (mosaicSize() - mosaicCounter)
	line

# The tilemap entry of a layer's column, with the scrolls as they are now (moved by the column's
# offset-per-tile words where BG3 enables them for the layer).
fn fetchEntry(bg i64, c i64, hires bool):
	h = hScroll[bg] << 1 if hires else hScroll[bg]
	v = vScroll[bg]
	if offsetH != 0 or offsetV != 0:
		enable = 0x2000 if bg == 0 else 0x4000
		if ppuRegs[5] & 7 == 4:
			if offsetH & 0x8000 == 0 and offsetH & enable != 0: h = (h & 7) | (offsetH & 0x3F8)
			if offsetH & 0x8000 != 0 and offsetH & enable != 0: v = offsetH & 0x3FF
		else:
			if offsetH & enable != 0: h = (h & 7) | (offsetH & 0x3F8)
			if offsetV & enable != 0: v = offsetV & 0x3FF
	if hires: h >>= 1
	row = (fetchLine(bg) + v) >> (4 if isLargeTiles(bg) else 3)
	column = c + (h >> 3)
	if not hires and isLargeTiles(bg): column >>= 1
	at = bg * columns + c
	tileEntry[at] = mapEntry(bg, column, row)
	tileScroll[at] = v

# One word (two planes) of the character of a layer's column: plane pair `pair` of its tile, or
# of the second tile of a 16-wide one (hires).
fn fetchChr(bg i64, c i64, bpp i64, pair i64, hires bool, second bool):
	at = bg * columns + c
	entry = tileEntry[at]
	large = isLargeTiles(bg)
	flipY = entry & 0x8000 != 0
	flipX = entry & 0x4000 != 0
	y = fetchLine(bg) + tileScroll[at]
	tile = entry & 0x3FF
	if hires or large:
		useSecond = second
		if not hires and large: useSecond = ((c << 3) + hScroll[bg]) & 8 != 0
		tile += (16 if (y & 8 != 0) != flipY else 0) if large else 0
		tile += 1 if useSecond != flipX else 0
		tile &= 0x3FF
	chrBits = i64(ppuRegs[0x0B + bg / 2]) >> (4 * (bg & 1))
	ty = 7 - (y & 7) if flipY else y & 7
	word = (((chrBits & 7) << 12) + tile * 4 * bpp + ty + (pair << 3)) & 0x7FFF
	tileChr[at * 4 + pair + (bpp / 2 if second else 0)] = vram[word]

# BG3's offset-per-tile word for a column: its horizontal one, or the vertical one a row below
fn offsetWord(c i64, vertical bool) i64:
	sc = i64(ppuRegs[9])
	columnAt = (((c << 3) + (hScroll[2] & ~7)) >> 3) & (0x3F if sc & 1 != 0 else 0x1F)
	rowAt = (vScroll[2] >> 3) & (0x3F if sc & 2 != 0 else 0x1F)
	base = (sc & 0x7C) << 8
	at = columnAt + (rowAt << 5)
	if vertical: at = (at + 0x20) & (0x7FF if sc & 2 != 0 else 0x3FF)
	vram[(base + at) & 0x7FFF]

# A layer's pixel at x drawn from the fetched columns: its colour | palette << 8 | priority bit
# << 11. `half` as layerPixel's: in high resolution the even (0) or the odd (1) of the 512.
fn fetchedPixel(layer Layer, x i64, half i64):
	h = hScroll[layer.bg]
	if half < 0:
		lookup = ((x + (h & 7)) >> 3).min(columns - 1)
		at = layer.bg * 8
		key = (drawings << 8) | lookup
		if columnRowKeys[layer.bg] != key:
			columnRowKeys[layer.bg] = key
			layer.decodeColumn(layer.bg * columns + lookup, 0, at)
		return columnRows[at + ((x + h) & 7)]
	lookup = (x + (h & 7)) >> 2
	chrAt = (lookup & 1) * (layer.bpp / 2)
	lookup >>= 1
	xOffset = ((x << 1) + half + (h << 1)) & 7
	at = layer.bg * columns + lookup.min(columns - 1)
	entry = tileEntry[at]
	shift = xOffset if entry & 0x4000 != 0 else 7 - xOffset
	color = 0
	for k in 0..layer.bpp / 2:
		word = tileChr[at * 4 + chrAt + k]
		color |= (((word >> shift) & 1) | (((word >> (8 + shift)) & 1) << 1)) << (2 * k)
	color | (((entry >> 10) & 7) << 8) | (((entry >> 13) & 1) << 11)

# fetchedPixel's columns decoded, by layer: the 8 pixels of the last one read, by their offset
# in it, and which column of which drawing (composeScreens) they are, so none is kept past it
mut columnRows i64[] = zeros(4 * 8)
mut columnRowKeys i64[] = [-1, -1, -1, -1]

# the fetched column at `at` (layer * columns + column) decoded into columnRows from `to`, each
# pixel at its offset in the column as fetchedPixel reads it
fn decodeColumn(layer Layer, at i64, chrAt i64, to i64):
	entry = tileEntry[at]
	attributes = (((entry >> 10) & 7) << 8) | (((entry >> 13) & 1) << 11)
	flipX = entry & 0x4000 != 0
	for offset in 0..8:
		columnRows[to + offset] = attributes
	for k in 0..layer.bpp / 2:
		word = tileChr[at * 4 + chrAt + k]
		for offset in 0..8:
			shift = offset if flipX else 7 - offset
			bits = ((word >> shift) & 1) | (((word >> (8 + shift)) & 1) << 1)
			columnRows[to + offset] |= bits << (2 * k)
