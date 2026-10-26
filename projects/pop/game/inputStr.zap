# input_str (SDLPoP's seg009.c): a line of text typed in a box, a tick at a time. A timer of 6
# ticks toggles the cursor; a key ends the wait, draws the cursor, and is acted on.

# a line being typed
pub type InputStr:
	rect Rect = Rect(0, 0, 0, 0)
	text str = ""
	pad i64 = 0   # the space left of the first letter
	color i64 = 15
	bg i64 = 0
	maxLen i64 = 24
	visible bool = false
	timer i64 = 0

# the box emptied and the first wait begun
pub fn startInputStr(mut g Game, rect Rect, color i64, bg i64, pad i64, maxLen i64):
	g.inputStr = InputStr(rect, pad, color, bg, maxLen)
	g.screen.drawRect(g.pal, rect, bg)
	g.cursorWait()

# where the next letter goes
fn inputStrPos(g Game):
	r = g.inputStr.rect
	f = g.font()
	empty = r.bottom - f.aboveBaseline - f.belowBaseline - r.top
	y = (empty - empty % 2) / 2 + f.aboveBaseline + empty % 2 + r.top
	x = r.left + g.inputStr.pad
	for k in 0..g.inputStr.text.len:
		x += g.charWidth(g.inputStr.text[k])
	(x, y)

fn drawCursor(mut g Game, color i64):
	x, y = g.inputStrPos()
	g.drawTextCharacter(95, x, y, color)

# the top of input_str's loop: the cursor drawn as it is, toggled, a timer started
fn cursorWait(mut g Game):
	g.drawCursor(g.inputStr.color if g.inputStr.visible else g.inputStr.bg)
	g.inputStr.visible = not g.inputStr.visible
	g.inputStr.timer = 6

# a tick of input_str: 0 while typing, 1 when Enter ends the line, -1 when Esc cancels it
pub fn inputStrTick(mut g Game) i64:
	s = g.inputStr.copy()
	if not (g.input.enter or g.input.backspace or g.input.typed != 0 or g.input.pressed != ""):
		g.inputStr.timer -= 1
		if g.inputStr.timer <= 0: g.cursorWait()
		return 0
	g.cursorWait()
	if g.inputStr.visible:
		g.drawCursor(s.color)
		g.inputStr.visible = false
	if g.input.enter: return 1
	if g.input.pressed == "esc":
		g.screen.drawRect(g.pal, s.rect, s.bg)
		return -1
	if g.input.backspace and not s.text.isEmpty:
		g.drawCursor(s.bg)
		last = i64(s.text[len - 1])
		g.inputStr.text = s.text[..s.text.len - 1].copy()
		x, y = g.inputStrPos()
		g.drawTextCharacter(last, x, y, s.bg)
		g.drawCursor(s.color)
	elif g.input.typed >= 0x20 and g.input.typed <= 0x7E and s.text.len < s.maxLen:
		x, y = g.inputStrPos()
		if g.charWidth(95) + g.charWidth(g.input.typed) + x < s.rect.right:
			g.drawCursor(s.bg)
			g.drawTextCharacter(g.input.typed, x, y, s.color)
			g.inputStr.text = "{s.text}{str.fromCode(g.input.typed)}"
	g.cursorWait()
	0
