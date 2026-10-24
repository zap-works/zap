# recomp.switch: what is left

The plan is by slices of the game, each made right before the next: slice 1 is the start, from
the boot to leaving the Shrine of Resurrection (README.md says what runs).

## Priority: the whole build's time

Building the whole game takes 26 to 36 minutes when the translation, cpu/core/ or arm64/ changes
(a part kept by its stamp otherwise: README.md); the compiler's side is root TODO.md's step 2, at
its top. This project's side:
1. Fewer lines per guest instruction (2.5 now): a label costs two lines (`label = x`, `continue`:
   15% of all lines), a call six; direct calls between parts in place of a search by address.

## Into main

The branch switch is not in main yet. It has main merged in (as main stood when the work stopped),
the lint's forms applied and its suite passing locally; `zap branch land switch` was stopped
before it ended, by request. The earlier lands failed on the lint of a main that kept moving and
once on memory, with an agent running beside them: land with the machine free.

## Slice 1: the start

1. Boot and loading screens right. The translated code writes wrong guest memory: the whole
   build (all functions, in parts) goes wrong after 4 frames; the profiled build after about
   3,233 frames, when a SUBMIT_GPFIFO of 472 entries has entry 240 as garbage (`00000270
   22905202`, 566,292 words at a low address; the ioctl is read as yuzu reads it). A bisection
   needs both halves of the functions: an interaction (a call between parts, a calling
   convention). Where it stopped: branch switch-lock (worktree zap-wt-switch-lock, a junction
   to rom/) holds cpu/lockstep.zap, finished but never run: `lockstep` in ZAP_RUN runs each
   translated function the dispatcher enters with its stores journaled, undoes them, runs the
   interpreter from the same state and stops at the first register, flag, vector or byte that
   differs (lockstep=n from turn n). Next: check its hooks (cpu/dispatch.zap, frontend/screen.zap)
   compile, rebuild the whole build there (`main.zap <exefs> --name botwall --build --jobs 2`,
   about 36 min; the layout changed, so the old parts are stale), run it with lockstep, fix the
   function it names, add a test, then rerun the profiled build for the GPFIFO garbage.
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

## Android

1. The app reads its input queue only at its frames: a frame of seconds makes Android kill it
   as not responding when touched. A thread of its own fixed it, but used the threads layer's
   Task from the core layer (every program then loaded threads): it needs a way to start a
   thread in core.

## 1. Extraction

1. the APK packs what the game reads from rom/ (step 5's work); BotW's updates (1.8.2) need
   the update NSP, which the user does not have.

## 2. AArch64 translation

1. loadable builds on Linux and Android (an ELF part, the adrp fixes of AArch64), so the phone
   runs the whole translation; the 258 unresolved tables; forms for the rest of the common
   operations (bitfield, FP) and fewer lines a label (`label = x` and `continue` are 15% of the lines,
   a call 6 lines); the calls between parts through a search.

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
