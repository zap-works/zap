# QuickDraw's globals and graphics ports, in memory as programs read them. The globals lie below
# the variable thePort, whose address InitGraf keeps at 0(A5): the patterns white, black, gray,
# ltGray and dkGray, the arrow cursor, screenBits and randSeed. A GrafPort is 108 bytes: device,
# portBits (a BitMap: baseAddr, rowBytes, bounds), portRect, visRgn, clipRgn, bkPat, fillPat,
# pnLoc, pnSize, pnMode, pnPat, pnVis, txFont, txFace, txMode, txSize, spExtra, fgColor, bkColor,
# colrBit, patStretch, picSave, rgnSave, polySave and grafProcs.

import cpu

pub portBits u32 = 2
pub portBounds u32 = 8
pub portRect u32 = 16
pub portVisRgn u32 = 24
pub portClipRgn u32 = 28
pub portBkPat u32 = 32
pub portFillPat u32 = 40
pub portPnLoc u32 = 48
pub portPnSize u32 = 52
pub portPnMode u32 = 56
pub portPnPat u32 = 58
pub portPnVis u32 = 66
pub portTxFont u32 = 68
pub portTxFace u32 = 70
pub portTxMode u32 = 72
pub portTxSize u32 = 74
pub portSpExtra u32 = 76
pub portFgColor u32 = 80
pub portBkColor u32 = 84
pub portPicSave u32 = 92
pub portRgnSave u32 = 96
pub portPolySave u32 = 100
pub portGrafProcs u32 = 104
pub portSize = 108

globalWhite u32 = 8
globalBlack u32 = 16
globalGray u32 = 24
globalLtGray u32 = 32
globalDkGray u32 = 40
globalArrow u32 = 108
globalScreenBits u32 = 122
globalRandSeed u32 = 126

pub patCopy = 8
pub srcOr = 1

pub type Rect:
	top i64
	left i64
	bottom i64
	right i64

pub fn signed16(v u32) i64:
	i16.wrap(i64(v & 0xFFFF))

pub fn word(at u32) i64:
	signed16(cpu.read16(at))

pub fn setWord(at u32, v i64):
	cpu.write16(at, u32.wrap(v))

pub fn readRect(at u32) Rect:
	Rect(top = word(at), left = word(at + 2), bottom = word(at + 4), right = word(at + 6))

pub fn writeRect(at u32, r Rect):
	setWord(at, r.top)
	setWord(at + 2, r.left)
	setWord(at + 4, r.bottom)
	setWord(at + 6, r.right)

pub fn isEmptyRect(r Rect) bool:
	r.bottom <= r.top or r.right <= r.left

pub fn rectToArea(r Rect) Area:
	rectArea(r.top, r.left, r.bottom, r.right)

# a point's word pair as (v, h)
pub fn readPoint(at u32) (i64, i64):
	(word(at), word(at + 2))

# a Point passed by value: v in the high word, h in the low
pub fn pointOf(v u32) (i64, i64):
	(signed16(v >> 16), signed16(v))

pub fn pointValue(v i64, h i64) u32:
	u32.wrap(v) << 16 | u32.wrap(h) & 0xFFFF

# the variable thePort, below the globals InitGraf was given
pub fn thePortVar() u32:
	cpu.read32(cpu.a5)

pub fn thePort() u32:
	cpu.read32(thePortVar())

pub fn setPort(p u32):
	cpu.write32(thePortVar(), p)

pub fn screenBitsAt() u32:
	thePortVar() - globalScreenBits

fn setPattern(at u32, high u32, low u32):
	cpu.write32(at, high)
	cpu.write32(at + 4, low)

pub fn copyPattern(to u32, from u32):
	cpu.write32(to, cpu.read32(from))
	cpu.write32(to + 4, cpu.read32(from + 4))

arrowData = [
	0x0000,
	0x4000,
	0x6000,
	0x7000,
	0x7800,
	0x7C00,
	0x7E00,
	0x7F00,
	0x7F80,
	0x7C00,
	0x6C00,
	0x4600,
	0x0600,
	0x0300,
	0x0300,
	0x0000
]
arrowMask = [
	0xC000,
	0xE000,
	0xF000,
	0xF800,
	0xFC00,
	0xFE00,
	0xFF00,
	0xFF80,
	0xFFC0,
	0xFFE0,
	0xFE00,
	0xEF00,
	0xCF00,
	0x8780,
	0x0780,
	0x0380
]

