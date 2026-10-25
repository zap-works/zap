# The bytes of a texture's levels in each format the engine uploads: 4 a pixel, or blocks of 4x4
# pixels (BC1 8 bytes, BC3 16) or of 4x4 and 6x6 (ASTC, 16), a level smaller than a block taking
# one.

import engine

test "the bytes of a level by format":
	expect engine.levelBytes(.Rgba8, 13, 9) == 13 * 9 * 4
	expect engine.levelBytes(.Rgba8Srgb, 2, 2) == 16
	expect engine.levelBytes(.Bc1, 256, 128) == 64 * 32 * 8
	expect engine.levelBytes(.Bc1Srgb, 4, 4) == 8
	expect engine.levelBytes(.Bc3, 256, 128) == 64 * 32 * 16
	expect engine.levelBytes(.Bc3Srgb, 2, 1) == 16
	expect engine.levelBytes(.Bc1, 13, 9) == 4 * 3 * 8
	expect engine.levelBytes(.Astc4x4, 13, 9) == 4 * 3 * 16
	expect engine.levelBytes(.Astc6x6Srgb, 64, 64) == 11 * 11 * 16
	expect engine.levelBytes(.Astc6x6, 2, 1) == 16
