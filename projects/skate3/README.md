# Skate 3 (Xbox 360) rewritten in Zap

Skate 3 rewritten in Zap on the engine, opening in University. It needs your own Skate 3 (Xbox
360) disc image, an `.iso` in `projects/skate3/disc/` (or `--iso <file>`); the first run decodes
University and the skater from it into `projects/skate3/assets/` (`zap run
projects/skate3/prepare.zap` does it by hand), then `zap run projects/skate3/main.zap` plays.

What the Xbox 360 disc of Skate 3 holds and how Skate 3 reads it. Everything is read from the
user's own image at run time (or once, into `projects/skate3/assets/`); nothing of the game is committed.
The formats were learned from the community's reverse engineering, read and reimplemented in Zap
(no code copied):

- [SK8-ENGINE/skate-3-rust-engine](https://github.com/SK8-ENGINE/skate-3-rust-engine) (GPL-3.0):
  the asset pipeline (`tools/owned_game/big.py`, `tools/vendor/university/.../skate3_streams.py`,
  `prepare_hawaiian_dream.py`, `retail_collision_mesh.py`, `retail_lightmap_uv.py`,
  `tools/vendor/utt/`), the default skater (`tools/extract_default_skater.py` and its manifest),
  the world shader (`crates/skate-game/src/retail_world.wgsl`).
- [Ethanw05/DumbadsSkate3ModdingTools](https://github.com/Ethanw05/DumbadsSkate3ModdingTools):
  the RW4 arena layout and object types (`ArenaBuilder.Core`, `docs/X360_Port_Deltas.md`), the
  static mesh vertex packing (`MeshVertexPacker.cs`).
- [mchughalex/skate3recomp](https://github.com/mchughalex/skate3recomp): the native recompilation,
  for exact behaviour later.

## The disc

An XGD2 disc: the game partition starts at byte 0xFD90000, its XDVDFS volume descriptor
("MICROSOFT*XBOX*MEDIA") 32 sectors in. `xbox/disc.zap` walks the directory trees (binary trees of
little-endian entries) and reads files in place. The image holds **103 files, 6,404,940,920
bytes**, the counts the Rust engine's notes give for `extract-xiso -l`
(`zap run projects/skate3/list.zap`):

| Path | What |
|---|---|
| `default.xex` | the game |
| `data/content/worldDIST_*.big` | the districts: University (798 MB), DownTown, Industrial, the parks |
| `data/content/createacharacter.big` | the skater's models and textures (4230 entries) |
| `data/content/global_locators/...` | named locations (`.rx2`, `.loc`) per district |
| `data/big/miscload.big` | recipes (`data/cacrecipes/`), animations (`data/anim/*.abin`), ... |
| `data/big/scene.big`, `db.big`, `fe*.big` | cutscene animation, the attribute database, the front end |
| `data/audio/`, `data/movies/*.vp6` | sound banks and streams, VP6 movies |

## EA BIG v3 (`ea/big.zap`)

Big-endian: "EB", version 3, the entry count, flags (bit 0: 20-byte entries), the offset shift,
the index and name sizes; entries (offset << shift, stored size, unpacked size), a compression
byte per entry (0 stored, 1 RefPack, 2-4 "chunkref": chunks each stored, RefPack or deflate),
then names (folder index + name) and folders. RefPack (`ea/refPack.zap`) is EA's LZ77.

## District streams (`skate/stream.zap`)

A district's BIG holds `data/content/world/stream/<district>/`: for each stream (Pres: drawn,
Sim: collision, Tex: textures) an ATOC table (`<district>_<stream>.xst`: 64-byte records, the
asset id, size, type: 1 simulation, 4 model, 0x1000 texture) and SFIL files per map cell
(`c<stream>_<x>_<z>_high.xsf`, cells of 100 m) holding the assets, each whole or as a CPU and a GPU
part, each raw or RefPack. University: Pres 2665 assets (479 models, 2046 textures, 140 other),
Tex 689 textures, Sim 1013.

## RW4 arenas (`rw4/`)

Every asset is a RenderWare 4 arena, `\x89RW4xb2`: the dictionary (count at 0x20, offset at 0x30)
of 24-byte entries (offset, size, type), objects addressed by dictionary index, the GPU base
resources (type 0x10031) after the CPU objects (from 0x44). Types used:

- **Texture** 0x200E8: 28 bytes of D3D resource, then the Xenos texture fetch constant (format,
  endian swap, tiled flag, size, pitch, dimension, packed mips). `xbox/xenos.zap` untiles
  (XGAddress2DTiledOffset over 32x32-element macro tiles), swaps bytes and decodes DXT1, DXT3,
  DXT5, DXN, DXT5A, CTX1, 8888, 565, 8, 88. University uses DXT1 and DXT5 for color, DXT1 for
  lightmap pages, 565 for small ones.
- **TableOfContents** 0x00EB000B: names and 64-bit ids (a texture's "0x<id>.Texture"; materials
  refer to textures by these ids; a material subreference 0x00EB0066 ties a material's GUID to the
  handle a mesh uses).
- **RenderMaterialData** 0x00EB0005: 32-byte parameters (`Name`, `AttribulatorMaterialName` = the
  shader, texture channels `diffuse lightmap normal specular transparent decal detail
  macrooverlay environment`, floats).
- **RenderOptiMeshData** 0x00EB0023: a mesh: bounds, material handle (0x24), vertex descriptor
  (0x28), index buffer (0x30), vertex buffer (0x34), primitive (0x60). Buffers' bytes are the base
  resource before them; 16-bit big-endian indices.
- **VertexDescriptor** 0x200E9: 16-byte elements (offset, Xenos vertex format, usage, usage index);
  the format's low 6 bits give the layout (57 float3, 31/32 half2/half4, 25/26 short2/short4
  normalized, 16 packed 11:11:10, 6 ubyte4). Static world meshes have no normal: their second
  texture coordinate (short4) holds the lightmap UV (absolute values) and the normal's x, y (the
  sign of v gives z). Character positions are short4: twice the normalized value, raised 0.8 m.
- **InstanceData** 0x00EB000D: a 4x4 matrix (identity for University's static models: they are in
  world space, meters, y up, right-handed) and the instance's name.
- **ClusteredMesh** 0x80006 (Sim): RenderWare collision, clusters of compressed vertices and
  triangle/quad units with surface ids (`rw4/collision.zap`).

University decodes to 8546 meshes (2.08 M vertices, 1.65 M triangles), 4471 draw batches, 1657
textures (273 color, 1247 lightmap pages, ...), 1.13 M collision triangles. Preparing it takes
about 12 s.

## Drawing (`graphics/`)

The game's world shaders work on squared colors: diffuse² × lightmap² × 0.93 × exposure, then the
square root (`retail_world.wgsl`); Skate 3 draws diffuse × lightmap × 1.4 with a soft shoulder, the
haze of distance, cut-out (alpha test, trees) and blended (water, glass) passes, decals laid over
by their second UV pair.

## The skater (`skate/skater.zap`)

`data/cacrecipes/SavedRecipeFallbackMale.bin` (miscload.big) is the recipe the game uses when no
skater is saved; parsed, it gives the same models and textures as the Rust engine's manifest
(Arm 0x00000dce03e38811, Feet, Hair, Organ, OuterTorso, Pants, Rostral, SkateBoard, SkateTruck,
SkateWheel). Models are in `createacharacter/model/cas_db/<slot>/0x<id>.rx2`, textures in
`createacharacter/texture/0x<id>.rx2`; skin and hair are tinted. He is drawn in his bind pose.
