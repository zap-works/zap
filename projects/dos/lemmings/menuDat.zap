# main.dat's pictures for the screens outside a level: section 3 (the brown background, the logo,
# the signs of the main menu and the sound icons) and section 4 (the blinking eyes, the scroller's
# lemmings and reel, the rating boards and the purple font), as ccexplore's document lays them out,
# painted in the menus' palette.

import dos
import fs
import image

pub type MenuData:
	background image.Image   # 320 x 104, tiled
	logo image.Image   # 632 x 94
	signs image.Image[]   # F1, F2, F3 (no sound), the rating, exit to DOS, F4: 120 x 61 each
	musicIcon image.Image   # drawn over the F3 sign: music, or effects only
	effectsIcon image.Image
	blinks image.Image[]   # seven blinking eyes of 8 frames, 32 x 12 each: eye e's frame f at e * 8 + f
	scrollerLeft image.Image[]   # 16 frames of 48 x 16
	scrollerRight image.Image[]
	reel image.Image   # 16 x 16
	ratings image.Image[]   # Fun, Tricky, Taxing, Mayhem boards: 72 x 27 each
	font image.Image[]   # "!" .. "~": 16 x 16 each

# the menus' palette (the document's table, in VGA steps)
pub fn menuPalette() dos.Palette:
	steps = [
		(0, 0, 0),
		(32, 16, 8),
		(24, 12, 8),
		(12, 0, 4),
		(8, 2, 31),
		(16, 11, 36),
		(26, 22, 41),
		(38, 35, 47), (0, 20, 0), (0, 24, 4), (0, 28, 8), (0, 32, 16), (52, 52, 52), (44, 44, 0),
		(16, 20, 44), (56, 32, 36)]
	colors image.Rgba8[16]
	for i, s in steps:
		r, g, b = s
		colors[i] = dos.vgaColor(u8(r), u8(g), u8(b))
	dos.Palette(colors)

fn pictureAt(data u8[], at i64, w i64, h i64, bpp i64, pal dos.Palette):
	dos.paint(dos.planarIndices(data, at, w, h, bpp), none, w, h, pal)

# n frames of w x h one after another
fn framesAt(data u8[], at i64, n i64, w i64, h i64, bpp i64, pal dos.Palette):
	(0..n).map(pictureAt(data, at + it * (w / 8 * h * bpp), w, h, bpp, pal))

# the purple font's index of the character c ('!' .. '~'), none for others (a space is a gap)
pub fn glyphIndex(c u8) i64?:
	if c < '!' or c > '~': return none
	i64(c - '!')

pub fn loadMenuData(dir str) MenuData:
	sections = sectionsOf(fs.readBytes("{dir}/main.dat") ?? fail("cannot read main.dat: {error}"))
	if sections.len < 5: fail("main.dat has {sections.len} sections, not 7")
	pal = menuPalette()
	s3 = sections[3].bytes
	s4 = sections[4].bytes
	MenuData(
		background = pictureAt(s3, 0x0000, 320, 104, 2, pal),
		logo = pictureAt(s3, 0x2080, 632, 94, 4, pal),
		signs = [0x9488, 0xA2D4, 0xB120, 0xBF6C, 0xCDB8, 0xDC04].map(pictureAt(s3, it, 120, 61, 4, pal)),
		musicIcon = pictureAt(s3, 0xEA50, 64, 31, 4, pal),
		effectsIcon = pictureAt(s3, 0xEE30, 64, 31, 4, pal),
		blinks = framesAt(s4, 0, 56, 32, 12, 4, pal),
		scrollerLeft = framesAt(s4, 0x2A00, 16, 48, 16, 4, pal),
		scrollerRight = framesAt(s4, 0x4200, 16, 48, 16, 4, pal),
		reel = pictureAt(s4, 0x5A00, 16, 16, 4, pal),
		ratings = [0x65E4, 0x6218, 0x5E4C, 0x5A80].map(pictureAt(s4, it, 72, 27, 4, pal)),
		font = (0..0x5E).map(pictureAt(s4, 0x69B0 + it * 0x60, 16, 16, 3, pal))
	)
