# Text in QuickDraw: the Font Manager's bitmap fonts (FONT resources of the System file, ID the
# family times 128 plus the size, a size of 0 holding the family's name) read into strikes, and
# characters drawn from them at the pen in the port's font, size, style and transfer mode.

import cpu

fontType = 0x464F_4E54   # 'FONT'

pub type Strike:
	first i64
	last i64
	widthMax i64
	kernMax i64
	height i64
	ascent i64
	descent i64
	leading i64
	rowWords i64
	image u8[]   # rowWords * 2 bytes a row, height rows
	locations i64[]   # a character's first column in the image, one past the last's too
	offsets i64[]   # a character's offset from the pen, -1 for one the font lacks
	widths i64[]

mut strikes {i64: Strike} = {}
mut noStrike = Strike(
	first = 0,
	last = -1,
	widthMax = 0,
	kernMax = 0,
	height = 0,
	ascent = 0,
	descent = 0,
	leading = 0,
	rowWords = 0,
	image = [],
	locations = [],
	offsets = [],
	widths = []
)

fn readStrike(p u32):
	first = word(p + 2)
	last = word(p + 4)
	height = word(p + 14)
	rowWords = word(p + 24)
	imageAt = p + 26
	image = (0..rowWords * 2 * height).map(u8(cpu.read8(imageAt + u32(it))))
	count = last - first + 3
	locAt = imageAt + u32(rowWords * 2 * height)
	owAt = p + 16 + u32(word(p + 16) * 2)
	locations = (0..count).map(word(locAt + u32(2 * it)))
	offsets = []
	widths = []
	for i in 0..count:
		ow = cpu.read16(owAt + u32(2 * i))
		offsets.push(-1 if ow == 0xFFFF else (ow >> 8))
		widths.push(0 if ow == 0xFFFF else (ow & 0xFF))
	Strike(
		first,
		last,
		widthMax = word(p + 6),
		kernMax = word(p + 8),
		height,
		ascent = word(p + 18),
		descent = word(p + 20),
		leading = word(p + 22),
		rowWords,
		image,
		locations,
		offsets,
		widths
	)

# the family a port's txFont names: 0 the system font, 1 the application font
fn familyOf(font i64):
	match font:
		0: 0
		1: word(apFontIdAt)
		_: font

fn pointSize(family i64, size i64):
	if size > 0: return size
	12

# the FONT resource for the family and size, the nearest size there when that one is not
fn fontId(family i64, size i64) i64:
	for d in 0..64:
		for s in [size - d, size + d]:
			if s <= 0 or s > 127: continue
			if findResource(fontType, family * 128 + s, [], false) != none: return family * 128 + s
	if family != 0: return fontId(0, 12)
	12

pub fn strikeFor(font i64, size i64) ref Strike:
	family = familyOf(font)
	id = fontId(family, pointSize(family, size))
	if id not in strikes:
		h = getResource(fontType, id, [], false)
		if h == 0: return noStrike
		strikes[id] = readStrike(address(cpu.read32(h)))
	strikes.get(id) ?? noStrike

pub fn portStrike(port u32) ref Strike:
	strikeFor(word(port + portTxFont), word(port + portTxSize))

fn glyphIndex(s Strike, c i64):
	missing = s.last - s.first + 1
	if c < s.first or c > s.last: return missing
	if s.offsets[c - s.first] < 0: return missing
	c - s.first

pub boldStyle = 1
pub italicStyle = 2
pub underlineStyle = 4
pub condenseStyle = 32
pub extendStyle = 64

# a character's advance in the port's style
pub fn charWidth(s Strike, c i64, face i64) i64:
	w = s.widths[s.glyphIndex(c)]
	if face & boldStyle != 0: w += 1
	if face & condenseStyle != 0: w -= 1
	if face & extendStyle != 0: w += 1
	w

pub fn textWidth(port u32, bytes u8[]) i64:
	s = portStrike(port)
	face = i64(cpu.read8(port + portTxFace))
	extra = i64(i32.wrap(i64(cpu.read32(port + portSpExtra)))) >> 16
	total = 0
	for c in bytes:
		total += charWidth(s, c, face)
		if c == ' ': total += extra
	total

