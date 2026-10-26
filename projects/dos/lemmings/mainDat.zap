# main.dat: the lemmings' animations (section 0), the masks they dig with and the countdown
# digits (section 1), the skill panel and its green font (section 6) and the skill digits
# (section 2), laid out as ccexplore's and Mindless's document says.

import dos
import fs
import image

# an animation of the lemming: its frames one under another in `sheet`, its foot at
# (footX, footY) of a frame
pub type Animation:
	name str
	frames i64
	width i64
	height i64
	footX i64
	footY i64
	once bool   # played once, else looped
	indices u8[]   # the frames' palette indices, one under another
	sheet image.Image   # the frames in the menus' palette

# a mask: each frame's solid pixels take terrain away
pub type Mask:
	frames i64
	width i64
	height i64
	solid bool[]   # frames * width * height

pub type MainData:
	animations Animation[]   # animationIndex's order
	bashMasks Mask[2]   # right, left
	mineMasks Mask[2]
	explosionMask Mask
	countdown image.Image[]   # digits 0..9, 8 x 8
	panel image.Image   # 320 x 40
	font image.Image[]   # "%0123456789-ABC...Z", 8 x 16 each
	skillDigits image.Image[]   # digit d at [d * 2] (right half) and [d * 2 + 1] (left half)

type AnimationSpec:
	at i64
	name str
	frames i64
	width i64
	height i64
	bpp i64
	footX i64
	footY i64
	once bool

# the order of main.dat's section 0 (walking right, jumping right, walking left...)
# long: the game's table
animationTable = [
	AnimationSpec(0x0000, "walking", 8, 16, 10, 2, 8, 10, false),
	AnimationSpec(0x0140, "jumping", 1, 16, 10, 2, 8, 10, true),
	AnimationSpec(0x0168, "walking left", 8, 16, 10, 2, 8, 10, false),
	AnimationSpec(0x02A8, "jumping left", 1, 16, 10, 2, 8, 10, true),
	AnimationSpec(0x02D0, "digging", 16, 16, 14, 3, 8, 12, false),
	AnimationSpec(0x0810, "climbing", 8, 16, 12, 2, 8, 12, false),
	AnimationSpec(0x0990, "climbing left", 8, 16, 12, 2, 8, 12, false),
	AnimationSpec(0x0B10, "drowning", 16, 16, 10, 2, 8, 10, true),
	AnimationSpec(0x0D90, "hoisting", 8, 16, 12, 2, 8, 12, true),
	AnimationSpec(0x0F10, "hoisting left", 8, 16, 12, 2, 8, 12, true),
	AnimationSpec(0x1090, "building", 16, 16, 13, 3, 8, 13, false),
	AnimationSpec(0x1570, "building left", 16, 16, 13, 3, 8, 13, false),
	AnimationSpec(0x1A50, "bashing", 32, 16, 10, 3, 8, 10, false),
	AnimationSpec(0x21D0, "bashing left", 32, 16, 10, 3, 8, 10, false),
	AnimationSpec(0x2950, "mining", 24, 16, 13, 3, 8, 13, false),
	AnimationSpec(0x30A0, "mining left", 24, 16, 13, 3, 8, 13, false),
	AnimationSpec(0x37F0, "falling", 4, 16, 10, 2, 8, 10, false),
	AnimationSpec(0x3890, "falling left", 4, 16, 10, 2, 8, 10, false),
	AnimationSpec(0x3930, "floating", 8, 16, 16, 3, 8, 16, false),
	AnimationSpec(0x3C30, "floating left", 8, 16, 16, 3, 8, 16, false),
	AnimationSpec(0x3F30, "splatting", 16, 16, 10, 2, 8, 10, true),
	AnimationSpec(0x41B0, "exiting", 8, 16, 13, 2, 8, 13, true),
	AnimationSpec(0x4350, "vaporizing", 14, 16, 14, 4, 8, 14, true),
	AnimationSpec(0x4970, "blocking", 16, 16, 10, 2, 8, 10, false),
	AnimationSpec(0x4BF0, "shrugging", 8, 16, 10, 2, 8, 10, true),
	AnimationSpec(0x4D30, "shrugging left", 8, 16, 10, 2, 8, 10, true),
	AnimationSpec(0x4E70, "oh no", 16, 16, 10, 2, 8, 10, true),
	AnimationSpec(0x50F0, "exploding", 1, 32, 32, 3, 16, 25, true)
]

