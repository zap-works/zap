# What the pause menu draws with (SDLPoP's menu.c, seg009.c draw_rect_with_alpha and
# draw_rect_contours): the small font and the arrowheads, a translucent layer over the display, and
# the layer laid over the picture that was on the display when the menu opened.

import dos.pop
import image

# the glyph of a string of rows ("#.#/.#."), as a picture of 1 for a pixel set
fn glyphPicture(rows str):
	lines = rows.split("/")
	width = lines[0].len
	indices u8[] = []
	for line in lines:
		for k in 0..width:
			indices.push(1 if line[k] == '#' else 0)
	pop.Picture(width, lines.len, indices)

# hc_small_font: the characters 32 to 126, 5 lines above the baseline, 2 below
pub fn smallFont() pop.Font:
	pictures pop.Picture?[] = []
	for rows in smallGlyphs:
		pictures.push(glyphPicture(rows))
	pop.Font(
		first = 32,
		last = 126,
		aboveBaseline = 5,
		belowBaseline = 2,
		lineSpace = 1,
		charSpace = 1,
		pictures
	)

arrowUp = 0
arrowDown = 1
arrowLeft = 2
arrowRight = 3

# draw_image_with_blending: an arrowhead in white, its empty pixels left alone
fn drawArrow(mut g Game, which i64, x i64, y i64):
	g.screen.drawMono(g.pal, glyphPicture(arrowGlyphs[which]), x, y, 15)

# draw_rect_with_alpha: the rectangle replaced by a colour of the palette at an opacity
fn fillOverlay(mut g Game, r Rect, color i64, alpha i64):
	c = g.pal.colors[color]
	g.fillOverlayRgba(r, image.Rgba8(c.r, c.g, c.b, u8.wrap(alpha)))

fn fillOverlayRgba(mut g Game, r Rect, c image.Rgba8):
	for y in r.top.max(0)..r.bottom.min(screenHeight):
		for x in r.left.max(0)..r.right.min(screenWidth):
			g.screen.overlay[x, y] = c

# draw_rect_contours: the outline of a rectangle
fn drawContours(mut g Game, r Rect, color i64):
	c = g.pal.colors[color]
	for x in r.left.max(0)..r.right.min(screenWidth):
		g.screen.overlay[x, r.top] = c
		g.screen.overlay[x, r.bottom - 1] = c
	for y in r.top + 1..r.bottom - 1:
		g.screen.overlay[r.left, y] = c
		g.screen.overlay[r.right - 1, y] = c

# one colour of the display under one of the layer: SDL2's ALPHA_BLEND_RGBA (SDL_blit.h) as
# BlitNtoNPixelAlpha (SDL_blit_A.c) applies it from the 32-bit layer to the 24-bit merged surface:
# dst + (src - dst) * alpha / 255, the division truncating toward zero
fn blendChannel(over i64, under i64, alpha i64):
	under + (over - under) * alpha / 255

# the picture with the layer blended over a rectangle of it
fn blended(g Game, base image.Image, r Rect):
	out = base.copy()
	for y in r.top.max(0)..r.bottom.min(screenHeight):
		for x in r.left.max(0)..r.right.min(screenWidth):
			o = g.screen.overlay[x, y]
			b = base[x, y]
			a = i64(o.a)
			if a == 0: continue
			if a == 255:
				out[x, y] = o
			else:
				out[x, y] = image.Rgba8(
					u8.wrap(blendChannel(o.r, b.r, a)),
					u8.wrap(blendChannel(o.g, b.g, a)),
					u8.wrap(blendChannel(o.b, b.b, a)),
					255
				)
	out

# the display shown: the picture under the menu with the layer over it
pub fn composeMenu(mut g Game):
	g.screen.onscreen = g.blended(g.menu.base, Rect(0, 0, screenHeight, screenWidth))

# the time as the timer overlay writes it: minutes left, seconds, ticks
fn timerText(g Game):
	minutes = g.remMin - 1
	seconds = g.remTick / 12
	ticks = g.remTick % 12
	if g.remMin < 0:
		minutes = -(g.remMin + 1)
		seconds = (719 - g.remTick) / 12
		ticks = (719 - g.remTick) % 12
	"{minutes:02}:{seconds:02}:{ticks:02}"

# one box of the timer overlay: a translucent black box and the text over it
fn drawTimerBox(mut g Game, top i64, text str):
	extra = (text.len - 8).max(0)
	box = Rect(top, 0, top + 11, 2 + 5 + (6 + extra) * 9)
	g.fillOverlay(box, 0, 128)
	g.screen.toOverlay = true
	g.showText(Rect(top + 2, 2, top + 10, 100), -1, -1, text, 15)
	g.screen.toOverlay = false
	box

# the picture to show: the screen, with the timer (draw_overlay's overlay 1, T) when it is on
pub fn displayImage(mut g Game) image.Image:
	if not g.timerShown or g.startLevel <= 0 or g.menu.shown: return g.screen.onscreen.copy()
	box = g.drawTimerBox(0, g.timerText())
	shown = g.blended(g.screen.onscreen, box)
	if not g.replaying: return shown
	ticksBox = g.drawTimerBox(12, "T: {g.currTick}")
	g.blended(shown, ticksBox)
