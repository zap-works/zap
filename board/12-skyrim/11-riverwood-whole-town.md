---
size: XL
---
# Riverwood, the whole town, is drawn and lived in (milestone 14)

After the inn, the project (`projects/skyrim`) extends to Riverwood's exterior, its people, terrain,
sky, weather, shadows, distant land, water and grass. Tests are `exteriorTests.zap`,
`exteriorShotTests.zap`, `terrainTests.zap`, `skyTests.zap`, `lodTests.zap`, `grassTests.zap` and
`townWalkTests.zap`; the executable's code is read from the export at `C:/tools/skyrim-decomp`
(`projects/recomp/tools/decompInfo.zap`) and its tables are in `reference/exe/README.md`. Each task
is done when its test or a headless shot against a capture shows the game's behavior.

## The exterior

- [ ] stream the exterior grid cell by cell: write one prepared file per cell, so a step loads only
  the cells that enter. `main.zap` reloads the whole area once the player is past the middle ring,
  since the prepared file is one per area; walking across a cell border no longer reloads the area
- [ ] normalize the NIF texture sets' Bethesda build paths (`textures/skyrimhd/build/pc/data/...`,
  28 textures missing outside) as the executable does, and trace the garbled keys (`meshes/g.`,
  `textures/nor`) to their record; no texture is missing in the exterior
- [ ] capture Riverwood in the real game, to measure the exterior against (poses in
  `reference/poses.json`)
- [ ] the emittance (`XEMI`) light: the region's weather is its likeliest (SkyrimClear, first of the
  equal chances) where the game takes the sky's current one, carried in from outside; the flag is per
  model, so a ref of an externally lit model without `XEMI` would take the cell's source (none in the
  inn). Take the sky's current weather as the game does

## The town's people

- [ ] the residents' low-process speed: 130 units a real second is a stand-in; read the executable's
  `AIProcess` code for it and use the real value
- [ ] the sounds and footsteps of the exterior's people, and greetings and ambient lines outdoors
  beyond the dialogue the cast already has
- [ ] prepare the town's interiors one by one in a running game (they prepare on first use, through
  their doors)
- [ ] carry a cell's residents across a load door in a running game (`departed` and `arrival` are
  the hand-off; `main.zap` does not yet deliver them)
- [ ] carry Papyrus state between cells (each cell's VM is new, as a new game finds it)

## Terrain

- [ ] the border geometry along each cell's edge (`BSTriShape` at `LoadedLandData+0x4880`, built in
  0x1402ae650); the landscape's shadows (sun shadow maps); snow; the parallax; the vertex stage's
  distance fade (`LandBlendWeights2.w`); the physics material per texture (all 0.5 friction today);
  cells with no `LAND` (the world's default land height is read, not drawn); the vertex normals and
  tangents of the executable's tangent generation (ours: u along +x); and xEdit values (it has no
  CLI, so the heights are checked against the trees and the normals instead)

## Sky, weather and moons

- [ ] diff against the executable in `x64diffs.zap` what is only read from the code and unit tested
  (`skyTests.zap`): fog (day share ramp), the sun's windows, track and arc, stars' alpha, cloud
  scroll, weather life, transition, the region pick and the keep-on-entering roll, and the image
  space as a weighted sum
- [ ] the sun's blend: the sun is added like the glare, on an assumption, since the sun mesh has no
  alpha property of its own in `Init` and its sky shader property's blend is not read; read it
- [ ] lightning scheduling; the sun's occlusion fade of the glare (0.25 to 1 by terrain queries);
  the cloud mesh's blending modes and the layers' color swap when the current has none
  (0x14040c220); the accelerated transition flag; fog clamped to the far plane; the stars' real
  rotation by days passed; the moons' stencil mask
- [ ] the MOONMASK shadow quad (a stencil that keeps the stars and clouds off the moon: `Sky.hlsl`'s
  MOONMASK, `MoonShadow.dds`) and the moons' clouds-edge scatter

## Precipitation

- [ ] the precipitation occlusion map (rain under a roof), `bUsePrecipitationOcclusion`; and the
  game's use of an amount over 1 (the pool holds three cubes), which is not read

## The sun's shadows

- [ ] diff the cascade fit (0x14157f080) against the executable with `projects/recomp/x64`: the
  slice and fit code lives in the middle of a 1,400-line function that allocates cameras and
  culling processes, so it is unit-tested in `skyTests.zap` only
- [ ] the shadow pass's rasterizer state, which gives the mask its bias, is not read: the engine's
  depth bias stands in; read it
- [ ] the actors' focus shadows (`iNumFocusShadow`), the screen-space shadow refinement, the update
  interval (`fSunShadowUpdateTime`), and trees' and grass's casting flags (`bShadowsOnGrass`,
  `fMaxHeightShadowCastingTrees`)

## Distant LOD

- [ ] the loaded area's box for the land's sink (its centre and half side `uGridsToLoad` x 4096 / 2)
  is an assumption; read it
- [ ] the objects' tangent-space normal maps are not read (they use their vertex normals); read them

## Water

- [ ] the cube map the executable reflects (the planar reflection stands for it), the screen-space
  reflection, ripples, displacement and wading, the shadow on the water, the underwater pass and its
  stencil, the refraction's fog term (a number under 1 to the power of the fog's 150: nothing), and
  `FrameParams.w` (taken 0)

## Grass

- [ ] the per-instance fade-in, the grass LOD, shadows on grass, the wind's blend across a weather
  change, `bGrassPointLighting`, and the executable's own pixel stage (Community Shaders' stands for
  it)
