---
size: XL
priority: P1
---
# Assets compressed

Every image a project makes reaches the GPU as RGBA8 though
`TextureFormat` has BC1..BC7; a skinned vertex is 22 floats (88 bytes); a sound is kept as f32.
`zap prepare` encodes BC7 (BC1 for opaque, BC5 for normals) with the mips into the prepared
file; vertices keep position in f32 and normal, tangent and uv in snorm16 or f16, joints in u8,
weights in unorm8 (about 40 bytes); sounds in i16. ASTC is there for Android (TextureFormat's
Astc4x4/6x6 and sRGB, `engine.astcTextures`, std/image/astc's encoder, `engine.astcLevels`;
skyrim's `prepare.zap --textures astc`); left of it:
- [ ] the prepared file holds one set per target: skyrim's ASTC set replaces the BC one in the same
  dir today, and a run on a GPU without the set's blocks stops at newTextureOfFormat;
- [ ] the encoder's quality and time: one or two partitions (one seed tried, by k-means), single
  endpoints refit once; PSNR 38.1, 35.8, 41.5 and 53.1 dB at 4x4 on the test images where
  astcenc -fast gives 43.2, 48.1, 43.1 and 51.5 (6x6: 33.6, 34.6, 38.9, 43.4 against 36.3,
  38.9, 38.3, 39.0); a 2048x2048 texture takes 1.6 s at 4x4 and 6x6 on the 8 threads here.
  More seeds, three partitions and a refit per choice close the gap;
- [ ] the other ASTC footprints (BotW's 8x8 and others, recomp.switch's 0x41..0x57) are decoded to
  RGBA on every GPU: in the rhi they would go to an ASTC GPU as they are.
DDS reaches the GPU prepared too (game/textures.zap keeps BC only at multiples of 4 and not sRGB
though render.zap has Bc1Srgb/Bc3Srgb, decodes cube faces to RGBA8, makes no mips). Measured by
`--only size` and the projects' memory, `--only shots` unchanged.
