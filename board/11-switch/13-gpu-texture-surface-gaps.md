---
size: XL
priority: P0
---
# Zap's GPU code covers the textures, surfaces and memory the Switch shaders use

Zap's GPU code (the shader language in `compiler/shader` and `compiler/gpu`) lacks features that
BotW's Maxwell shaders need. For each one the shader translation
(`projects/recomp/switch/shaders`) notes the instruction and writes zeros, or does as said below.
For each item: add the feature to Zap's GPU language with a test in `tests/` (or in
`projects/recomp/switch/shaders/tests`), then make the translation use it; the result is seen as a
translated shader test that no longer notes the instruction.

- [ ] 1D textures and arrays, 3D arrays and multisampled ones (TEX, TEXS, TLD, TLDS, TLD4, TMML and
  TXD of types 0, 1 and 5, TEXS encoding 0, TLDS 0, 1 and 6, TLD.MS); a compared cube or 3D texture;
  TXD of a 3D texture or a cube
- [ ] a lod clamp (TEX.LC, TXD.LC; yuzu has none either), per-texel gather offsets (TLD4.PTP), the
  level count (TXQ's fourth component), TMML's third and fourth results, f16 results (TEXS, TLDS,
  TLD4S), sparse results
- [ ] offsets the code does not show: Zap's offsets are constants of -8 to 7 (`IVec2(x, y)`), so a
  TEX, TLD4 or TXD.AOFFI translates only when a MOV32I or a MOV of an immediate in the same block
  gave the register (TLD4's six-bit offsets only inside that range); a fetch's offsets (TLD, TLDS)
  are added to its coordinates, whatever they are. Accept an offset that is a value in a register
- [ ] integer textures as the texture image control (TIC) says (`Source.integers`: the handles of
  textures of integers, signed or not, read as `UintTexture` or `IntTexture`, their TEX a fetch of
  the texel the uv falls in): nothing fills it yet, since the renderer reads the TIC pool after the
  programs are translated. Fill it, and add integer arrays and 3D textures, with their gathers and
  gradients
- [ ] surfaces past a 2D one of one 32-bit number a texel (SULD and SUST translate as a
  `UintImage`'s load and store, SUATOM and SURED as its atomics): 1D, layered and 3D surfaces;
  SULD.D and SUST.D of 8, 16, 64 and 128 bits and .P of more than red (a `UintImage` is R32UI; a
  surface of colors needs its format from the TIC); SUATOM's INC, DEC, signed MIN and MAX, 64-bit
  and float sizes, CAS; images in vertex and pixel stages (Vulkan's `vertexPipelineStoresAndAtomics`
  and `fragmentStoresAndAtomics`); an array of images (they are `Params` fields, `image<slot>`)
- [ ] bindless handles the code does not show (TEX.B, TLD4.B, TXD.B and TMML.B: a handle register
  not loaded from a constant buffer word in the same block; TLD.B and TXQ.B); `Texture[]` indexes
  textures with their own samplers, so a computed handle also needs separate sampler arrays
- [ ] global memory (LDG, STG, LD, ST, ATOM, RED with a 64-bit address; Zap has bound storage
  buffers only): deko3d's sinewave compute program writes through one, which is the test
- [ ] tessellation and geometry stages (ISBERD, OUT, AL2P, ALD and AST of patches)
- [ ] a vertex stage's number beside its attributes (ALD of attribute 191 when generic ones are
  read: Zap's vertex stage takes one or the other), and outputs other than the position and generic
  attributes (AST of point size, clip distances, layer, viewport)
- [ ] a pixel stage's front face (IPA of attribute 255), flat and linear float inputs (SPH modes
  constant and linear, translated as perspective today), IPA's centroid, sample and offset modes,
  and its sample mask output. Its colors and depth already translate as yuzu's ExitFragment reads
  them (each target that writes a component four registers from r0, the depth the second register
  after them) into `Targets<name>`'s `targetN` fields, so a stage writing target 5 alone writes it
