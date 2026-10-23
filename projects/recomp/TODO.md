# TODO: recomp


1. Whole-game runs for Zelda and DKC. No USA Zelda movie syncs in Mesen 2 (TASVideos' are Snes9x
   1.43); zelda3's reference saves (snesrev/zelda3, 13 chapters, input logs; chapter 1 from
   power-on) can drive it once each input is anchored to the game's state changes, since zelda3
   counts the polyhedral cutscenes' frames its own way. DKC: 3415M (101%, BizHawk) through
   tools/bk2route.zap.
2. Speed: the build runs some 140 frames a second headless; a profile, then lines drawn whole
   when nothing changes mid-line, decoded tiles cached, hashing only when asked.
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