# the colours of main.dat's in-level pictures (the panel, the lemmings)
pub fn mainPalette() dos.Palette:
	custom = [image.Rgba8(124, 124, 0, 255), image.Rgba8(160, 160, 160, 255),
		image.Rgba8(208, 208, 208, 255),
		image.Rgba8(176, 176, 0, 255),
		image.Rgba8(64, 80, 176, 255),
		image.Rgba8(96, 48, 32, 255), image.Rgba8(128, 64, 32, 255), image.Rgba8(
			224,
			128,
			144,
			255
	)]
	levelPalette(custom)

fn animationOf(data u8[], a AnimationSpec, pal dos.Palette):
	frameBytes = a.width / 8 * a.height * a.bpp
	indices = []
	for f in 0..a.frames:
		indices.extend(dos.planarIndices(data, a.at + f * frameBytes, a.width, a.height, a.bpp))
	sheet = dos.paint(indices, none, a.width, a.height * a.frames, pal)
	Animation(a.name.copy(), a.frames, a.width, a.height, a.footX, a.footY, a.once, indices, sheet)

# the frames in a level's palette: its colour 7 (the bricks, a digger's earth) is the set's
pub fn sheetIn(a Animation, pal dos.Palette) image.Image:
	dos.paint(a.indices, none, a.width, a.height * a.frames, pal)

fn maskOf(data u8[], at i64, frames i64, w i64, h i64):
	solid = []
	for f in 0..frames:
		solid.extend(dos.planarMask(data, at + f * (w / 8 * h), w, h))
	Mask(frames, width = w, height = h, solid)

fn pictureOf(data u8[], at i64, w i64, h i64, bpp i64, pal dos.Palette):
	dos.paint(dos.planarIndices(data, at, w, h, bpp), none, w, h, pal)

# one-bit pictures in `color` on transparent
fn maskPicture(data u8[], at i64, w i64, h i64, color image.Rgba8):
	img = image.Image(w, h, fill = image.Rgba8(0, 0, 0, 0))
	solid = dos.planarMask(data, at, w, h)
	for y in 0..h:
		for x in 0..w:
			if solid[y * w + x]:
				img[x, y] = color
	img

pub fn loadMainData(dir str) MainData:
	sections = sectionsOf(fs.readBytes("{dir}/main.dat") ?? fail("cannot read main.dat: {error}"))
	if sections.len < 7: fail("main.dat has {sections.len} sections, not 7")
	pal = mainPalette()
	lem = sections[0].bytes
	animations = animationTable.map(animationOf(lem, it, pal))
	masks = sections[1].bytes
	countdown = []
	for d in 0..10:
		countdown.push(maskPicture(masks, 0x17C - d * 8, 8, 8, pal.colors[3]))
	panelData = sections[6].bytes
	font = []
	for i in 0..38:
		font.push(pictureOf(panelData, 0x1900 + i * 0x30, 8, 16, 3, pal))
	digitData = sections[2].bytes
	skillDigits = []
	for i in 0..20:
		skillDigits.push(
			maskPicture(digitData, 0x1900 + i * 8, 8, 8, image.Rgba8(255, 255, 255, 255))
		)
	MainData(
		animations,
		bashMasks = [maskOf(masks, 0x0000, 4, 16, 10), maskOf(masks, 0x0050, 4, 16, 10)],
		mineMasks = [maskOf(masks, 0x00A0, 2, 16, 13), maskOf(masks, 0x00D4, 2, 16, 13)],
		explosionMask = maskOf(masks, 0x0108, 1, 16, 22),
		countdown,
		panel = pictureOf(panelData, 0, 320, 40, 4, pal),
		font,
		skillDigits
	)
