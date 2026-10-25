# A texture's first level as the GPU at hand takes it: BC1, BC3 and BC7 blocks as they are where
# the GPU reads BC, every BC texture transcoded to ASTC where it reads ASTC and no BC (Android's:
# engine.astcLevels), ASTC blocks of 4x4 and 6x6 as they are where it reads ASTC; anything else (a
# swizzle other than the identity, BC4 and BC5, whose GPU reads fill other channels than the
# decode, BC not a multiple of 4, other formats) decoded to RGBA. sRGB is read as stored, as the
# RGBA decode does.

import engine

# a texture's first level for the GPU: its format, size and bytes
pub type Upload:
	format engine.TextureFormat
	width i64
	height i64
	bytes u8[]

# the format of the engine a TIC's blocks are drawn from as they are
fn keptFormat(t Tic) engine.TextureFormat?:
	match t.format:
		0x24: .Bc1
		0x26: .Bc3
		0x17: .Bc7
		0x40: .Astc4x4
		0x42: .Astc6x6
		_: none

# the format of the engine of a TIC's BC blocks (BC2 as BC3, its size), none for another format
fn bcFormat(t Tic) engine.TextureFormat?:
	match t.format:
		0x24: .Bc1
		0x25, 0x26: .Bc3
		0x27: .Bc4
		0x28: .Bc5
		0x17: .Bc7
		_: none

# The first level for a GPU that reads `target`'s blocks (none: neither), or none for a format not
# decoded here.
pub fn uploadOf(t Tic, raw u8[], target engine.BlockTarget?) Upload?:
	if t.swizzle == [2, 3, 4, 5] and t.keptFormat() is kept:
		astc = kept in [.Astc4x4, .Astc6x6]
		fits = target == .Astc if astc else target == .Bc and t.width % 4 == 0 and t.height % 4 == 0
		if fits: return Upload(kept, t.width, t.height, try t.textureBlocks(raw))
	img = try t.decodeTexture(raw)
	if target == .Astc and t.bcFormat() is bc:
		format = bc.astcFormatOf()
		return Upload(format, t.width, t.height, engine.astcLevels([img], format)[0])
	Upload(.Rgba8, img.width, img.height, img.cells.bytes().copy())
