# Textures of blocks for the GPU at hand: BC where it reads BC (Windows' and Linux's), ASTC where
# it reads ASTC and no BC (Android's). A texture of BC blocks goes as it is to the first, and is
# transcoded for the second: decoded, then encoded again by std's ASTC encoder. What a project
# prepares from a game's BC textures goes through here.

import image
import image.astc

# the blocks a texture is laid in for a GPU
pub type BlockTarget:
	Bc   # the BC blocks as they are
	Astc   # ASTC blocks, transcoded from them

# what the GPU at hand reads: BC where it does, else ASTC where it does, else none (RGBA)
pub fn deviceBlockTarget() BlockTarget?:
	if bcTextures(): return .Bc
	if astcTextures(): return .Astc
	none

# The ASTC format a format of BC blocks becomes: BC1 and BC4 (4 bits a texel) as 6x6 blocks (3.6
# bits), the others as 4x4 (8 bits, as theirs); sRGB kept.
pub fn astcFormatOf(format TextureFormat) TextureFormat:
	match format:
		Bc1, Bc4: .Astc6x6
		Bc1Srgb: .Astc6x6Srgb
		Bc3Srgb, Bc7Srgb: .Astc4x4Srgb
		_: .Astc4x4

# the levels (level 0 first, decoded) as ASTC blocks of the format
pub fn astcLevels(levels image.Image[], format TextureFormat) u8[,]:
	side = 6 if format in [.Astc6x6, .Astc6x6Srgb] else 4
	srgb = format in [.Astc4x4Srgb, .Astc6x6Srgb]
	out = []
	for level in levels:
		out.push(level.encodeAstc(side, side, srgb).blocks)
	out
