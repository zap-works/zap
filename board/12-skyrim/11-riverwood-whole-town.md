---
size: XL
---
# The whole town of Riverwood (milestone 14)

The exterior:

- [ ] The exterior grid streamed cell by cell: per-cell prepared files, so that a step loads only the
  cells that enter. `main.zap` reloads the whole area once the player is past the middle ring,
  since the prepared file is one per area.
- [ ] NIF texture sets' Bethesda build paths (`textures/skyrimhd/build/pc/data/...`, 28 textures
  missing outside) normalized as the executable does, and the garbled keys (`meshes/g.`,
  `textures/nor`) traced to their record.
- [ ] Captures of Riverwood to measure the exterior against.
- [ ] The emittance (XEMI) light: the region's weather is its likeliest (SkyrimClear, first of the
  equal chances) where the game takes the sky's current one, carried in from outside; the flag is
  per model, so a ref of an externally lit model without XEMI would take the cell's source (none
  in the inn).

The town's people:

- [ ] The residents' low-process speed: 130 units a real second is a stand-in, the executable's
  AIProcess code has not been read for it.
- [ ] The sounds and footsteps of the exterior's people; greetings and ambient lines outdoors beyond the
  dialogue the cast already has.
- [ ] The town's interiors prepared one by one in a running game (they prepare on first use, through
  their doors).
- [ ] A cell's residents carried across a load door in a running game (`departed` and `arrival` are the
  hand-off, `main.zap` does not yet deliver them).
- [ ] Papyrus state carried between cells (each cell's VM is new, as a new game finds it).

Terrain:

- [ ] The border geometry along each cell's edge (BSTriShape at LoadedLandData+0x4880, built in
  0x1402ae650), the landscape's shadows (sun shadow maps), snow, the parallax and the vertex stage's
  distance fade (LandBlendWeights2.w), the physics material per texture (all 0.5 friction), cells
  with no LAND (the world's default land height is read, not drawn), the vertex normals and tangents
  of the executable's tangent generation (ours: u along +x), and xEdit values (it has no CLI; the
  heights are checked against the trees and the normals instead).

Sky, weather and moons:

- [ ] Diff against the executable in `x64diffs.zap` what is only read from the code and unit tested
  (`skyTests.zap`): fog (day share ramp), the sun's windows, track and arc, stars' alpha, cloud
  scroll, weather life, transition, the region pick and the keep-on-entering roll, the image space
  as a weighted sum.
- [ ] The sun's blend: the sun is added like the glare on an assumption, the sun mesh having no alpha
  property of its own in Init and its sky shader property's blend not being read.
- [ ] Lightning scheduling, the sun's occlusion fade of the glare (0.25 to 1 by terrain queries), the
  cloud mesh's blending modes and the layers' color swap when the current has none (0x14040c220),
  the accelerated transition flag, fog clamped to the far plane, the stars' real rotation by days
  passed, the moons' stencil mask.
- [ ] The MOONMASK shadow quad (a stencil that keeps the stars and clouds off the moon: Sky.hlsl's
  MOONMASK, MoonShadow.dds) and the moons' clouds-edge scatter.

Precipitation:

- [ ] The precipitation occlusion map (rain under a roof), `bUsePrecipitationOcclusion`; the game's use
  of an amount over 1 (the pool holds three cubes) is not read.

The sun's shadows:

- [ ] The cascade fit (0x14157f080) diffed against the executable with `projects/recomp/x64`: the slice
  and fit code lives in the middle of a 1,400-line function that allocates cameras and culling
  processes, so it is unit-tested in `skyTests.zap` only.
- [ ] The shadow pass's rasterizer state, which gives the mask its bias, is not read: the engine's depth
  bias stands in.
- [ ] The actors' focus shadows (iNumFocusShadow), the screen-space shadow refinement, the update
  interval (fSunShadowUpdateTime), trees' and grass's casting flags (bShadowsOnGrass,
  fMaxHeightShadowCastingTrees).

Distant LOD:

- [ ] The loaded area's box for the land's sink (its centre and half side uGridsToLoad x 4096 / 2) is
  an assumption.
- [ ] The objects' tangent-space normal maps are not read (they use their vertex normals).

Water:

- [ ] The cube map the executable reflects (the planar reflection stands for it), the screen-space
  reflection, ripples, displacement and wading, the shadow on the water, the underwater pass and its
  stencil, the refraction's fog term (a number under 1 to the power of the fog's 150: nothing),
  FrameParams.w (taken 0).

Grass:

- [ ] The per-instance fade-in, the grass LOD, shadows on grass, the wind's blend across a weather
  change, bGrassPointLighting, the executable's own pixel stage (Community Shaders' stands for it).
