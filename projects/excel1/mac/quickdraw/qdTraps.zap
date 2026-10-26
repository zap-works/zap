# long: QuickDraw's traps, one arm each
#
# QuickDraw's traps: their Pascal arguments popped (the last pushed first) and their work done on
# the current port.

import cpu

fn popRect():
	readRect(popLong())

fn popPoint():
	pointOf(popLong())

pub fn bytesAt(at u32, count i64) u8[]:
	(0..count).map(u8(cpu.read8(at + u32(it))))

# the bytes of the Pascal string at `at`
pub fn pascalAt(at u32) u8[]:
	bytesAt(at + 1, cpu.read8(at))

pub fn writePascal(at u32, bytes u8[]):
	cpu.write8(at, u32(bytes.len))
	for i, b in bytes:
		cpu.write8(at + 1 + u32(i), b)

fn port():
	thePort()

# the pen's position, then moved to (h, v)
fn movePen(h i64, v i64):
	setWord(port() + portPnLoc, v)
	setWord(port() + portPnLoc + 2, h)

fn penAt():
	(word(port() + portPnLoc + 2), word(port() + portPnLoc))

fn lineTo(h i64, v i64):
	h0, v0 = penAt()
	a = lineArea(port(), h0, v0, h, v)
	movePen(h, v)
	if a.recordOutline(): return
	penPaint(port(), a)

# a shape drawn by one of the five verbs: 0 frame, 1 paint, 2 erase, 3 invert, 4 fill
fn drawShape(verb i64, outer Area, inner Area, pattern u32):
	p = port()
	match verb:
		0:
			if outer.recordOutline(): return
			penPaint(p, outer.frameOf(inner))
		1: penPaint(p, outer)
		2: paintArea(p, outer, p + portBkPat, patCopy)
		3: paintArea(p, outer, blackPattern(), 10)
		_: paintArea(p, outer, pattern, patCopy)

# the outer and inner (moved in by the pen) areas of a rectangle
fn rectAreas(r Rect):
	pv, ph = penSize(port())
	(r.rectToArea(), rectArea(r.top + pv, r.left + ph, r.bottom - pv, r.right - ph))

fn ovalAreas(r Rect):
	pv, ph = penSize(port())
	(
		r.ovalArea(),
		ovalArea(
			Rect(top = r.top + pv, left = r.left + ph, bottom = r.bottom - pv, right = r.right - ph)
		)
	)

fn regionOp(op i64):
	dst = popLong()
	b = areaOfHandle(popLong())
	a = areaOfHandle(popLong())
	writeArea(dst, a.combine(b, op))

# between OpenRgn and CloseRgn: the outlines framed, gathered (each xor'd in) instead of drawn
pub mut recording = emptyArea()
pub mut isRecording = false

fn recordOutline(a Area):
	if not isRecording: return false
	recording = recording.combine(a, 3)
	true

fn sectRect(a Rect, b Rect):
	r = Rect(
		top = a.top.max(b.top),
		left = a.left.max(b.left),
		bottom = a.bottom.min(b.bottom),
		right = a.right.min(b.right)
	)
	Rect(top = 0, left = 0, bottom = 0, right = 0) if r.isEmptyRect() else r

