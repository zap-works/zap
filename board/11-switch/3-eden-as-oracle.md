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

## Handoff

- Done: tools/edenStop.zap `--hit n` now counts (oracle/remote.zap `resumeTo`: Eden's stub stops again at the breakpoint's address, and its first `c` after a step runs one instruction only). run.zap `--entropy ,,<hex>,<hex>` gives svcGetInfo 11 Eden's words (the sdk reads only 2 and 3; Eden with rng_seed 0: 9a4eb343dba252fb, 8b7d76c3d8e57d67); svcGetInfo 0 answers 7 as Eden does.
- With them every register agrees with Eden at the 2nd svcGetInfo (stop at 0xad08be4, the sdk's wrapper) and at the 3rd but for the cores, now fixed.
- Differs: the sdk picks the thread stack's address at random (svc 4 dst); the 1st agrees (0x51417000), later ones differ (hit 6 of 0xad08be4: sp 0x1f233b10 here, 0x581eeb10 in Eden) because Eden's 2nd svcCreateThread stop is never reached by edenStop (after the 1st svc 8 Eden's `c` returns once, then nothing: the stub seems to lose the breakpoint or block with the new thread paused).
- Left: make edenStop reliable across a created thread (try z0/Z0 around the step, or `vCont`), find why the 2nd stack address differs (the sdk's random from entropy plus what else: svcGetSystemTick?), and frames from Eden (its Vulkan window fails with SDL's offscreen driver).
