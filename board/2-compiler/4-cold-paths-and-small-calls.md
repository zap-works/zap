---
size: M
priority: P1
---
# Generated code stays small around rare paths and tiny calls

A small method's rare path is inlined into every caller together with what it formats. In
recomp.switch, `Memory.index` noted a fault as `"{n} bytes at {at:x}..."`, which put the formatting
and a 1.5 KB frame, zeroed at each entry, into every translated function (190 bytes of x64 per
guest instruction, 90 without it). That one was fixed by keeping the fault as numbers
(`Memory.faultAt`, `projects/recomp/switch/cpu/core/memory.zap`) and formatting it where it is
read, but the compiler still inlines rare paths this way. Separately, small functions called a
pixel at a time (`layerColor`, `combineWindows` and the colour math's channels in
`projects/recomp/snes/console/compose.zap` and `backgrounds.zap`) are not inlined, and were worked
around by hand.

- [ ] keep a rare path (one that only fails or reports) out of line when inlining a small method
  (`compiler/ir/irLowerFunction.zap`): a method whose rare path formats text adds no frame
  zeroing to its callers; a test program shows its caller's code without the formatting
- [ ] inline the tiny pixel functions above without hand workarounds; `zap test --only bench` on
  a snes project shows them as fast as the hand-inlined version