# long: a dispatch, an arm a trap
pub fn quickdrawTrap(n i64, trapWord i64, back u32) u32:
	match n:
		0x50, 0x51, 0x52, 0x53, 0x55, 0x56: popArgsOfCursor(n)
		0x61:
			seedAt = thePortVar() - 126
			seed = cpu.read32(seedAt)
			next = u32((u64(seed) * 16_807) % 0x7FFF_FFFF)
			cpu.write32(seedAt, next)
			resultWord(next & 0xFFFF)
		0x62, 0x63:
			color = popLong()
			cpu.write32(port() + (portFgColor if n == 0x62 else portBkColor), color)
		0x65:
			v = popInt()
			h = popInt()
			p = port()
			c = canvasOf(p)
			isInside = v >= c.bounds.top and v < c.bounds.bottom and h >= c.bounds.left and
				h < c.bounds.right
			resultBool(isInside and c.isPixelSet(h, v))
		0x6A: resultWord(popLong() >> 16)
		0x6B: resultWord(popLong() & 0xFFFF)
		0x6D: initPort(popLong())
		0x6E: initGraf(popLong())
		0x6F: openPort(popLong())
		0x70, 0x71:
			at = popLong()
			v, h = readPoint(at)
			gv, gh = localToGlobal(port(), v, h) if n == 0x70 else globalToLocal(port(), v, h)
			setWord(at, gv)
			setWord(at + 2, gh)
		0x72: setWord(port(), popInt())
		0x73: setPort(popLong())
		0x74: cpu.write32(popLong(), port())
		0x75:
			bits = popLong()
			moveBytes(port() + portBits, bits, 14)
		0x76:
			height = popInt()
			width = popInt()
			r = readRect(port() + portRect)
			writeRect(port() + portRect, Rect(..r, bottom = r.top + height, right = r.left + width))
		0x77:
			top = popInt()
			left = popInt()
			p = port()
			r = readRect(p + portRect)
			b = readRect(p + portBounds)
			writeRect(
				p + portBounds,
				Rect(
					top = r.top - top,
					left = r.left - left,
					bottom = r.top - top + b.bottom - b.top,
					right = r.left - left + b.right - b.left
				)
			)
		0x78:
			v = popInt()
			h = popInt()
			setOrigin(port(), h, v)
		0x79: writeArea(cpu.read32(port() + portClipRgn), areaOfHandle(popLong()))
		0x7A: writeArea(popLong(), areaOfHandle(cpu.read32(port() + portClipRgn)))
		0x7B: setRectRegion(cpu.read32(port() + portClipRgn), popRect())
		0x7C: copyPattern(port() + portBkPat, popLong())
		0x7D: closePort(popLong())
		0x7E, 0x7F:
			at = popLong()
			sv, sh = popPoint()
			v, h = readPoint(at)
			sign = 1 if n == 0x7E else -1
			setWord(at, v + sign * sv)
			setWord(at + 2, h + sign * sh)
		0x80:
			v = popInt()
			h = popInt()
			at = popLong()
			setWord(at, v)
			setWord(at + 2, h)
		0x81:
			b = popLong()
			a = popLong()
			resultBool(a == b)
		0x82:
			popLong()
			popLong()
			at = popLong()
			count = popInt()
			drawText(port(), bytesAt(at, count))
		0x83: drawTextVia(port(), [popWord() & 0xFF])
		0x84:
			text = pascalAt(popLong())
			if traceTraps:
				font = word(port() + portTxFont)
				size = word(port() + portTxSize)
				h, v = penAt()
				eprint("  \"{str(text)}\" at {h},{v} in font {font} size {size} face {cpu.read8(port() + portTxFace)}")
			drawTextVia(port(), text)
		0x85:
			count = popInt()
			first = popInt()
			at = popLong()
			drawTextVia(port(), bytesAt(at + u32(first), count))
		0x86:
			count = popInt()
			first = popInt()
			at = popLong()
			resultWord(textWidth(port(), bytesAt(at + u32(first), count)))
		0x87: setWord(port() + portTxFont, popInt())
		0x88: cpu.write8(port() + portTxFace, popWord() & 0xFF)   # a Style set: its byte low
		0x89: setWord(port() + portTxMode, popInt())
		0x8A: setWord(port() + portTxSize, popInt())
		0x8B:
			at = popLong()
			ascent, descent, widMax, leading = fontInfo(port())
			setWord(at, ascent)
			setWord(at + 2, descent)
			setWord(at + 4, widMax)
			setWord(at + 6, leading)
		0x8C: resultWord(textWidth(port(), pascalAt(popLong())))
		0x8D: resultWord(textWidth(port(), [popWord() & 0xFF]))
		0x8E: cpu.write32(port() + portSpExtra, popLong())
		0xED:
			info = popLong()
			popLong()
			popLong()
			at = popLong()
			count = popInt()
			ascent, descent, widMax, leading = fontInfo(port())
			setWord(info, ascent)
			setWord(info + 2, descent)
			setWord(info + 4, widMax)
			setWord(info + 6, leading)
			resultWord(textWidth(port(), bytesAt(at, count)))
		0xEC:
			mask = popLong()
			mode = popInt()
			to = popRect()
			from = popRect()
			dest = popLong()
			copyBits(popLong(), dest, from, to, mode, mask)
		0xFE: pass
		0xFF:
			at = popLong()
			writePascal(at, fontName(popInt()))
		0x100:
			at = popLong()
			setWord(at, fontNumber(pascalAt(popLong())))
		0x102:
			size = popInt()
			family = popInt()
			resultBool(findResource(0x464F_4E54, family * 128 + size, [], false) != none)
		0x103: popWord()
		0x91:
			v = popInt()
			h = popInt()
			lineTo(h, v)
		0x92:
			dv = popInt()
			dh = popInt()
			h, v = penAt()
			lineTo(h + dh, v + dv)
		0x93:
			v = popInt()
			h = popInt()
			movePen(h, v)
		0x94:
			dv = popInt()
			dh = popInt()
			h, v = penAt()
			movePen(h + dh, v + dv)
		0x96: setWord(port() + portPnVis, word(port() + portPnVis) - 1)
		0x97: setWord(port() + portPnVis, word(port() + portPnVis) + 1)
		0x98: moveBytes(popLong(), port() + portPnLoc, 18)
		0x99: moveBytes(port() + portPnLoc, popLong(), 18)
		0x9A:
			at = popLong()
			cpu.write32(at, cpu.read32(port() + portPnLoc))
		0x9B:
			height = popInt()
			width = popInt()
			setWord(port() + portPnSize, height)
			setWord(port() + portPnSize + 2, width)
		0x9C: setWord(port() + portPnMode, popInt())
		0x9D: copyPattern(port() + portPnPat, popLong())
		0x9E:
			p = port()
			cpu.write32(p + portPnSize, 0x0001_0001)
			setWord(p + portPnMode, patCopy)
			copyPattern(p + portPnPat, blackPattern())
		0xA1, 0xA2, 0xA3, 0xA4:
			outer, inner = popRect().rectAreas()
			drawShape(n - 0xA1, outer, inner, 0)
		0xA5:
			pattern = popLong()
			outer, inner = popRect().rectAreas()
			drawShape(4, outer, inner, pattern)
		0xA6:
			b = popRect()
			a = popRect()
			resultBool(a == b)
		0xA7:
			bottom = popInt()
			right = popInt()
			top = popInt()
			left = popInt()
			writeRect(popLong(), Rect(top, left, bottom, right))
		0xA8, 0xA9:
			dv = popInt()
			dh = popInt()
			at = popLong()
			r = readRect(at)
			if n == 0xA8:
				writeRect(
					at,
					Rect(
						top = r.top + dv,
						left = r.left + dh,
						bottom = r.bottom + dv,
						right = r.right + dh
					)
				)
			else:
				inset = Rect(
					top = r.top + dv,
					left = r.left + dh,
					bottom = r.bottom - dv,
					right = r.right - dh
				)
				writeRect(
					at,
					Rect(top = 0, left = 0, bottom = 0, right = 0) if inset.isEmptyRect() else inset
				)
		0xAA:
			dst = popLong()
			b = popRect()
			a = popRect()
			r = a.sectRect(b)
			writeRect(dst, r)
			resultBool(not r.isEmptyRect())
		0xAB:
			dst = popLong()
			b = popRect()
			a = popRect()
			writeRect(
				dst,
				Rect(
					top = a.top.min(b.top),
					left = a.left.min(b.left),
					bottom = a.bottom.max(b.bottom),
					right = a.right.max(b.right)
				)
			)
		0xAC:
			dst = popLong()
			bv, bh = popPoint()
			av, ah = popPoint()
			writeRect(
				dst,
				Rect(top = av.min(bv), left = ah.min(bh), bottom = av.max(bv), right = ah.max(bh))
			)
		0xAD:
			r = popRect()
			v, h = popPoint()
			resultBool(v >= r.top and v < r.bottom and h >= r.left and h < r.right)
		0xAE: resultBool(popRect().isEmptyRect())
		0xB0, 0xB1, 0xB2, 0xB3, 0xB4:
			pattern = popLong() if n == 0xB4 else 0
			ovalHeight = popInt()
			ovalWidth = popInt()
			r = popRect()
			pv, ph = penSize(port())
			outer = r.roundRectArea(ovalWidth, ovalHeight)
			inner = roundRectArea(
				Rect(top = r.top + pv, left = r.left + ph, bottom = r.bottom - pv, right = r.right - ph),
				ovalWidth - 2 * ph,
				ovalHeight - 2 * pv
			)
			drawShape(n - 0xB0, outer, inner, pattern)
		0xB7, 0xB8, 0xB9, 0xBA, 0xBB:
			pattern = popLong() if n == 0xBB else 0
			outer, inner = popRect().ovalAreas()
			drawShape(n - 0xB7, outer, inner, pattern)
		0xD2, 0xD3, 0xD4, 0xD5, 0xD6:
			pattern = popLong() if n == 0xD6 else 0
			a = areaOfHandle(popLong())
			pv, ph = penSize(port())
			drawShape(n - 0xD2, a, a.inset(ph, pv), pattern)
		0xD8: cpu.write32(cpu.a7, newRegion())
		0xD9: disposeHandle(popLong())
		0xDA:
			isRecording = true
			recording = emptyArea()
		0xDB:
			isRecording = false
			gathered = recording.copy()
			writeArea(popLong(), gathered)
			recording = emptyArea()
		0xDC:
			dst = popLong()
			writeArea(dst, areaOfHandle(popLong()))
		0xDD: writeArea(popLong(), emptyArea())
		0xDE:
			bottom = popInt()
			right = popInt()
			top = popInt()
			left = popInt()
			setRectRegion(popLong(), Rect(top, left, bottom, right))
		0xDF:
			r = popRect()
			setRectRegion(popLong(), r)
		0xE0, 0xE1:
			dv = popInt()
			dh = popInt()
			h = popLong()
			a = areaOfHandle(h)
			writeArea(h, a.offset(dh, dv) if n == 0xE0 else a.inset(dh, dv))
		0xE2: resultBool(areaOfHandle(popLong()).isEmpty)
		0xE3:
			b = areaOfHandle(popLong())
			a = areaOfHandle(popLong())
			resultBool(a.combine(b, 3).isEmpty)
		0xE4: regionOp(1)
		0xE5: regionOp(0)
		0xE6: regionOp(2)
		0xE7: regionOp(3)
		0xE8:
			a = areaOfHandle(popLong())
			v, h = popPoint()
			resultBool(a.containsPoint(h, v))
		0xE9:
			a = areaOfHandle(popLong())
			r = popRect()
			resultBool(not a.combine(r.rectToArea(), 1).isEmpty)
		0xEA:
			at = popLong()
			for i, trap in stdProcTraps:
				cpu.write32(at + u32(4 * i), romAddress(256 + trap))
		_: return utilityTrap(n, trapWord, back)
	back

# the traps of a QDProcs record's procedures, in its order: text, line, rect, rRect, oval, arc,
# poly, rgn, bits, comment, txMeas, getPic, putPic
stdProcTraps = [0x82, 0x90, 0xA0, 0xAF, 0xB6, 0xBD, 0xC5, 0xD1, 0xEB, 0xF1, 0xED, 0xEE, 0xF0]

# the cursor's traps: nothing drawn (the screen shows no cursor), their arguments popped
fn popArgsOfCursor(n i64):
	match n:
		0x51: popLong()
		0x55:
			popLong()
			popLong()
		_: pass
	0
