---
size: M
priority: P2
---
# Eden's and the interpreter's threads run in the same order

`tools/edenStop.zap` and `tools/run.zap --at` print the same registers at the boot's stops until
the sdk's third thread stack is allocated (`ace9148`, hit 3): Eden runs the guest's threads on
parallel cores and the kernel here runs them in turns, so the thread-stack allocator's draws of
random (`nn::os::detail::RngManager`, seeded from `svcGetInfo` 11) are made in another order and
land on other addresses (the shared memory mapped by `svc 0x13` comes before the third stack here,
after it in Eden). Stops must also avoid a branch and the instruction after a supervisor call: Eden's
gdb stub steps a taken branch as a fall-through and runs a call again, which changes the guest.

- [ ] find which thread draws and maps in Eden at each point of the boot (`edenStop.zap --at <hex>
  --hit n --monitor "get mappings"` at non-branch addresses) and in `tools/run.zap --calls`, and
  write down the order they differ in
- [ ] make the kernel's scheduler (`horizon/threads.zap`) run the threads in Eden's order up to the
  title screen, so `ace9148` at hits 1 to 4 prints the same registers in both
