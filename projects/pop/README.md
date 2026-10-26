# Prince of Persia (DOS v1.4) in Zap

Prince of Persia as the DOS game v1.4 plays, written in Zap on the engine from the player's own
game files (never committed), its logic SDLPoP's ported routine by routine and checked frame by
frame against a headless SDLPoP. `zap run projects/pop/main.zap` plays it.

## Layout

- `projects/dos/pop/`: readers of the player's own files (never committed): `dat.zap` (DAT
  archives), `image.zap` (pictures and sprite tables), `level.zap` (LEVELS.DAT), `exe.zap`
  (PRINCE.EXE's data segment: sequence table, frame tables, sword table, tile tables, font),
  `sound.zap` (the sound DATs: speaker, digitized, MIDI), `midi.zap` (the MIDI tunes on the
  synthesizer, SDLPoP's midi.c).
- `projects/dos/opl3.zap`: the OPL3 FM synthesizer (Nuked OPL3's two-operator paths); the
  music renders sample for sample as SDLPoP's (checked on the presentation, title, death and
  Jaffar tunes).
- `projects/pop/game/`: the game, SDLPoP's `seg000.c`..`seg008.c` ported routine by routine,
  each file naming the segment it ports.
- `main.zap` plays (title, demo, levels, cutscenes, ending); `check.zap` plays headless along a
  key route and prints each frame's state (`--show title|ending|expired|cutsceneN` runs a show a
  tick a frame); `inspect.zap` dumps the sprite sheets and level maps.
- The title, the cutscenes, the time's end and the ending are scripts of steps (`show.zap`,
  `scenes.zap`) run a tick at a time: the original's blocking loops (waits, fades, transitions,
  `proc_cutscene_frame`) unrolled.

## Authority and choices

- SDLPoP decides the DOS behaviour, with its `fixes` off and every unconditional `#ifdef FIX_`
  block left out (the original's bugs kept), its `custom` options at their defaults, and none of
  its additions (fake tiles, teleports, super high jump, jump grab, coloured torches, lighting).
- v1.4's data addresses are SDLPoP's v1.0 ones plus 0x10C in the sequence and frame tables;
  further on the shift grows (the VGA palette is at 0x2CBE, not 0x2BA6 + 0x10C).
- The screen is composed as SDLPoP composes it: a 192-line picture off the display (200 for the
  title and the cutscenes after an ending), the tables drawn onto it, the dirty rectangles copied
  to the 320x200 display, the DAC's 256 colours for the monochrome blits and rectangles.
- Sounds last a number of ticks of 60 a second: digitized ones their samples, speaker tunes their
  notes, MIDI tunes their longest track at its tempos; the game waits on them as it waits on the
  real playback.
- SDLPoP's defaults kept: no copy protection (the potions level 15 is not entered after level
  1), the hall of fame kept in memory (no PRINCE.HOF written).

## Oracle

A headless SDLPoP built from its source with the same choices (scratchpad, not committed):
`oracle.exe --level N --frames F --keys "right@10-40,shift@50" --seed S --out DIR` prints the
lines `check.zap` prints (sequence addresses there are v1.0's: 0x10C less) and saves each
frame's display. Compared frame by frame (`cmp.py`, `fuzz.py` with random key routes on every
level), state and pixels agree on every route tried. It skips the cutscenes, so runs that cross
levels are compared within a level.

## SDLPoP's saves, replays and options (ported)

- `game/saveState.zap` (quick_process bytes, sequence addresses shifted 0x10C), `keys.zap`
  (process_key, pause, F6/F9 quicksave, Ctrl+G/Ctrl+L PRINCE.SAV, cheats with `cheatsEnabled`),
  `replay.zap` (.p1r record and play, Tab cycles the replays folder), `hof.zap` (PRINCE.HOF),
  `copyProt.zap` (potions level when enable_copyprot), `options.zap` (SDLPoP.ini by option name,
  replay option sections). Files go under `Game.saveDir` (`--save-dir`, `--ini dir`, `--record`,
  `--replay`, `--cheats` of check.zap). `tests.zap` holds the self-checks.
- Checked against an SDLPoP oracle built with replay, quicksave and copyProt (scratchpad, not
  committed): replays recorded there play frame-exact here, ours are byte-equal in savestate,
  options and moves; F6/F9, restart, Shift+L, copy protection and changed custom options agree.
- The pause menu (`game/menu.zap`, `menuSettings.zap`, `menuDraw.zap`; `menuTable.zap` and
  `menuFont.zap` are generated from SDLPoP's menu.c): Esc and Backspace open it, keyboard only; the
  pause menu, the settings the options have (general, gameplay, mods) and the two confirmations.
  F and Shift+F skip a replay to the next room or level; stopping a recording asks the file name in
  SDLPoP's dialog (`inputStr.zap`); the custom options are all read where SDLPoP reads them.
- The `fix_*` and enhancement flags are read and written under SDLPoP.ini's names and change nothing
  (the fixes stay off).
- The menu is whole: the mouse (hover, click, right button back, wheel), all six settings pages
  (General, Gameplay, Visuals, Mods, Controls, and a level's after "Customize level..."), the key
  redefinition, the restore and quit dialogs. Settings changed in it are written to `SDLPoP.cfg` when
  the menu closes and read over SDLPoP.ini's unless the ini is newer. The cfg is this port's text
  (`name = numbers`), not SDLPoP's struct dump, which only its own executable's checksum accepts; the
  key settings hold the engine's virtual-key codes, not SDL scancodes. `use_custom_options` off puts
  `custom` at the defaults and keeps the values (custom_saved), also from the ini and the cfg.
- Ctrl is an engine key, so Ctrl+A, G, J, K, L, R, S, V and Ctrl+Tab reach `process_key`; T with the
  cheats shows the time over the game (draw_overlay's overlay 1), and the ticks in a replay.
- The layer blend is SDL2's ALPHA_BLEND_RGBA (SDL_blit.h) as BlitNtoNPixelAlpha (SDL_blit_A.c) uses
  it for the 24-bit merged surface: `dst + (src - dst) * a / 255`, truncating toward zero (read from
  SDL 2.30's source, not the single `(src*a + dst*(255-a))/255` form, which rounds differently).
