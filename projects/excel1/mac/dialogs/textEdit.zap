# TextEdit: text in a rectangle, broken into lines at word boundaries (and at returns) to fit its
# width, and the edit record (TERec) of a dialog's editable text: destRect, viewRect, selRect,
# lineHeight, fontAscent, selPoint, selStart, selEnd, active, ..., teLength, hText, ..., txFont,
# txFace, txMode, txSize, inPort, ..., nLines and lineStarts.

import cpu

teDestRect u32 = 0
teViewRect u32 = 8
teLineHeight u32 = 24
teFontAscent u32 = 26
teSelStart u32 = 32
teSelEnd u32 = 34
teActive u32 = 36
teCaretTime u32 = 52
teCaretState u32 = 56
teJust u32 = 58
teLength u32 = 60
teTextField u32 = 62
teCrOnly u32 = 72
teFont u32 = 74
teFace u32 = 76
teMode u32 = 78
teSize u32 = 80
tePort u32 = 82
teLines u32 = 94
teLineStarts u32 = 96
teRecordSize = 104 + 2 * 64

# the starts of the lines of the text broken to fit `width` in the port's font: at a return, and
# before a word that would pass the width
pub fn lineStarts(port u32, text u8[], width i64) i64[]:
	starts = [0]
	lineStart = 0
	lastBreak = -1
	i = 0
	while i < text.len:
		c = text[i]
		if c == 13:
			starts.push(i + 1)
			lineStart = i + 1
			lastBreak = -1
		else:
			if c == ' ': lastBreak = i + 1
			if textWidth(port, text[lineStart..i + 1]) > width and i > lineStart:
				next = lastBreak if lastBreak > lineStart else i
				starts.push(next)
				lineStart = next
				lastBreak = -1
				i = next
				continue
		i += 1
	starts.push(text.len)
	starts

fn lineHeight(port u32):
	ascent, descent, _, leading = fontInfo(port)
	(ascent + descent + leading, ascent)

# TextBox: the text drawn in the rectangle, its lines aligned by `just` (0 left, 1 center, -1
# right), the rectangle erased first
pub fn textBox(port u32, text u8[], r Rect, just i64):
	paintArea(port, r.rectToArea(), port + portBkPat, patCopy)
	drawLines(port, text, r, just)

fn drawLines(port u32, text u8[], r Rect, just i64):
	saved = cpu.read32(port + portClipRgn)
	clip = areaOfHandle(saved)
	area = r.rectToArea()
	writeArea(saved, clip.combine(area, 1))
	height, ascent = lineHeight(port)
	starts = lineStarts(port, text, r.right - r.left)
	y = r.top + ascent
	for k in 0..starts.len - 1:
		end = starts[k + 1]
		while end > starts[k] and (text[end - 1] == 13 or text[end - 1] == ' '):
			end -= 1
		line = text[starts[k]..end]
		w = textWidth(port, line)
		# a left-aligned line starts a pixel in, the caret's column before it
		x = match just:
			1: r.left + (r.right - r.left - w) / 2
			-1: r.right - w
			_: r.left + 1
		setWord(port + portPnLoc, y)
		setWord(port + portPnLoc + 2, x)
		drawTextVia(port, line)
		y += height
		if y - ascent >= r.bottom: break
	writeArea(saved, clip)

fn rec(te u32):
	address(cpu.read32(te))

pub fn teText(te u32) u8[]:
	h = cpu.read32(rec(te) + teTextField)
	bytesAt(address(cpu.read32(h)), word(rec(te) + teLength))

# TENew: an edit record over the rectangles, in the current port's font, its text empty
pub fn teNew(dest Rect, view Rect) u32:
	te = newHandle(theZone(), u32(teRecordSize))
	p = rec(te)
	port = thePort()
	writeRect(p + teDestRect, dest)
	writeRect(p + teViewRect, view)
	height, ascent = lineHeight(port)
	setWord(p + teLineHeight, height)
	setWord(p + teFontAscent, ascent)
	setWord(p + teSelStart, 0)
	setWord(p + teSelEnd, 0)
	setWord(p + teActive, 0)
	setWord(p + teJust, 0)
	setWord(p + teLength, 0)
	text = newHandle(theZone(), 0)
	p2 = rec(te)
	cpu.write32(p2 + teTextField, text)
	setWord(p2 + teCrOnly, 0)
	setWord(p2 + teFont, word(port + portTxFont))
	cpu.write8(p2 + teFace, cpu.read8(port + portTxFace))
	setWord(p2 + teMode, word(port + portTxMode))
	setWord(p2 + teSize, word(port + portTxSize))
	cpu.write32(p2 + tePort, port)
	setWord(p2 + teLines, 1)
	te

