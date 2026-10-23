# A line's pixels composed as the PPU outputs them: on the main and the sub screen (212C, 212D)
# the sprites and the mode's backgrounds, the highest priority value showing, each layer cut by
# the windows its mask (212E, 212F) names; the backdrop where none shows; the colour math (2130,
# 2131) with the sub screen or the fixed colour, halved or not, clipped and allowed by the colour
# window; the brightness (2100); forced blank black. Lines 1 to 224 are the picture's rows 0-223.

pub screenWidth = 256
pub screenHeight = 224

mut drawnTo = 0   # the next x of the line to draw

# the line's main screen after the colour math, whether its pixel took the math, whether the sub
# screen had a layer's: what high resolution's sub pixels read of the main pixel left of them
mut lineMain i64[] = zeros(256)
mut lineMath bool[] = zeros(256)
mut lineSubShown bool[] = zeros(256)

# Draws the line's pixels up to x `last` (the dot a write lands on, less 22: the PPU's delay),
# the tiles fetched up to that dot first (fetch.zap).
fn drawTo(last i64):
	if line < 1 or line > screenHeight: return
	fetchTo(last + 22)
	stop = last.min(screenWidth - 1)
	if stop < drawnTo: return
	drawPixels(drawnTo, stop)
	drawnTo = stop + 1

fn drawPixels(from i64, to i64):
	if from == 0: recordScrolls()
	if isBlanked():
		for x in from..=to:
			outputPixel(x, 0, 0)
			if wideOn: wideStore(x, 0)
		if wideOn: drawMargins(from, to, [], [0, 0, 0, 0])
		return
	mode = i64(ppuRegs[5] & 7)
	layers = currentLayers()
	markWindows(from, to)
	if mode == 7: startMode7(from)
	priorities = spritePriorities(mode)
	composeScreens(from, to, layers, priorities, mode == 5 or mode == 6)
	wide = isDoubleWidth()
	for x in from..=to:
		inside = windowMask[5 * 256 + x]
		at = x + spriteMargin
		main = mathPixel(mainColor[at], subColor[at], mainMath[at], subPrio[at] > 0, inside)
		sub = 0
		if wide:
			left = (x - 1).max(0)
			before = lineMain[x - 1] if x > 0 else 0
			sub = mathPixel(subColor[at], before, lineMath[left] if x > 0 else mainMath[at],
				lineSubShown[left] if x > 0 else subPrio[at] > 0, inside)
		lineMain[x] = main
		lineMath[x] = mainMath[at]
		lineSubShown[x] = subPrio[at] > 0
		outputPixel(x, withBrightness(main), withBrightness(sub))
		if wideOn: wideStore(x, withBrightness(main))
	if wideOn: drawMargins(from, to, layers, priorities)

# The segment's main and sub screens, a layer at a time as the PPU (and Mesen 2) draws them: the
# sprites, then the mode's layers in order, each pixel kept where its priority value is above what
# is there and no window hides it; the backdrop where none shows. In high resolution (modes 5 and
# 6) a layer's odd pixel goes on the main screen and its even one on the sub.
# by x + spriteMargin: the widescreen's margins too (widedraw.zap)
mut mainColor i64[] = zeros(256 + 2 * spriteMargin)
mut mainPrio i64[] = zeros(256 + 2 * spriteMargin)
mut mainMath bool[] = zeros(256 + 2 * spriteMargin)
mut subColor i64[] = zeros(256 + 2 * spriteMargin)
mut subPrio i64[] = zeros(256 + 2 * spriteMargin)

fn composeScreens(from i64, to i64, layers Layer[], priorities i64[4], hires bool):
	math = i64(ppuRegs[0x31])
	for x in from..=to:
		at = x + spriteMargin
		mainPrio[at] = 0
		subPrio[at] = 0
		mainMath[at] = false
		if spritePriority[at] < 4:
			palette = i64(spritePalette[at])
			color = paletteColor(128 + palette * 16 + i64(spriteColor[at]))
			placeAt(
				4,
				x,
				priorities[spritePriority[at]],
				color,
				math & 0x10 != 0 and palette > 3,
				3
			)
	for layer in layers:
		if (ppuRegs[0x2C] | ppuRegs[0x2D]) & (u8(1) << u8(layer.bg)) == 0: continue
		takesMath = math & (1 << layer.bg) != 0
		plain = not layer.mode7 and not hasMosaic(layer.bg) and from >= 0 and to <= 255
		for x in from..=to:
			if hires:
				layer.placeLayerAt(x, layer.layerPixel(x, 1), takesMath, 1)
				layer.placeLayerAt(x, layer.layerPixel(x, 0), takesMath, 2)
			elif plain:
				layer.placeLayerAt(x, layer.fetchedPixel(x, -1), takesMath, 3)   # layerPixel's common case
			else:
				layer.placeLayerAt(x, layer.layerPixel(x, -1), takesMath, 3)
	for x in from..=to:
		at = x + spriteMargin
		if mainPrio[at] == 0:
			mainColor[at] = paletteColor(0)
			mainMath[at] = math & 0x20 != 0
		if subPrio[at] == 0: subColor[at] = paletteColor(0)

