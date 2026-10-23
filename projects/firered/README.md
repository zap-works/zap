# Pokemon FireRed recompiled into native Zap

The cartridge's ARM and Thumb code translated ahead of time into Zap (`prepare.zap`), built into
one executable with the GBA's hardware written in Zap on the engine (`gba/`). It needs your own
Pokemon FireRed (USA) cartridge dump at `projects/firered/rom/firered.gba`, never committed, read
once by `prepare.zap`, which writes the game's code into `recomp/` and its data into `assets/`
(out of git); the game then plays without the ROM.

    zap run projects/firered/main.zap                                 the arrows move, Z is A, X is B, Enter
                                                                      Start, Backspace Select, A and S the shoulders
    zap run projects/firered/main.zap --frames 2400 --hash --headless   the title screen's hash, no window
    zap run projects/firered/main.zap --frames 2400 --shot title.png    the frame saved
    zap run projects/firered/main.zap --uncapped                        as fast as it runs

## State

From the dump it reaches the title screen headless (frame 2400) and, with scripted keys, the
player's room; EWRAM, VRAM, palette and OAM match mGBA's up to VBlank 1000. About 270 fps
uncapped, 25 MB running, 100 s and 2.3 GB to compile its generated code. Set aside at this
state; its layers are drawn on the CPU because one function cannot yet serve the CPU and the GPU
(the root TODO.md, "Set aside").
