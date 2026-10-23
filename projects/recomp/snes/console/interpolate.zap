# A frame rate above the cartridge's 60 (`--fps N`, with `--wide`, in the window): the game's logic
# still runs at the cartridge's rate; between its frames the picture is drawn again with what moved
# carried part of the way, by the share of the frame time the picture stands for. What is carried:
# each background's scroll line by line (the camera and the parallax HDMA), and the sprites that
# were in the same slot with the same tile and attributes in the frame before (their x and y).
# Anything else, a scene that is not a level's, a sprite that changed, a jump of more than 48
# pixels (a teleport, a scene cut), shows the frame as it is. The pictures drawn here touch neither
# the cartridge's picture (output.zap, which the hashes read) nor its timing.

mut interpolating = false    # the pictures between frames are drawn
mut redrawing = false        # one is being drawn now: the native output is left alone
mut scrollsBefore i64[] = zeros(224 * 6)   # each line's scrolls (BG1-3 h, then v) in the frame before
mut scrollsNow i64[] = zeros(224 * 6)
mut oamBefore u8[] = zeros(544)
mut oamNow u8[] = zeros(544)
maxStep = 48   # the most a scroll or a sprite moves between frames and is carried

# the pictures to show for each of the cartridge's frames at a rate: a whole number of them
fn presentsPerFrame(rate i64):
	count = ((rate * 10 + 301) / 601).max(1)
	interpolating = count > 1 and hasPresetFlag("--wide")
	count if interpolating else 1

# a line's scrolls as the drawing is about to use them: kept for the frame
fn recordScrolls():
	if not interpolating or redrawing or line < 1 or line > screenHeight: return
	at = (line - 1) * 6
	for bg in 0..3:
		scrollsNow[at + bg] = hScroll[bg]
		scrollsNow[at + 3 + bg] = vScroll[bg]

# the frame ended: its sprites are noted (its scrolls were, line by line)
fn noteFrameEnd():
	oamNow = oam.copy()

# the frame is shown: it becomes the frame before
fn rotateFrame():
	scrollsBefore = scrollsNow.copy()
	oamBefore = oamNow.copy()

# a 10-bit scroll `part` of the way from before to now, by the short way round
fn carriedScroll(before i64, now i64, part f64):
	step = ((now - before + 512) & 1023) - 512
	if step > maxStep or step < -maxStep: return now
	(before + i64(step * part)) & 1023

# the sprite's x as the OAM's 9 bits say it in the wide picture
fn oamX(buffer u8[], n i64):
	high = (i64(buffer[0x200 + (n >> 2)]) >> ((n & 3) * 2)) & 1
	wideSpriteX(i64(buffer[n * 4]) + 256 * high)

# the OAM with the sprites that kept their slot, tile and attributes carried part of the way
fn carriedOam(part f64):
	out = oamNow.copy()
	for n in 0..128:
		if oamBefore[n * 4 + 2] != oamNow[n * 4 + 2] or oamBefore[n * 4 + 3] != oamNow[n * 4 + 3]:
			continue
		dx = oamX(oamNow, n) - oamX(oamBefore, n)
		dy = i64(oamNow[n * 4 + 1]) - i64(oamBefore[n * 4 + 1])
		if dx > maxStep or dx < -maxStep or dy > maxStep or dy < -maxStep: continue
		x = oamX(oamBefore, n) + i64(dx * part)
		out[n * 4] = u8.wrap(x)
		slot = 0x200 + (n >> 2)
		bit = u8(1) << u8((n & 3) * 2)
		out[slot] = (out[slot] & ~bit) | (bit if x & 0x100 != 0 else u8(0))
		out[n * 4 + 1] = u8.wrap(i64(oamBefore[n * 4 + 1]) + i64(dy * part))
	out

# The picture `part` (0 to 1) of the way from the frame before to this one, drawn again from the
# state the frame ended in.
fn interpolatedColors(part f64):
	savedOam = oam.copy()
	savedScrolls = [hScroll[0], hScroll[1], hScroll[2], vScroll[0], vScroll[1], vScroll[2]]
	savedLine = line
	savedOver = rangeOver, timeOver
	redrawing = true
	oam = carriedOam(part)
	for y in 1..=screenHeight:
		at = (y - 1) * 6
		for bg in 0..3:
			hScroll[bg] = carriedScroll(scrollsBefore[at + bg], scrollsNow[at + bg], part)
			vScroll[bg] = carriedScroll(scrollsBefore[at + 3 + bg], scrollsNow[at + 3 + bg], part)
		evaluateSprites(y - 1)
		line = y
		drawPixels(0, screenWidth - 1)
	redrawing = false
	line = savedLine
	oam = savedOam
	for bg in 0..3:
		hScroll[bg] = savedScrolls[bg]
		vScroll[bg] = savedScrolls[3 + bg]
	rangeOver, timeOver = savedOver
	wideFrame.copy()