# a layer's pixel (0 transparent) on the screens of `screens` (1 main, 2 sub)
fn placeLayerAt(layer Layer, x i64, pixel i64, math bool, screens i64):
	if pixel & 0xFF == 0: return
	p = layer.high if pixel & 0x800 != 0 else layer.low
	placeAt(layer.bg, x, p, layer.layerColor(pixel), math, screens)

# a pixel put on each screen of `screens` (1 main, 2 sub) that shows its layer, where it is above
# what is there and no window hides it
fn placeAt(layer i64, x i64, priority i64, color i64, math bool, screens i64):
	bit = u8(1) << u8(layer)
	at = x + spriteMargin
	if screens & 1 != 0 and ppuRegs[0x2C] & bit != 0 and mainPrio[at] < priority and
		not (ppuRegs[0x2E] & bit != 0 and insideWindows(layer, x)):
		mainColor[at] = color
		mainPrio[at] = priority
		mainMath[at] = math
	if screens & 2 != 0 and ppuRegs[0x2D] & bit != 0 and subPrio[at] < priority and
		not (ppuRegs[0x2F] & bit != 0 and insideWindows(layer, x)):
		subColor[at] = color
		subPrio[at] = priority

# whether x is in the layer's window (0-3 the backgrounds, 4 the sprites, 5 the colour window):
# window 1 and window 2 as 2123-2125 enable and invert them, combined by 212A-212B's logic; the
# widescreen's margins take their edge pixel's
fn insideWindows(layer i64, column i64):
	if column >= 0 and column <= 255: return windowMask[layer * 256 + column]
	computeWindows(layer, column.clamp(0, 255))

# the windows of every layer at each x of the segment, as computeWindows says, kept for its pixels
mut windowMask bool[] = zeros(6 * 256)

fn markWindows(from i64, to i64):
	for layer in 0..6:
		select = (i64(ppuRegs[0x23 + layer / 2]) >> (4 * (layer & 1))) & 0xA
		for x in from..=to:
			windowMask[layer * 256 + x] = select != 0 and computeWindows(layer, x)   # no window enabled: outside

fn computeWindows(layer i64, x i64):
	select = (i64(ppuRegs[0x23 + layer / 2]) >> (4 * (layer & 1))) & 0xF
	one = select & 2 != 0
	two = select & 8 != 0
	if not one and not two: return false
	a = insideWindow(0, select & 1 != 0, x)
	b = insideWindow(1, select & 4 != 0, x)
	if not two: return a
	if not one: return b
	logic = i64(ppuRegs[0x2A]) >> (2 * layer) if layer < 4
		else i64(ppuRegs[0x2B]) >> (2 * (layer - 4))
	match logic & 3:
		0: a or b
		1: a and b
		2: a != b
		_: a == b

fn insideWindow(w i64, inverted bool, x i64):
	left = i64(ppuRegs[0x26 + 2 * w])
	right = i64(ppuRegs[0x27 + 2 * w])
	if inverted: return left > right or x < left or x > right
	left <= right and x >= left and x <= right

# whether a colour window setting of 2130 (0 never, 1 outside, 2 inside, 3 always) holds
fn windowSays(setting i64, inside bool):
	match setting:
		1: not inside
		2: inside
		3: true
		_: false

# The colour math on colour a with b (the sub screen's, or in high resolution's sub pixels the
# main pixel left of them): a cleared and the halving dropped as the colour window says, the math
# where a's layer takes it, with b when the sub screen shows a layer, else the fixed colour.
fn mathPixel(a i64, b i64, math bool, subShown bool, inside bool):
	control = i64(ppuRegs[0x30])
	half = ppuRegs[0x31] & 0x40 != 0
	main = a
	clip = (control >> 6) & 3
	if windowSays(clip, inside):
		main = 0
		if clip != 3: half = false
	if not math or windowSays((control >> 4) & 3, inside): return main
	other = fixedColor
	if control & 2 != 0:
		if subShown:
			other = b
		else:
			half = false
	subtract = ppuRegs[0x31] & 0x80 != 0
	mathChannel(main, other, 0, subtract, half) | mathChannel(main, other, 5, subtract, half) |
		mathChannel(main, other, 10, subtract, half)

# one channel (5 bits at `shift`) of the colour math
fn mathChannel(a i64, b i64, shift i64, subtract bool, half bool):
	x = (a >> shift) & 0x1F
	y = (b >> shift) & 0x1F
	c = (x - y).max(0) if subtract else x + y
	(c >> 1 if half else c).min(0x1F) << shift

fn withBrightness(c i64):
	level = brightness()
	if level == 15: return c
	((c & 0x1F) * level / 15) | ((((c >> 5) & 0x1F) * level / 15) << 5) |
		((((c >> 10) & 0x1F) * level / 15) << 10)

# a BGR555 colour as 0xRRGGBB
pub fn rgb(c i64) u32:
	(widen(c & 0x1F) << 16) | (widen((c >> 5) & 0x1F) << 8) | widen((c >> 10) & 0x1F)

fn widen(v i64) u32:
	u32((v << 3) | (v >> 2))
