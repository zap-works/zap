# Skyrim: what is left

Numbered in the order the milestones put it; a step is deleted when it lands. What exists and what
is measured is in `README.md`; the executable's tables are `reference/exe/README.md`.

## 1. The inn's picture (milestone 4)

- Orgnar's place in the captures, and the fire's and smoke's random draws.
- Thin bluish lines at the top of the fire's mesh flames (FireplaceWood01Burning.nif, FXFireAtlas04
  through GradFireExplosion, billboard mode 1, V scrolled over 5.67 s) at eye height, which the game
  does not show; their cause is not found from the files alone.
- The ambient's true form (the executable's, at full strength) totalled less than the flat mean
  when it was measured: the reason is unfound, floors being where the game is darker than any
  ambient gradient gives.
- Light flicker in play: `flicker.zap` stays the measured form until the term of ours that is about
  20% too bright is found (the executable's form ported totalled 346.6 then; the render captures
  pin the executable's dimmers per pose).
- TAA's BlendParams (0.8 at rest, 0.5 at speed, post sharpen and overlay 0.21) took backroom from
  95.1 to 91.1 with the weight alone: the cause is unfound.
- The ambient occlusion's motion vectors are ours, from the depths and the views, not the game's.
- Remeasure the up, down and side bias by facing per pose under the y fix: normals drawn through
  the `--ids` pass (n * 0.5 + 0.5), then ours minus the game's by normal y.
- The depth bias of the interior shadow lights: fShadowBiasScale 0.15 comes from the mod guides'
  default prefs; the executable holds the name, the value was not read.

## 2. Sound (milestone 5)

- The attenuation curve's points are read as linear volume between min and max; ducking pauses
  instead of lowering; the knock threshold is approximated.
- The lip track is not drawn: the GPU heads have no morphs yet.

## 3. The NPCs, their packages and animation (milestone 7)

- The sync points of the behavior graph (`iSyncIdleLocomotion`, `iSyncTurnState`,
  `iSyncForwardState`, `iSyncStrafeState`, `iSyncSprintState`) are still set by hand; the writers of
  the sync integers in the executable are unread.
- The stagger's mass terms: fStaggerMassOffsetBase and the player's mass multiplier.
- The AI's own movement over a 900-second time-skip step: the port takes it as reaching the place.

## 4. Interaction: doors (milestone 8)

- Doors: the distance at which the follower sends MovementMessageActivateDoor, and the lock rule
  (the cast's doors carry no lock), are not read.
- Movable doors: a door's shadow (the shadow maps are of the baked buffer); quaternion rotation
  keys (read, mixed linearly and normalised); the door's Havok body moving (its collision leaves
  the physics world when it opens); sounds on the sequences' text keys.

## 5. The interface and saving (milestone 9)

- The scene blurred under menus: its radius is unmeasured, the menu captures hold the menus alone.
- The interface sounds that are not asked, for the menu or game they belong to is not modelled: the
  lockpicking menu (UILockpicking*), the stats menu's constellation (UISkillsFocus, Forward,
  Backward, Stop, Glow, PerkSelect2D), crafting (UISmithing*, UIAlchemy*, UIEnchanting*), UISelectOn
  and Off, UIShoutLearn*, UISpellLearned (a spell tome learned), UIQuest* and the discovery music,
  UISneakAttack, ITMPoisonUse, ITMTorchHeldEquip.
- The lockpicking menu and its sounds (UILockpicking*, 0x14094f000..0x1409502f0), which no lock of
  the inn opens, and the container's own unlock notice (TESObjectCONT::Activate 0x140281c10).
- The book menu: the game lays the pages on its animated book model (render targets on Book01.nif,
  the open and turn animations).
- The journal's help list: the game's own subset and order are not read from anywhere, so the list
  is a guess.
- The journal's system page: its settings values (the executable's compiled defaults are not
  readable) and its controls list (RequestInputMappings, from controlmap.txt).
- The scroll of a text taller than its field (it is clipped; `scroll` and `maxscroll` are fixed),
  Scaleform's edge anti-aliasing of shapes and glyphs, glows and blurs of placed objects,
  MovieClip.createTextField.
- The dialogue's topics show smaller glyphs in the game than the 24 pixels their field gives at the
  list's 0.8, for a reason not found yet.
- The InventoryMenu's list filling (0x1409452b0, 0x1409451e0, 0x140945050, 0x140945e20) and the item
  card's 0x1409472c0 (5,167 bytes): which fields each item kind sets (`infoValue`, `effects`,
  `potionType`...). The field names and the entry's six members are known; the per-kind logic is
  not. `itemmenu.zap` already matches the captures, which is why it waited.
- The HUD's `ProcessMessage` (0x140933180), read only for its Invoke names and message kinds.
- Saves do not carry the sounds playing.

