---
size: XL
priority: P0
---
# GPU: textures, surfaces and memory Zap lacks

What Zap's GPU code lacks, each with the instructions that need it (the translation notes the
instruction and writes zeros, or does as said):
- [ ] 1D textures and arrays, 3D arrays and multisampled ones (TEX/TEXS/TLD/TLDS/TLD4/TMML/TXD of
  types 0, 1 and 5, TEXS encoding 0, TLDS 0, 1 and 6, TLD.MS); a compared cube or 3D texture; TXD
  of a 3D texture or a cube.
- [ ] A lod clamp (TEX.LC, TXD.LC; yuzu has none either), per-texel gather offsets (TLD4.PTP), the
  level count (TXQ's fourth component), TMML's third and fourth results, f16 results (TEXS, TLDS,
  TLD4S), sparse results.
- [ ] Offsets the code does not show: Zap's offsets are constants of -8 to 7 (`IVec2(x, y)`), so a
  TEX/TLD4/TXD.AOFFI translates when a MOV32I or MOV of an immediate in the same block gave the
  register (TLD4's six-bit offsets only inside that range); a fetch's (TLD, TLDS) are added to its
  coordinates, whatever they are.
- [ ] Integer textures as the TIC says (Source.integers: the handles of textures of integers, signed
  or not, read as UintTexture or IntTexture, their TEX a fetch of the texel uv falls in): nothing
  fills it yet (the renderer reads the TIC pool after the programs are translated); integer
  arrays and 3D textures, and their gathers and gradients.
- [ ] Surfaces past a 2D one of one 32-bit number a texel (SULD/SUST translate as a UintImage's load
  and store, SUATOM/SURED as its atomics): 1D, layered and 3D surfaces, SULD.D/SUST.D of 8, 16,
  64 and 128 bits and .P of more than red (a UintImage is R32UI; a surface of colors needs its
  format from the TIC), SUATOM's INC, DEC, signed MIN and MAX, 64-bit and float sizes, CAS;
  images in vertex and pixel stages (Vulkan's vertexPipelineStoresAndAtomics,
  fragmentStoresAndAtomics); an array of images (they are Params fields, `image<slot>`).
- [ ] Bindless handles the code does not show (TEX.B, TLD4.B, TXD.B, TMML.B: a handle register not
  loaded from a constant buffer word in the same block; TLD.B, TXQ.B); `Texture[]` indexes
  textures with their own samplers, so a computed handle also needs separate sampler arrays.
- [ ] Global memory (LDG, STG, LD, ST, ATOM, RED: a 64-bit address; Zap has bound storage buffers):
  deko3d's sinewave compute program writes through one.
- [ ] Tessellation and geometry stages (ISBERD, OUT, AL2P, ALD/AST of patches).
- [ ] A vertex stage's number beside its attributes (ALD of attribute 191 when generic ones are read:
  Zap's vertex stage takes one or the other), and outputs other than the position and generic
  attributes (AST of point size, clip distances, layer, viewport).
- [ ] A pixel stage's front face (IPA of attribute 255), flat and linear float inputs (SPH modes
  constant and linear: translated as perspective), IPA's centroid, sample and offset modes, and
  its sample mask output. Its colors and depth translate as yuzu's ExitFragment reads them (each
  target that writes a component four registers from r0, the depth the second register after
  them) into `Targets<name>`'s `targetN` fields, so a stage writing target 5 alone writes it.
