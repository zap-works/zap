---
size: L
priority: P0
branch: switch-3
by: ca89024e-19e3-43a9-894e-10502a600884
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

- Done: oracle/remote.zap `resumeTo` takes a list of addresses and uses the protocol Eden's stub needs (it patches a BRK into the code): at a breakpoint `z0`, `s`, `Z0`, then `c` until a listed address. edenStop `--trace <hex>,...` prints each such stop with the registers. Hit counts are now reliable and repeatable: ad08be4 hit 6 gives sp 0x2951cb10 in Eden on every run (the earlier 0x581eeb10 was an artifact of the old step).
- Registers at ad08be4 hit 6 agree with the interpreter's (with --entropy ,,9a4eb343dba252fb,8b7d76c3d8e57d67 and --steps 400000000) but x4, x29, sp: the thread stack is 0x1f233... here, 0x2951c... in Eden. The first stack (0x51417000) agrees; the sdk's AddressSpaceAllocator::AllocateSpace (aceb3b4..) draws the 2nd one from its random, so a draw consumed differently (a rejected candidate or another input) is the cause: not yet found.
- Failed: a breakpoint on an `svc` itself, or stepping often over the ones after it (a24, a44 hit 2), makes the guest abort in nn::os GetThreadCoreMask (Eden's log: nn::svc::Break; stops at unmapped 0x1b8 before it): the stub steps only the stopped thread with the others suspended. Only stops that are rare or after the svc are safe (ad08be4 is).
- Left: find the allocator's draws (read AllocateSpace's code with tools/dump.zap and names.zap, compare the rejected candidates), then frames from Eden (its Vulkan window fails with SDL's offscreen driver).
