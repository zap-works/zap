# Donkey Kong Country rebuilt in Zap

Donkey Kong Country (Rare, 1994, SNES, the USA v1.0 cartridge) recompiled into native Zap from the
player's own dump: `projects/dkc/rom/dkc1.sfc` (sha256 `fa8cacf5bbfc39ee6bbaa557adf89133d60d42f6cf9e1db30d5a36a469f74d15`),
never committed, nor anything taken from it (`.gitignore`: `rom/`, `recomp/`, `assets/`,
`reference/`).

The aim, in this order: the game frame for frame as the cartridge runs, checked against an
emulator every frame; then a wider picture and a higher frame rate; nothing of the look or the
feel changed.

## The route: FireRed's

As `projects/firered` did for the GBA: the cartridge's 65816 code is translated ahead of time
into Zap functions (`prepare.zap`, once, from the ROM), built into one executable with the SNES
written in Zap on the engine: the PPU (mode 1 backgrounds, sprites, HDMA, colour math, the
windows DKC uses), DMA, the joypads, the SPC700 and its DSP (the sound driver recompiled the same
way, its samples read from the ROM), the timing of frames and VBlank. The game's data the code
reads stays in the ROM image loaded at start (`assets/`).

What the community has, and what is taken from it (licenses respected, nothing of the game
copied into the repository):

