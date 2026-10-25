# recomp: static recompilers in Zap

A game's machine code translated ahead of time into Zap functions and built into one executable
with the machine written in Zap on the engine, checked frame by frame against an emulator.
Nothing of any game is in the repository; a game is the player's own dump. The parts:

- `snes/`: any SNES cartridge (below); `projects/dkc` and `projects/smw` are games on it.
- `x64/`: a Windows x86-64 executable's functions run in an emulator, one instruction at a time
  (`tools/x64run.zap <exe> <function> <args>` prints what one returns), to diff a port's math
  against the original's (projects/skyrim).
- `touch/`: a console's picture with touch controls over it for a phone: the picture scaled by a
  whole number into a frame of the screen's shape, a stick, the buttons, PAD and MENU.
- `tools/decompinfo.zap`: what a decompiler's export says of a function.

## recomp.snes: any SNES cartridge recompiled into native Zap

A cartridge's 65816 code translated ahead of time into Zap functions, built into one executable
with the SNES written in Zap on the engine, and checked frame by frame against Mesen 2 (2.1.1,
the version winget installs). Nothing of any game is in the repository (`.gitignore`: `rom/`,
`out/`); a game is the player's own dump.

    zap run projects/recomp/snes/main.zap <rom.sfc|.smc> [--out <dir>] [--tables <dir>] [--mesen N [--route f]] [--build | --release <dir>]
    zap run projects/recomp/snes/check.zap <rom> <frames> [--seed n] [--every n]

- `main.zap` writes `out/<name>/<name>.zap` (a program) and its module `game/`; `--build` builds
  `build/<name>.exe`; `--release dir` builds two binaries into dir, `<name>.exe` as the cartridge
  draws it and `<name>-wide.exe` with the widescreen on by default; each finds the player's dump
  beside it (or `--rom`), `--native` turns the presets off.
- `--tables` names per-bank cfg files (DKC1Recomp's form) that seed the flow; none are needed:
  the flow starts at the vectors and the interpreter runs whatever the translation did not see.
  `--mesen N` plays N frames in Mesen 2 to find where the jumps through memory go, so more of the
  game is translated (speed only, never correctness).
- `check.zap` plays a seeded random route in the build and in Mesen 2 and compares every frame's
  picture and work RAM; `--every n` hashes Mesen's every n-th frame (twice as fast at 10).
- The program's options (console/screen.zap): `--headless`, `--frames`, `--route`, `--hashes`,
  `--shot`, `--memory`, `--wide [--wide-scenes all]`, `--interpret` (no translated code: the
  interpreter's check), `--trace`, `--steps`, `--writes 2100-21FF [--writes-from f]`,
  `--save-at N file` (a save state at frame N's end, any number) and `--load file`; in a window
  F5 saves `<dump's stem>.state` beside the dump and F7 loads it.

### Layout


- `snes/`: the recompiler. Decoder table, assembler, the flow from the cfg's entries or the
  vectors (the interrupt vectors in every widths, since an interrupt keeps M and X), the
  translation of each function (`emit*.zap`), the interpreter's functions written by the same
  translation (`interpret.zap`: every opcode in every widths, its operand and address variables),
  `game.zap` (`Game`, `Patch`), `project.zap` (what a game project's entry files share: the dump
  checked, prepared, built and run), `write.zap`.
- `cartridge/`: dump reading (a copier header dropped), header, LoROM/HiROM map, region.
- `console/`: the SNES as Mesen 2 runs it: memory map (a page table of 8 KB pages,
  engine.memorymap), PPU (modes 0-7, mosaic, windows, colour math, high resolution), DMA/HDMA, the
  multiplier and divider a step a cycle (`alu.zap`), the open bus, joypads, H/V timer, NTSC and PAL
  (`region.zap`), SPC700 and DSP, the screen and sound,
  widescreen (`wide.zap`: by the PPU alone for any game, or a game's hooks and the helpers they
  share), presets.
- `cpu/`: registers and the translated code's calls; interrupts (handlers entered in the widths of
  the code they stop; a return elsewhere, a task switch, unwinds and goes on there, as a loaded
  save state does: `savestate.zap` beside console/'s, `requestSave`/`requestLoad`), brk and cop,
  `interpret.zap` (the loop over the interpreter's functions, handing over to a translated function
  wherever one starts in the code's widths).
- `mesen/`, `tools/oracle.lua`: Mesen 2 headless; modes hashes, wram, screen, writes, ports,
  trace, played. `compare.zap`. `tools/bk2route` turns a BizHawk movie into a route by joypad reads.
- `tests/games.zap`: SMW and Zelda prepared by the tool alone (no tables) play 3,000 frames of a
  random route as Mesen 2 does, translated and, for SMW, interpreted whole. `tests/savestates.zap`:
  DKC and SMW saved at their title and in a level, each state loaded plays on as the run that saved
  it, translated and interpreted.

### State


Checked against Mesen 2 frame by frame (picture and the first 8 KB of work RAM):

| Game | Route | Result |
|---|---|---|
| Super Mario World (USA) | 20,000 frames of random input | every frame equal |
| Zelda: A Link to the Past (USA) | 20,000 frames of random input | every frame equal |
| Donkey Kong Country (USA), the tool alone, no tables | 20,000 frames of random input | every frame equal |
| DKC (its project, community tables) | title, jungle, TAS 8,000 | every frame equal, translated and interpreted whole |
| Aladdin (USA) | 20,000 frames of random input | every frame equal |
| Street Fighter II Turbo (E, PAL) | 20,000 frames of random input | every frame equal |
| Super Mario Kart (DSP-1), the chip rewritten (no firmware) | 20,000 frames of menus; a 12,000-frame route into a race | every frame equal |
| Super Mario RPG | | not run: SA-1 is not modelled |

Whole-game TAS runs (TASVideos, inputs only): SMW "96 exits" (6738M, BizHawk, keyed by joypad
reads) and Zelda (1269M, Snes9x 1.43, whose movie records only the frames that read the joypads,
so it is the polls form as it is). The Zelda movie desyncs in Mesen 2 in its first minutes (Link
turns back with the lamp): its run is still a valid comparison, but covers little of the game.
Zelda: 288,000 frames, every frame equal. SMW: 292,000 frames, every frame equal.

Released binaries (`--release`, the tool alone, no tables): smw, zelda and dkcg, each original and
widescreen. The originals, run from the release dir with the dump beside them, equal Mesen 2 on
20,000 random frames; the widescreen ones run the same routes with the margins drawn.

Android: `main.zap <rom> --android dir` writes `<name>.apk` and `<name>-wide.apk` for a phone
(arm64; `--target android-x64` for the emulator zap37), each carrying the player's dump (copied
into the app's files dir at its first start), so the device needs nothing else; made from the
player's own dump, never committed. DKC on the emulator plays as Mesen 2 does (headless: title
900, jungle 3,700 and TAS 8,000 frames equal), and plays on an arm64 phone. On a phone the picture
is scaled three times into a frame of the screen's shape with touch controls over it
(projects/recomp/touch: a stick, the SNES buttons, PAD hiding them, MENU pausing the game), a game
pad or the keyboard also read; AAudio's sound, battery RAM kept in dkcg.srm, Back ending it.