# InitGraf: the globals below thePort's variable, at globalPtr
pub fn initGraf(globalPtr u32):
	cpu.write32(cpu.a5, globalPtr)
	g = globalPtr
	setPattern(g - globalWhite, 0, 0)
	setPattern(g - globalBlack, 0xFFFF_FFFF, 0xFFFF_FFFF)
	setPattern(g - globalGray, 0xAA55_AA55, 0xAA55_AA55)
	setPattern(g - globalLtGray, 0x8822_8822, 0x8822_8822)
	setPattern(g - globalDkGray, 0x77DD_77DD, 0x77DD_77DD)
	arrow = g - globalArrow
	for i in 0..16:
		cpu.write16(arrow + u32(2 * i), u32(arrowData[i]))
		cpu.write16(arrow + 32 + u32(2 * i), u32(arrowMask[i]))
	cpu.write32(arrow + 64, 0x0001_0001)
	bits = g - globalScreenBits
	cpu.write32(bits, screenBase)
	setWord(bits + 4, screenRowBytes)
	writeRect(bits + 6, Rect(top = 0, left = 0, bottom = screenHeight, right = screenWidth))
	cpu.write32(g - globalRandSeed, 1)
	cpu.write32(g, 0)
	cpu.write8(qdExistAt, 0)

pub fn blackPattern() u32:
	thePortVar() - globalBlack

pub fn whitePattern() u32:
	thePortVar() - globalWhite

pub fn grayPattern() u32:
	thePortVar() - globalGray

# NewRgn: an empty region's handle
pub fn newRegion() u32:
	h = newHandle(theZone(), 10)
	p = address(cpu.read32(h))
	cpu.write16(p, 10)
	writeRect(p + 2, Rect(top = 0, left = 0, bottom = 0, right = 0))
	h

pub fn setRectRegion(h u32, r Rect):
	if r.isEmptyRect():
		writeArea(h, emptyArea())
		return
	writeArea(h, r.rectToArea())

# InitPort: the port's fields as a new port has them, over the whole screen
pub fn initPort(port u32):
	bits = screenBitsAt()
	setWord(port, 0)
	cpu.write32(port + portBits, cpu.read32(bits))
	setWord(port + portBits + 4, word(bits + 4))
	screen = readRect(bits + 6)
	writeRect(port + portBounds, screen)
	writeRect(port + portRect, screen)
	setRectRegion(cpu.read32(port + portVisRgn), screen)
	setRectRegion(
		cpu.read32(port + portClipRgn),
		Rect(top = -32_767, left = -32_767, bottom = 32_767, right = 32_767)
	)
	copyPattern(port + portBkPat, whitePattern())
	copyPattern(port + portFillPat, blackPattern())
	cpu.write32(port + portPnLoc, 0)
	cpu.write32(port + portPnSize, 0x0001_0001)
	setWord(port + portPnMode, patCopy)
	copyPattern(port + portPnPat, blackPattern())
	setWord(port + portPnVis, 0)
	setWord(port + portTxFont, 0)
	setWord(port + portTxFace, 0)
	setWord(port + portTxMode, srcOr)
	setWord(port + portTxSize, 0)
	cpu.write32(port + portSpExtra, 0)
	cpu.write32(port + portFgColor, 33)
	cpu.write32(port + portBkColor, 30)
	setWord(port + 88, 0)
	setWord(port + 90, 0)
	cpu.write32(port + portPicSave, 0)
	cpu.write32(port + portRgnSave, 0)
	cpu.write32(port + portPolySave, 0)
	cpu.write32(port + portGrafProcs, 0)
	setPort(port)

# OpenPort: a port's regions made, then its fields as InitPort sets them
pub fn openPort(port u32):
	cpu.write32(port + portVisRgn, newRegion())
	cpu.write32(port + portClipRgn, newRegion())
	initPort(port)

pub fn closePort(port u32):
	disposeHandle(cpu.read32(port + portVisRgn))
	disposeHandle(cpu.read32(port + portClipRgn))

# the port's local point (v, h) in global coordinates
pub fn localToGlobal(port u32, v i64, h i64) (i64, i64):
	bounds = readRect(port + portBounds)
	(v - bounds.top, h - bounds.left)

pub fn globalToLocal(port u32, v i64, h i64) (i64, i64):
	bounds = readRect(port + portBounds)
	(v + bounds.top, h + bounds.left)

# SetOrigin: the port's rectangle, bounds and visRgn moved so its top left is (h, v)
pub fn setOrigin(port u32, h i64, v i64):
	r = readRect(port + portRect)
	dh = h - r.left
	dv = v - r.top
	if dh == 0 and dv == 0: return
	writeRect(
		port + portRect,
		Rect(top = v, left = h, bottom = r.bottom + dv, right = r.right + dh)
	)
	b = readRect(port + portBounds)
	writeRect(
		port + portBounds,
		Rect(top = b.top + dv, left = b.left + dh, bottom = b.bottom + dv, right = b.right + dh)
	)
	vis = cpu.read32(port + portVisRgn)
	writeArea(vis, areaOfHandle(vis).offset(dh, dv))
