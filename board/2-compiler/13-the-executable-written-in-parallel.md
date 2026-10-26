---
size: S
---
# The executable's write: what stays on the main thread

The same-code signatures and confirmations, the jumps' reach checks, the code rewritten and the
positions moved run on every processor (sameCode.zap, relax.zap): FireRed's write 775 ms to 400.
Left on the main thread, about 260 M cycles of the compiler's write:

- [ ] asmRelax's layout (five scans: a padding depends on every byte before it)
- [ ] the fixups' compaction in removeCode and asmRelax
- [ ] the code's copy in removeCode
