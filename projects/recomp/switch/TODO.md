# recomp.switch: what is left

The plan is by slices of the game, each made right before the next: slice 1 is the start, from
the boot to leaving the Shrine of Resurrection (README.md says what runs).

## The whole build's time

A cold build of the whole game takes 25 minutes (README.md: 35 processor-seconds a part, nearly
all the IR passes; a warm one about a minute, an unchanged part 0.03 s). Left:
0. The whole cold build (25 minutes) against its batches (four cold parts 17 s, nine minutes
   projected): the likely cause is the machine, a four-core notebook that holds turbo clocks for
   a batch and not for 25 minutes of full load (not main.zap's loop: eight parts cold took 60 s
   through it and 52 s by a plain loop; not the translator, 116 MB; late parts cost the same as
   early ones). Confirm by sampling the processor clock during a run; measure on a desktop. The
   caches a part writes are still worth cutting: a 60 MB kept stage of its own module (pointless
   for a part the stamp keeps whole) and a 48 MB IR shard, 14 GB a build, 17 GB in build/cache.
1. The passes' cost per part: what of a translated function's form (one `match` of hundreds of
   integer arms over straight-line arms of u64 arithmetic) the passes spend their rounds on,
   measured with the compiler's pass counters, then the pass or the form changed so a cold part
   costs a few processor-seconds (root TODO.md step 2 has the settle rounds).
2. Fewer lines per guest instruction (1.8 now): a compare fused with its branch where the flags
   are dead; direct calls between parts in place of a search by address.

## Slice 1: the start

1. Boot and loading screens right. The whole build (all functions, in parts) loads and runs:
   `lockstep` in ZAP_RUN (cpu/lockstep.zap: each translated function the dispatcher enters run
   again on the interpreter from the same state, stores journaled) finds no difference in turns
   0-100 nor 250-257, so the translation is not what goes wrong first. The game boots slowly in
   guest time (a turn is 1/60 s, 16 million instructions): the Yaz0 streaming decompressor
   (main 0x91ee754, fed 128 KB at a time by a loader thread through a message queue) and a
   dedup of 48-byte records by memcmp against every earlier one (main 0x8b4eb44) take most of
   the first 1,000 turns; the first SUBMIT_GPFIFO comes after that, and its CLEAR_SURFACE has
   render target registers that ask for gigabytes (maxwell/clear.zap notes and skips a clear
   over 256 MB). Next: read the first submit's methods (`--calls`: each svc with its call chain,
   `turn n` markers, the log streamed, the live threads' registers and frames at the end; the
   pc sampled at each turn's end), find why the render target is garbage (the macro that sets
   it, or the registers the game wrote), then the profiled build's garbage at frame 3,233
   (`00000270 22905202`). Tools: tools/names.zap names sdk addresses by .dynsym; tools/dump.zap
   writes guest code for an outside disassembler (capstone); tools/romat.zap names the RomFS
   file at an image offset.
