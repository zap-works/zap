# Lemmings (DOS) in Zap

DOS Lemmings rebuilt in Zap on the engine, its mechanics Lemmix's, from the player's own game
files (never committed), checked frame by frame against the DOS game run in BizHawk's DOSBox-X
core on a hidden desktop. `projects/dos/lemmings/` reads the game's files, `game/` is the game,
`main.zap` plays it (`zap run projects/lemmings/main.zap`), `compare.zap` runs the oracle and
compares, `tools/` drives the emulator.

## State

- Mechanics are Lemmix's (src/Game.pas). Checked frame by frame against the DOS game: Just Dig
  with no skills matches for 1200 iterations, and with `digger@123` it matches for 708 iterations,
  up to the level's end. Fixes from the oracle:
  - walking and jumping lemmings that face left use their own animations (2 and 3);
  - lemming sprites use the level's palette (colour 7);
  - looping objects start two frames on;
  - the digger's row keeps pixels 0, 4 and 8 on screen for one more iteration
    (`World.lingering`);
  - the pace is 1193182/16384/5 iterations a second;
  - a fall of 60 pixels kills (`maxFallDistance` 59);
  - a piece flagged both no-overwrite and erase draws like a no-overwrite one (Taxing 1's pillar).
  Tricky 1, Taxing 1 and Mayhem 1 (codes from the Lemmings Archive's list, `levelKeys` now presses
  F1 after the code) match for 600 iterations. The one difference left is a lemming walking
  through the view's last column (319): the DOS game draws other pixels of it than this build.
- Oracle: `tools/oracle.zap` and `tools/oracle.lua`. They run BizHawk 2.11's DOSBox-X core
  (`winget install TASEmulators.BizHawk`) on a hidden desktop (`win.runHidden`), booted from
  a FAT12 image of the install (`tools/floppy.zap`). The Lua script drives the mouse from memory:
  - the cursor is at 0x125E0 and 0x125E2;
  - the iteration counter is the byte at 0x12622;
  - the AdLib driver is found by its signature, and its songs and effects are logged.
- `compare.zap` does the comparison:
  - it aligns the two runs by content (offset -1);
  - it turns a `--route` into clicks;
  - it blanks the cursor's span;
  - it prints the first iteration that differs and writes first-dos.png, first-zap.png and
    first-diff.png.
- Screens (`game/screens.zap`, `dos/lemmings/menuDat.zap`): the menu, preview and result screens
  are drawn at 640x350 and shown at 3x. They use main.dat's sections 3 and 4. Checked against the
  oracle's shots by eye: the menu's signs sit 4 pixels left of Lemmix's, its footer is the
  copyright text, the preview shows the level at a quarter size over the lines 32 rows apart,
  and the result's buttons' lines are one row up. The menu's scrolling credits are not checked.
- Sound:
  - `dos/lemmings/adlib.zap` is adlib.dat's Sound Images driver, ported from its disassembly.
    It covers songs 1 to 21, effects 1 to 18, a tick at 72.8 Hz, and `render(n)`.
  - `dos/opl2.zap` is an OPL2 ported from Nuked OPL3 1.8. The PoP branch's `opl3.zap` (1.7.4)
    plays the same data but its envelopes attack about half as fast and it ignores register
    0xBD's depth bits, so it was not adopted.
  - `main.zap` plays them through an `audio.Feed`.
  - `game/sound.zap` (`effectOf`) has the numbers the oracle's log ("effect N iteration I") gave:
    skill button 1, entrance 2, let's go 3, assigning a skill 4, oh no 5, splat 8, steel 10,
    explosion 12, vaporizing 13, yippee 16, drowning 17, the builder's warning 18 (the traps carry
    their own numbers, 6 to 15). A failed assignment makes no sound in DOS (a skill on a lemming
    facing steel); the steel sound is the digger's, and the basher's and miner's when they run into
    steel (the latter two not yet seen in the oracle).
  - The song order `(rating*30+number)%21+1` is Lemmix's guess.
