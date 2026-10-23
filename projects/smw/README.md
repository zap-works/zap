# Super Mario World rebuilt in Zap

Super Mario World (Nintendo, 1990, SNES, the USA cartridge) recompiled into native Zap by
`projects/recomp/snes` from the player's own dump: `projects/recomp/snes/rom/smw.sfc` (sha256
`0838e531fe22c077528febe14cb3ff7c492f1f5fa8de354192bdff7137c27f5b`), never committed, nor anything
taken from it (`.gitignore`: `*.sfc`, `projects/smw/recomp/`).

The game runs as recomp.snes runs any cartridge (its README): the 65816 code translated ahead of
time, the SNES written in Zap, every frame's picture and work RAM Mesen 2's. What this project
adds is a real widescreen: the level's terrain and sprites in the margins of a picture up to 512
pixels wide (a phone's 486x224), where the generic wide drawing (`--wide-scenes all`) can only show
what the PPU's tilemaps hold past the view, stale or empty columns at a level's start.

What the community has, and what is taken from it (read, nothing copied):

- **snesrev/smw** (github.com/snesrev/smw, a C port of the game): the names and addresses of the
  routines and tables used here (the column streamers, the Map16 pointers, GetDrawInfo,
  SubOffscreen, the sprite spawner) and the level's layout in work RAM. Its widescreen is the
  PPU's extra columns alone; the cartridge's windows are not widened there.
- **SMWCentral's RAM and ROM maps**: the variables (`$1A` the camera, `$5B` the layout, `$5D` the
  screens, `$1925` the level mode, `$1931` the tileset, `$0FBE` the Map16 pointers, `$7EC800` and
  `$7FC800` the level's blocks).

## Run

From the repository root:

- `zap run projects/smw/main.zap`: prepares once (`prepare.zap`, into `recomp/`), builds
  `build/smw.exe`, plays (Enter is Start, the arrows move, Z is B, X is A, A is Y).
- `zap run projects/smw/main.zap --wide --wide-width 486`: the widescreen in a window;
  `--headless --frames n --shot x.png` or `--shots-at f,f --shots-dir dir` saves pictures, and
  `--wide-hashes out.txt` a line per frame (frame, hash, wide or not, the scene: level mode and
  level, why it is centred).
- `zap run projects/smw/main.zap --android <dir> [--target android-x64]`: `smw.apk` and
  `smw-wide.apk` (the widescreen as wide as the screen's shape), the dump inside each
  (recomp.snes's `releaseApps`).

## Layout

- `cartridge/`: the dump's check, the `snes.Game` (its tables, its setup line installing the
  widescreen) and the widescreen's patches (`patches.zap`).
- `tables/played.cfg`: the targets of the cartridge's two pointer dispatchers ($00:86F7 and
  $00:871B) Mesen 2 saw over `tests/routes/yi1.txt` (`zap run projects/recomp/snes/main.zap
  projects/recomp/snes/rom/smw.sfc --tables projects/smw/tables --mesen 5000 --route
  projects/smw/tests/routes/yi1.txt`): with them the flow finds some 770 functions, the sprite
  routines the patches change among them; the rest runs in recomp.snes's interpreter.
- `wide/`: the scene's judge (`scene.zap`), the level map's decode (`level.zap`), the widened
  sprite windows' helpers (`sprites.zap`).
- `tests/`: `routes.zap` (native play and wide drawing with native logic against Mesen 2, the
  random route recomp.snes keeps and `routes/yi1.txt`, a new game into Yoshi's Island 1 with
  Mesen's hashes beside it), `wide.zap` (the wide picture's baseline over that route).

## Widescreen

- The judge (fail-closed), at the end of line 0: game mode $14 (a level), mode 1 drawing at low
  resolution with no mosaic, layer 1 a level's (its level mode streams it), the decode of the
  native viewport matching the live BG1 tilemap (7 in 10, every other tile), and the level
  wider than the picture and scrolling ($1411). Anything else, the title, the map, Yoshi's house
  (a screen that does not scroll), fades, is the native frame centred on black.
- The margins: BG1, and BG2 where the level mode streams level blocks into it (the layer-2
  levels), are decoded from the level's blocks in work RAM through the cartridge's own tables
  (`level.zap`): the screen lists at $00:BDA8 and $00:BDE8, the streamers at $05:8823 and
  $05:888C (which says a layer is horizontal, vertical, a background or still), a block's four
  tilemap entries through $0FBE in bank $0D, the pipes' colours by screen ($05:8776). A
  background layer 2 and layer 3 come from their own tilemaps: SMW keeps a background's whole
  512-pixel period in VRAM.
- The edges: the picture is pinned inside the level (`console.edgeBias`, as a camera as wide as the
  picture would be), so nothing past its first or last screen shows.
- Sprites: GetDrawInfo's window ($40 left, $180 wide) widened in banks 01, 02 and 03; the horizontal
  edges SubOffscreen erases at, from its byte tables, moved out by the margins in the three banks;
  the spawner's column ($02:A802, -$30 and +$120 from the camera) moved out the same, in horizontal
  levels. FinishOAMWrite already sets the 9th bit of x for a tile past either edge, so a sprite in
  the margin is drawn whole. With the windows widened sprites spawn earlier than natively, so a
  wide run's work RAM is not Mesen's, by design; `--wide-native-logic` keeps them native.
- Shots: `tests/wide.zap`'s route at 486 wide shows Yoshi's Island 1 with the ground, the hills and
  the sprites (Banzai Bill, Rexes, coins) across both margins, the level's start pinned at the
  left edge.
