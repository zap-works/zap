# The copy protection (SDLPoP's seg000.c start_game and show_copyprot, seg003.c play_level and
# draw_rooms, seg005.c, seg008.c): the potions level, entered after a level when
# enable_copyprot is on, where the one potion that begins with the letter the manual's entry
# gives is the right one to drink.

# the 40 entries of the manual: the letter and the word, the line and the page it is on
copyprotLetter = "AABBCCDDEFFGHHIIJJKLLMMNOOPPRRSSTTUUVYWY"
copyprotWord = [
	9,
	1,
	6,
	4,
	5,
	3,
	6,
	3,
	4,
	4,
	3,
	2,
	12,
	5,
	13,
	1,
	9,
	2,
	2,
	4,
	9,
	4,
	11,
	8,
	5,
	4,
	1,
	6,
	2,
	4,
	6,
	8,
	4,
	2,
	7,
	11, 5, 4, 1, 2
]
copyprotLine = [
	2,
	1,
	5,
	4,
	3,
	5,
	1,
	3,
	7,
	2,
	2,
	4,
	6,
	6,
	2,
	6,
	3,
	1,
	2,
	3,
	2,
	2,
	3,
	10,
	5,
	6,
	5,
	6,
	3,
	5,
	7,
	2,
	2,
	4,
	5,
	7,
	2, 6, 5, 5
]
copyprotPage = [
	5,
	3,
	7,
	3,
	3,
	4,
	1,
	5,
	12,
	5,
	11,
	10,
	1,
	2,
	8,
	8,
	2,
	4,
	6,
	1,
	4,
	7,
	3,
	2,
	1,
	7,
	10,
	1,
	4,
	3,
	4,
	1,
	4,
	1,
	8,
	1, 1, 10, 3, 3
]

# the 14 potions' places: the room and the tile
copyprotTile = [1, 5, 7, 9, 11, 21, 1, 3, 7, 11, 17, 21, 25, 27]

# the dialog's rectangle, its text one pixel in and two (dialog_rect_1)
dialogRect = Rect(60, 56, 124, 264)

# the letters the 14 potions get: which of the 40 entries each shows, no two the same, none
# with a letter another has (start_game's draws)
pub fn initCopyprot(mut g Game):
	g.copyprotPlac = g.prandom(13)
	entryUsed = zeros(40)
	letterUsed = zeros(26)
	for pos in 0..14:
		which = 0
		loop:
			which = g.prandom(39)
			if pos == g.copyprotPlac: g.copyprotIdx = which
			if entryUsed[which] == 0 and letterUsed[i64(copyprotLetter[which]) - 65] == 0: break
		g.cplevelEntr[pos] = which
		entryUsed[which] = 1
		letterUsed[i64(copyprotLetter[which]) - 65] = 1

# the level to play when n is asked for: the potions level in the place of the copy protection's
pub fn protectedLevel(g Game, n i64) i64:
	15 if g.options.isOn("enable_copyprot") and n == g.options.opt("copyprot_level") else n

# the level that follows a level played (play_level's "hacked" end): the potions level after the
# copy protection's, the level after the potions
pub fn levelAfter(mut g Game, n i64) i64:
	if g.options.isOn("enable_copyprot") and n == g.options.opt("copyprot_level"): return 15
	if n == 16:
		after = g.options.opt("copyprot_level")
		g.options.values["copyprot_level"] = [-1]
		return after
	n

# the letters over the potions of the level, drawn with the room (draw_rooms)
pub fn drawCopyprotLetters(mut g Game):
	if g.currentLevel != 15: return
	g.screen.toOnscreen = false
	for i in 0..14:
		if g.copyprotRoom[i] == g.drawnRoom:
			x = copyprotTile[i] % 10 * 32 + 24
			y = copyprotTile[i] / 10 * 63 + 38
			g.drawTextCharacter(copyprotLetter[g.cplevelEntr[i]], x, y, 15)
	g.screen.toOnscreen = true

# a potion drunk on the potions level loses its letter (seg005.c)
pub fn removeCopyprotLetter(mut g Game, room i64, tilepos i64):
	if g.currentLevel != 15: return
	for i in 0..14:
		if g.copyprotRoom[i] == room and copyprotTile[i] == tilepos:
			g.copyprotRoom[i] = 0
			return

# the tile of the right potion is a bubbling open one (seg008.c)
pub fn isRightPotion(g Game, room i64, tilepos i64) bool:
	g.currentLevel == 15 and g.copyprotRoom[g.copyprotPlac] == room and
		copyprotTile[g.copyprotPlac] == tilepos

# show_copyprot: where 0 the question in a dialog that waits for a key, where 1 the answer's
# place in the manual at the bottom, when no text is there
pub fn showCopyprot(mut g Game, where i64):
	if g.currentLevel != 15: return
	word = copyprotWord[g.copyprotIdx]
	line = copyprotLine[g.copyprotIdx]
	page = copyprotPage[g.copyprotIdx]
	if where != 0:
		if g.textTimeRemaining != 0: return
		g.textTimeTotal = 1188
		g.textTimeRemaining = 1188
		g.isShowTime = 0
		g.displayTextBottom("WORD {word} LINE {line} PAGE {page}")
	else:
		g.showDialog(
			"Drink potion matching the first letter of Word {word} on Line {line}\nof Page {page} of the manual."
		)

# show_dialog: the text in a framed box over the screen, until a key
fn showDialog(mut g Game, text str):
	g.drawDialog(text)
	g.dialogWait = true

# the rectangle the dialog's frame covers (the dialog's peel)
fn dialogPeelRect():
	t = dialogRect
	Rect(t.top - 4, t.left - 4, t.bottom + 4 + 3, t.right + 4 + 4)

# the dialog's frame and text (dialog_method_2_frame)
fn drawDialog(mut g Game, text str):
	g.drawDialogTrimmed(text, 0)

# the dialog with its text `trim` lines of pixels shorter at the bottom (room for buttons)
fn drawDialogTrimmed(mut g Game, text str, trim i64):
	t = dialogRect
	peel = dialogPeelRect()
	white = 15
	shadow = 8
	g.screen.drawRect(g.pal, t, colorBlack)
	g.screen.drawRect(g.pal, Rect(peel.top, peel.left, peel.bottom - 3, peel.right - 4), colorBlack)
	g.screen.drawRect(g.pal, Rect(t.top, peel.right - 4, peel.bottom, peel.right), shadow)
	g.screen.drawRect(g.pal, Rect(peel.bottom - 3, t.left, peel.bottom, peel.right), shadow)
	g.screen.drawRect(g.pal, Rect(peel.top + 1, peel.left + 1, t.bottom, t.left), white)
	g.screen.drawRect(g.pal, Rect(peel.top + 1, t.left, t.top, t.right + 3), white)
	g.screen.drawRect(g.pal, Rect(t.top, t.right, t.bottom + 3, t.right + 3), white)
	g.screen.drawRect(g.pal, Rect(t.bottom, peel.left + 1, t.bottom + 3, t.right), white)
	g.showText(Rect(t.top + 1, t.left + 2, t.bottom - 1 - trim, t.right - 2), 0, 0, text, 15)
