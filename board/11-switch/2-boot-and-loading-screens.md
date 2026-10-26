---
needs: [switch-1]
size: XL
---
# Boot and loading screens right

Boot and loading screens right. The whole build (all functions, in parts) loads and runs:
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
with tests (tests/maxwell.zap, tests/gpuServices.zap): the channel's SyncpointOperation is
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
