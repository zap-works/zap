# The sprites of a line, found as the PPU finds them during the line before: the first 32 in range
# (from sprite 0, or from 2102's when 2103 bit 7 asks), their tiles fetched from the last found
# back to the first, 34 at most (what is left past them dropped), each 8 pixels of 4 bits into the
# line's buffers, a lower sprite's pixels over a higher one's whatever their priorities.

# OBSEL's sizes (bits 5-7) small then large: width, height
spriteWidths = [8, 8, 8, 16, 16, 32, 16, 16, 16, 32, 64, 32, 64, 64, 32, 32]
spriteHeights = [8, 8, 8, 16, 16, 32, 32, 32, 16, 32, 64, 32, 64, 64, 64, 32]

# the line's sprite pixels: colour 1-15 (0 none), palette 0-7, priority 0-3 (4 none); x from
# -spriteMargin, the widescreen's room (wide.zap) left and right of the 256 of the picture
spriteMargin = 256   # as far as the wide picture reaches past either side (all of it, pinned at an edge)
mut spriteColor u8[] = zeros(256 + 2 * spriteMargin)
mut spritePalette u8[] = zeros(256 + 2 * spriteMargin)
mut spritePriority u8[] = fill(256 + 2 * spriteMargin, 4)

fn spriteSizeIndex(n i64):
	large = (i64(oam[0x200 + (n >> 2)]) >> ((n & 3) * 2 + 1)) & 1
	(ppuRegs[1] >> 5) | (large << 3)

# x, -256 to 255; in the widescreen the 9 bits keep their high values for the right margin
fn spriteX(n i64):
	high = (i64(oam[0x200 + (n >> 2)]) >> ((n & 3) * 2)) & 1
	if wideOn: return wideSpriteX(i64(oam[n * 4]) + 256 * high)
	i64(oam[n * 4]) - (256 if high == 1 else 0)

fn isSpriteOnLine(n i64, scanline i64):
	size = spriteSizeIndex(n)
	x = spriteX(n)
	if x != -256 and (x + spriteWidths[size] <= -reachLeft() or x >= 256 + reachRight()):
		return false
	y = i64(oam[n * 4 + 1])
	end = y + spriteHeights[size]
	(scanline >= y and scanline < end) or ((end & 0xFF) < y and scanline < (end & 0xFF))

# 2100's forced blank as the line's sprite search meets it. Mesen 2 searches in steps, each up to
# a register access, with the blank of that moment: sprite k (from the first) at dot 2k + 1. The
# writes of this line, the dot each came at and whether the screen was blanked before it.
mut blankWrites BlankWrite[] = []

type BlankWrite:
	at i64
	blanked bool

fn noteBlankWrite():
	blankWrites.push(BlankWrite(at = dot(), blanked = isBlanked()))

fn isBlankedFor(k i64):
	for w in blankWrites:
		if w.at >= 2 * k + 1: return w.blanked
	isBlanked()

# The sprites the line after `scanline` shows, into the buffers.
fn evaluateSprites(scanline i64):
	for x in 0..spriteColor.len:
		spriteColor[x] = 0
		spritePriority[x] = 4
	first = (oamInternal & 0x1FC) >> 2 if ppuRegs[3] & 0x80 != 0 else 0
	found = []
	for k in 0..128:
		n = (first + k) & 0x7F
		if isBlankedFor(k) or not isSpriteOnLine(n, scanline): continue
		if found.len == 32 + extraSlots():
			rangeOver = true
			break
		found.push(n)
	tiles = 0
	for n in found.reversed():
		tiles = fetchSprite(n, scanline, tiles)
		if tiles > 34 + extraSlots():
			timeOver = true
			return

# the sprite's tiles on the line, left to right from the first one on screen, until the 35th of
# the line; gives the line's count of tiles
fn fetchSprite(n i64, scanline i64, before i64):
	size = spriteSizeIndex(n)
	width = spriteWidths[size]
	columns = width / 8
	x = spriteX(n)
	left = columns + ((x + reachLeft()) / 8 if x <= -8 - reachLeft() and x != -256 else 0)
	tiles = before
	while true:
		tiles += 1
		if tiles > 34 + extraSlots(): return tiles
		left -= 1
		column = columns - left - 1
		drawSpriteTile(n, scanline, width, left, column)
		if left == 0 or (0 if x == -256 else x) + column * 8 + 8 >= 256: return tiles
	tiles

fn drawSpriteTile(n i64, scanline i64, width i64, left i64, column i64):
	flags = i64(oam[n * 4 + 3])
	flipX = flags & 0x40 != 0
	gap = (scanline - oam[n * 4 + 1]) & 0xFF
	if flags & 0x80 != 0:
		# flipped: square sprites whole, a rectangle's halves each on its own
		gap = width - 1 - gap if gap < width else width * 3 - 1 - gap
	name = i64(oam[n * 4 + 2])
	row = ((name >> 4) + (gap >> 3)) & 0x0F
	tileColumn = ((name & 0x0F) + (left if flipX else column)) & 0x0F
	obsel = i64(ppuRegs[1])
	table = (((obsel >> 3) & 3) + 1) << 12 if flags & 1 != 0 else 0
	at = ((obsel & 7) << 13) + (((row << 4) | tileColumn) << 4) + table + (gap & 7)
	low = i64(vram[at & 0x7FFF])
	high = i64(vram[(at + 8) & 0x7FFF])
	drawX = spriteX(n) + column * 8
	for px in 0..8:
		sx = drawX + px
		if sx < -reachLeft() or sx >= 256 + reachRight(): continue
		bitAt = px if flipX else 7 - px
		color = ((low >> bitAt) & 1) | (((low >> (8 + bitAt)) & 1) << 1) |
			(((high >> bitAt) & 1) << 2) | (((high >> (8 + bitAt)) & 1) << 3)
		if color == 0: continue
		spriteColor[sx + spriteMargin] = color
		spritePalette[sx + spriteMargin] = (flags >> 1) & 7
		spritePriority[sx + spriteMargin] = (flags >> 4) & 3
