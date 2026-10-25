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

0. Work on the start's partition alone, never the whole build: record the profile of the start
   (a run of about 1,200 turns of the whole build already in C:/Lucas/dev/zap/build, which still
   loads under the runtime before the .load format changed, with the dispatcher's recording on
   and `cpu.entered` written as tools/run.zap's --profile does), then `main.zap <exefs>
   --profile <file> --build`: the functions the start entered (5,000 to 10,000 of 141,000) in a
   few parts, 2-3 min cold and seconds warm, the rest on the interpreter; a fix rebuilds the one
   part it touches. The whole build is built once more, at the end of the slice. Rebuilding all
   131 parts (25 min) is not done again while a slice is worked on: today it happened twice (a
   cpu/core change for the lockstep, and the .load format change of loadelf).
1. Boot and loading screens right. The whole build (all functions, in parts) loads and runs:
   `lockstep` in ZAP_RUN (cpu/lockstep.zap: each translated function the dispatcher enters run
   again on the interpreter from the same state, stores journaled) finds no difference in turns
   0-100 nor 250-257, so the translation is not what goes wrong first. The game boots slowly in
   guest time (a turn is 1/60 s, 16 million instructions): the Yaz0 streaming decompressor
   (main 0x91ee754, fed 128 KB at a time by a loader thread through a message queue) and a
   dedup of 48-byte records by memcmp against every earlier one (main 0x8b4eb44) take most of
   the first 1,000 turns; the first SUBMIT_GPFIFO comes after that, and its CLEAR_SURFACE has
   render target registers that ask for gigabytes (maxwell/clear.zap notes and skips a clear
   over 256 MB). Seen on the current build (131 parts, Windows,
   `--frames 1500`: 10 minutes, 2.3 GB; `lockstep=0` over turns 0-99 and `lockstep=250` over
   250-257 find no difference): the game presents from turn 9 to turn 1114 (3,449 frames, 66,439
   draws, none after) and then idles to turn 1500 on audren's RequestUpdate, nfp polls, a sleep
   (svc 0xb) and nvhost-ctrl's SYNCPT_WAIT_EVENT (error 5) and CLEAR_EVENT_WAIT every few turns; the
   last IPC at turn 1114 is nvmap create/alloc and nvhost-as-gpu MAP_BUFFER_EX. The GPU report has
   0 syncpoint increments over 3,449 frames and the garbage entries the next sentence names: entry
   244 `00000270 22905202` (566,292 words), entries of 19,113 and 40,530 words, class f bound to
   subchannel 4, a macro at 0 that ran 1,048,576 steps without its exit, `a wait on syncpoint 0 that
   never reaches its value`, methods on a subchannel holding no class. Read against yuzu (citron's
   nvhost_gpu.cpp, nvhost_ctrl.cpp, puller.cpp), the syncpoints were wrong three ways, now fixed
   with tests (tests/maxwell.zap, tests/gpuservices.zap): the channel's SyncpointOperation is
   yuzu's FenceAction (bit 0 increments, the id in bits 8 and up; it was read as bit 16 and
   bits 0-11, so every increment became a wait on a wrong id); the 3D engine's sync info (0xB2)
   increments too; SUBMIT_GPFIFO always returns the channel's syncpoint and its maximum after
   the increments the flags promise (2 for bit 1, the fence's value for bit 8; it wrote a fence
   only for bit 1, one increment), and a syncpoint short of that maximum after the entries ran is
   noted and raised to it; KICKOFF_PB (0x481B by Ioctl1) reads its entries from guest memory at the
   argument's address (they were read past the 24-byte argument, so none ran). nvhost-ctrl's
   error 5 is yuzu's answer too (Timeout while the event is armed), so the idle was the game
   waiting on a fence that never came. Not yet seen: how far the boot goes with the fix. The
   program now takes `--profile f` (cpu.writeProfile), so item 0's profile can come from a
   translated run: a profile of the interpreter's first 1.5 billion instructions (24,513 blocks,
   6 min) built as 4,935 functions in 7 parts, but that build's run of 1,500 turns had not ended
   after 30 minutes (the start's later code on the interpreter); record with `--calls` to see the
   turns go by, rebuild from the longer profile, then check the presents past turn 1114, the
   notes left (the garbage entries, `syncpoint n fell short`), and which ioctls BotW submits by.
   Next: read the first submit's methods (`--calls`: each svc with its call chain,
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

1. the whole translation run on the phone: the parts pushed to the app's files by adb with the ExeFS and loaded there; the 258 unresolved
   tables; forms for the rest of the common
   operations (bitfield, FP); the calls between parts through a search.

## 3. Horizon HLE

1. whatever the game asks next; the 3D renderer.

## 4. GPU

1. What Zap's GPU code lacks, each with the instructions that need it (the translation notes the
   instruction and writes zeros, or does as said):
   - 1D textures and arrays, 3D arrays and multisampled ones (TEX/TEXS/TLD/TLDS/TLD4/TMML/TXD of
     types 0, 1 and 5, TEXS encoding 0, TLDS 0, 1 and 6, TLD.MS); a compared cube or 3D texture; TXD
     of a 3D texture or a cube.
   - A lod clamp (TEX.LC, TXD.LC; yuzu has none either), per-texel gather offsets (TLD4.PTP), the
     level count (TXQ's fourth component), TMML's third and fourth results, f16 results (TEXS, TLDS,
     TLD4S), sparse results.
   - Offsets the code does not show: Zap's offsets are constants of -8 to 7 (`IVec2(x, y)`), so a
     TEX/TLD4/TXD.AOFFI translates when a MOV32I or MOV of an immediate in the same block gave the
     register (TLD4's six-bit offsets only inside that range); a fetch's (TLD, TLDS) are added to its
     coordinates, whatever they are.
   - Integer textures as the TIC says (Source.integers: the handles of textures of integers, signed
     or not, read as UintTexture or IntTexture, their TEX a fetch of the texel uv falls in): nothing
     fills it yet (the renderer reads the TIC pool after the programs are translated); integer
     arrays and 3D textures, and their gathers and gradients.
   - Surfaces past a 2D one of one 32-bit number a texel (SULD/SUST translate as a UintImage's load
     and store, SUATOM/SURED as its atomics): 1D, layered and 3D surfaces, SULD.D/SUST.D of 8, 16,
     64 and 128 bits and .P of more than red (a UintImage is R32UI; a surface of colors needs its
     format from the TIC), SUATOM's INC, DEC, signed MIN and MAX, 64-bit and float sizes, CAS;
     images in vertex and pixel stages (Vulkan's vertexPipelineStoresAndAtomics,
     fragmentStoresAndAtomics); an array of images (they are Params fields, `image<slot>`).
   - Bindless handles the code does not show (TEX.B, TLD4.B, TXD.B, TMML.B: a handle register not
     loaded from a constant buffer word in the same block; TLD.B, TXQ.B); `Texture[]` indexes
     textures with their own samplers, so a computed handle also needs separate sampler arrays.
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
