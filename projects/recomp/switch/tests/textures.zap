# Textures decoded from their TIC and bytes: plain formats in pitch and block-linear layouts, a
# swizzle, and a BC1 block.

import image
import recomp.switch.textures

fn ticOf(format i64, width i64, height i64, layout i64) textures.Tic:
	textures.Tic(
		format,
		componentTypes = [2, 2, 2, 2],
		swizzle = [2, 3, 4, 5],
		address = 0,
		layout,
		pitch = 32,
		blockWidth = 0,
		blockHeight = 0,
		blockDepth = 0,
		width,
		height,
		depth = 1,
		levels = 1,
		baseLevel = 0,
		maxLevel = 0,
		target = textures.target2d,
		srgb = false,
		normalizedCoordinates = true
	)

# the 2x2 texels' RGBA bytes, a row a pixel pair
fn texels() u8[]:
	[u8(1), 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]

test "an A8B8G8R8 texture in pitch rows, its alpha swizzled to one":
	t = ticOf(0x08, 2, 2, textures.layoutLinear)
	t.swizzle = [2, 3, 4, 7]
	raw u8[] = zeros(64)
	for k in 0..8:
		raw[k] = texels()[k]
		raw[32 + k] = texels()[8 + k]
	expect textures.textureBytes(t) == 40
	img = textures.decodeTexture(t, raw) ?? fail("not decoded")
	expect img[0, 0] == image.Rgba8(1, 2, 3, 255) and img[1, 1] == image.Rgba8(13, 14, 15, 255)

test "a block-linear texture reads back what was swizzled":
	t = ticOf(0x08, 2, 2, textures.layoutBlockLinear)
	s = textures.Surface(rowBytes = 8, rows = 2, blockHeight = 0)
	img = textures.decodeTexture(t, s.swizzle(texels())) ?? fail("not decoded")
	expect img[1, 0] == image.Rgba8(5, 6, 7, 8) and img[0, 1] == image.Rgba8(9, 10, 11, 12)

test "a BC1 block of one color":
	t = ticOf(0x24, 4, 4, textures.layoutLinear)
	t.pitch = 8
	block u8[] = [0x00, 0xF8, 0, 0, 0, 0, 0, 0]   # color 0 pure red, every index 0
	img = textures.decodeTexture(t, block) ?? fail("not decoded")
	expect img[3, 3] == image.Rgba8(255, 0, 0, 255)

test "a format not decoded gives none":
	expect textures.decodeTexture(ticOf(0x10, 4, 4, textures.layoutLinear), zeros(16)) == none
