# The margins of a line drawn wide: the pixels left of x 0 and right of x 255 composed as the
# native ones are (compose.zap's composeScreens), from the margin's tiles and sprites.

# The margin pixels of the line the segment [from, to] of the native line belongs to: the left
# ones with the line's first segment, the right ones with its last.
fn drawMargins(from i64, to i64, layers Layer[], priorities i64[4]):
	if from == 0: drawMarginRange(0 - reachLeft(), -1, layers, priorities)
	if to == screenWidth - 1:
		drawMarginRange(screenWidth, screenWidth + reachRight() - 1, layers, priorities)

fn drawMarginRange(from i64, to i64, layers Layer[], priorities i64[4]):
	if to < from: return
	if isBlanked():
		for x in from..=to:
			wideStore(x, 0)
		return
	composeScreens(from, to, layers, priorities, false)
	for x in from..=to:
		at = x + spriteMargin
		main = mathPixel(
			mainColor[at],
			subColor[at],
			mainMath[at],
			subPrio[at] > 0,
			insideWindows(5, x)
		)
		wideStore(x, withBrightness(main))
