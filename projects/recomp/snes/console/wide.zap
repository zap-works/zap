# The widescreen picture: `--wide` (342 pixels, 43 more each side), `--wide --wide-width N` (an even
# width from 256 to 512, as far as a sprite's 9 bits of x reach) or `--wide-width screen`, as wide as
# the screen's shape asks once the screen is known (fitWideToScreen).
# The cartridge runs as it does natively, its work RAM, camera and collision untouched; only what
# is drawn grows: a second composition of each line that reaches past the 256 pixels (widedraw.zap),
# its sprites from the 9 bits of the OAM's x (sprites.zap), the object windows the cartridge culls
# by widened (the helpers below, called where a game's patches put them, snes/game.zap).
#
# What a scene is and what lies beyond its 256 pixels is judged each frame at the end of line 0:
# by the PPU alone for any game (ppuScene), or by a game's hooks that know its levels (dkc's).
# Fail-closed: a frame not judged a scene is the native 256 pixels centred on black.

pub mut wideWidth = 256   # the picture's width: 256, or with --wide its --wide-width (342 by default)
pub mut sideLeft = 0      # columns the picture adds left of the native 256 at rest
pub mut sideRight = 0
pub mut wideOn = false    # this frame's scene is drawn wide
pub mut wideWhy = 0       # why the scene is centred, as the game's judge says it (0: it is not)
pub mut logicNative = false   # --wide-native-logic: the cartridge's windows are not widened, so its
                          # work RAM stays what Mesen 2's is (the routes keep in step); only drawing is wide
mut wideBias = 0          # the native picture's shift in the wide one, 0 when the scene allows
mut wideFrame u16[] = []  # the wide frame's colours (BGR555), row by row, while wideOn

# whether the frame that begins is drawn wide, why not (a number of the game's, in the
# --wide-hashes lines), and the native picture's shift in the wide one
pub type SceneJudgement:
	on bool = false
	why i64 = 1
	bias i64 = 0

# What the game tells the wide drawing (installed by the program's setup lines, game.zap); without
# them the drawing judges by the PPU alone (below).
pub type WideHooks:
	judge fn() SceneJudgement = ppuScene   # at the end of line 0
	sceneId fn() i64 = noSceneId          # what names the scene, in the --wide-hashes lines
	marginPixel fn(Layer, i64) i64 = tilemapPixel   # a layer's pixel at x < 0 or x > 255

fn noSceneId():
	0

# `--wide-scenes all`: every frame of one screen's width drawn wide, not mode 7's alone
mut allScenes = false

# Any game, as bsnes-hd widens it: mode 7, whose plane goes on past the 256 pixels, and with
# --wide-scenes all every mode of one screen's width, its margins from what the tilemaps hold
# past the view (the next columns in many games, the view's other edge again in others). Never
# a blanked, mosaic or high-resolution frame.
fn ppuScene():
	mode = ppuRegs[5] & 7
	if isBlanked() or mode == 5 or mode == 6 or ppuRegs[0x33] & 8 != 0 or
		ppuRegs[6] & 0xF0 != 0 and ppuRegs[6] & 0x0F != 0:
		return SceneJudgement(why = 1)
	if mode != 7 and not allScenes: return SceneJudgement(why = 2)
	SceneJudgement(on = true, why = 0)

# a layer's pixel in the margin from its own tilemap (mode 7's plane is drawn whole by layerPixel);
# a tilemap one screen wide (32 columns) has nothing past the view, only the view again: none
fn tilemapPixel(layer Layer, x i64):
	if ppuRegs[7 + layer.bg] & 1 == 0: return 0
	layer.tilePixel(x + hScroll[layer.bg], line, false)

pub mut wideHooks = WideHooks()

fn setupWide():
	if not hasPresetFlag("--wide"): return
	given = presetOption("--wide-width") ?? "342"
	wideToScreen = given == "screen"
	setWideWidth(342 if wideToScreen else i64.parse(given) ?? 0)
	logicNative = hasPresetFlag("--wide-native-logic")
	allScenes = (presetOption("--wide-scenes") ?? "mode7") == "all"

mut wideToScreen = false   # --wide-width screen

# the picture made `width` wide, its sides alike
fn setWideWidth(width i64):
	if width < 256 or width > 256 + 2 * spriteMargin or width % 2 != 0:
		fail("--wide-width is an even number from 256 to 512, or screen")
	wideWidth = width
	sideLeft = (wideWidth - 256) / 2
	sideRight = sideLeft
	wideFrame = zeros(wideWidth * screenHeight)

# With --wide-width screen, the width that fills a screen of that shape at the picture's height,
# taken between two frames (a screen of no size yet leaves it).
pub fn fitWideToScreen(screen IVec2):
	if not wideToScreen or screen.y <= 0: return
	want = (screenHeight * screen.x / screen.y / 2 * 2).clamp(256, 512)
	if want != wideWidth: setWideWidth(want)

# how far left of the native 256 the picture shows now, and right of them
fn reachLeft():
	(sideLeft - wideBias).max(0) if wideOn else 0

fn reachRight():
	(sideRight + wideBias).max(0) if wideOn else 0

# the sprites and sliver slots a line gains, one for each 8-pixel column the margins add
fn extraSlots():
	(reachLeft() + 7) / 8 + (reachRight() + 7) / 8 if wideOn else 0

# The cartridge's object windows, widened while the scene is: a left edge moves out by the left
# margin, a span grows by both. The recompiled code calls these where it loads those constants.
pub fn widenLeft(literal u16) u16:
	literal + u16(sideLeft) if growsLogic() else literal

pub fn widenSpan(literal u16) u16:
	literal + u16(sideLeft + sideRight) if growsLogic() else literal

# whether the cartridge's own windows are widened now
pub fn growsLogic() bool:
	wideOn and not logicNative

# Line 0 ended: the game judges the scene for the frame that begins
fn judgeScene():
	wideOn = false
	wideWhy = 1
	if wideWidth == 256: return
	j = wideHooks.judge()
	wideWhy = j.why
	if not j.on: return
	wideBias = j.bias
	wideOn = true

# a native-picture pixel (column x of the line) in the wide frame
fn wideStore(x i64, color i64):
	at = x + sideLeft - wideBias
	if at < 0 or at >= wideWidth: return
	wideFrame[(line - 1) * wideWidth + at] = u16(color)

# The picture's colours (BGR555, rows from the top): the wide frame, or the native picture centred
# on black where the scene is not drawn wide.
fn pictureColors():
	out u16[] = zeros(wideWidth * screenHeight)
	if wideOn: return wideFrame.copy()
	for y in 0..screenHeight:
		for x in 0..screenWidth:
			out[y * wideWidth + sideLeft + x] = u16(nativeColorAt(x, y))
	out