## 6. Items, combat, magic, stealth and skills (milestone 10)

- Combat AI, not modelled: special attacks, block attack, backoff, the target selector's scoring
  (only its 1 s / 3 s timers), the flight decision (the confidence thresholds stay approximate),
  CombatState's random confidence modifier (fCombatConfidenceModifierMin/Max), cover, flanking,
  ranged and magic nodes. An Idle child's weight 1 in the behavior tree is an assumption.
- Magic, not drawn: the casting art's billboard glow and every particle system of the spell models
  (their birth rates are blends of the controller sequences, which the NIF loader does not play),
  the impact and hit effects, the light's shadow; the hand's light stands at an approximate place
  (feet, facing) because the arm's bones are not followed. Not modeled: summons, wards,
  invisibility and the rest of the archetypes, dual casting, charge time, perks, the hands' magic
  for the NPCs.
- Stealth, not modelled: the perks of detection, combat stealth points, race sizes, a weapon's own
  sound level, and the sneak animation when the prepared cast lacks the sneak clips (the walk's
  plays). Detection events, not modelled: the explosions', impacts' and summons' events (no
  projectiles in flight or explosions), a weapon's sound level, where the executable sends a heard
  actor (its search package), the reaction of the hostile among the heard, and the events of NPC
  casters heard by NPCs.