- **DKC1Recomp** (github.com/elliotttate/DKC1Recomp, MIT; its engine `recomp.snes` PolyForm
  Noncommercial): a working static recompilation in C. Its `recomp/bank*.cfg` give, per bank,
  the data regions inside the code banks, 1,276 function entries with their M/X flag states, and
  the targets of the 25 indirect-dispatch sites (the 460-entry game-mode dispatcher, the animation
  commands): the flow analysis seeded from these instead of discovered blind. Its docs record the
  measured frame costs and the widescreen findings (what can be widened without touching the
  cartridge's state).
- **Yoshifanatic1's DKC1 disassembly** (GPL-3): byte-exact, labeled; `RAM_Map_DKC1.asm` names
  the variables, `SPC700/` the sound engine, `AsarScripts/` extract the assets. Read for names
  and structure; its text is not copied.
- **DKC-Recomp/DKC-disassembly** (GPL-3, in progress): a second reading to settle doubts.

## The oracle: Mesen 2, frame by frame

Mesen 2 (GPL-3, `winget install SourMesen.Mesen2`) runs headless with a Lua script
(`--testrunner`): `recomp.snes/tools/oracle.lua` plays a scripted input route from power-on and writes, for
every frame, the hash of the framebuffer and of WRAM (the settings that make its run the Zap
build's are in its header). `zap run projects/dkc/main.zap --route <file> --frames n --hashes
out.txt` writes the same from the Zap build, and `recomp.snes/compare.zap` names the first frame whose WRAM
and whose picture differ; `--memory prefix` dumps the memories and the picture to find what
differs, `--trace n` prints the recompiled functions entered from frame n, `--steps n` every
instruction with the master cycle it starts at (recomp.snes/tools/oracle.lua's trace mode lists Mesen's the same way) and
`--ports` the APU's port accesses (its ports mode). `zap test projects/dkc` plays the routes
kept in `tests/routes/` (a route and the hashes Mesen wrote for it) and fails unless every frame
matches.

Matching every frame takes the CPU's time as Mesen counts it, bus cycle by bus cycle: the
translated code runs each instruction's cycles in Mesen's order (`recomp.snes/snes/cycles.zap`), each access
as long as where it lands, and the console runs its events, a DMA or HDMA the hardware asked for
and the NMI and IRQ lines at the cycle Mesen does (`recomp.snes/console/bus.zap`).

## Layout

The SNES, the 65816 and the recompiler are `projects/recomp/snes` (projects/recomp/README.md): the decoder, the
flow, the translation, the console (PPU, DMA, SPC700, DSP, timing), the CPU's runtime, Mesen 2 as
the oracle (`recomp.snes/recomp.snes/tools/oracle.lua`, `recomp.snes/compare.zap`, `bk2Route`). Here only what is
Donkey Kong Country's:

- `cartridge/`: the dump's check (size, SHA-256), the `recomp.snes.snes.Game` that names its ROM,
  tables and recomp dir, and the widescreen's patch table (`patches.zap`: the object windows
  widened, the rope and banana hooks, the type-$05 retry).
- `wide/`: the widescreen's scene (the level gate, the camera range, `glide`), the level map
  decoded from the ROM, the rope helpers and the retry, installed into the console's `WideHooks`
  by the generated program's setup line.
- `tables/`: `bank*.cfg` and `symbols.toml` are DKC1Recomp's (github.com/elliotttate/DKC1Recomp,
  MIT, see LICENSE-DKC1Recomp): per bank of the USA v1.0 cartridge, the data regions inside the
  code banks, the function entries with their M and X flag states, the targets of each
  indirect-dispatch site, and the names of the routines the community has identified, distilled
  by that project from Yoshifanatic1's GPL-3 disassembly (no code or data of the game is in
  them); `played.cfg` the jumps through memory Mesen's runs of the routes found. The recompiler
  reads them so the flow analysis starts from known entries instead of guessing.
- `prepare.zap`: checks the ROM, writes `recomp/`.
- `main.zap`: prepares when needed, builds `build/dkc.exe`, runs it.
- `tests/`: the routes against Mesen 2, the walkthrough, the wide pictures, the flow over the ROM.

## State: the milestones

1. The ROM read, the decoder over every byte the cfg calls code (53,230 instructions), each
   instruction assembled back to its bytes (the decoder's test).
2. The flow: functions, labels, dispatch tables; the translation into Zap of one bank; the
   program builds.
3. The console: memory, DMA, PPU mode 1, joypads, VBlank/NMI; the Nintendo and Rare logos and
   the title match Mesen 2's frames.
4. The SPC700 and DSP; the title's music: the 900 frames of `tests/routes/title.txt` (the Rare
   logo, Start, the intro, their sound uploads) match Mesen 2 in every picture and in WRAM.
5. Jungle Hijinxs playable; the oracle route through its first seconds frame-exact: the 3,700
   frames of `tests/routes/jungle.txt` (the title, a new game, Kongo Jungle's map, Jungle
   Hijinxs walked and jumped through) match Mesen 2 in every picture and in WRAM, every NMI
   entered at Mesen's master cycle. The jumps through memory the cfg does not name come from
   Mesen's run of the routes (`tables/played.cfg`, recomp.snes/tools/oracle.lua's played mode).
6. Presentation: the picture wider than 256 pixels where the level's map proves it safe (done,
   below), the frame rate above 60 by interpolation of the picture (done; the game's logic stays
   at the cartridge's rate).

## Widescreen as DKC1Recomp does it

Read from DKC1Recomp's `docs/WIDESCREEN.md` (MIT; its `recomp.snes` is PolyForm Noncommercial, read,
never copied). Its other `recomp/` files are the cfgs already in `tables/`; `recomp/dixie/` is a
mod variant, not taken.

- 342x224: 43 extra pixels each side of the 256x224 frame, 1.78125 with the 7:6 pixel, a pixel
  off 16:9 (also 308x224 for 16:10). Only the host framebuffer, its pitch and the window change;
  WRAM, camera, collision and level state are the cartridge's.
- What is widened: the picture, from a world-keyed shadow tilemap. Level maps are static ROM data
  (`Level_SetTilemapPointers` at $81:8C66, column DMA at $81:883F, vertical at $81:8A6F/$81:8DFA),
  so the margin tiles are decoded from the ROM's metatiles and checked against the live rolling
  tilemap before use; BG3/parallax only where proven periodic. Sprites: the two common display
  cull windows, placed objects (18 left, 14 span, two right prefetches), bananas, vertical ropes,
  with 9-bit OAM X; type-$05 groups retry children; the PPU's 32-sprite/34-sliver limits grow by
  one per visible extra 8-pixel column.
- What is left alone: camera and layer coordinates, collision and player limits, exit and
  transition tests, boss arenas, tilemap stream coordinates. Presentation reveals pixels, it never
  moves gameplay coordinates (the SuperZSNES ROM patch moved the camera bounds and needed many
  repairs).
- Fail-closed: a scene identity (mode, level, entrance, map/metatile/VRAM signatures, layers)
  gates it; a scene that fails calibration, and fixed screens (logos, menus), show the native
  frame centered on black. Known hard spots: moving-margin levels (Slip-Slide Ride), walls, water
  and vertical levels.

## Widescreen: what runs

`console/wide.zap` (the scene gate, the shift, the picture), `widelevel.zap` (the ROM's level map),
`wideDraw.zap` (the margins of a line), `snes/widen.zap` (the cull constants widened). Native play
is untouched: without `--wide` nothing changes, and the 256x224 picture the route tests hash is the
same bytes (the wide picture is a second composition, in its own buffer).

- Run: `zap run projects/dkc/main.zap --wide` (window 342x224 at an integer zoom, `--wide-width 308`
  for 16:10), headless `--headless --wide --frames n --shot x.png` saves the wide picture,
  `--wide-hashes out.txt` writes a line "frame hash wide" per frame (wide: 1 when the scene was
  drawn wide, 0 when it is the native frame centred on black).
- Gate (fail-closed), judged at the end of line 0 of every frame: mode 1, low resolution, no
  mosaic, the camera range (1B23, 1B25) spanning both margins, and the ROM's map reproducing the
  live tilemap (7 in 10 of the viewport's tiles, either streamer layout, either coordinate key).
  Anything else, the logos, menus, the map, an unrecognised level, is the native frame on black.
- Terrain beyond the 256 pixels: the metatile map decoded from the ROM (`decodeTile`, the formulas of
  the two streamers $81:8705 and $81:8DFA), keyed by world tile, no stored shadow: the decode is the
  shadow. The other layers repeat their native scanline. The native picture is shifted inside the
  wide one at a level's edge as DKC1Recomp's `glide` does, so no pixel past the wall is shown.
- Sprites: the 9 bits of OAM x read as 0-341 right and above 341 as negative; the 32 sprites and 34
  slivers a line grows by one for each 8-pixel margin column drawn. The cartridge's own windows are
  widened by `console.widenLeft` and `widenSpan` in place of their constants (the shared sprite
  renderer's two, the placed-object scanners' left, span and prefetch ones): the objects there
  spawn earlier than natively, so a wide run's work RAM is not Mesen's, by design.
- Bananas and vertical ropes: the banana formations' two cull windows (their right edge, left
  edge and width) widened as the others, and the carry their `asl` takes for the OAM's x-high bit
  read from bit 8 of the x, not the sign (a hook in `snes/widen.zap`); the rope's cull key biased by
  the left margin, its size bit merged into the upper OAM with the x-high bit set afresh.
- The type-$05 group's retry of the children the pool lost (`cpu/widenretry.zap`), entered at the
  scanner's start while the scene is wide.
- The cartridge's tilemap initialisers (the 32-column backstep of $80:9E32 and $80:C501) are not
  widened: the margins are never read from VRAM, they are decoded from the ROM, so nothing needs
  them filled.
- A rate above 60 (`--fps N` with `--wide`, the window): the logic stays at the cartridge's rate;
  between two frames the picture is drawn again (`console/interpolate.zap`) with each line's
  background scroll and each unchanged sprite carried part of the way, a move over 48 pixels
  taken whole. `--headless --fps 120 --shots-at f` also saves frame f's half-way picture,
  `f-half.png`, which is how it is looked at without a window.
- Test: `tests/wide.zap` plays jungle.txt wide and keeps every 100th frame's wide hash, the count of
  frames drawn wide and one digest of all of them (`zap test projects/dkc wide --update` keeps a
  deliberate change).
- `--wide-native-logic`: the drawing is wide but the cartridge's windows are not widened, so its
  work RAM and native picture stay Mesen 2's and a route stays in step (a run with the windows
  widened diverges from the TAS: objects spawn earlier, and from about frame 98,000 the route no
  longer reaches its levels). `tests/routes.zap` plays jungle.txt so against Mesen.

## Whole-game route

TASVideos' 3956M (Tompa, "all stages, walkathon", BizHawk 2.2.2's BSNES core, 148,390 frames, USA
v1.0, the dump's SHA-1; inputs only, kept in the ignored `reference/tas/`). Keyed by frame, as the
movie is, it left the game in Mesen 2 at frame 4,534: the load out of Jungle Hijinxs lags one frame
in Mesen and none in the movie's bsnes, so every later button landed a frame early (the RAM at
power-on, the joypad and the ROM were not it: both emulators' level bytes and lag frames agree to
there). So the route is keyed by the game's joypad reads: `recomp.snes/tools/bk2Route.zap` plays the movie in
BizHawk on a hidden desktop and keeps the buttons of each frame that reads the joypads (the lag
frames' are never seen by the game), and `recomp.snes/tools/oracle.lua` with `SNESRECOMP_POLLS` gives them at Mesen's
own reads and writes the route by frame that the Zap build plays. Loads lag differently in the two
emulators all through the game (Mesen ends some 50 frames later, 148,440), yet the game reads the
same buttons and follows the movie's levels (checked against BizHawk's level and entrance bytes
through frame 82,000, and by the shots after).

The route, 148,700 frames: Kongo Jungle at 10,000, Monkey Mines' map by 30,000, Kremkroc
Industries at 80,000, Gang-Plank Galleon at the end. State, unfinished: Mesen's run of it
(`build/tas/run-full.sh`, about an hour) and its `played` mode are done, `tables/played.cfg` holds
what it found; the Zap build's shots at every 10,000 frames to 130,000 show Mesen's scenes, but its
run stopped at frame 135,206 on a native stack overflow, not compared by hash. The cause: the
title's first NMI comes with the stack at 02FA, its handler moves it to 01FF and waits, and every
NMI after nested under the last, the native stack growing a frame's work each frame until a
stretch with no unwinding ran it out (`cpu/interrupts.zap` judged an interrupt left for good only
above the outermost frame). Fixed to the innermost frame; `tas8000` still matches on a 2 MB stack.
`tests/walkthrough.zap` keeps its first 8,000 frames (`tests/routes/tas8000.txt`); the rest is
compared by hand, the hashes of the whole run being 3 MB of text. `recomp.snes/tools/oracle.lua`'s `wram`
mode dumps the work RAM at a frame, to set against `--memory prefix` when a frame differs; its
`played` mode (run from the repository root, `SNESRECOMP_JUMPS` an absolute path, else the script stalls
to its timeout) finds the jumps through memory (`tables/played.cfg`).

Every flag is computed after every instruction (`recomp.snes/snes/flags.zap`): an interrupt polled between two
instructions pushes the status register, so a flag judged dead still shows in the stacked byte.
Speed, headless, `jungle.txt` 3,700 frames, the same machine in turns: flags dead-eliminated 91 and 72
frames a second, all flags live 103 and 79; the change costs nothing measurable (the machine's load
moves the figures more than the code does), so flags stay live. The Zap build runs the cartridge's
60 frames a second with little to spare.

## Widescreen over the whole route

Measured on the old route keyed by frame, which left the game after Jungle Hijinxs (above).

The 148,400 frames of the TAS played `--wide --wide-native-logic` (about 35 minutes): every frame's
work RAM and native picture match Mesen 2 (the wide drawing disturbs nothing). By the level's source
(the map's bank and address, the metatiles' address, `--wide-hashes`'s fourth field):

- Jungle Hijinxs, `d90000a3c0`: 80,020 frames, 73,753 drawn wide; the 6,267 centred are its fades and
  iris (forced blank, mosaic).
- Kong's Banana Hoard cave, `da0000bf00`: 12,626 frames, all centred: a fixed screen whose camera
  range is shorter than the margins, as DKC1Recomp's notes say it stays.
- Outside a level, 55,730 frames (logos, menus, the map, the intro and other fixed screens): centred.

This route reaches no water, vertical or moving-margin level (those sources never occur in it), so
their calibration (both layouts, both coordinate keys, 7 tiles in 10) is not exercised and not
proven: where it fails the scene is centred, never wrong. They need a route that reaches them.
`--shots-at f,f --shots-dir dir` saved a wide frame in each stretch; looked at, the margins carry
the terrain, the parallax and the sprites across the seam.