pub fn teSetText(te u32, text u8[]):
	h = cpu.read32(rec(te) + teTextField)
	setHandleSize(h, u32(text.len))
	at = address(cpu.read32(h))
	for i, b in text:
		cpu.write8(at + u32(i), b)
	setWord(rec(te) + teLength, text.len)
	setWord(rec(te) + teSelStart, text.len)
	setWord(rec(te) + teSelEnd, text.len)

# TESetSelect: the selection hidden, moved, and shown again with the caret on
pub fn teSetSelect(te u32, start i64, end i64):
	if isShown(te): teHighlight(te)
	n = word(rec(te) + teLength)
	setWord(rec(te) + teSelStart, start.clamp(0, n))
	setWord(rec(te) + teSelEnd, end.clamp(0, n))
	setWord(rec(te) + teCaretState, 1)
	cpu.write32(rec(te) + teCaretTime, cpu.read32(ticksAt))
	if isShown(te): teHighlight(te)

# TEUpdate: the text drawn in its destination rectangle, in its own font, the selection inverted
# when the record is active
pub fn teUpdate(te u32):
	p = rec(te)
	port = cpu.read32(p + tePort)
	saved = word(port + portTxFont), cpu.read8(port + portTxFace), word(port + portTxSize)
	setWord(port + portTxFont, word(p + teFont))
	cpu.write8(port + portTxFace, cpu.read8(p + teFace))
	setWord(port + portTxSize, word(p + teSize))
	view = readRect(p + teViewRect)
	paintArea(port, view.rectToArea(), port + portBkPat, patCopy)
	drawLines(port, teText(te), readRect(rec(te) + teDestRect), 0)
	if isShown(te): teHighlight(te)
	font, face, size = saved
	setWord(port + portTxFont, font)
	cpu.write8(port + portTxFace, face)
	setWord(port + portTxSize, size)

# the selection inverted on one line (a dialog's field holds one): the caret when it is empty
fn teHighlight(te u32):
	p = rec(te)
	port = cpu.read32(p + tePort)
	text = teText(te)
	start = word(p + teSelStart).min(text.len)
	end = word(p + teSelEnd).min(text.len)
	dest = readRect(p + teDestRect)
	top = dest.top
	bottom = top + word(p + teLineHeight)
	left = dest.left + textWidth(port, text[..start])
	right = dest.left + textWidth(port, text[..end])
	box = rectArea(top, left, bottom, right.max(left + 1) if start == end else right)
	paintArea(port, box, blackPattern(), 10)

# whether the selection is shown: a range always while active, the caret while its blink is on
fn isShown(te u32):
	p = rec(te)
	if word(p + teActive) == 0: return false
	word(p + teSelStart) != word(p + teSelEnd) or word(p + teCaretState) != 0

# TEActivate and TEDeactivate: the selection shown (the caret on, its blink started) or hidden
pub fn teActivate(te u32, on bool):
	if (word(rec(te) + teActive) != 0) == on: return
	wasShown = isShown(te)
	setWord(rec(te) + teActive, 1 if on else 0)
	setWord(rec(te) + teCaretState, 1 if on else 0)
	cpu.write32(rec(te) + teCaretTime, cpu.read32(ticksAt))
	if isShown(te) != wasShown: teHighlight(te)

# TEIdle: the caret of an active record turned on or off each CaretTime ticks
pub fn teIdle(te u32):
	p = rec(te)
	if word(p + teActive) == 0 or word(p + teSelStart) != word(p + teSelEnd): return
	now = cpu.read32(ticksAt)
	if now - cpu.read32(p + teCaretTime) < cpu.read32(caretTimeAt): return
	setWord(p + teCaretState, 1 - word(p + teCaretState))
	cpu.write32(p + teCaretTime, now)
	teHighlight(te)

pub fn teDispose(te u32):
	disposeHandle(cpu.read32(rec(te) + teTextField))
	disposeHandle(te)

# The text from `start` to `end` replaced by `inserted`, the caret after it, the text drawn again.
fn teReplace(te u32, start i64, end i64, inserted u8[]):
	text = teText(te)
	out = text[..start].copy()
	out.extend(inserted)
	out.extend(text[end..])
	teSetText(te, out)
	teSetSelect(te, start + inserted.len, start + inserted.len)
	teUpdate(te)

fn selection(te u32):
	n = word(rec(te) + teLength)
	(word(rec(te) + teSelStart).min(n), word(rec(te) + teSelEnd).min(n))

# TEKey: a typed character in place of the selection; backspace takes the one before
pub fn teKey(te u32, c u8):
	start, end = selection(te)
	if c != 8:
		teReplace(te, start, end, [c])
	elif start != end:
		teReplace(te, start, end, [])
	elif start > 0:
		teReplace(te, start - 1, start, [])

# TEDelete: the selection taken out
pub fn teDelete(te u32):
	start, end = selection(te)
	teReplace(te, start, end, [])

# TEInsert: the text put before the selection
pub fn teInsert(te u32, inserted u8[]):
	start, _ = selection(te)
	teReplace(te, start, start, inserted)
