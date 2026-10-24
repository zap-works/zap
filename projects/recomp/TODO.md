# TODO: recomp


1. Whole-game runs for Zelda and DKC. No USA Zelda movie syncs in Mesen 2 (TASVideos' are Snes9x
   1.43); zelda3's reference saves (snesrev/zelda3, 13 chapters, input logs; chapter 1 from
   power-on) can drive it once each input is anchored to the game's state changes, since zelda3
   counts the polyhedral cutscenes' frames its own way. DKC: 3415M (101%, BizHawk) through
   tools/bk2route.zap.
2. Speed: SMW natively 8.1 ms a frame on the arm64 host (Neoverse N1), 9.2 ms wide at 486 in
   Yoshi's Island 1; the S26 is about 3.3 times faster. Left: lines drawn whole when nothing
   changes mid-line, the fetch a column at a time instead of a dot, the margins' pixels a tile row
   at a time instead of a hook call each, hashing only when asked.
3. Coprocessors: the DSP-1 is rewritten in Zap, every command (console/dsp1.zap,
   dsp1commands.zap; the firmware only as the test's oracle); DSP-2 to DSP-4 and ST010/011 run from the player's
   firmware (tools/gather.zap brings it into rom/); SA-1 (Super Mario RPG: a second 65816, its own
   translation) and SuperFX are not modelled.
4. Generic widescreen in all scenes repeats or blanks what the tilemaps do not hold; a game's hooks
   (dkc's) do better where they exist.
5. Memory: lineMain, mainColor, subColor, mainPrio, subPrio, tileEntry, tileChr, dspRegs, necRam
   and the like are `i64[]` holding bytes and 15-bit colours (eight times their size): `u8[]` and
   `u16[]` now that fmt drops the redundant casts. Flat tables indexed by hand
   (`windowMask[layer * 256 + x]`, `tileChr[4 * columns * 4]`, x64's `xmm[2 * r]`) as fixed
   arrays of two dimensions (`bool[6, 256]`, `a[layer, x]`, spec 3.5), or `Grid<T>` where the
   size is the picture's.
6. Phones: the apps not yet seen on the S26 since the performance hints, the sound feed's lead and
   the pacing to the clock (smoothness, sound, the tearing the player saw before them); the
   pictures paced by the display (AChoreographer) instead of the clock, between the cartridge's
   60.1 and the screen's 60 or 120 Hz; 120 fps (interpolation) measured there.
7. Phones: the picture drawn by the GPU (Vulkan) with the look's filters as shaders (xBR, CRT)
   in place of touch/look.zap's CPU work, which keeps the zoom at 3 (4 cost 16.5 ms a frame on the
   S26).
