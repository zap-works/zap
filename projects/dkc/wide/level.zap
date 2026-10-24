# The level's terrain beyond the 256 pixels the cartridge keeps in VRAM, read from the ROM. DKC's
# level maps are static data: the cartridge streams a column of the map into a rolling 64-column
# tilemap as the camera moves ($81:883F, $81:8A6F), from a map of metatiles (4x4 tiles, a cell with
# flip bits) and their definitions. The same decode here names any tile of the world; it is
# trusted only after it reproduces the live tilemap in the native viewport (calibrateTerrain).
# The other layers (a parallax plane, the sky) repeat their native scanline.

import recomp.snes.console

# where a level's map and metatile definitions are, and how the world's tiles map to the map's
type LevelSource:
	vertical bool = false         # the map's cells run down (the vertical streamer) not across
	mapBank i64 = 0
	definitionBank i64 = 0
	mapBase i64 = 0
	metatileBase i64 = 0
	fromCamera bool = false       # the rolling map is keyed by the camera, not the scroll
	offsetX i64 = 0               # tiles from the scroll's world to the map's
	offsetY i64 = 0

mut levelMap = LevelSource()
mut terrainBg = -1       # the background that shows the level (BG1 or BG2), -1 none
mut anchorX = 0          # the camera's, which the 10-bit scroll registers are unwrapped against
mut anchorY = 0

# what names the level the cartridge is in: its map's bank and address and its metatiles'
pub fn levelSource() i64:
	(i64(console.wram[0xD5]) << 32) | (wramWord(0xD3) << 16) | wramWord(0x1B11)

# a 16-bit word of ROM at bank:address, -1 outside the cartridge
fn levelWord(bank i64, address i64):
	if bank == 0x7E or bank == 0x7F: return -1
	if bank & 0x40 == 0 and address < 0x8000: return -1
	at = ((bank & 0x3F) << 16) | address
	if at + 1 >= console.rom.len: return -1
	console.rom[at] | (i64(console.rom[at + 1]) << 8)

# the tilemap entry of the world's tile (tx, ty) as the ROM's map gives it, -1 where it has none
fn decodeTile(src LevelSource, tx i64, ty i64):
	if tx < 0 or ty < 0: return -1
	mx = tx >> 2
	my = ty >> 2
	cellAt = src.mapBase + ((mx & 0x3F) << 1) + (my << 7) if src.vertical
		else src.mapBase + (mx << 5) + ((my & 0xF) << 1)
	cell = levelWord(src.mapBank, cellAt & 0xFFFF)
	if cell < 0: return -1
	flips = cell & 0xC000
	subX = tx & 3
	subY = ty & 3
	if flips & 0x4000 != 0: subX = 3 - subX
	if flips & 0x8000 != 0: subY = 3 - subY
	source = levelWord(
		src.definitionBank,
		(((cell << 5) & 0xFFFF) + src.metatileBase + subX * 2 + subY * 8) & 0xFFFF
	)
	if source < 0: return -1
	source ^ flips

# the tiles from `ppu` to `source` pixels, the nearer whole tile (a half tile toward 0)
fn nearestTiles(source i64, ppu i64):
	d = source - ppu
	(d + 3) / 8 if d >= 0 else 0 - (3 - d) / 8

# How many of the native viewport's tiles (every other row and column) the decode reproduces, and
# how many it could decode; the source's offsets set from where the camera and the scroll are.
fn scoreLevel(mut src LevelSource, ppuX i64, ppuY i64):
	worldX = anchorX if src.fromCamera else ppuX
	worldY = anchorY if src.fromCamera else ppuY
	src.offsetX = nearestTiles(worldX, ppuX)
	src.offsetY = nearestTiles(worldY, ppuY)
	decoded = src.copy()
	console.viewportMatches(terrainBg, worldX >> 3, worldY >> 3, (tx, ty):
		decoded.decodeTile(tx, ty)
	)

# The background whose tilemap the cartridge streams the level into: 64 columns, 8x8 tiles, shown.
fn findTerrain():
	stream = wramWord(0x1B13) & 0xFC00
	for bg in 0..2:
		sc = i64(console.ppuRegs[7 + bg])
		visible = (console.ppuRegs[0x2C] | console.ppuRegs[0x2D]) & (u8(1) << u8(bg)) != 0
		if visible and sc & 1 != 0 and (sc & 0xFC) << 8 == stream and
			console.ppuRegs[5] & (u8(0x10) << u8(bg)) == 0:
			return bg
	-1

# Whether the level's ROM map reproduces the live tilemap: the last source that did is tried first,
# else both layouts, the definition banks the cartridge names and both coordinate keys are scored
# and the best accepted when 7 in 10 match (animated tiles and pickups differ legitimately).
fn calibrateTerrain() bool:
	terrainBg = findTerrain()
	if terrainBg < 0: return false
	why = 4
	anchorX = wramWord(0x088B)
	anchorY = wramWord(0x0895)
	ppuX = console.unwrapScroll(console.hScroll[terrainBg], anchorX)
	ppuY = console.unwrapScroll(console.vScroll[terrainBg], anchorY)
	mapBank = i64(console.wram[0xD5])
	alternate = i64(console.wram[0xD6])
	mapBase = wramWord(0xD3)
	metatileBase = wramWord(0x1B11)
	tried = levelMap.copy()
	tried.mapBank = mapBank
	tried.mapBase = mapBase
	tried.metatileBase = metatileBase
	matches, decodable = tried.scoreLevel(ppuX, ppuY)
	if tried.definitionBank != 0 and console.viewportAgrees(matches, decodable):
		levelMap = tried
		return true
	best = LevelSource()
	bestMatches = 0
	bestDecodable = 0
	for vertical in [false, true]:
		first = mapBank if not vertical else 0x81
		banks = [first, alternate] if alternate != 0 and alternate != first else [first]
		for bank in banks:
			for fromCamera in [false, true]:
				candidate = LevelSource(
					vertical,
					mapBank,
					bank,
					mapBase,
					metatileBase,
					fromCamera
				)
				m, d = candidate.scoreLevel(ppuX, ppuY)
				if m > bestMatches:
					best = candidate
					bestMatches = m
					bestDecodable = d
	if not console.viewportAgrees(bestMatches, bestDecodable): return false
	levelMap = best
	true

# a terrain layer's pixel in the margin at x (below 0 or above 255), from the ROM's tile there
fn terrainPixel(layer console.Layer, x i64):
	px = console.unwrapScroll(console.hScroll[layer.bg], anchorX) + x
	py = console.unwrapScroll(console.vScroll[layer.bg], anchorY) + console.line
	entry = levelMap.decodeTile((px >> 3) + levelMap.offsetX, (py >> 3) + levelMap.offsetY)
	if entry < 0: return 0
	layer.entryPixel(entry, px, py, false)

# a layer's pixel in the margin: the terrain's from the ROM, the others' the native line's repeated
pub fn marginPixel(layer console.Layer, x i64) i64:
	if layer.bg == terrainBg: return layer.terrainPixel(x)
	layer.layerPixel(x & 255, -1)
