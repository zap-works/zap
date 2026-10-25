# The level beyond the 256 pixels, read from where the cartridge keeps it decoded in work RAM: each
# layer a run of screens of Map16 blocks (low bytes in bank 7E, high bytes at the same address in
# 7F), a screen 16 blocks wide and 27 high in a horizontal layer, two halves of 16 by 16 side by side
# in a vertical one. Where a level mode's screens are and how it streams a layer are the
# cartridge's own tables: the screen lists at $00:BDA8 (layer 1) and $00:BDE8 (layer 2), the
# column streamers at $05:8823 and $05:888C. A block's four tilemap entries (top left, bottom
# left, top right, bottom right) are where the pointer table at $0FBE says, in bank $0D; the pipes
# (blocks 133-13A) of a horizontal layer 1 are coloured by their screen ($05:8776), as the
# streamer ($05:877E) gives them. The decode is trusted only where it reproduces the live
# tilemap in the native viewport (scene.zap).

import recomp.snes.console

# a layer of the level as the cartridge lays out its blocks
type LevelLayer:
	bg i64 = -1               # the background showing it, -1 when the layer holds no level
	vertical bool = false
	screens i64[] = []        # each screen's low bytes, as work RAM offsets
	pipes bool = false        # the pipes' colours by screen
	palette i64 = 0           # bits added to its entries (layer 2 of tileset 3: palettes 4-7)
	camera i64 = 0            # the cartridge's layer position ($1A, $1E), the scroll's anchor
	cameraY i64 = 0

pub mut levelLayers LevelLayer[] = []
mut blockBank = 0x0D   # the bank of the blocks' tilemap entries

fn wramWord(at i64) i64:
	console.wramByte(at) | (i64(console.wramByte(at + 1)) << 8)

fn romByte(at i64) i64:
	i64(console.memoryByte(u32(at)) ?? 0)

fn romWord(at i64) i64:
	romByte(at) | (romByte(at + 1) << 8)

fn romLong(at i64) i64:
	romWord(at) | (romByte(at + 2) << 16)

# the level's layers this frame, as the level mode lays them out: layer 1 unless the mode does not
# scroll it, layer 2 where it streams level blocks (not a background)
pub fn readLevelLayers():
	lastTile = -1, 0, 0, -1
	mode = i64(console.wramByte(0x1925) & 0x1F)
	tileset = i64(console.wramByte(0x1931))
	blockBank = 0x0D if tileset < 0x10 else 0x05
	count = i64(console.wramByte(0x5D)).clamp(1, 32)
	levelLayers = []
	streamer1 = romLong(0x05_8823 + 3 * mode)
	if streamer1 != 0x05_8A9A:
		vertical = streamer1 == 0x05_8A9B
		levelLayers.push(
			layerOf(0, vertical, romWord(0x00_BDA8 + 2 * mode), count, not vertical, 0)
		)
	streamer2 = romLong(0x05_888C + 3 * mode)
	if streamer2 == 0x05_8B8D or streamer2 == 0x05_8C71:
		palette = 0x1000 if tileset == 3 else 0
		layer2 = layerOf(
			1,
			streamer2 == 0x05_8C71,
			romWord(0x00_BDE8 + 2 * mode),
			count,
			false,
			palette
		)
		levelLayers.push(layer2)
	levelLayers = levelLayers.filter(not .screens.isEmpty)

fn layerOf(bg i64, vertical bool, list i64, count i64, pipes bool, palette i64) LevelLayer:
	screens i64[] = []
	if list != 0:
		for screen in 0..count:
			screens.push(romLong(list + 3 * screen) & 0x1_FFFF)
	LevelLayer(
		bg = bg,
		vertical = vertical,
		screens = screens,
		pipes = pipes,
		palette = palette,
		camera = wramWord(0x1A + 4 * bg),
		cameraY = wramWord(0x1C + 4 * bg)
	)

# the level's width in pixels as the layer lays it out
pub fn levelWidth(layer LevelLayer) i64:
	512 if layer.vertical else layer.screens.len * 256

# the tilemap entry of the world's tile (tx, ty) of the layer, -1 where the level has none
pub fn decodeTile(layer LevelLayer, tx i64, ty i64) i64:
	if tx < 0 or ty < 0: return -1
	bx = tx >> 1
	by = ty >> 1
	screen = by >> 4
	at = ((bx & 0x10) << 4) | ((by & 0xF) << 4) | (bx & 0xF)
	if not layer.vertical:
		if by >= 27: return -1
		screen = bx >> 4
		at = (by << 4) | (bx & 0xF)
	elif bx >= 32:
		return -1
	if screen >= layer.screens.len: return -1
	low = layer.screens[screen] + at
	block = i64(console.wramByte(low)) | (i64(console.wramByte(low + 0x1_0000)) << 8)
	if block >= 0x200: return -1
	pointer = wramWord(0x0FBE + 2 * block)
	if layer.pipes and block >= 0x133 and block <= 0x13A:
		pointer = romWord(0x05_8776 + ((bx >> 3) & 6)) + 8 * (block - 0x133)
	corner = ((tx & 1) << 2) | ((ty & 1) << 1)
	romWord((blockBank << 16) | ((pointer + corner) & 0xFFFF)) | layer.palette

# the world's tile at the top left of the native viewport of the layer
pub fn viewportTile(layer LevelLayer) (i64, i64):
	x = console.unwrapScroll(console.hScroll[layer.bg], layer.camera)
	y = console.unwrapScroll(console.vScroll[layer.bg], layer.cameraY)
	(x >> 3, y >> 3)

mut lastTile = -1, 0, 0, -1   # the layer, the tile and its entry last decoded: a tile's 8 pixels

fn tileAt(level LevelLayer, tx i64, ty i64) i64:
	bg, x, y, entry = lastTile
	if bg == level.bg and x == tx and y == ty: return entry
	decoded = level.decodeTile(tx, ty)
	lastTile = level.bg, tx, ty, decoded
	decoded

# a layer's pixel in the margin at x (below 0 or above 255): the level's where the layer is level
# blocks, else what its own tilemap holds there (a background SMW keeps whole in VRAM, the status bar)
pub fn marginPixel(layer console.Layer, x i64) i64:
	for level in levelLayers:
		if level.bg != layer.bg: continue
		px = console.unwrapScroll(console.hScroll[layer.bg], level.camera) + x
		py = console.unwrapScroll(console.vScroll[layer.bg], level.cameraY) + console.line
		entry = level.tileAt(px >> 3, py >> 3)
		if entry < 0: return 0
		return layer.entryPixel(entry, px, py, false)
	layer.tilemapPixel(x)