- Eating and drinking, not done: an ingredient eaten (first effect only); a poison applied to a
  weapon (the case is refused); the effects of other archetypes (absorb, cure, invisibility...);
  the Alchemy skill and perks that scale a potion when it is brewed (a perk's entry points 0x1d
  0x1e 0x29 0x2a do change one drunk); the AI's choice to eat or drink (NPCs consume through the
  same call, no package calls it); the quest-item refusal ("You can not eat quest items"); Survival
  mode hunger; the executable's rule at the end of a Fortify Health (read, its effect at low health
  unverified); effects carried between the menus' world and the fight's copy of the actors (the
  fight gets the values back, not the effects); addiction (ENIT's addiction fields). An actor's
  (Orgnar's) use sound is not played, and the executable's site that plays it is not found.
- Skills and perks, not modelled: the entry points the inn does not hit (critical hits, armor and
  resistance, detection 0x2f 0x30 0x39 0xf whose formulas take no world, lockpicking, smithing,
  enchanting, alchemy at the table), the leveled-list, spell and text functions, the
  constellations' 3D scene and a perk node's description card, the legendary skill reset, a skill's
  description card (SetDescriptionCard), the "Level up available." HUD reminder (iLevelUpReminder),
  lockpicking, smithing, enchanting and alchemy experience (the sites are listed in the "Skills,
  levels and the stats menu" section of `reference/exe/README.md`), the skill order of the
  constellations (the AVIF perk tree's, taken as the actor value order), a spell's cost taken from
  its record where the executable takes its costliest effect's (the same for one effect), the
  unarmed hit's Block experience when a weapon bashes, the rare event the game fires on a skill
  increase (recorded as a line of `GameWorld.events`).
- The perks no inn mechanic hits (critical, armor, detection).
- The Creation Club plugins (Survival's ALCH overrides) are not loaded.

## 7. Dialogue (milestone 11)

- Turning the third person camera to a speaker further aside than fDialogueSoftStopAngle3P is the
  settings' reading, not measured.
- The dialogue's info choice 0x1403ef230 (conditions, random, say once) and the `DialogueItem`
  builder 0x1405ed830; the manager's walk around them is read. `choose.zap` does it from the
  records and `dialoguetests.zap` holds, which is why it waited.

## 8. Physics (milestone 12)

- Not read (approximated): the solver's own term in the contact's allowance (taken as none); the
  velocity stabilization's table (the skeletons' byte 48, 1.067, for every ragdoll ball and socket;
  the NIF constraints', not read, take none) and why a hung rabbit's swing lasts (about half is
  left after 20 s; the old stable socket damped it to rest in 15 s); the stabilized ball socket (the
  skeletons do not use it; a NIF constraint built at run time might); the prismatic's rows (the lin
  atoms); the motors; the order a world's constraints are turned into rows (the joints', in the
  world's order, after the contacts); the twist limit's softness (tau 0.6 times 0.8 times the
  squared half length of the twist axes' sum: Orgnar's loaded shoulder rests 14 degrees past its
  twist limit, unchecked against the game); restitution (Box2D's relax pass above 1 m/s); rolling
  friction (none: every rolling friction multiplier of the inn's clutter is 0); the island
  deactivation's checks after the counts. Restitution, the lin constraint atoms and the motors are
  Havok's own code, reached from the `hkp*ConstraintData` vtables in the "Havok (the physics)"
  classes section of `reference/exe/README.md`; the collision filter and the angular constraint
  schemas are read.
- The two CLOUDTRAP/PORTAL and CLOUDTRAP/ACOUSTIC SPACE bits of the layer matrix, cleared through a
  temporary the parser skipped (the "Havok: the collision filter" section).

## 9. A gameplay comparison

- A scripted run in the game and in ours, compared by state.

## 10. The frame rate (milestone 13)

- A frame rate above the game's on Windows, measured on this PC in the same cell; the frame rate
  unlocked.

## 11. The whole town of Riverwood (milestone 14)

The exterior:

- The exterior grid streamed cell by cell: per-cell prepared files, so that a step loads only the
  cells that enter. `main.zap` reloads the whole area once the player is past the middle ring,
  since the prepared file is one per area.
- NIF texture sets' Bethesda build paths (`textures/skyrimhd/build/pc/data/...`, 28 textures
  missing outside) normalized as the executable does, and the garbled keys (`meshes/g.`,
  `textures/nor`) traced to their record.
- Captures of Riverwood to measure the exterior against.
- The emittance (XEMI) light: the region's weather is its likeliest (SkyrimClear, first of the
  equal chances) where the game takes the sky's current one, carried in from outside; the flag is
  per model, so a ref of an externally lit model without XEMI would take the cell's source (none
  in the inn).

The town's people:

- The residents' low-process speed: 130 units a real second is a stand-in, the executable's
  AIProcess code has not been read for it.
- The sounds and footsteps of the exterior's people; greetings and ambient lines outdoors beyond the
  dialogue the cast already has.
- The town's interiors prepared one by one in a running game (they prepare on first use, through
  their doors).
- A cell's residents carried across a load door in a running game (`departed` and `arrival` are the
  hand-off, `main.zap` does not yet deliver them).
- Papyrus state carried between cells (each cell's VM is new, as a new game finds it).

Terrain:

- The border geometry along each cell's edge (BSTriShape at LoadedLandData+0x4880, built in
  0x1402ae650), the landscape's shadows (sun shadow maps), snow, the parallax and the vertex stage's
  distance fade (LandBlendWeights2.w), the physics material per texture (all 0.5 friction), cells
  with no LAND (the world's default land height is read, not drawn), the vertex normals and tangents
  of the executable's tangent generation (ours: u along +x), and xEdit values (it has no CLI; the
  heights are checked against the trees and the normals instead).

Sky, weather and moons:

- Diff against the executable in `x64diffs.zap` what is only read from the code and unit tested
  (`skytests.zap`): fog (day share ramp), the sun's windows, track and arc, stars' alpha, cloud
  scroll, weather life, transition, the region pick and the keep-on-entering roll, the image space
  as a weighted sum.
- The sun's blend: the sun is added like the glare on an assumption, the sun mesh having no alpha
  property of its own in Init and its sky shader property's blend not being read.
- Lightning scheduling, the sun's occlusion fade of the glare (0.25 to 1 by terrain queries), the
  cloud mesh's blending modes and the layers' color swap when the current has none (0x14040c220),
  the accelerated transition flag, fog clamped to the far plane, the stars' real rotation by days
  passed, the moons' stencil mask.
- The MOONMASK shadow quad (a stencil that keeps the stars and clouds off the moon: Sky.hlsl's
  MOONMASK, MoonShadow.dds) and the moons' clouds-edge scatter.

Precipitation:

- The precipitation occlusion map (rain under a roof), `bUsePrecipitationOcclusion`; the game's use
  of an amount over 1 (the pool holds three cubes) is not read.

The sun's shadows:

- The cascade fit (0x14157f080) diffed against the executable with `projects/recomp/x64`: the slice
  and fit code lives in the middle of a 1,400-line function that allocates cameras and culling
  processes, so it is unit-tested in `skytests.zap` only.
- The shadow pass's rasterizer state, which gives the mask its bias, is not read: the engine's depth
  bias stands in.
- The actors' focus shadows (iNumFocusShadow), the screen-space shadow refinement, the update
  interval (fSunShadowUpdateTime), trees' and grass's casting flags (bShadowsOnGrass,
  fMaxHeightShadowCastingTrees).

Distant LOD:

- The loaded area's box for the land's sink (its centre and half side uGridsToLoad x 4096 / 2) is
  an assumption.
- The objects' tangent-space normal maps are not read (they use their vertex normals).

Water:

- The cube map the executable reflects (the planar reflection stands for it), the screen-space
  reflection, ripples, displacement and wading, the shadow on the water, the underwater pass and its
  stencil, the refraction's fog term (a number under 1 to the power of the fog's 150: nothing),
  FrameParams.w (taken 0).

Grass:

- The per-instance fade-in, the grass LOD, shadows on grass, the wind's blend across a weather
  change, bGrassPointLighting, the executable's own pixel stage (Community Shaders' stands for it).

## 12. Android (milestone 15)

- Skyrim on Android, after the frame rate.