2. Eden as the oracle (done on Windows): Eden 0.2.1 (C:/tools/eden/eden, portable, the user's
   keys, outside the repository) runs BotW 1.0.0 headless with the null renderer and a fixed
   RNG seed, so its layout is the same every run; this recompiler lays a game out as it does
   (modules packed from 0x8000000, Horizon's 36-bit regions in svcGetInfo, the main stack 9 pages
   past the modules). tools/edenstop.zap stops Eden at an address through its gdb stub
   (oracle/remote.zap: GDB's remote protocol in Zap) and prints the registers and memory;
   tools/run.zap --at <hex> [--hit n] [--memory a,n] stops the interpreter at the same place and
   prints the same. At the first svcQueryMemory of the sdk (0xad08a20) both agree but for the
   registers that hold leftovers of the random entropy (svcGetInfo 11). Left: frames from Eden
   (its Vulkan window fails with SDL's offscreen driver), and the entropy matched to compare
   further.
3. The title screen, its logo and "Press any button", answering the pad.
4. A new game: the waking in the Shrine, with its sound.
5. Control in the Shrine, by touch and pad, to the Sheikah Slate and out of the door.
Each right on Windows headless (shots against the oracle), then on the zap37 emulator.

## 1. Extraction

1. the APK packs what the game reads from rom/ (step 5's work); BotW's updates (1.8.2) need
   the update NSP, which the user does not have.

## 2. AArch64 translation

1. the whole translation run on the phone: part 36 built for arm64 (root TODO.md, Compiler 1),
   the parts pushed to the app's files by adb with the ExeFS and loaded there; the 258 unresolved
   tables; forms for the rest of the common
   operations (bitfield, FP); the calls between parts through a search.

## 3. Horizon HLE

1. whatever the game asks next; the 3D renderer.

## 4. GPU

1. What Zap's GPU code lacks, each with the instructions that need it (the translation notes the
   instruction and writes zeros, or does as said):
   - Texel fetch (TLD, TLDS: integer coordinates and a level, no sampler): written as `sampleLevel`
     at the texel's centre after a `size` query; exact inside the texture with nearest or linear
     filtering, but outside it the sampler's wrap answers where a fetch gives 0.
   - 1D, 3D, cube and multisampled textures (TEX/TEXS/TLD4/TMML/TXD types 0, 1, 4-7, TEXS encodings
     0 and 10-13, TLDS's): BotW's 21 TEX left are 3D (17, with offsets, at a level) and cube arrays
     (4), its 5 TEXS cubes at a level.
   - A compare at a level or with a bias (TEX.DC with LL/LB, TEXS 2D.LL.DC): Zap's `compare` reads
     a shadow map's first level, so TEX.DC and TEX.DC.LZ translate and these do not.
   - A lod clamp (TEX.LC, TXD.LC; yuzu has none either), per-texel gather offsets (TLD4.PTP), the
     level count (TXQ's fourth component), TMML's third and fourth results, f16 results (TEXS, TLDS,
     TLD4S), sparse results.
   - Offsets the code does not show: Zap's offsets are constants of -8 to 7 (`IVec2(x, y)`), so a
     TEX/TLD4/TXD.AOFFI translates when a MOV32I or MOV of an immediate in the same block gave the
     register (TLD4's six-bit offsets only inside that range).
   - Integer textures (a TEX or TLD of an R32UI texture reads integers; Zap samples Vec4 floats, and
     has no IVec4/UVec4).
   - Images (SULD, SUST, SURED, SUATOM: storage images by integer coordinates, and their atomics).
   - Bindless handles the code does not show (TEX.B, TLD4.B, TXD.B, TMML.B: a handle register not
     loaded from a constant buffer word in the same block; TLD.B, TXQ.B); `Texture[]` indexes
     textures with their own samplers, so a computed handle also needs separate sampler arrays.
   - f64 (DADD, DMUL, DFMA, DMNMX, DSET, DSETP, F2F/F2I/I2F of f64, MUFU.RCP64H/RSQ64H).
   - Global memory (LDG, STG, LD, ST, ATOM, RED: a 64-bit address; Zap has bound storage buffers):
     deko3d's sinewave compute program writes through one.
   - Tessellation and geometry stages (ISBERD, OUT, AL2P, ALD/AST of patches).
   - A vertex stage's number beside its attributes (ALD of attribute 191 when generic ones are read:
     Zap's vertex stage takes one or the other), and outputs other than the position and generic
     attributes (AST of point size, clip distances, layer, viewport).
   - A pixel stage's front face (IPA of attribute 255), flat and linear float inputs (SPH modes
     constant and linear: translated as perspective), IPA's centroid, sample and offset modes, and
     its sample mask output. Its colors and depth translate as yuzu's ExitFragment reads them (each
     target that writes a component four registers from r0, the depth the second register after
     them) into `Targets<name>`'s `targetN` fields, so a stage writing target 5 alone writes it.

2. condition codes (CC, .X: IADD.CC/IADD.X pairs, BRA by a condition),
   indirect and call flow (BRX, JMX, CAL, RET), a jump to an outer if's end or an outer loop (no
   labelled break: the program is left out), rounding modes other than nearest-even, IADD.SAT,
   IADD3.RS, I2I.SAT, IMNMX's extended modes, XMAD.CSFU, P2R/R2P of condition codes or by a register,
   IMAD, IMUL, LEA, PRMT, half floats (HADD2, HMUL2, HFMA2, HSET2, HSETP2), SHFL and VOTE (Zap has
   `laneAt`, `laneAll`), special registers but the lane and the thread and group ids. The renderer
   (not written) must give the depth range the game set (the compiler maps z from -1..1 to 0..1,
   spec 11), the y direction, the vertex formats as Vec4 floats, constant buffer banks and texture
   handles as above.

3. nothing reads the pools or the program bytes through the DrawCall yet (a renderer fetches TIC/TSC
   entries by handle from the texture constant buffer); geometry's viewport index, stencil, logic ops, color
   masks, transform feedback, indirect and instanced-by-macro draws are not decoded; a tessellation or
   geometry program is recorded but not translated.

## 5. Audio and controls

1. the window run itself is not tried on a phone (the overlay is drawn on the CPU image, not on
   the GPU picture), the touch points carry no multi-finger identity across frames (a finger's index
   in the list), and the opacity and per-control sizes have no menu.
