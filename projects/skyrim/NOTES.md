# Skyrim: the Sleeping Giant Inn rebuilt in Zap

One cell of Skyrim Special Edition (the Anniversary Edition's base files are the same), Riverwood's
Sleeping Giant Inn (`RiverwoodSleepingGiantInn`), rebuilt in Zap on Zap's engine from the player's
own install, copied into `projects/skyrim/assets/game/` by `zap run projects/skyrim/fetch.zap`:
nothing of the game is committed (`projects/skyrim/assets/` is ignored) and the project reads the
game from that copy alone. `zap run projects/skyrim/prepare.zap` reads it once and writes the cell
ready to use into `assets/prepared/`; the game reads only that.
A prepare keeps every laid-out and baked texture in `assets/prepared/cache/` under a key of the
game's file it reads and the sources of the code that makes it (game/texturecache.zap), so a second
prepare reads them back: about 10 s of processor against 28 s from nothing. The lit parts keep
their materials whole (the shader property's fields and texture set) and take their looks when the
cell is drawn (world/looks.zap), every map a flag may turn on prepared: a change of how the fields
and flags become the shader's uniforms, or of the shaders, needs no new prepare.

The aim, in this order: the inn exactly as the game draws it, frame by frame, with the player
walking in it and the Havok physics of its clutter; then a frame rate above the game's on
Windows; then Android. Every rule is learned from the game's data, its shaders and its code,
and measured against captures of the real game (`compare.zap`, pictures in `assets/reference/`, never committed; the poses and what each capture pinned in `reference/poses.json`, versioned). The references are each RenderDoc capture's final presented frame (`<pose>-final.png`, the pose's `capture`), the old PNGs only a fallback; total 544.0, see `reference/exe/render-captures.md`.

## Fidelity: what we read, port and copy

The user's rule (2026-10-21): maximum fidelity; code may be copied as long as it ends up as Zap.
So the order of sources for any behaviour is:

1. **The game's own data**: the plugin (ESM records: lighting, image spaces, lights, placements),
   the NIFs (materials, controllers, particles, collision), the HKX files (skeletons,
   animations), the ini defaults (`Skyrim_Default.ini`).
2. **The game's own shaders**: `Data/Skyrim - Shaders.bsa` holds one file, the package of every
   compiled shader (DXBC) of the SE: BSLightingShader, BSEffectShader, the particle, sky, water
   and shadow shaders, the image-space passes (eye adaptation, bloom, grading, FXAA/TAA).
   Disassembled DXBC gives the exact formulas. Shortcut: **Community Shaders**
   (github.com/doodlum/skyrim-community-shaders) reconstructed these shaders in readable HLSL from
   that DXBC; its `package/Shaders/*.hlsl` (Lighting.hlsl, Effect.hlsl, ISHDR*, ISApplyVolumetricLighting...)
   are the reference to port to `.gpu.zap`, formula by formula.
3. **The executable** (`SkyrimSE.exe`, 1.7.104.0 in this AE install by its version resource, 64-bit, no symbols): camera heights and
   conventions, movement speeds and turning, animation blends, Havok settings (step, gravity,
   collision layers' matrix, character proxy), the AI sandbox packages. Read with **Ghidra**
   (NSA, open source; Java) helped by the community's names: the **Address Library for SKSE
   Plugins** (function ids per version) and **CommonLibSSE-NG** (github.com/CharmedBaryon/CommonLibSSE-NG:
   the engine's classes and functions declared in C++ with their offsets, in effect a header of
   the engine). **REA** (github.com/morluto/rea, MIT) wraps Ghidra (and Hopper or IDA) as a local MCP
   server and CLI, so an agent can ask for a function's pseudocode, its references and symbols
   instead of driving Ghidra's window. Setup when needed: Java 21, Ghidra, `npx rea-agents`
   pointed at the exe; the first analysis of the exe takes hours, kept in a Ghidra project
   outside the repository.
4. **Community reimplementations** to port where they match the game: the Skyrim shader
   reconstructions above; **HavokLib** (PredatorCZ, for the spline-compressed animations, already
   used), **hkxPoser** and **hkxpack** (the 2010 packfile layouts); **NifSkope**'s nif.xml (the
   blocks); **xEdit**'s record definitions and **UESP** (the plugin format); **BSArch** (the
   archives); Havok's own behaviour as documented by the Havok 2010 SDK docs and by
   **Bullet**/**Jolt** for the general algorithms (sequential impulses, SAT, MOPP-like trees).
5. **Shortcuts before reading the executable** (look here first, port into Zap):
   - **CommonLibSSE-NG** and **SKSE64**'s source: the engine's classes with their fields and
     offsets (Actor, CombatController, the menus' data, PlayerCamera, ImageSpaceManager,
     BSLight) and SKSE's Scaleform hooks, which show exactly how the game fills the menus'
     entry objects (ItemList entries, the barter and dialogue menus).
   - **Address Library** ids plus Ghidra/REA for the functions those name (flicker, bloom
     constants, the dialogue camera, the combat behaviour tree, barter prices).
   - **HKX2** (C#) and **Pandora Behaviour Engine** (github.com/Monitor221hz/Pandora-Behaviour-Engine-Plus):
     the Havok 2010 behavior graph classes (hkbBehaviorGraph, state machines, transitions,
     generators, events), so the character's animation graph (turns, attacks, sit and sleep
     transitions) is the game's own instead of a hand table.
   - **OpenAnimationReplacer**, **Precision** and **TrueHUD** (open SKSE plugins): the animation
     graph and the hit detection as the game runs them, reverse engineered.
   - **Community Shaders**' ISTemporalAA.hlsl and the ISHDR bloom passes: TAA and bloom.
   - **UESP**'s reverse-engineering notes (DavidJCobb and others): combat, stagger, barter,
     detection formulas.
   - **OpenMW** (Morrowind's engine): the design of AI packages, dialogue, barter and the
     scripting scheduler, close to the Creation Engine's.

Whatever is copied is written as Zap in the module where the knowledge belongs (the engine for
what is general, `projects/skyrim` for Skyrim's formats and conventions), with the source named
in a comment at the top of the file.

## How a port of the executable's math is checked

A port of a function of SkyrimSE.exe that is pure math is checked against the executable itself:
`x64diffs.zap` runs the function in the x86-64 emulator (`projects/recomp/x64`: the PE loaded at
its base, an interpreter of the integer and SSE instructions, the Windows x64 convention, the C
runtime's imports run in this machine's ucrtbase) on a few thousand seeded inputs, the structs it
reads in scratch memory and the calls it makes beyond the math stubbed, and compares each result
bit for bit with the port's. Where they differ the port is changed: the executable decides. The
exe is read where it lies (`C:/tools/skyrim-input/SkyrimSE.exe`); without it the tests pass
quietly. `zap run projects/recomp/tools/x64run.zap <exe> <address> --float 1 --float 2 --trace`
runs one function by hand, `--disasm n` lists its instructions.

Checked so far: Havok's atan2 approximation (engine/physics `angleOf`), the flicker's dimmer and
offset from its phases (`world/flicker.zap`, rewritten to the exe's constants and order of
operations; its sine table is the exe's angles but the exe's sines come from its vector sincos,
140 of 512 an ulp from the correctly rounded ones, so the core is compared on the exe's table),
the skill-use experience loop (`gainExperience`), the perk entry points' number functions
(`entryFunctionValue`) and the detection sum (`valueAt`, its terms' association fixed; powf is
the platform's, the port's pow rounded from double precision differs on about 1 case in 4000).

## The install

| Data/ | What |
|---|---|
| `Skyrim.esm`, `Update.esm` | the world: cells, the objects placed in them, lights, NPCs |
| `Skyrim - Meshes0/1.bsa` | the NIF models (Gamebryo 20.2.0.7, BS version 100) |
| `Skyrim - Textures0..8.bsa` | the DDS textures: DXT1, DXT5 and raw RGBA (no BC7 in the base game) |
| `Skyrim - Animations.bsa` | the HKX skeletons and animations (Havok 2010.2.0 packfiles, 64-bit) |
| `Skyrim - Shaders.bsa` | the compiled shader package (see above) |
| `Skyrim - Sounds.bsa`, `Voices_*.bsa` | the sounds: effects as WAV, music as xWMA (WMA version 2, 32 to 48 kHz stereo), voices as FUZ (lip data and a mono xWMA) |
| `cc*.bsa/.esm/.esl`, `_ResourcePack.bsa` | Creation Club content, copied, not read yet |

## Fetching the game

`zap run projects/skyrim/fetch.zap [--install <the install's dir>]` copies what the game reads out
of the player's install (by default `C:/games/Skyrim Anniversary Edition`) into
`projects/skyrim/assets/game/`, laid out as the install is: Data's archives, plugins (base game,
Update, the DLC masters, the Creation Club's) and videos, and the install's `Skyrim.ccc` and
default ini files; not the executable (what the project uses of it is text in `reference/exe`).
About 22 GB; a second run copies nothing. Every tool and test then reads the game from
`projects/skyrim/assets/game/Data` alone (`esm.defaultData`); `--install <Data dir>` points one at
another. In a worktree the dir is a junction to the main checkout's copy. The dir is ignored by
git and never committed.

## What exists

- `skyrim/bsa`, `skyrim/install.zap`: BSA v105 read in place (LZ4 frames, `std/lz4`).
- `skyrim/esm`: the plugin read in place; a cell by editor id, its lighting and image space,
  its refs resolved to base records (model paths, lights, placements).
- `skyrim/nif`: models into draw parts (static, skinned, billboards, switch and LOD nodes,
  materials, controllers and particle systems) and into Havok colliders (`havok.zap`,
  `collision.zap`: compressed meshes, hulls with their shell radius, boxes, spheres, capsules;
  the constraint blocks with their frames and limits, malleable and breakable wrappers too).
- `std/image/dds`: DDS with BC1 to BC7 decoders (checked bit for bit against Pillow).
- `skyrim/hkx`: the skeleton (99 bones) and the spline-compressed animations; skeleton.hkx's
  ragdoll (`ragdoll.zap`: 18 capsule bodies, 17 ragdoll and limited hinge constraints) and its
  two skeleton mappers (`mapper.zap`, Havok's mapPose in model space).
- `skyrim/actor`, `game/player.zap`: the player's body from the plugin (race skin, outfit, head
  parts), skinned to the skeleton, as the engine's skinned model.
- `skyrim/actor/npc.zap` and its neighbours, `game/npcs.zap`: the NPCs from their records as the
  game builds them (templates and leveled lists at level 1, outfits, head parts, tints, the
  localized names of `skyrim/strings.zap`), their heads from the baked FaceGen files (the TRI
  morphs as the fallback, `tri.zap`, `face.zap`), their AI packages with schedules and conditions
  (`package.zap`, `esm/condition.zap`); the inn's actors: those it places and those its packages
  bring (`game/sim/cellactors.zap`, which the dialogue reads too).
- The residents at a new game and over time: each starts at the reference the cell placed it at
  (`takePlan` with `Entry.Loading`; one without a reference at its package's place) and walks to
  its package's place over the navmesh (`findPath` draws each portal in by the capsule's radius,
  so a turn keeps the body off a jamb). A sandbox package whose place holds the actor settles in a
  marker as before.
- Doors (`game/doors.zap`, read from the exe, its header has the addresses). The pathing system cuts
  every loaded door into the navmesh ("Add Door %08x"), so a path through a closed door carries it
  as a point (PathingDoor, 0x1404e1d00 names the reference); the actor reaching that point sends
  itself MovementMessageActivateDoor, whose handler (Actor 0x1406a81d0) calls
  TESObjectREFR::Activate (0x1402f11b0) unless the door is the one the actor last went through
  (process +0xd8, set only by a teleport door's action); a non-teleport door's Activate
  (0x140283210) is the toggle 0x1401d9590 (the Open sequence on a closed door). Nothing in the AI
  plays Close: an open door cuts nothing, so no path names it, an actor that opens a door leaves it
  open. fDistanceAutomaticallyActivateDoor (250) has one reader, 0x140786780, run when a door is
  activated by anyone but the player (0x140283f00): every actor of the process list whose mover
  heads for that door within 250 of it is taken to have been through it. fINIDetectDoorsForPathingTime
  (0.5 s, times a random scale) is the timer of a phantom-box query ahead of the actor (0x1407029e0)
  that finds a door and discards it (the tail call, 0x1406b5150 to 0x1406a5540, takes the actor only).
  What the port does: `walkTo` lists the closed doors the path crosses (the leaf's segment, the
  door's origin and half width from its model, against the path); reaching the point (the radius,
  the leaf's half thickness and the arrival distance, not read from the exe) the actor opens the
  door (`sim.activate`, its sound by `placeInWorld`'s openings), its collision leaves the physics
  world, the actors within 250 lose that crossing. Not read: the distance the follower sends the
  message at, the lock rule (the cast's doors carry no lock).
- The time skip (`skipTime`, main.zap calls it as a wait or sleep ends with the seconds waited).
  SleepWaitMenu (0x140974e00) adds the frame's time and, each second, calls Actor::AdvanceSleepWaitTick
  (0x140749560): iSecondsToSleepPerUpdate (900; the global 0x1420a0ee0 holds 0x384) game seconds
  a tick, the seconds left in the player (+0x8f4) down by it. A tick: the player's cast
  interrupted; the ProcessLists clock (0x140780ec0) and the calendar (0x140645d60) moved on by 900
  over the time scale; the calendar's values cached (0x14077d080); then, unless the player's flag
  0xb12 bit 1 is set (only its active effects, 0x1405d2080), every actor of the high list
  (0x14077ccc0 over +0x30, per actor 0x14067be00) is updated with the tick as its elapsed time
  (the movement and AI object at actor +0x150), and those of the two lower lists (0x14077c5f0,
  0x14077c280) whose process stamp differs by a tick or more run the Character update
  (0x140679d50) with it; each 3600 seconds of ticks UpdateNonHighActors (0x14077bbc0) runs the
  low list's helpers. So an actor reaches its package's place within a tick at the tick's hour and
  the doors on its way open; the port runs `takePlan` at each tick's hour (`Entry.Skipping`),
  `openAlong` opening the closed doors on the navmesh path from where the actor stood to its new
  place, and the sleep and wait's regeneration already per tick (`game/sim/sleepwait.zap`). Not
  read: the AI's own movement over a 900-second step (the port takes it as reaching the place,
  which the speed and the paths of the inn make true).
- Movable doors (`game/movable.zap`, `world/movables.zap`, `skyrim/nif/sequences.zap`): a door
  whose model has a NiControllerManager with Open and Close sequences (the farmhouse doors: one
  second, clamped, NiTransformInterpolator on the node Door02, an XYZ Euler key group, 0 to about
  90 degrees about z) is left out of the cell's baked buffer and kept as `Movable`s in the prepared
  head (format 32): its parts' triangles in the model's space, the frames of the nodes the
  sequences move (rest local, parent and own transform), the two sequences. The scene poses it:
  the node's local transform at the sequence's time (the interpolator's value where it has keys
  or a constant, the node's own elsewhere), the part moved by parent x local x inverse(rest
  world), the reference's placement on top; drawn in the opaque passes (and the normal pass)
  from dynamic models, the blended and added parts with the particles. The state is what the
  game does: SetOpenState (0x1401d9eb0) on load puts a door at the end of its state's sequence;
  Activate (0x1401d9590) toggles by flag 4 of the reference and plays the new state's
  sequence, ignoring the activation while either sequence is animating (state 1 of the
  sequence, +0x68); main.zap tells the scene each frame (`setOpen` from the world's form).
  The sequences' names are the table 0x140224be0 fills ("Open" at 0x1417e0084, "Close"). Not done:
  a door's shadow (the shadow maps are of the baked buffer), quaternion rotation keys (read, mixed
  linearly and normalised), the door's Havok body moving (its collision leaves the physics world when it opens), sounds on the
  sequences' text keys.
- `game/cast.zap` and its neighbours, `world/actor.zap`: the cast prepared with the cell and drawn
  as one crowd: every actor's body toned as the skin shader does (the FaceGen tint, the skin
  tone, the hair color), women on the female skeleton, the clips shared by skeleton with their
  root motion; the furniture and idle markers (`markers.zap`) and the navmesh
  (`esm/navmesh.zap`, A* and the funnel in `engine/scene/navmesh.zap`). `residents.zap`,
  `sandbox.zap`, `look.zap`: the actors' packages taken by the hour (and EvaluatePackage), the
  sandbox at the markers, the head turned to the player. The character's behavior graph is the
  game's own for locomotion (idle, walk, run in every direction, turn in place) and for sitting
  and sleeping: `skyrim/hkx/graph.zap` and `graphjoin.zap` read 0_master.hkx with the behaviors it
  refers to (state machines with their transitions and nested states, blenders, selectors,
  clips with their triggers, variable bindings, expression modifiers); `game/graph.zap` runs it
  (events down the active tree, blends, a clip's end events, parametric and cyclic blends, the
  expressions of `engine/scene/expression.zap`), fed by the body's speed and turn
  (`Walker`) and by the marker events (`graphMarkers` in `markers.zap`), and gives the clips and
  weights the pose code samples. The marker kinds are entered, looped and left by the events of
  their IDLE records (ENAM: EnterChairFront, IdleLeanTableEnter, IdleCounterStart,
  IdleLooseSweepingStart...) found by running the graph (`markerClipsOf`), a seat entered from behind
  sitting at once (the enter event, then IdleChairEnterInstant) and left by tablebackexit. The fight
  is the graph's too: `fightevents.zap` tells each fighter's animator what the fight does (WeapEquip,
  Unequip, attackStart, attackPowerStartForward and attackRelease, blockStart, bashStart,
  staggerStart, bleedOutStart, Ragdoll) and `fightmagic.zap` the spells (BeginCastRight/Left, the
  MRh_/MLh_ start, release and CastStop events), the clips and the attacks' timings (a clip's length
  and where the HitFrame its generator sends lies) are read off the graph run with those events
  (`fightclips.zap`), a spell let go leaving the hand at its clip's MRh_SpellFire_Event; the
  footsteps sound at the Foot keys of the clip the graph plays most. The blender children that move
  only some bones lay their clip over the others by their hkbBoneWeightArray (`Layer.bones`, mixed
  bone by bone in `engine.Pose.mixed`); a spell's charge is its SPIT charge time after the graph's
  own wind-up (`castIntros`); a stagger's magnitude is the hit's (weapon stagger times the attack's)
  clamped to the places of the graph's staggerMagnitude blend, its length measured at each; a
  shout (SHOU, `sim/shouts.zap`, given to the player: a new game knows none) is told to the graph
  as shoutStart and the exhale of its word count, its spell cast at the Voice_SpellFire_Event. Still
  by hand: the sync points, and the stagger's mass terms (fStaggerMassOffsetBase and the player's
  mass multiplier). `graphinfo.zap` prints the graph (`--tree`, `--event`).
- The engine's `engine/physics` (`import engine.physics`): rigid bodies (SAT over hulls), Havok
  2010's solver as SkyrimSE.exe runs it (`solver.zap`, `friction.zap`, read from the executable's
  hkpWorld step, solver loop at 0x140c12e20 and contact jacobians at 0x140c243c0, 1.7.104):
  `iterations` sub-steps of dt / iterations, gravity given before each, rows asking for
  -(tau / damping) * error / h and solved for damping * (rhs - v) / K (hkpConstraintQueryIn's
  rhsFactor and virtMassFactor), the errors measured once and the sub-steps integrated virtually
  (each body's velocity carries tau / damping times its motion so far, the step's mean velocity
  carries it), no warm starting, a manifold's points solved two at a time (the pair spanning it),
  an overlap past a step's recovery held as the point's allowance and given back 5% a step (at
  most 1 m/s), its friction one 2D friction (and a turn about the normal) at the points' center
  bounded by last step's normal impulse and anchored at friction tau (tau / 2); the joints' rows
  as `havok-solver.md` has the executable's schemas (`rows.zap`, `constraints.zap`): the ball
  and socket's old method (three bilateral rows, rhs 144 times the gap less 1.067 times the
  pivots' rotational velocity), the stiff spring, the 2d ang axle, the angular limits (twist,
  cone with the stabilized cone's ratchet, planes, the hinge's angle by Havok's atan2
  approximation, tau factor 0.8 for a ragdoll, 1 for a hinge; the bias and the velocity weighed
  apart, the impulse's sign kept by a test), the angular friction (each pass cut to the torque
  over the sub-step), and what the limits and friction leave for the next step (internal solver
  data, saved with the joints); the solver deactivation's slowing at each
  sub-step's end (per axis, its rest share stopping the body); Havok's deactivation checks
  (`sleep.zap`: every 4th step against 0.02 m, every 16th against 0.08 m, an island asleep after
  more than 5 checks passed). The joints of Havok's constraints solved with the contacts
  (`constraints.zap`, `rows.zap`), ragdolls (`ragdoll.zap`), the player's capsule controller; the
  inn's clutter settles, its 17 hanging animals hang from their hooks (`game/hanging.zap`, `physinfo.zap --hanging`), a dead actor
  falls as his skeleton's ragdoll (`game/fallen.zap`; `main.zap --kill frame:EditorId` until the
  combat is hooked to the scene). Read: each body's damping, friction, restitution, mass, own
  speed caps and solver deactivation class (bhkRigidBody; a skeleton's hkpRigidBody motion state);
  from SkyrimSE.exe: the deactivation classes' table (hkpWorld's constructor, run on gravity 9.81:
  `game/havokworld.zap`: the speeds below which a class slows a body, the share of its velocity
  it keeps a sub-step and the share of those speeds below which it stops), the deactivation
  checks' distances and turns, hkpWorldCinfo's gravity (0,0,-9.81), solver tau 0.6,
  damping 1.0, 4 iterations, step 1/60, all adopted (`game/havokworld.zap`). The ragdoll's constraints
  (skeleton.hkx): limits and friction as read; every priority is PSI (the discrete step's); each
  joint's hkpPositionConstraintMotor is read (tau 0.8, damping 1, recovery 5 and 0.2) but its atom
  is switched off, as the game leaves a dead actor's ragdoll limp, so no motor runs.
  Not read (approximated): the solver's own term in the contact's allowance (taken as none), the
  velocity stabilization's table (the skeletons' byte 48, 1.067, for every ragdoll ball and
  socket; the NIF constraints', not read, take none) and why a hung rabbit's swing lasts (about
  half is left after 20 s; the old stable socket damped it to rest in 15 s), the stabilized ball socket (the skeletons do not use it; a NIF
  constraint built at run time might), the prismatic's rows (the lin atoms), the motors, the
  order a world's constraints are turned into rows (the joints', in the world's order, after the
  contacts), the twist limit's softness (tau 0.6 times 0.8 times the squared half length of the
  twist axes' sum: Orgnar's loaded shoulder rests 14 degrees past its twist limit, unchecked
  against the game), restitution (Box2D's relax pass above 1 m/s), rolling friction (none: every rolling friction
  multiplier of the inn's clutter is 0), the island deactivation's checks after the counts.
- `world/`, `game/prepare.zap`, `main.zap`: the cell prepared and drawn (bindless textures, the
  cell's lights, fire by the NIF's controllers and particles, the image space's grading with eye
  adaptation and bloom). Measured against the captures (compare.zap), not read from the
  executable: a directional fade of 0 as full (the inn's own fade is 0, its template's color
  65 70 80 lights the walls facing east), the interior's directional light reaching as (n.l)²
  without a highlight and not on effects, its ambient the mean of the DALC cube's six colors from every side (the engine's form is linear, mul(float3x4, float4(n, 1)): a base color plus the normal times each axis' half difference, as Community Shaders' State.cpp and Nukem9's BSLightingShader read it, but at full strength it totals 437.6 of share within 8 against 462.4 flat, and every sign of the three axes totals about the same; the squared cube was worse too; 0.2 of the difference totals 474.1 but is a fitted constant and is left out; the template keeps its cube in LGTM's DALC, read now; the reason the true form loses is unfound; exact6: the cube's names are the light's travel direction, so a surface takes the color of the side opposite its normal on all three axes, which is the form that totals 440 (full strength, linear sun 443), floors being the cause: the bias by facing under the flat mean is up -0.8 to -6, down +2 to +4, and under the full form up +3 to +8 at start, firepit, table, where the game's floor is darker than any ambient gradient gives; the normal map's tangent frame has the game's handedness (flipped 425.5) and its z from the texture or from x and y totals the same; vertex colors, the lights' radius and fade offsets (each dropped 297 to 302), the squared sun, fog (off 427) are all as measured) the game's limit of seven lights a draw changes nothing here, the cell having eight lights none of which all
  reach one part; a half pixel of yaw or pitch on firepit moves red and blue in opposite ways), the ambient occlusion's radius (50) and intensity (10), the backs of
  two-sided parts lit as their fronts. Ported from the game's shaders: TAA (jittered projection, depth reprojection, the luma bracket; the
  edge confidence of the game's version measured worse and is left out), the bloom bright pass
  (the light over the threshold times the scale), the environment cube maps of glass and metal
  and the eyes (faces laid side by side in a 2D texture), the scene blurred under menus (its
  radius unmeasured: the menu captures hold the menus alone). Each moves compare by under 0.2.
  The candle flame's tall shape is NiParticlesData's aspect (after the atlas cells: ratio, flags,
  ratio at speed 2, speeds 1 and 2; MPSCandleFlame01's flame 1, 0x101, 0.42, 0.3, 7.5, its glow 2.1,
  0; the fire's flames and smoke 0.9, 0x1): flag 0x1 turns the ratio on (the glow's 2.1 is off),
  0x100 moves it with the speed (laying the quads along the velocity instead turned the fire's
  flames into streaks and is not the game's), the ratio read as height = size / ratio (as the captures show the flame; width = ratio x size totals 503.6
  against 503.2, the candles being a few pixels). BSPSysSimpleColorModifier as the executable updates it
  (0x14157d420, engine.colorOverLife): one blend at a time (the first to the second before the
  second's start, else the second to the third after the second's end; a span of 0 skips it), the
  alpha the second color's, from the first's before fadeIn and toward the third's after fadeOut (a
  start, not a length); all times 0 hold the middle color, so the candle glows show: 503.2 to 513.2
  (table 91.9, pelt 96.0). An effect's alpha as Effect.hlsl orders it: the vertex alpha times the falloff
  and the soft fade is the row the palette's alpha is read from (not a factor after it): 513.0 to
  523.5 (bar 83.7 to 93.1); particles always take their vertex color and alpha (VC). The
  clamp mode of BSEffectShaderProperty is read and applied per axis. Left: thin bluish lines at
  the top of the fire's mesh flames (FireplaceWood01Burning.nif, FXFireAtlas04 through
  GradFireExplosion, billboard mode 1, V scrolled over 5.67 s) at eye height, which the game does
  not show; their cause is not found from the files alone.
- Shadows (exact7), measured against compare.zap's share within 8 (462.7 flat ambient on a fresh prepare; a prepared cell copied from another worktree can hold an older cube, so run `prepare.zap` after changing what it stores): the cell has 8 lights and only 2 cast shadows (LIGH flags 0x1009: `FarmInteriorFireLight01` and `FarmInteriorShadowLight01`; the 0x400/0x800/0x1000 bits are the spot, hemisphere and omni shadow flags), as ours; drawing none costs 34 points (428.1), so shadows are the biggest single term. Tried as the game's own forms: the hemispheres as halves of one atlas (Community Shaders' Utility.hlsl RENDER_SHADOWMASKDPB and LightLimitFix.hlsli GetLocalShadow: `uv.y = lowerHalf ? 1 - 0.5 uv.y : 0.5 uv.y`), a 2048 by 1024 map each: +0.5, kept; the engine's depth bias (LightLimitFix.h `LOCAL_SHADOW_DEPTH_BIAS` 0.00025 times BSShadowLight's shadowBiasScale at 0x540, fShadowBiasScale 0.15 from the default prefs of the mod guides, the exe holds the name but the value was not read): -0.1; the mask at iShadowMaskQuarter 4 (TruePBR.cpp: 4 reads the mask with nearest filtering, anything else bilinear, so the game's mask is full size: one hardware compare a pixel, no normal offset): -0.4; all three -0.3; the map size alone (1024 square) +0.8 at the time but is not the game's. Full-strength directional ambient, DALC sign-flipped (mean of the six minus each axis' half difference times the normal component): 440.4; unflipped 336.1; flat mean stays. What is left at start is a shadow of the pit step the game stretches about 80 px further than ours on the right of the post; found: the paraboloids' axis is the light's own x axis (Gamebryo's direction of a light, the refs' rotations being 0), not the up axis: axis x 468.6 (table +4.0, pelt +1.5), axis z 448.8, up 462.9 (renderer x is the game's x; the sign makes no difference). The ambient matrix from the executable (Community Shaders' Hooks.cpp `Sky_SetDirectionalAmbientColors`, `REL::RelocationID(98989, 105643)`, offset 0; in this SkyrimSE.exe 1.7.104.0 it is the function at 0x1414EC3B0, found by its 12 stores to `directionalAmbientTransform` at 0x1420D6978, no Address Library present): for the six cube colors c0..c5 (+x -x +y -y +z -z, game axes, z up) the rotate's column k is (c[2k+1] - c[2k]) * 0.5 per channel, the translate is (c0 + ... + c5) * (1/6) (the added vector at 0x14331D6F0 is the zero constant), the scale 1.0, no clamp; so a normal n takes mean + sum over axes of n_k * (c[2k+1] - c[2k]) / 2, the sign flipped form at full strength, which is what compare measured at 440 to 446 against 468.6 flat; 0x1414EC730 builds the six colors back from the transform as t -/+ column. The function's inputs (Sky::UpdateColors, 0x140413016) were not followed, nor the pixel stage's use, The inputs and the pixel stage were followed too: Sky::UpdateColors (0x140413016) reads an interior's six colors through 0x140416fc0, each byte of the cell's lighting data (or, when its inherit flag 0x1 is set and it has a template, the template's DALC) times 1/255 with no other term (the blend toward a second source is 0 in an interior); the geometry setup (0x1415496CA, 0x141549C14) multiplies the transform's rotate by the geometry's world rotation (a model-space normal), which is the world-space form for ours; Lighting.hlsl takes max(0, mul(DirectionalAmbient, float4(n, 1))) of the normal-mapped normal, times the albedo, times the vertex color. All of it is what ours does, and the sign-flipped form at full strength still totals 446 against 468.6; the ambient occlusion at intensity 20 or 40 on top of it totals 436 and 398, so a stronger occlusion does not make up the gap. The fire light's flicker (period 0.33, amplitude 0.4, movement 2 units) is already in `flicker.zap` and the shadow follows it; 2 units moves a shadow edge by under 10 px, and the LIGH has no model, so no node offset.
- Interface sounds (`game/sim/uisounds.zap`, `interface/menusounds.zap`, `game/sound/uisound.zap`):
  the game asks UI::PlaySound (0x1409920a0) for a sound by editor id; here every ask is queued in
  the world (`SoundAsk`, `playUi`) and main plays them after the interface's frame
  (`Screen.takeSounds`, `Book.playAsk`). The name is a sound descriptor (SNDR) played through the
  default objects' interface output model (IOPM, 2D), else a sound marker (SOUN: "UIMenuOK",
  "UIMenuCancel", "DRSLocked", "UILevelUp", "UISkillIncrease") whose SDSC descriptor plays with its
  own rules. Asked: every menu movie's GameDelegate PlaySound (menus.md's handler 0x140991e00:
  UIMenuFocus, UIMenuPrevNext, UIMenuBladeOpenSD and CloseSD, UIMenuOK, UIObjectiveNew), the
  journal's UIJournalOpen (0x1409abe30), the stats menu's UISkillsTransitionUp (0x140976a50), the
  wait menu's UIMenuOK on its OK and UIMenuCancel as a run ends (0x1409752a0, 0x140974e00), the
  message box's UIMenuOK (0x140962f50), a note's ITMNotePageTurn (0x1409063d0), UIFavorite on a
  favorite marked or its hotkey used (0x14092e110, 0x14092d0d0), UIMagicSelect and UIMagicUnselect
  as the player's spell goes in and out of a hand (0x1406de200..0x1406df550), UISkillIncrease as a
  skill rises (the HUD notification, 0x140937570), UILevelUp as the level rises (0x14078e270), the
  notices of a lock (above) and the player's eating and drinking (ENIT). Not asked, for the menu
  or game they belong to is not modelled: the lockpicking menu (UILockpicking*), the stats menu's
  constellation (UISkillsFocus, Forward, Backward, Stop, Glow, PerkSelect2D), crafting
  (UISmithing*, UIAlchemy*, UIEnchanting*), UISelectOn and Off, UIShoutLearn*, UISpellLearned (a
  spell tome learned), UIQuest* and the discovery music, UISneakAttack, ITMPoisonUse, ITMTorchHeldEquip.
  `uisoundtests.zap` checks each path's queue, that every name resolves to a descriptor with files
  and that a play is 2D in the offline mixer's log; `Screen` itself needs the GPU, so its calls are
  tested through the functions it calls.
- Sounds: `engine/audio/xwma` decodes xWMA (WMA version 2, as ffmpeg does to the sample) and
  the engine's streams play it; `skyrim/fuz.zap` the voices; `skyrim/esm/sound.zap` the sound
  descriptors, markers, acoustic spaces and music, resolved to the archives' keys, with their
  categories, output models, materials, impacts and footsteps (`esm/impact.zap`). `game/sound/`
  plays the inn as the game does through the engine's audio: the music system (types by
  priority, tracks at random), the acoustic space's and the fires' loops, footsteps from the
  clips' text keys on the floor's Havok material, the clutter's knocks, activation and menu
  sounds, the hellos with their lip tracks (`soundinfo.zap --scene`, offline mix to a WAV).
  Approximated: the attenuation curve's points read as linear volume between min and max, ducking
  pauses instead of lowering, the knock threshold; the lip track is not drawn (no morphs on the
  GPU heads yet).
- `papyrus/`: the game's scripts. PEX files (`Skyrim - Misc.bsa`, scripts/) read whole, the VMAD
  field that binds them to records, and a Papyrus VM: objects bound to forms, threads, latent
  waits and registered updates stepped per frame, the natives over the game's model (Debug, Math,
  Utility, updates, enable/disable, quest stages, globals, references' inventories, links, owners,
  locks and placement, actors' equipment and values; the rest stubs that log the call), the
  events that reach the scripts from the world (activation, triggers, `activation.zap`).
- `game/sim/`, the game's model headless (the `GameWorld` the scripts act on, the menus and the
  scene will read): the items from their records (`items.zap`), inventories with the game's
  instance data and equipping (`inventory.zap`, `equip.zap`), actor values (`actors.zap`),
  containers and leveled lists (`containers.zap`, `esm/leveled.zap`'s dice), ownership, theft
  and barter (`economy.zap`), activation by kind with doors, furniture markers and harvests
  (`activate.zap`, `furniture.zap`), the cell's world built from the plugin (`build.zap`).
- `save/`, saving and loading in the inn (`savetests.zap`), headless: `snapshot.zap` reads what play
  changes from the live game (the world's forms, actors, inventories, quests, globals, clock,
  furniture, books, crimes; what the dialogue remembers; the Papyrus VM's objects, arrays, threads
  by script name, updates; each resident's package and body; the player's body) and `restore.zap`
  writes it back (the animators start again, a resident in a marker's loop is run into it).
  `entries.zap` cuts the keyed part into entries, each a part of a change form (REFR, ACHR, QUST,
  INFO, BOOK, FURN, FACT, UESP's types; their parts are ours and documented there), and keeps only
  those that differ from the game as it began (`Session.base`); the rest (globals, Papyrus, the
  loose world, the dialogue's relations, the player's body) are global data blocks (types 1 and 3
  as UESP lays them out, 1001 and 2001 to 2003 ours). `ess.zap` is the file after UESP's "Skyrim
  Mod:Save File Format" for SE (form version 78, header, RGBA screenshot, the body as one LZ4 block
  from `std/lz4`'s `encodeBlock`, the file location table, the three global tables, change forms,
  the form id array); its header, tables and location table are checked against a real save of the
  player's when there is one (the header and the 100 bytes of the table are written back to the
  same bytes). `files.zap` names and lists the saves in `Documents/My Games/Skyrim Zap/Saves`
  (beside the game's folder, never in it): "Save3_...", "Quicksave0_..." (replaced each time),
  "Autosave1_...". `session.zap` saves (refused in combat, as the game does, unless it is given the
  scene's fight: the `...In` functions take the fights, the player's animator and the cell's physics
  world; the plain `saveGame`, `loadGame`, `quickSave` and `quickLoad` leave the scene out) and loads.
  `arena.zap` holds the scene's part: the fight in progress (each Fighter as a change form part of
  its actor, the fight's clock, dice and lines and the player's draw and swing as block 2004), the
  dead's ragdolls (an ACHR part laying the ragdoll again from its fall pose, then each body's
  transform and velocity), the Havok clutter (a REFR part per body, `havokRefs` plus its place in the
  world, so only the moved ones are written) and the physics' warm start (contacts, joint impulses,
  block 2005); every resident's walker (graph states, clips' times) is in its SavedResident, the
  player's in block 2006. Play time is `GameWorld.playSeconds`, real seconds ticked by the VM.
  Not saved: the sounds playing.
- `interface/`: the Scaleform menus played by the engine's SWF player and its ActionScript 2
  machine (`engine/swf/avm1`, after Ruffle): imported libraries (the inventory components)
  merged in, the fonts of `fontconfig.txt`, the texts of `translate_english.txt`, the safe zone
  of fSafeZoneX/Y (15, the executable's defaults). The game stretches its menus to the window
  (`exactFit`, the tween menu whole), as `assets/reference/` shows. The game drives a menu by
  Invoke and by GameDelegate's callbacks; what a menu asks of the game is kept in the machine's
  `external`, and a call the game answers at once (the item card) is answered from the movie
  (`Machine.answers`). Filled from `game/sim`: the inventory and container menus
  (`itemmenu.zap`, `items.zap`: the categories by the game settings' names with their filter
  bits, the rows with count, equip icon, best in class and theft, the item card, the bottom bar;
  equipping, dropping, taking with the theft recorded), the message box, the wait menu, the
  tween menu and the journal on its system page (`panels.zap`); the HUD (`hud.zap`) with the
  player's meters (full ones faded), the compass from the cell's north marker and the activate
  prompt (`texts.zap`'s targetText, `game/sim/pick.zap`'s rough pick). `screen.zap` is what
  main.zap shows: the HUD each frame and a menu by the game's keys (I, Q, Tab, Esc, T, E).
  The HUD's notices (`hud.zap` showNotice: GameDelegate's ShowMessage, as
  SendHUDMessage::ShowHUDMessage 0x140991a30 sends them): the world's notifications as they come
  (Debug.Notification, the game's own). Delphine's secret door (MQDelphineSecretDoor, the inn's
  only lock, 255: key only) says sImpossibleLock without MQDelphineSecretDoorKey and "Unlocked with
  <key>" (sOpenWithKey) with it, then opens (TESObjectDOOR::Activate 0x140283210,
  LockpickingMenu::OpenMenu 0x14094dc60), each with its sound (ShowHUDMessage's second argument:
  DRSLocked, UILockpickingUnlock), the same text not shown nor sounded again for 5 s (its table
  of the last eight, `game/sim/uisounds.zap` showNotice). A lock that is picked, with no lockpick
  in the pack (nor the skeleton key), says sOutOfLockpicks with DRSLocked. Missing: the
  lockpicking menu and its sounds (UILockpicking*, 0x14094f000..0x1409502f0), which no lock of
  the inn opens, and the container's own unlock notice (TESObjectCONT::Activate 0x140281c10).
  The book menu (`book.zap`: book.swf, opened by activating a book): the text (DESC) set through
  GameDelegate's SetBookText, the movie paginating it on an interval with the GFx TextField
  extensions getLineOffset, getCharBoundaries and getLineIndexAtPoint (engine/swf/avm1), turned
  by BookMenu.BookMenuInstance.TurnPage (2 a book, 1 a note) on controlmap.txt's Book context
  (PrevPage, NextPage) and the mouse buttons, closed by Menu Mode's Cancel, the book taken by
  Accept (BookMenu::ProcessMessage 0x1409063d0), which plays ITMNotePageTurn when a note's page
  turned (a book's turn and the open and close are its animated model's, not a UI sound). Missing:
  the game lays the pages on its animated book model (render targets on Book01.nif, the open and
  turn animations); here the pages are drawn flat side by side.
  The magic menu (`spellmenu.zap`: magicmenu.swf, Tab then Left then Enter) lists the spells and
  powers the player knows under the schools (the game settings sAlteration...), the card says the
  effects, the cost (castTime 0 makes it "per sec") and the level, the school's skill rides the
  card to the bottom bar; Enter puts the spell in the right hand, the right button in the left, F
  marks a favorite; the favorites menu (favoritesmenu.swf, Q) lists the favorite items and
  spells and equips the chosen. The magic menu also lists Active Effects (the effects of the
  abilities the player knows, `sim.activeEffects`: a Nord's Resist Frost, then the timed effects of
  a potion or a drink with the seconds left) and Shouts (listed empty: shouts are not in the model); the keys 1 to 8 are the
  hotkeys of controlmap.txt (`sim/hotkeys.zap`): in the favorites menu one assigns the selected
  favorite to its slot (again takes it off, the list shows "1. Name"), in the game it wears the item
  or puts the spell in the right hand and takes it off when it is there. The journal's system page
  has the executable's version (SkyrimSE.exe's, a constant), the quit list (RequestIsOnPC), the help
  list and texts (`journal.zap`: the MESG records whose editor id starts with Help, the long PC text
  of each title; the game's own subset and order are not read from anywhere, so this is a guess) and
  the key art of "[Activate]"-style tokens (`controls.zap`: controlmap.txt's keys, answered to
  GetButtonFromUserEvent); what the game writes into a call's arguments the machine answers at once (`Machine.replies`),
  because the page's code goes on from the call. Text fields' drop shadows (PlaceObject3's filters:
  black, 2 pixels at 45 degrees, blur 2) are drawn as offset copies of the text (`drawfilter.zap`),
  not as the player's blur. The page's Save, Load, Quicksave and Quit are the game's (`saves.zap`: the page's lists filled from
  the saves folder, its calls turned into requests main.zap carries out; F5 and F9 too). Missing: its settings values (the executable's compiled defaults
  are not readable) and its controls list (RequestInputMappings, from controlmap.txt), the scroll
  of a text taller than its field (it is clipped; `scroll` and `maxscroll` are fixed), the scene's
  blur under menus, Scaleform's edge anti-aliasing of shapes and glyphs, glows and blurs of
  placed objects, MovieClip.createTextField. Fields wrap their words (wordWrap) and space their
  letters (letterSpacing, which the subtitle's width bears out: 784 pixels laid out, 782 inked in the game's capture); the
  dialogue's topics show smaller glyphs in the game than the 24 pixels their field gives at the
  list's 0.8, for a reason not found yet.
- `game/dialogue/`, the dialogue as the game evaluates it, headless: the topics (DIAL), branches
  (DLBR), responses (INFO) and quests (QUST, with stages and alias fills) read once
  (`records.zap`, `quests.zap`), the condition functions over the world and the VM
  (`conditions.zap`, `checks.zap`; the names of all 402 in `esm/functions.zap`), the hello, the
  menu's topics with their prompts, the response chosen (say once, reset hours, random) and what
  saying it does: the TIF fragments run in the VM, the quests' stage fragments after them, gold,
  owners and stages read back (`choose.zap`, `say.zap`); each line's voice file
  (`voice.zap`: `sound/voice/skyrim.esm/<voice type>/<quest>_<topic>_<info>_<n>.fuz`, the quest and
  topic sharing 25 letters) and its lip track (`skyrim/lip.zap`: a format with no public
  description, read from the files: zero runs packed, then 16 phonemes and 17 modifiers a frame).
  The rent is Delphine's at a new game (Orgnar's rank in JobRentRoomFaction is -1 until she
  leaves): her fragment makes the bed the player's and takes 10 gold; the room's door has no lock.
- Talking in the scene (`game/talk.zap`, `interface/dialoguefeed.zap`, `talktests.zap`): E on an
  actor opens a conversation and dialoguemenu.swf fed through its GameDelegate callbacks
  (SetSpeakerName, ShowDialogueText and NotifyVoiceReady per line, HideDialogueText,
  PopulateDialogueList and ShowDialogueList, StartHideMenu; it answers TopicClicked, SkipText,
  CloseMenu, FadeDone; the dialogue's GameDelegate.call puts its call's id before the arguments). Each line lasts
  its FUZ's decoded length; `game/speak.zap` is the one hook the sound branch fills (voice, lip
  sync). The menu lists the topics by their priority then their quest's, lowest first, and one
  rumors topic at a time (the highest quest's), as the game's captures of Orgnar show
  (`assets/reference/menus/dialogue-*.png`: before, greeting, response, topics after; third person
  at -1080, 79 yaw 270, subtitles on). The speaker holds its package (one at a marker stays at it,
  one standing turns to the player over fDialogueRotationSecs); the third person camera does not
  move or zoom when the speaker is already in view (the before and greeting captures agree to the
  pixel); turning it to a speaker further aside than fDialogueSoftStopAngle3P is the settings'
  reading, not measured. The ini's settings (`skyrim/ini.zap`) and the dialogue's executable
  defaults were read from SkyrimSE.exe's static settings (value before the name's pointer).
- `game/combat/`, the combat as the game computes it, headless: the formulas from the GMSTs by
  name (the plugin's, else the executable's defaults listed in `sim/settings.zap` with their source):
  weapon damage by skill, power, sneak and bash, armor and block (`damage.zap`); the actors'
  derived values (auto-calculated stats by level and class, race boosts and regeneration, in
  `sim/actors.zap`); the attacks' timings from the clips and the behavior graph's HitFrame triggers
  (`game/fightclips.zap` measures them on the graph; `clips.zap` holds the types); the AI as a state machine from AIDT and CSTY (`ai.zap`),
  swings, hits, staggers, bleedout and death (`strike.zap`), the ties (RELA, faction reactions) and
  the crimes with their witnesses and bounty (`crime.zap`), a seeded fight in fixed steps
  (`fight.zap`, `scene.zap`). The AI's weights are the executable's (`chances.zap`, SkyrimSE.exe
  v1.7.104, found without an Address Library by the settings' static objects: the value sits before
  the name pointer, and the code referencing it, 0x1408f1xxx-0x1408f3xxx, lerps `fCombat*Min/Max` by a
  CSTY multiplier: attack 0x1408f2720 (offensive, grouped by 0x1408f1ad0), power variants 0x1408f2830,
  block 0x1408f2960, bash 0x1408f2b20/0x1408f2b80/0x1408f2be0, circle 0x1408f1ec0/0x1408f1ef0, fall
  back 0x1408f1e00/e30/e90, block time 0x1408f2ae0; field offsets after CommonLibSSE-NG's
  TESCombatStyle). The tree is built in code by one function per context, naming its nodes: Block
  Context 0x1408809c0 (Block Selector: Bash, Block, Offensive Bash, Block Attack, Block Idle),
  Melee Context 0x1408b9ba0 (Attack Selector: Attack, Special Attack, Attack Idle), Close Movement
  Context 0x140885fa0 (Movement Selector: In Range = Fallback/Circle Selector over Backoff, Circle,
  Fallback; Out of Position = Surround, Reposition; Out of Range = Circle Distant, Advance, Fallback
  To Ranged); the Idle nodes wait 0.25 s. Read from the code, not from the selector classes: a
  selector picks by weighted random (the class names RandomNode / ValueNode / WeightedRandomChild
  Selector), and an Idle child's weight 1 is an assumption. The power attack's 0.2 against the plain
  attack's 1 is the Nord race's ATKD attackChance (attackPowerStartInPlace). Not modelled: special
  attacks, block attack, backoff, the target selector's scoring (only its 1 s / 3 s timers), the
  flight decision (confidence thresholds stay approximate), CombatState's random confidence
  modifier (fCombatConfidenceModifierMin/Max), cover, flanking, ranged and magic nodes.
- `game/sim/spells.zap`, `game/combat/magic.zap`, `game/spellart.zap`, `game/spellshow.zap`: the
  player's magic as the game has it. SPEL, MGEF and PROJ are read (the effects whose conditions do
  not hold at a new game, a perk's, are left out); the player knows what its record and its race
  list (SPLO): Flames, Healing, the Nord's battle cry, and abilities no hand casts. A spell goes in
  a hand (EitherHand by default the right), taking off what held it; a weapon in a hand takes the
  spell out. Casting is the fight's: a spell let go costs its record's magicka (the Creation Kit's
  stored cost, which is the effects' base cost times (magnitude x duration)^1.1 floored: Flames
  14, Healing 12) and gives its effects at once; a held one (Flames, Healing) costs that a second
  and gives its magnitude a second (8 fire damage, 10 health) for as long as the button is down
  and the magicka lasts. Skill does not enter the cost (the GMSTs fMagicCasterPCSkillCostBase
  and the like are Oblivion's and unused; only perks lower a cost, perks.zap). An aimed effect reaches the
  nearest living fighter in front within the projectile's range (Flames 768) and width, its
  damage lowered by the fire resistance and the magic resistance, through `hurt`, so a crime, a
  death or a bleedout follow as for a sword; the effects of other archetypes cost their magicka
  and say in the fight's lines that the model does not play them. The scene shows it: the cast
  pose is the game's mrh_/mlh_ clips (equip, readyloop, aimedconcentration, selfconcentration),
  the stream the flames projectile's model (FireSprayFX01.nif: its fire cylinder, an effect
  shader mesh, stretched to the reach) and the hand's light the effect's (MagicLightFireInHand)
  at an approximate hand place (feet, facing; the arm's bones are not followed), both prepared
  with the cell as `SpellArt` (the model's triangles in its own space, drawn each frame by
  `CellScene.showArt`). Not drawn: the casting art's billboard glow and every particle system of
  the spell models (their birth rates are blends of the controller sequences, which the NIF
  loader does not play), the impact and hit effects, the light's shadow. Not modeled: summons,
  wards, invisibility and the rest of the archetypes, dual casting, charge time, perks, the hands' magic for the NPCs.
- `game/stealth/`, `game/sim/stealth.zap`, `game/seen.zap`, `stealthtests.zap`,
  `reference/exe/stealth.md`: sneaking, detection and pickpocketing as SkyrimSE.exe does them.
  Ctrl (the map's Sneak) toggles `GameWorld.stealth.sneaking`; the player then moves at the sneak
  clips' speeds (47 walking, 133 running) and the graph gets SneakStart/SneakStop. Every present
  resident reads the player every quarter second (a reading is kept 1 s): `detection.zap` is
  `Actor::CalculateDetection` and its sum (0x14041cd90: noise from the action and the steps, the
  light on him in the watcher's view cone and line of sight, the Sneak skills, less
  fSneakBaseValue), `sight.zap` the eye, the body points the rays go to and the light level (the
  cell's lamps from the prepared light list, `game.detectionLighting`), `watch.zap` the world's
  actors in it, with the rays cast on the cell's physics (`game/seen.zap`). Crimes are witnessed
  only by actors that have detected the player (read again at the crime), a sneaking player's hit
  on one that has not is a sneak attack (`fCombatSneak*Mult`), his swings make noise (Loud, fists
  Normal) for fActorAlertSoundTimer s. The HUD's eye (`StealthMeterInstance`: FadeIn/FadeOut, the
  `SneakAnimInstance` frame, `$HIDDEN`/`$DETECTED`) shows 100 when anyone detects him. E on a living
  actor while sneaking (the prompt reads Pickpocket) opens `containermenu.swf` in its pickpocket
  mode (`bNPCMode`): the actor's loose items, each card with `pickpocketChance` as the exe computes
  it; taking rolls against it, a failure making the victim notice (level 100), adding a pickpocket
  crime (the faction's CRVA gold), a notice and closing the menu. The state (sneaking, the
  detections, the noise, the roll's sequence) is in the save's misc block. Pickpocket perks are
  `game/sim/perks.zap`'s. Not modelled: the perks of detection, combat stealth points, race sizes, a weapon's own sound
  level, and the sneak animation when the prepared cast lacks the sneak clips (the walk's plays).
  Detection events (`game/stealth/hearing.zap`, `game/combat/hearing.zap`, the second half of
  `CalculateDetection`): a spell cast stores the caster's event (its place, the effect's casting
  sound level, 0x1405cdf50; the player's also sets his action noise), a papyrus
  `CreateDetectionEvent` one at the reference (0x140a451f0), kept 5 s
  (`fDetectionEventExpireTime`); a watcher whose sight gave nothing above 0 hears the player's
  event within 1536 units (3072 very loud) and his projectiles in the air within 1024, when it
  fights, he fights or it would attack him on sight, never an ally or friend: level 0 with the
  place of the sound, which is no detection, so no crime is witnessed and no one joins or flees
  for it; an idle fighter looks up (`Alert`). The punch of fighttests makes no event (the exe has
  none for a blow), so Embry, far off and facing away, stays idle, and the test says why. Not
  modelled: the explosions', impacts' and summons' events (no projectiles in flight or
  explosions), a weapon's sound level, where the exe sends a heard actor (its search package),
  the reaction of the hostile among the heard, and the events of NPC casters heard by NPCs.
- `reference/exe/`: what REA (github.com/morluto/rea over Ghidra 12.1.4) read out of the install's
  `SkyrimSE.exe` 1.7.104.0, one small file a theme with the addresses as evidence: `README.md`
  (identity, how to open it again), the 5,250 settings compiled into it with their defaults
  (`gmst-*.md`, `ini-*.md`: every GMST the plugin may leave out and every ini key), the RTTI classes
  of the inn's systems with their vtables (`classes-*.md`, 1,197 classes), the menus as the game
  drives them (`menus.md`: each menu's GameDelegate callbacks with their handlers, what
  `ProcessMessage` invokes per message and user event, the `UserEvents` and `InterfaceStrings`
  tables by offset, the item list and item card members), the dialogue manager (`dialogue.md`:
  `MenuTopicManager`'s layout and the topic/response walk), the stagger and confidence formulas
  (`combat.md`), the Havok collision filter's layer and biped-part matrices (`havok.md`) and the
  behavior graph's node, variable and event names the game uses (`animation.md`).
- `game/sim/consume.zap`, `consumetests.zap`, `reference/exe/consume.md`: eating and drinking and
  the effects that last, as SkyrimSE.exe does them. Using an ALCH item (the inventory's use, a
  favorite or a hotkey: `sim.consume`) refuses a poison (it is put on a weapon), takes one of the
  item and starts each effect on the actor (`TimedEffect`, kept in `ActorState.effects`, so the
  saves carry it). A value modifier (archetype 0, and 34 the peak one: of equal effects only the
  strongest holds) works by the MGEF's Recover flag: a fortify adds its magnitude to the value's
  modifier for its duration and gives it back; the others change the damage taken: no duration,
  once at the start; a duration, magnitude x dt on every update, so magnitude x duration in all
  (Ale: 15 stamina at once and 30 less stamina rate for 30 s; a Red Apple 2 health). A lowering
  never takes more than the value has, harm is lowered by the resistances (one `resistedShare` for
  spells and potions), the magnitude tapers by the MGEF's taper. `tickEffects` runs in the Papyrus
  clock (`vm.tick`) and in each step of a fight; a dead actor loses its effects. The item's
  `useSound` (ENIT) and `isFood` (food flag without poison) come out for the menus and sound. The
  actor values table now runs to 163 (the Fortify effects change the modifiers and rate
  multipliers above 95). The player's use sound is queued (`playDescriptorForPlayer`) and played
  where the listener is; an actor's (Orgnar's) is not played, and the exe's site that plays it is
  not found. Not done: an ingredient eaten (first effect only); a poison applied to a weapon (the
  case is refused); the effects of other archetypes (absorb, cure, invisibility...); the Alchemy skill and perks that scale a potion
  when it is brewed (a perk's entry points 0x1d 0x1e 0x29 0x2a do change one drunk); the AI's choice to eat or drink (NPCs consume through
  the same call, no package calls it); the quest-item refusal ("You can not eat quest items");
  Survival mode hunger; the exe's rule at the end of a Fortify Health (read, its effect at low
  health unverified); effects carried between the menus' world and the fight's copy of the actors
  (the fight gets the values back, not the effects); addiction (ENIT's addiction fields).
- `game/sim/skills.zap`, `game/combat/practice.zap`, `interface/statsmenu.zap`, `skilltests.zap`, `game/sim/perks.zap`, `game/sim/perktree.zap`, `skyrim/esm/perk.zap`, `perktests.zap`,
  `reference/exe/skills.md`: skills advancing by use, the character's levels and the stats menu, as
  SkyrimSE.exe does them (every address is in the reference). A skill gains the amount of its use
  times its AVIF's AVSK use mult (plus the use offset) and rises at pow(level, fSkillUseCurve) x
  improve mult + improve offset, the character gaining the new skill level in experience; the
  character rises at level x fXPLevelUpMult + fXPLevelUpBase, by the level-up menu's choice (+10
  to health, magicka or stamina, stamina also fLevelUpCarryWeightMod of carry weight, the three
  restored in full). The uses: a landed swing gives the weapon's base damage to its skill (fists
  nothing), a bash 5 (shield) or 1 to Block, a blow that hurts the player the damage his block took
  to Block or, unblocked, its damage to Light or Heavy Armor by a roll over what he wears (the body
  piece counts twice), a spell its cost times its costliest effect's usage (once let go, a second's
  worth every second held), Sneak 0.5 a second in view of someone not sure of him and 2.5 when he
  slips out of sight, Pickpocket the stolen value to fPickpocketSkillUsesCurve, Speech the value
  of what is bought or sold, a skill book `incrementSkill` (the share earned kept). The state
  (`GameWorld.progress`: the experience, each skill's, the perk points) is in the save's misc block
  and the header's curExp and levelUpExp. Tab's Up opens the level-up menu when the character has the
  experience (its addHealth, addMagicka and addStamina calls raise the attribute, `answerLevelUp`),
  else the stats menu: `StatsMenu.SkillStatsA` (five values for each of the 18 skills), then
  UpdateSkillList and SetPlayerInfo through GameDelegate; the tween menu gets the level-up flag and
  the progress. Perks (`reference/exe/perks.md`): `skyrim/esm/perk.zap` reads PERK (conditions,
  ranks, the quest, ability and entry-point entries with their function and data) and the nodes of
  a skill's tree (AVIF); `game/sim/perks.zap` keeps what each actor holds (`ActorState.perks`, the
  rank; the perks of the abilities it knows through their magic effect's perk, Rested's), the
  Papyrus `Actor.AddPerk`, `RemovePerk` and `HasPerk`, and `entryPointValue`, the exe's
  `HandleEntryPoint` for the entry points that change a number (the entries of the owner's perks
  at their rank, by priority then rank, each asked its conditions at its parameters, then its
  function: set, add, multiply, add range, the actor-value ones, absolute); it is asked where the
  exe asks it: a skill's use amount (0x16, Well Rested's 1.1), a hit's damage (0x1c, 0, 0x23,
  0x24, the sneak multiplier 0x12; Armsman), the barter factors (8, 0x3c; Haggling), the
  pickpocket chance (0x38; Cutpurse), a spell's cost (0x26; the schools' Novice perks through
  `SpellHasCastingPerk`) and an ingested effect's magnitude and duration (0x1d, 0x1e, 0x29, 0x2a).
  `game/sim/perktree.zap` is the stats menu's choice (`interface/statsmenu.zap` chooseSkillPerk):
  the node's perk chain, the first perk not held, the record's conditions, a perk point. A spell
  or perk a script gives an actor before the world has its record waits in `GameWorld.unlearned`
  until `learnPending` (the main loop, and after a save is loaded) reads it. The perks are in the
  save with the actors. Perk conditions answer the functions in `perkFunctionValue` (actor values,
  HasPerk, HasKeyword, WornHasKeyword, level, race, faction, equipped, spells, sneaking...); the
  others give 0. Not modelled: the entry points the inn does not hit (critical hits, armor and
  resistance, detection 0x2f 0x30 0x39 0xf whose formulas take no world, lockpicking, smithing,
  enchanting, alchemy at the table), the leveled-list, spell and text functions, the
  constellations' 3D scene and a perk node's description card, the legendary
  skill reset, a
  skill's description card (SetDescriptionCard), the "Level up available." HUD reminder
  (iLevelUpReminder), lockpicking, smithing, enchanting and alchemy experience (the sites are
  listed in the reference), the skill order of the constellations (the AVIF perk tree's, taken
  as the actor value order), a spell's cost taken from its record where the exe takes its costliest
  effect's (the same for one effect), the unarmed hit's Block experience when a weapon bashes, the
  rare event the game fires on a skill increase (recorded as a line of `GameWorld.events`).
- Tools: `list.zap`, `inspect.zap`, `nifinfo.zap` (`--shaders`: every shader property's fields,
  SLSF1 and SLSF2 by name and raw), `esminfo.zap` (records across the game's load order by
  `--form`, `--edid` or `--field TAG=value`, with every plugin that overrides them), `dumptex.zap`, `hkxinfo.zap`, `actorinfo.zap`,
  `npcinfo.zap` (the inn's NPCs and their packages at an hour, one NPC drawn),
  `physinfo.zap`, `soundinfo.zap` (a sound's format and decoding, `--inn` the inn's sounds),
  `pexinfo.zap` (a script's listing, the inn's bindings, a function run), `iteminfo.zap` (the
  inn's items and containers, an activation, the player's start), `menuinfo.zap` (a menu's
  movie, played, fed from the inn's world: `--feed magic`, `--feed favorites`), `magicinfo.zap` (a
  record's fields, the spells with their effects, the game settings, the translations), `combatinfo.zap` (an actor's combat values, a fight,
  the player against Orgnar), `dialogueinfo.zap` (each actor's hello and topics with their voice
  files, a conversation played, a lip track); `compare.zap` against the reference captures, poses
  and menus (`reference/`). SkyrimSE.exe's functions by address or name: `decompinfo`
  (projects/recomp/tools).

### Terrain (milestone 14)

The land of the exterior cells, read from Skyrim.esm and its overlays and drawn as the executable's
landscape (TESObjectLAND::LoadVertices 0x1402ad5c0 and its helpers, read with REA; CommonLibSSE-NG's
LoadedLandData; the landscape permutation of Community Shaders' Lighting.hlsl).

- `skyrim/esm/land.zap`: `landOf(plugin, world, x, y)` (LAND: VHGT heights in whole units times 8,
  VNML, VCLR, BTXT and the ATXT/VTXT layers with their opacities; the last overlay that has the cell
  wins), `landTexture` (LTEX with its TXST's diffuse and normal paths, the grass list),
  `worldLand` (WRLD DNAM), `placedOfKind` (what a cell places, to check the land against).
  `terraininfo.zap --cell 5,-11` prints a land, `--ground x,y` the heights around a position,
  `--find riverwood` the cells of a location (Riverwood02 is Tamriel's (5, -11); the town spans
  (4..6, -12..-10)).
- `engine/physics/heightfield.zap`: the grid of heights, its checkerboard triangles (the game's
  index order), `gridHeight`, and `addHeightfield`, a static surface of the Havok world the
  character walks on (the game builds its land collision from the same triangles). `engine/terrain/`:
  the patch (`TerrainPatch`: heights, normals, colors, up to six weighted tiles) made into
  vertices, and the pixel stage's tile shares (each weight over their sum, under 0.01 dropped).
- `game/terrain.zap`, the way in for the cell agent: `terrainOf(install, plugin, world, x0, y0, x1,
  y1)` gives a `Terrain` (y-up vertices and indices of the cells' four quadrants of 17 x 17, their
  textures laid in a body, each cell's heights z up); `sc.showTerrain(t)` adds it to a CellScene
  (`world/terrain.zap`; drawn with the opaque parts and into the normal buffer, shaded by
  `world/shaders/terrain.gpu.zap` with the cell's lights and fog), `w.collideTerrain(t)` to the
  physics world, `t.heightAt(x, y)` the ground. Exactness from the executable: the quadrants'
  tiles are the base then the layers whose mean opacity reaches 0.001 (at most five), weighted by the
  opacity as a byte with the base taking what the layers leave; the textures repeat 0.75 times
  from one vertex to the next (fLandTextureTilingMult 3 / 4); a quadrant with no BTXT or a layer
  of texture 0 takes Landscape\Dirt02.dds.
- Checked: `terraintests.zap` (heights, edge continuity with the neighbours, 961 of 961 normals
  within 18 degrees of the heights' slope, the Riverwood trees standing within 25 units of the
  ground, the character walking on it); `terrainshot.zap --shot x.png` is a header shot of
  `zap test --only shots` on both backends.
- Left: the border geometry along each cell's edge (BSTriShape at LoadedLandData+0x4880, built in
  0x1402ae650), the landscape's shadows (sun shadow maps), snow, the parallax and the vertex
  stage's distance fade (LandBlendWeights2.w), the physics material per texture (all 0.5 friction), cells
  with no LAND (the world's default land height is read, not drawn), the vertex normals and
  tangents of the executable's tangent generation (ours: u along +x), and xEdit values
  (it has no CLI; the heights are checked against the trees and the normals instead).

### Sky, weather and time of day (milestone 14)

The exterior's sky from SkyrimSE.exe 1.7.104 (Sky::UpdateColors 0x140412df0, FillColorBlend
0x140416760, SetColor 0x140414cf0, the DALC blend 0x140416490, fog 0x140413a30, Sun::Update
0x14041bd90, Stars::Update 0x14041a4b0, Clouds::Update 0x14040c220, UpdateWeather 0x140412810, the
weighted pick 0x14030a3c0), as plain numbers in `world/sky.zap`.

- Records: `skyrim/esm/weather.zap` reads WTHR (17 colors by 4 times, fog, DATA, cloud layers with
  speed, color and alpha, IMSP, the four DALC), CLMT (TNAM hours and volatility, WLST, sun and glare
  textures), REGN (RDWT with chances and globals, RDAT priority, RPLD areas: `weatherRegionsAt`;
  Riverwood is in WeatherPineForest, 7 weathers). `weatherinfo.zap` prints them and the sky at an hour.
- Exact against the executable in `x64diffs.zap`, bit for bit: FillColorBlend's times and weights,
  SetColor with its flash and clamp, the ambient cube blend. Read from the code and unit tested
  (`skytests.zap`) but not diffed: fog (day share ramp), the sun's windows (an hour either side of the
  middle of sunrise and sunset), track and arc (light toward (400 s, 25, 100), disc toward
  (400 s, 25, 400 (1 - |s|))), stars' alpha, cloud scroll (byte * 0.2 / 254 - 0.1, times 0.1 dt),
  weather life (1 + 22 (255 - volatility) / 255 hours), transition (0.01 to 0.25 h by DATA's byte),
  the region pick and the keep-on-entering roll, the image space as a weighted sum.
- Drawing: `world/skydraw.zap` and `shaders/sky.gpu.zap` draw the game's own Atmosphere.nif (vertex
  colors weigh horizon, lower, upper), Stars.nif, Clouds.nif (shape k is layer k, scrolled) and the
  sun and glare quads, at the far plane behind everything. `game/sky.zap`: `SkyClock` (region's
  weathers, `advance`, `skyAt`, `imageSpaceAt`), `newSkyDrawing`. `world/skyscene.zap`: `sc.showSky`,
  `sc.setSky(sky, space, days)` sets ambient, sun, fog, emittance and image space, so the terrain
  takes them with no change of its own. `skyshot.zap` draws morning, noon, night and a transition
  over Riverwood (shots, vulkan); BSSkyShaderProperty is now read (nif `SkyBlock`).
- The sun disc: Sun::Init 0x14041b290 builds two squares of half-width fSunBaseSize 425 and
  fSunGlareSize 600 on billboards, scale 1; Sun::Update puts them at (400 s, 25, 400 (1 - |s|)), so
  the disc stands 400 units out at the horizon and noon and 283 half way (it grows as the sun
  climbs). Nothing above scales them (a root's scale would carry the place with it and leave the
  angles), so the old 0.44 guess is gone: the texture's disc (4 percent of the square) is 5 to 7
  degrees across. The sun is added like the glare (assumed: the sun mesh has no alpha property of its own
  in Init, its sky shader property's blend is not read).

- Left: lightning scheduling, the sun's occlusion fade of the glare (0.25 to 1 by terrain
  queries), the cloud mesh's blending modes and the layers' color swap when the current has none
  (0x14040c220), the accelerated transition flag, fog clamped to the far plane, the stars' real
  rotation by days passed, the moons' stencil mask.

### Moons (`world/moons.zap`)

Moon::Update 0x14040e0f0, Moon::Init 0x14040d930, the phase pick 0x14040d370. A moon's angle starts at
90 and turns speed * 60 degrees an hour (Masser 0.25, Secunda 0.3: 15 and 18 degrees an hour, so
Masser repeats every day and Secunda every 20 hours; the game's clock for it is the session's, here
`--days` of skyshot). Its quad (iMasserSize 94, iSecundaSize 40 units) stands 512 out on the moons'
root, turned by -angle about x and zOffset (35, 50) about z; it fades in between angle fadeEnd and
fadeStart (45 to 55; 40 to 55), holds, and fades out at 180 less those; the shadow mask has its own
fade (end to end less the early fade) held under the stars' alpha. The phase is
(day mod (8 * phase length)) / phase length of CLMT's TNAM byte (3 days here; bits 7 and 6 say
which moons the climate has), the textures `Sky\<moon>_<phase>.dds` (full, three_wan, half_wan,
one_wan, new, one_wax, half_wax, three_wax). Drawn added in the moon glare color after the stars.
Checked in `x64diffs.zap` against Moon::Update run in the emulator: the angle, the hour kept and
both alphas bit for bit, the root's rotation (the quad's right, center and up) to the executable's
own sincos rounding. Not drawn: the MOONMASK shadow quad (a stencil that keeps the stars and clouds
off the moon: Sky.hlsl's MOONMASK, MoonShadow.dds), the moons' clouds-edge scatter.

### Precipitation (`world/precipitation.zap`, `shaders/precipitation.gpu.zap`)

Precipitation::Update 0x14040eed0, the emitter 0x14029f4e0, its per-frame step 0x1402a0440, the wind
0x140413f10, drawn as Community Shaders' Particle.hlsl (ENVCUBE: RAIN and SNOW) does. The weather's
MNAM is an SPGD (`esm.precipitationOf`: fall speed 675 for rain, 100 for snow, quad size, the 4 x 2
or 4 x 4 cells of the texture, box size 1300 / 740 / 1400, density 1 to 3, spin). A cube of 10 x 10 x
10 particles (one a jittered cell, the border cells wrapped) about the eye, each particle's place plus
the offset the fall and wind have carried wrapped to the box; a rain streak is the head and the tail
(head less velocity / 15) blended by the corner's y (+-2: the streak runs a velocity either side),
its corners added to the clip position (0.35 clip units wide); a snow flake is turned by the spin
(rotationVelocity degrees a second) and its offsets scaled by the aspect. How many show: the current
weather's amount is (share - begin) * density / (1 - begin) with begin the DATA byte / 255 (153: rain
starts at 60 percent of the weather's coming in), the last weather's (1 - share / (end + 0.001)) *
density; each emitter shows amount * 1,000 particles (the pool holds three cubes, the game's use of
an amount over 1 is not read). The wind is fPrecipWindMult 500 times the weather's wind speed byte / 255
(blended by the share) toward its direction byte (360 / 256 degrees; the game strays up to the range
either side, the middle is used). Vanilla rain is faint by its data (the texture's alpha is at most
0.37 and mostly 0), so the shot shows thin streaks; the exe applies no wetness to the world (no
setting or shader of it: only the snow's own lighting), nothing here either. Not ported: the
precipitation occlusion map (rain under a roof), `bUsePrecipitationOcclusion`.

### The sun's cascaded shadow maps (`world/sunshadow.zap`, `shaders/sunshadow.gpu.zap`)

BSShadowDirectionalLight's per-frame fit 0x14157f080 and the mask as the vanilla shadow shader reads
it (Community Shaders' Utility.hlsl, RENDER_SHADOWMASK). Three cascades (the shader tests
`EndSplitDistances.w > 2.5`), each a 2048 x 2048 depth map (iShadowMapResolution). The slices: near is
the camera's, far is min(camera far, fShadowDistance 8000); with first = min(8000 / 3, max(
fFirstSliceDistance 1250, 500)) / 8000 the fractions climb linearly from first to 1, and slice k ends at
((far - near) f + near + near (far / near)^f) / 2 + fSplitOverlap 100 (for near 50: 801, 2893, 8100);
slice k + 1 starts at the end of k less twice the overlap, and the pixel stage blends the two
cascades across that start to the end with a smoothstep. Each slice's eight corners are boxed in the
sun's camera (looking along the light from 15000 units toward the sun of the slice's middle, the box
rounded to whole texels, depth over 30000), the map drawn from the cell's opaque and cut-out runs
(land casts nothing: bDrawLandShadows 0); read through 8 spiral taps rotated per place of radius
fPoissonRadiusScale 4 / 2048, the visibility faded by 1 - (d / shadow distance)^16, and the bias is
fShadowBiasScale 1 * 0.00025 * fShadowDirectionalBiasScale 0.3 for cascade 0 and 8.33e-5 for the rest
(0x141568300; the game's mask compares the raw depth and gets its bias from the shadow pass's
rasterizer state, which is not read: the engine's depth bias stands in and these terms are added).
`CellScene.sunShadows` is made when the sky has the sun up (`fitSunShadows` in drawCell, then
`drawSunShadowMaps`), `shaded` multiplies the sun by `sunVisibility`. `skyshot.zap --objects` stands
Breezehome and pines on the land to cast them (`--unshadowed` reads none); the cascade fit is
unit-tested in `skytests.zap`, not diffed against the executable: the slice and fit code lives in
the middle of a 1,400-line function that allocates cameras and culling processes. Not ported: the
actors' focus shadows (iNumFocusShadow), the screen-space shadow refinement, the update interval
(fSunShadowUpdateTime), trees' and grass's casting flags (bShadowsOnGrass, fMaxHeightShadowCastingTrees).

### Water, grass and distant LOD (milestone 14)

The land beyond the loaded cells, the water and the grass of the exterior from SkyrimSE.exe 1.7.104
(BGSTerrainManager, TESWaterSystem and BSWaterShader, BGSGrassManager) and Community Shaders'
Water.hlsl, RunGrass.hlsl, DistantTree.hlsl and Lighting.hlsl read against the vanilla permutations.
`watershot.zap` (the whole exterior in a cell scene, graded as the game grades it; its header lists
the shots, run by `zap test --only shots`), `lodinfo.zap` (a block's files and shaders),
`terraininfo.zap --water --survey --plants --grass --record` (the water, grass and records the
plugins hold); tests: `lodtests.zap`, `grasstests.zap`. A scripted run of a scene
needs `r.showFrame(win, frames)` each frame (it ends the frame and writes `--shot` on the last one):
without it Direct3D 12 loses the device on the second frame.

- Distant land (`game/lod.zap`, `world/lod.zap`, `shaders/lod.gpu.zap`): `Meshes\Terrain\<world>\
  <world>.<level>.<x>.<y>.btr` (the land) and `...\Objects\*.bto` are NIF files, read as any model:
  a BSTriShape with the block's own texture `Textures\Terrain\<world>\...DDS` and a model-space
  normal map `_n.DDS` (shader type 18, LODLandscapeNoise), and BSSubIndexTriShape objects over the
  atlas `Tamriel.Objects.DDS`; the land's positions are local to the block, the objects' absolute;
  the part with no texture is the block's distant water plane. Blocks are 4, 8, 16 and 32 cells a
  side, chosen by the executable's node rule (BGSTerrainNode, 0x140519c10: a block splits into its
  four quarters while the eye is within fSplitDistanceMult 1.5 x half its diagonal of its square,
  the smallest never; DAT_143203580 holds that setting, 584 the biggest level 32, 588 level 16, 58c
  uGridsToLoad 5), out to fBlockMaximumDistance 250000 (`lodBlocks`, tested). The land under the
  loaded cells sinks by fLODLandDropAmount 230 (Lighting.hlsl's AdjustLodLandscapeVertexPositionMS;
  the loaded area's box, its centre and half side uGridsToLoad x 4096 / 2, is an assumption),
  objects whose triangles lie wholly in it are left out and a block wholly inside it is not drawn;
  beyond 70000 units the land's clip depth is pushed back (AdjustLodLandscapeVertexPositionCS). The
  pixel stage is the land's blend (GetLodLandBlendParameter and GetLodLandBlendMultiplier over
  `Textures\Terrain\Noise.dds` read at uv x 3, the name at 0x14051c9f0) under the model-space normal
  (the map's xzy), lit and fogged by `shaded`; objects use their vertex normals (their tangent-space
  normal maps are not read).
- Distant trees (`game/lodtrees.zap`, `shaders/treelod.gpu.zap`): `<world>.lst` is a count then 8
  words a kind (its number, the billboard's width and height, the atlas rectangle's left, top, right
  and bottom, a pad word), `trees\<world>.4.<x>.<y>.btt` a count of groups (kind, count) of 32 byte
  trees (x y z, turn, scale, the reference, 8 bytes unread), the atlas `Textures\Terrain\<world>\
  Trees\<world>TreeLOD.DDS`. BGSDistantTreeBlock (0x14050c410) makes a kind's mesh two crossed
  vertical quads (width x height, the second turned 90 degrees, indices 0 1 2 1 3 2), the
  instance's cosine and sine turn them about z, DistantTree.hlsl lights them by half the sun plus
  the ambient along the face's normal turned away from the eye, alpha test 0x80 (NiAlphaProperty
  0xec, 0x14050c100). Trees within fTreeLoadDistance 75000 of the eye, those inside the loaded area
  left to the near trees.
- Water records (`skyrim/esm/water.zap`): a WATR's DNAM is TESWaterForm's 232 bytes of shader data
  (the layout of CommonLibSSE-NG's WaterShaderData; the executable reads TESWaterForm+0xd0), NAM2 to
  NAM4 the three normal maps, NAM5 the flow normals (RiverFlow.dds), FNAM 8 the flow map flag, ANAM
  the opacity, GNAM the types the weather swaps it for. A cell has water when its DATA says so (2):
  XCLW is its height (from 2^31 up the world's DNAM default, -14000 in Tamriel: 0x1402bee00), XCWT
  its type (WRLD NAM2 where it names none), and its flow map is `Textures\Water\Skyrim.esm\
  flow.<x>.<y>.dds` (64 x 64 texels over the cell, read texel by texel as the shader's four shifted
  samples with triangle weights imply). Riverwood's cells (3 to 5, -13 to -10) are RiverWaterFlow at
  -250, (5, -12) a pond; the distant planes use WRLD NAM3 and the block's own height.
  `exteriorCellRecord` gives the last plugin's record of a cell.
- Water shader (`shaders/water.gpu.zap`, `world/water.zap`, `game/water.zap`): Water.hlsl's non-LOD
  flow path as written there. Constants as BSWaterShader::SetupMaterial (0x14154d700) sets them: the
  shallow and deep colors are the type's bytes x the weather's waterMultiplier (Sky color 14, the
  tint at 0x143435bd8), deep w the sun specular magnitude (the sun's share through the water is
  1 - exp(-w)), VarAmounts (sun specular power, reflection amount, opacity, refraction magnitude),
  the amplitudes, the noise falloff (4037: the normals' detail fades out to 8192), the layers'
  scales, fog far 150 and range far - near, the depth factors, the fresnel amount. The layers scroll
  by the TESWaterNormals update (0x140528cd0): the wind direction in degrees through the executable's
  sincos (the sine first: x = sin, y = cos) times the speed times the clock, the fraction kept; the
  flow normals take the clock in seconds. The pass copies the picture's color and its depths (red,
  60000 where nothing is drawn) after the ambient occlusion, draws the sky, the land, the distant
  land and the trees once more from the eye mirrored in the water (an oblique near plane keeps what
  lies under it out; the picture is turned over to keep the triangles' winding), then the planes:
  the refraction through the normal's offset in the world's xy by VarAmounts.w x the depth factor,
  the depth block (planeMul), the sun's glint, the fog. Not ported: the cube map the executable
  reflects (the planar reflection stands for it), the screen-space reflection, ripples,
  displacement and wading, the shadow on the water, the underwater pass and its stencil, the
  refraction's fog term (a number under 1 to the power of the fog's 150: nothing), FrameParams.w
  (taken 0).
- Grass (`game/grassplace.zap`, `game/grass.zap`, `world/grass.zap`, `shaders/grass.gpu.zap`): a
  GRAS's DATA is TESGrass' 32 bytes (density, slopes, water distance and state, position, height and
  color ranges, wave period, flags 1 vertex lighting, 2 uniform scale, 4 fit to slope), MODL the
  plant's mesh. The placement is BGSGrassManager::AddCellGrass (0x140206d40) with a vertex's square
  (0x140209020) and its grass types (0x1402afb20) ported draw for draw: the cell's generator is the
  engine's own twister (a seed and a regeneration that are not the standard's, 0x140ce4460 and
  0x140ce44e0, checked against an independent transcription in `grasstests.zap`) seeded with x times
  y; each quadrant's vertices at odd columns then odd rows (a 256 unit square about each), the grass
  of its base texture and of each layer with more than 25 of 255 at a neighbour (one more than
  iMaxGrassTypesPerTexure a list), n x n sub-squares (n the least of 256 / 20 and 256 / the position
  range), each accepted by `rand(0x7fff) < density x bilinear x 32768`, jittered by two draws, its
  place kept as half floats about the origin of the block of 12 x 12 cells (the cell / 12 x 12 with
  the division toward zero) so that it is rounded to 16 units at Riverwood's x, the height by the
  triangle under it, the slope and the color those of the nearest of its three vertices (VNML, VCLR),
  the water's state, then the shade (luma 0.31 0.37 0.32 x the dice by the color range), the turn (a
  sine drawn straight), the basis (the slope's, its axis the normal's smallest component) and the
  height's delta, 16 half floats an instance. Riverwood02 has 2447 plants. The shader is the plain
  grass of RunGrass.hlsl: the model's z-up positions turned by the instance's rows, scaled by
  1 + delta (along z unless the uniform flag), swayed by GrassWindDisplacement (the phase (x + y) / -128
  of the stored place, the vertex alpha squared as the weight, a timer of seconds x wave period /
  600 x 2 pi, the magnitude the weather's wind speed from 5 to 125 units capped at 60, along +y:
  SetupGeometry 0x141522870), faded from fGrassStartFadeDistance 7000 over fGrassFadeRange 1000,
  alpha tested at 100 / 255, lit by the sun's color (no N.L, as that permutation) plus the ambient
  along the face's normal, times the texture, the vertex color and the shade. Not ported: the
  per-instance fade-in, the grass LOD, shadows on grass, the wind's blend across a weather change,
  bGrassPointLighting, the executable's own pixel stage (CS' stands for it).

## What the executable still has to give (reference/exe)

Read so far with REA and left for the next pass, with the entry points found:

- The InventoryMenu's list filling (0x1409452b0, 0x1409451e0, 0x140945050, 0x140945e20) and the
  item card's 0x1409472c0 (5,167 bytes): which fields each item kind sets (`infoValue`, `effects`,
  `potionType`...). The field names and the entry's six members are known; the per-kind logic is
  not. Why: the function is large and the port's `itemmenu.zap` already matches the captures.
- The dialogue's info choice 0x1403ef230 (conditions, random, say once) and the `DialogueItem`
  builder 0x1405ed830; the manager's walk around them is read. Why: `choose.zap` does it from the
  records and `dialoguetests.zap` holds.
- The sync integers' writers (the graph's `Speed`/`TurnDelta`/`Direction` channels are read and
  ported: `reference/exe/animation.md`).
- The emittance (XEMI) light: the region's weather is its likeliest (SkyrimClear, first of the
  equal chances) where the game takes the sky's current one, carried in from outside; the flag is
  per model, so a ref of an externally lit model without XEMI would take the cell's source (none in
  the inn). Why: no exterior sky runs yet. Plugins: Skyrim.esm with Update.esm and the DLC masters as
  overlays of `recordOf` only (no cell or reference of the inn is overridden); the Creation Club
  plugins (Survival's ALCH overrides) are not loaded.
- Havok's restitution, the lin constraint atoms and the motors: Havok's own code, reached from the
  `hkp*ConstraintData` vtables in `classes-havok.md`; the collision filter and the angular
  constraint schemas are read.
- The plugin loaders: the record signatures are not defined strings in the image (they are 4-byte
  immediates in the loaders), so no record-format table came out of the exe; the port's readers
  follow UESP and xEdit and `readertests.zap` holds. The form type byte is `form+0x1a`
  (CommonLibSSE's `FormType`; 0x1a ARMO, 0x29 WEAP, 0x2e ALCH, 0x34 SLGM, 0x3e ACHR, 0x77 SHOU
  observed).
- The HUD's `ProcessMessage` (0x140933180) was read only for its Invoke names and message kinds.
- The two CLOUDTRAP/PORTAL and CLOUDTRAP/ACOUSTIC SPACE bits of the layer matrix cleared through a
  temporary the parser skipped (`havok.md`).

How to go on: open the exe in REA (`README.md`), find a setting's readers by `xrefs` on its
object's value (`combat.md` explains), a class's functions by its vtable slots (`classes-*.md`),
a menu callback by its name string's `xrefs`, and decompile with `procedure_pseudo_code`; results
over about 50k characters come back as a file to grep.

## The MVP

The user's definition (2026-10-21): the game 100% functional inside the inn, not only its picture:
menus, items, combat, dialogue, the NPCs and their routines, everything the game does there.
Exactness against the game comes first at every step, performance after, Android last.

## Milestones

1. The inn drawn, free camera. Done.
2. The player walking in it with the physics. Done (skyrim-player).
3. Reference captures of the real game and the pixel comparison. Done (compare.zap).
4. The render made exact from the game's shaders (ported from the DXBC reconstruction):
   shadows of the interior lights, the lighting formulas, the image space passes.
5. Sound: xWMA and FUZ decoders, the cell's acoustic space, music and the fire.
6. Papyrus: the PEX scripts of the inn run in Zap, bound by the plugin's VMAD, over the game's
   native API implemented step by step as the inn's scripts need it.
7. The NPCs: Orgnar, Delphine, Sven and the patrons from their NPC_ records (bodies, FaceGen
   heads and tints, outfits), their AI packages (sandbox: sit, eat, sweep, serve, sleep by the
   hour), their idles and dialogue.
8. Interaction: activators, doors (the exits lead nowhere yet), furniture (sit, sleep), pickup,
   containers, the room for rent.
9. The interface: the HUD, the pause and system menus, inventory, container, dialogue, the
   barter and sleep menus, as the game's Scaleform SWF menus draw them (the SWF read for its
   shapes, bitmaps and fonts; the ActionScript 2 of the menus run or rewritten in Zap, decided
   by what gives the same pixels).
10. Items and combat: inventory, equipping, weapons and armor, the hit and damage formulas,
    health, stamina and magicka, the NPC combat AI and the crime response, death.
11. Dialogue: the DIAL/INFO records with their conditions, the voice FUZ with lip sync, the
    subtitles, the topics the inn's NPCs have.
12. The Havok constraints (hanging animals, chains) and the rest of the physics the inn uses.
    Done (skyrim-ragdoll): the inn's only constraints are limited hinges (17 hanging animals, 5
    books); actors' ragdolls from skeleton.hkx.
13. Frame rate above the game's, measured on this PC in the same cell.
14. The whole town of Riverwood (user, 2026-10-21, before Android): the exterior worldspace
    cells around it (WRLD, LAND terrain with its texture layers, water and the river, the sky,
    weather and the time of day, the sun's shadows, trees and grass, distant LOD), the other
    interiors (Alvor's house, the Riverwood Trader, the mill, Sven's and Faendal's houses), the
    town's NPCs and their day, the exits of the inn leading out.
   Exteriors and the doors (esm/area.zap, game/travel.zap, game/land.zap; exteriortests.zap):
   the game's loaded grid is GridCellArray's uGridsToLoad squared cells (SkyrimSE.exe 0x140226FA0
   forces the setting to at least 5 and odd; the ini's 5), centred on the player's cell. An area,
   named by its centre cell (`exterior_<world form id>_<x>_<y>`: Riverwood is `exterior_60_5_-11`),
   stands in for an interior wherever a cell is looked up by id (`findCell`, `cellRecords`): the
   references of the 25 cells' own groups plus the worldspace's persistent ones lying in them (the
   town's doors), so prepare.zap, the physics (`cellWorld`), the Papyrus VM, the sound and the
   fight scene take it unchanged (the area's cast is its people: the actors it places, enabled
   and of a people's race, and those whose packages bring them, never its animals). Prepared once (about 15 s, 1.2 million vertices, 800 MB); the
   physics world takes about 35 s to read, the game's own loading screen. Load doors: a door's XTEL
   holds where the player appears on the other side, its position and rotation; a door whose
   destination is an interior is resolved by one pass over the interiors' reference headers
   (`interiorCellOf`, `interiorCellRecord`), the HUD text is the destination's name (the exterior
   cell's FULL, else its location's: "Open Riverwood"; "Open Sleeping Giant Inn"). main.zap runs
   one cell after another: an activated load door (E, or `--use <frame>:<door>`) fades the screen,
   keeps the cell's state (`Left`) for the way back, carries the player, his inventory, the
   quests, the globals and the clock into the next cell's new world, and opens the destination
   with the player at the XTEL's place. The grid is made again round the player's cell once he
   is past the middle ring of the one loaded (no fade): a reload of the whole area, not the game's
   cell by cell streaming. A save outside records the area's centre cell and the feet. The land is the terrain agent's (game/land.zap: `terrainOfArea` drawn with
   `showTerrain`, its heights written into the area's physics.bin by `collideAreaLand`). A game of
   the town peaks at about 1.9 GB of RAM (it was 3.2 GB) and holds 1.3 GB of the card's memory plus
   0.2 GB host-visible (it was 1.5 GB: the upload ring grew to stage every texture of the level at
   once, and Vulkan ran out of memory with the people in the cast; `rhi/core` `staging` now runs
   and waits for the uploads when the ring is full and only uploads read it). The textures stay as
   the archives hold them (BC1, BC3, BC5, BC7, every level, shared by key; 1.1 GB live, of which
   0.2 GB are the per-body bent normal maps in RGBA8). `iTexMipMapSkip:Display` leaves the top
   levels of the archive textures out (0 by default, the game's ultra). `ZAP_RUN=gpumemory` prints
   the device's `gpu memory:` line each frame (rhi/core/budget.zap); exteriorshottests.zap holds the
   town to a budget (card 3000 MB, host-visible 512 MB, process 2500 MB). Hooks left
   for the other agents: the sky, weather and the exterior's lighting (`daylight()` in
   esm/cell.zap, a clear day's light), water, grass and LOD.
   The town's people (game/townfolk.zap, game/transit.zap; townfolktests.zap, townwalktests.zap,
   walktests.zap): `townAround` maps the exterior and the six interiors its doors lead to (the
   Trader, Alvor's, Sven's, Gerdur's, Faendal's house and the inn) with every placed reference, the
   load doors both ways (XTEL: where each leads and where it puts who goes through) and the people
   (the actors the cells place, then those whose packages bring them), each package's place
   resolved as the AI reads it (a reference, a cell, the actor's own place, its linked reference;
   an alias place is a quest's and does not hold). `spotAt` is the cell and point a package puts
   the actor at, by hour and day (Alvor: home asleep to 6, the forge from 8, home to eat at 20, the
   inn at 21, home again from 23); `route` and `legs` the doors between two cells and the walk in
   each. A cell not loaded is advanced as UpdateNonHighActors advances the actors out of the high
   list (0x14077bbc0, sliced each frame): each is at its package's place by the hour, and one whose
   package just changed is on the route's way at the gait's walk speed (`whereAt`, 130 units a real
   second: a stand-in for the low-process movement, whose speed the exe's AIProcess code has not
   been read for). In a loaded cell (`joinTown`) an actor whose next place is in another cell
   walks the navmesh to the load door and goes through it (`departed` hands it to the cell the
   door leads to); one coming from another cell is away for the walk the cells before this one
   take, then appears at the door's arrival (the XTEL position) and walks to its place. An actor
   the cell places that no package takes stands where it is. The exterior's navmesh now joins its
   meshes across their edge links, so the town's streets are one walkable mesh. Streaming: the
   grid's step per cell crossed is `gridShift` (a row or column enters and leaves, a diagonal step
   2 side - 1); main.zap still reloads the whole area once the player is past the middle ring,
   since the prepared file is one per area. Not done: per-cell prepared files, so that a step loads
   only the cells that enter; the sounds and footsteps of the exterior's people; greetings and
   ambient lines outdoors beyond the dialogue the cast already has; the town's interiors prepared
   one by one in a running game (they prepare on first use, through their doors); a cell's
   residents carried across a load door in a running game (`departed` and `arrival` are the
   hand-off, main.zap does not yet deliver them); Papyrus state carried between cells (each cell's
   VM is new, as a new game finds it).
15. Android.
- The pixel stage read in shaders011.fxp (permutations 04027 tangent normals, 04028 model normals, vertex 03904): diffuse is the lights plus dp4(cb2[11..13], float4(n, 1)) unclamped, plus the flat emit cb2[4].yzw and an IBL term cb1[8], per pixel with the normal map through the model-space tangent frame; the per-geometry matrix (0x141549BD5-0x141549EFB) is the DA rotate times the world rotate, rows (rotate, mean), no scale or fade; the ambient specular cb2[14] is off in the inn (its DALC, specular 0, comes whole from FarmLightingTemplate by inherit flag 0x1, 0x1402BC750/0x1402BC790; the cell's own XCLL specular is ignored); the directional light is linear dp3_sat(n, l). Unclamped (the exe's form, kept) totals 461.3, the same as clamped: no part of the inn goes below 0. Left to try against the floor's bias: the IBL term.
- The IBL constant cb1[8] (flat, IBLParams.yzw * IBLParams.x) is zero in every cell: BSLightingShader's constructor (0x141547210) zeroes +0xc8..+0xf0 and nothing writes them after (SetupMaterial 0x141548820 stores them at 0x141549398). So the pixel stage's diffuse is ours term for term; the floor's bias is outside the lighting shader.
- Firepit (exact8, 50.8%): the step top's dark band and the pit rim's dark top were the ambient occlusion, not the fire's shadow (shadows off: firepit 47.6%, the step top's red -12.3 to -9.9; occlusion off: 48.1%, the step top +6.1 +7.1 +6.8, the rim top -39.0 to +6.4). The fire light's data (FarmInteriorFireLight01: radius 512, color 173 103 52, fade 1, flags 0x1009, falloff 1, near clip 22.4 that the dual paraboloid passes do not use, flicker 0.333 / 0.4 / 2; the ref at -512.7 -0.1 170.9, no model) and the pit's shapes (shader flags 0x80400301: receive and cast shadows) agree with ours; the burning wood model carries no light. The cause: a target's first row is the clip space's y = -1 (rhi/vulkan/commands.zap), but view.gpu.zap took uv's y as growing downward, so the positions made from depths were the view mirrored in y while the normal buffer was not; on level surfaces the normal pointed into them. Fixed in viewAtDepth, the occlusion's taps and both reprojections (TAA's and the occlusion's): 463.8 with the 15-tap form. The SAO read in shaders011.fxp (no names in the package; found by their constants: 16012 ISSAORawAONoTemporal, 16010 ISSAORawAO, 16000-16004 ISSAOComposite with fog and SSR, CB2[11]) and the executable (0x141541E20 copies the Display settings fSAORadius 250, fSAOIntensity 15, fSAOBias 2.5, fSAOExpFactor 0.11, fSAOValueDiffFactor 0.3; 0x14154240B builds the raw pass's constants: projInfo (-2/(W m00), -2/(H m11), 1/m00, 1/m11), (random 32 bits times pi / 2^32, radius * 100, bias, intensity / radius^6), (W, H, 1/W, 1/H), (expFactor, radius², valueDiff, the camera z at depth 0.01, nearer taps ignored)): the no-temporal form is ours term for term (15 taps 3.349334 apart, the per-pixel turn (3x ^ (xy + y)) * 10, the bias 2 ndc.ndc + bias + 10 max(z / 7000 - 0.3, 0), sum / 3, the contrast pow) but for the 2 x 2 quad's gradient taken out where |ddx z| < 0.02; with bUseTAA=1 the game draws ISSAORawAO: 5 taps 2.512 apart on reach / 5, the frame's random angle added where z / 7000 <= 0.5, no / 3, the quad step, then the last frame's raw value at the reprojected place kept by (1 - 0.3 |ao - last|) (1 - 200 |key - last key|) max(1 - 200 |motion difference 0.055 away|, 0.2). Composite: the whole lit color times the occlusion (with SSR and snow added before), as ours. Ported: 467.6. The shadow mask at the place itself, no normal offset (RENDER_SHADOWMASKDPB): 467.8, kept. Not ported: the game's pixel rows counted from the top in the turn's hash and the quad's parity (ours from the bottom), the motion vectors (ours from the depths and the views).
- Image space from the executable (exact9, share within 8 467.9 to 503.3): the HDR setup 0x14153d860 passes the tone curve 1 / (fReinhardWhiteScale 1.1 x white)^2 (FarmInteriorIS's white 1 had made ours the identity; 493.9); the eye's adaptation (0x14153d120, the DXBC's DOWNADAPT) keeps 2 x 2 luminance references (bUseMultipleLuminanceReferences: the downsampling stops at 2 x 2, each quarter its own mean, sampled at the pixel by the grade and the bloom), the scene's closing at 1 - (1 - 0.01 / (strength x 0.4) x speed x 2)^(30 dt) and the target's at 1 - (1 - 0.01 x speed x 2)^(30 dt), a step at least 1/256 (502.9); TAA's BlendParams from 0x1415455c0 (0.8 at rest, 0.5 at speed, post sharpen and overlay 0.21: 503.3, backroom 95.1 to 91.1 with the weight alone, the cause unfound). The blend pass's DXBC confirms the luminance form of the curve and ends in pow(c, 1 / fGamma) (1 here). Soft effects (the fire pit's flames and smoke, the candle glow) had read the depth key with rows downward since the y fix and faded to nothing; fixed. Left: ours is still about 10% less saturated than the game's on every pose (a fit of game = a ours + b luma gives b about -0.1), outside the grade, which matches the DXBC term for term. Measured after: the ratio of the ambient to the point lights is what is off (ambient x 0.8 takes b to -0.05 and totals 504.2, lights x 1.25 to -0.03 but 369.3), not the highlight (off: b unchanged, 481.6); both are fitted factors and are left out. The lighting shader's directional color is the light's dimmer (+0x134) x the image space's sunlight scale x its color (0x141549550); with FarmInteriorIS's 1.5 the inn totals 459.3 and with no sun 397.6, so the interior's sun takes neither and its dimmer stays unread. The flicker (0x140274be0, LIGH +0xec flags, +0xfc period as a rate, +0x100 amplitude, +0x104 movement, +0x108 fade plus the ref's fade offset through 0x140300020): flag 0x8 runs three phases advanced each frame by random(1.1..13.1, 1.2..13.2, 1.3..19.3) x the rate and wrapped at 2 pi, f = (sin(1.3 y + 0.65) + 1)(sin(1.1 x + 1.87) + 1) / 12 + 0.2 sin(3 z + 0.9) clamped to 1, dimmer = (amp / 2 f + 1 - amp / 2) x fade (0.76 to 0.91 of the fade at amplitude 0.4, mean about 0.82; flags 0x180 a cosine pulse of the same mean), the position moved by movement x the sines; the point light's color is its diffuse x dimmer x the BSLight's distance fade (+0x14, 0x141575d20: 1 inside fLightLODStartFade 3500). Ported it totals 346.6 (every pose about 1.25 too bright, the saturation gap gone: b -0.03 to +0.08), against 503.3 with flicker.zap's measured rest at 0.6 of the fade (mean about 0.67); so some other term of ours is about 20% too bright and the measured flicker hides it. Checked and not it: the luminance downsampling writes one mean to every channel (DXBC), so the exposure at rest is 1; the shader's attenuation is 1 - (d / r)^2 as ours. flicker.zap stays the measured form until that term is found.
- Render captures (exact10, `reference/exe/render-captures.md`): RenderDoc captures of the game's six poses, taken headless, show the sun at 1.5x (sunlight scale), the lights at the executable's flicker (0.78, 0.87 of the fade, not the measured 0.6 rest) and a fog fade of 0.8333 the SAO composite multiplies the picture by; ported, they balance the colors (the 10% saturation gap closes) and the grade is shown exact (the game's blend formula on our scene gives our output on 100% of the pixels); share within 8 523.5 to 517.5, the rest is the scene pixel by pixel.
- Unfinished (exact8): the SAO noise, taps and depth pyramid now count rows from the top as the game's (468.1; the quad's parity is already the game's with an even height). Next was remeasuring the up, down and side bias by facing per pose under the y fix (normals drawn through the --ids pass, n * 0.5 + 0.5, then ours minus the game's by normal y): not run, the machine was out of memory.