- Level codes: `dos/lemmings/levelCode.zap` is Lemmini's LevelCode (Herman Perk's analysis of the
  DOS scheme: seed AJHLDHBBCJ, the level, the percent saved, a "magic"). 118 of the 119 codes of
  deveria.com's list come out of it (the list's own codes carry magic 0, 1, 5 or 64; the DOS game
  accepts magic 0). The one that does not, Mayhem 18 `JONHGMNMIP`, is a typo of the list: the
  scheme gives `JOLIGMNMIP` for 93%, two letters apart. The result screen shows the next level's code, `compare.zap` types it into
  the DOS game's F2 screen.
- What the oracle taught beyond the first levels (all in `game/` and `dos/lemmings/`):
  - one-way arrows are drawn in colour 5 and animate (they are objects drawn only on terrain,
    now drawn each iteration where the terrain is);
  - with two entrances the lemmings come out of 0, 1, 1, 0;
  - a click hits a lemming whose box starts 5 left of its x, 12 by 12, and the highest numbered
    one wins; a bomber's digit is the palette's colour 3 and counts from 78; its crater goes on
    the terrain when the exploder is handled, stays on the screen one iteration more
    (`World.lingering`), and its particles are Lemmix's table (`dos/lemmings/particles.zap`: 51
    frames of 80 pixels from the foot, drawn at the exploder's place in the drawing order);
  - the DOS click lands in the iteration asked or the next, by where the emulator's frames fall
    in it, so a run's recipe has two routes: `--route` (the clicks) and `--sim-route` (what this
    build plays, shifted by 0 or 1 per order until the pictures agree).
- Comparison recipes (`zap run projects/lemmings/compare.zap --rating R --level L --route ROUTE
  [--sim-route SIM] --iterations 400`, rating 0 Fun .. 3 Mayhem; the iterations all equal unless
  noted). The view's last two columns are not compared, and the cursor's box (and a margin) is
  blanked:
  - Fun 2 `floater@60`; 3 `blocker@60`; 4 `climber@80 miner@150`; 5 `basher@100`; 7
    `builder@70`; 9 (fire) and 23 (water) no route; 11 `miner@120` (steel);
    6 `bomber@100` sim `bomber@101`;
  - Tricky 2 `digger@80` sim `digger@81`; 3 `builder@70 basher@140` sim `builder@71 basher@141`;
    5 `bomber@100` sim `bomber@101`; 6 `floater@80 climber@120`; 25 (arrows) no route, 150;
    4 `digger@120` (steel; one iteration, 5 pixels of the dug row, differ at 241);
  - Taxing 2 `blocker@80`; 3 `climber@60 builder@110`; 4 `builder@70`; 5 `basher@100`;
  - Mayhem 2 `builder@80 digger@150`; 3 `bomber@40`; 4 `basher@100`;
    5 `floater@60 bomber@100` sim `floater@60 bomber@101`.

## Later levels (levels 10, 15, 20, 25 and 30 of each rating)

Recipes whose pictures match 450 iterations (`--route` / `--sim-route`, one oracle run at a time;
a click lands in the iteration asked or the next, so a sim route may be shifted by one):
- Fun 10 `floater@100 builder@180 basher@260 digger@340`; Fun 20 the same;
- Tricky 15 `bomber@100 bomber@200` sim `bomber@101 bomber@201`; Tricky 20
  `climber@100 digger@180 basher@260 miner@340`; Tricky 30 `climber@100 floater@160 blocker@220
  digger@300` sim blocker@221;
- Taxing 30 `digger@100 digger@200 digger@300`;
- Mayhem 10 `climber@100 builder@180 basher@260 digger@340`; Mayhem 25 `climber@100 builder@180
  floater@260 digger@340`; Mayhem 30 `builder@100 basher@180 digger@260 blocker@340`.

