---
size: L
priority: P0
branch: switch-3
by: d8598d14-f914-4f73-a93f-a3cc0afd7f86
---
# Eden as the oracle

Eden as the oracle (done on Windows): Eden 0.2.1 (C:/tools/eden/eden, portable, the user's
keys, outside the repository) runs BotW 1.0.0 headless with the null renderer and a fixed
RNG seed, so its layout is the same every run; this recompiler lays a game out as it does
(modules packed from 0x8000000, Horizon's 36-bit regions in svcGetInfo, the main stack 9 pages
past the modules). tools/edenStop.zap stops Eden at an address through its gdb stub
(oracle/remote.zap: GDB's remote protocol in Zap) and prints the registers and memory;
tools/run.zap --at <hex> [--hit n] [--memory a,n] stops the interpreter at the same place and
prints the same. At the first svcQueryMemory of the sdk (0xad08a20) both agree but for the
registers that hold leftovers of the random entropy (svcGetInfo 11). Left: frames from Eden
(its Vulkan window fails with SDL's offscreen driver), and the entropy matched to compare
further.