fn isGlyphBit(s Strike, row i64, column i64):
	s.image[row * s.rowWords * 2 + (column >> 3)] >> (7 - (column & 7)) & 1 != 0

# Draws the bytes at the pen in the port, the pen moved past them.
pub fn drawText(port u32, bytes u8[]):
	s = portStrike(port)
	face = i64(cpu.read8(port + portTxFace))
	mode = word(port + portTxMode)
	extra = i64(i32.wrap(i64(cpu.read32(port + portSpExtra)))) >> 16
	c = canvasOf(port)
	clip = clipOf(port)
	baseline = word(port + portPnLoc)
	start = word(port + portPnLoc + 2)
	pen = start
	isInverted = mode & 4 != 0
	# bold: each row ORed with itself one pixel right, the glyph one pixel wider
	isBold = face & boldStyle != 0
	for ch in bytes:
		g = glyphIndex(s, ch)
		from = s.locations[g]
		to = s.locations[g + 1]
		left = pen + s.kernMax + s.offsets[g]
		top = baseline - s.ascent
		for row in 0..s.height:
			y = top + row
			spans = clip.spansAt(y) ?? continue
			slant = (s.ascent - row) / 2 if face & italicStyle != 0 else 0
			width = to - from
			for col in 0..width + (1 if isBold else 0):
				isSet = col < width and isGlyphBit(s, row, from + col)
				bit = isSet or isBold and col > 0 and isGlyphBit(s, row, from + col - 1)
				x = left + col + slant
				if not inSpans(spans, x): continue
				if mode & 3 == 0 or bit != isInverted: c.transfer(x, y, bit != isInverted, mode)
		pen += charWidth(s, ch, face)
		if ch == ' ': pen += extra
	if face & underlineStyle != 0:
		y = baseline + 1
		spans = clip.spansAt(y) ?? []
		for x in start..pen:
			if inSpans(spans, x): c.transfer(x, y, true, 1)
	setWord(port + portPnLoc + 2, pen)

pub fn inSpans(xs i64[], x i64) bool:
	i = 0
	while i < xs.len:
		if x >= xs[i] and x < xs[i + 1]: return true
		i += 2
	false

# Text drawn as QuickDraw draws it: through the port's text bottleneck (its grafProcs' textProc,
# else the StdText trap), so a program's own bottleneck or patch draws it; the text is put on the
# stack for that code to read.
pub fn drawTextVia(port u32, text u8[]):
	procs = cpu.read32(port + portGrafProcs)
	proc = cpu.read32(procs) if procs != 0 else trapAddress(0xA882)
	if proc == romAddress(trapIndex(0xA882)):
		drawText(port, text)
		return
	room = u32((text.len + 1) & ~1)
	cpu.a7 -= room
	at = cpu.a7
	for i, b in text:
		cpu.write8(at + u32(i), b)
	saved = thePort()
	setPort(port)
	one = pointValue(1, 1)
	callPascal(proc, [(u32(text.len), 2), (at, 4), (one, 4), (one, 4)], 0)
	setPort(saved)
	cpu.a7 += room

# GetFontInfo's four words: ascent, descent, widMax and leading in the port's font and style
pub fn fontInfo(port u32) (i64, i64, i64, i64):
	s = portStrike(port)
	face = i64(cpu.read8(port + portTxFace))
	(s.ascent, s.descent, s.widthMax + (1 if face & boldStyle != 0 else 0), s.leading)

# a font's number by its name, the size-0 FONT resources' names
pub fn fontNumber(name u8[]) i64:
	for r in resourcesOfType(fontType, false):
		at = r.refAt()
		id = word(at)
		if id & 127 != 0: continue
		if r.resourceName() == name: return id >> 7
	0

pub fn fontName(family i64) u8[]:
	for r in resourcesOfType(fontType, false):
		if word(r.refAt()) == family * 128: return r.resourceName()
	[]