Still different (the first iteration that differs; the recipe is `--route` as listed, sim route in
parentheses):
- Fun 15 `climber@100 bomber@180 miner@260 blocker@340` (bomber@181 miner@261): one stray pixel
  under the roof for two iterations at DOS 295, unexplained;
- Fun 25 (same route and sim) from DOS 263 and Fun 30 `floater@100 builder@180 basher@260
  digger@340` (basher@261) from DOS 263: five lemmings overlap in a pit and the DOS game gives the
  skill to another of them than this build (the last one under the cursor is taken here, as
  Lemmix's `PrioritizedHitTest`); the click box (x: 5 left to 7 right of the lemming, y: 16 to 4
  above its foot) was fitted on a few cases only;
- Tricky 25 `floater@100 builder@180 bomber@260 digger@340` (builder@181 bomber@260) from DOS 183,
  Taxing 10 (from 369), 20 (from 223), 25 (from 343) and Mayhem 20 (from 343): the same, a skill in
  a crowd on stairs; Taxing 10's difference is large (13500 pixels) because the bomber's crater
  then differs;
- Tricky 10 and Mayhem 15 (two entrances): the first 80 pictures do not align with the DOS game
  (offset -8, as Fun 11 had): the entrances open at another iteration than here;
- Taxing 15 (a special level): 13 static pixels at the first iteration (olive, palette colour 4,
  on the terrain's slanted edge) are in the DOS picture and not here.

## Higher resolution and wider views

SuperLemmini (a Lemmini fork) and NeoLemmix keep the mechanics on the original 1x level bitmap:
terrain, the object map and every lemming's position stay integer pixels of the DOS level, so a
route plays the same at any size. The picture is only scaled for the window, by an integer
factor (nearest-neighbour or a smoothing filter), and the skill panel and text are drawn at that
factor. Higher resolution here is therefore the `zoom` of `main.zap`, nothing in `game/`.

The view is widened, not stretched: NeoLemmix shows more of the level as the window grows, and
scrolls the same way, so the camera's width is a parameter of the drawing and of the clamp.
Here that is the view width (`win.width / zoom`, 384 and up) passed to `drawView`; the world stays
1600 wide. A level narrower than the view is centred, and the oracle keeps comparing the 320
columns of the DOS view only.

## Crowd click rule (read from the DOS game's memory)

- `compare.zap --mem "n ..."` and `tools/oracle.lua`'s `dump` keep the DOS memory per iteration;
  `probe.zap` hovers or clicks over a crowd and keeps it; `lemmingsAt.zap` prints this build's
  lemmings. The lemming records are 45 bytes from 75346 (x word at +6, y at +8, action at +2,
  climber +42, floater +43, bomber fuse +38); 0x125E0/2 hold the cursor; the word at 75304 is
  45 * hit index + 136 and the byte at 75315 the number of lemmings under the cursor.
- Over Fun 25's crowd (86 of 99 samples exact) the hit box is: cursor less the lemming's foot
  4 to 8 across and -11 to 1 down (a walker), the last lemming in order winning, the cursor
  point 4 right of and 1 above Lemmix's. `clickLeft`/`clickTop` in game.zap now say so.
- A target off the screen's right edge makes the DOS cursor clamp and scroll the view (a diff of
  some 13000 pixels): `aimAt` now clamps, but recipes must not aim past the view (Fun 25's 4th
  order was dropped for that). The oracle's cursor now leads a click by 2 iterations.
- Fun 25 `climber@100 bomber@180 miner@260` sim `bomber@181` matches 449 iterations. With the
  new box, still different (first iteration, 4-order recipes of the lists above): Fun 30 DOS 263
  (7 pixels), Tricky 25 DOS 183, Taxing 10 DOS 182, Taxing 20 DOS 263 (7 pixels); Taxing 25
  `builder@100 basher@180 bomber@261 builder@340` matches 449; Mayhem 20 not rerun.
