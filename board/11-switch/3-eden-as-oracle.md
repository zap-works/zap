---
size: L
priority: P0
---
# Eden's frames and entropy match, so it serves as the oracle

Eden 0.2.1 (portable, in `C:/tools/eden/eden`, with the user's keys, outside the repository) runs
BotW 1.0.0 headless with the null renderer and a fixed RNG seed, so its memory layout is the same
every run. The recompiler lays a game out as Eden does (modules packed from 0x8000000, Horizon's
36-bit regions in `svcGetInfo`, the main stack 9 pages past the modules). This is done on Windows.

`tools/edenStop.zap` stops Eden at an address through its gdb stub (`oracle/remote.zap`: GDB's
remote protocol in Zap) and prints the registers and memory. `tools/run.zap --at <hex> [--hit n]
[--memory a,n]` stops the interpreter at the same place and prints the same. At the first
`svcQueryMemory` of the sdk (0xad08a20) both agree except for the registers that hold leftovers of
the random entropy (`svcGetInfo` 11). Left:

- [ ] get frames from Eden: its Vulkan window fails with SDL's offscreen driver. Find a way to have
  Eden write its frames headless (another video backend or a patch of its settings), and write it
  here; a frame of the title screen from Eden is on disk
- [ ] match the entropy (`svcGetInfo` 11) in the recompiler to Eden's, so the registers compare
  equal at later stops; `tools/edenStop.zap` and `tools/run.zap --at` print identical registers at
  the stops after the first `svcQueryMemory`
