---
size: S
branch: write2
by: 05c1402a-077b-4bef-a22a-b65dbb8e7ce8
---
# The executable's write: what stays on the main thread

The same-code signatures and confirmations, the jumps' reach checks, the code rewritten, the
fixups kept and the positions moved run on every processor (sameCode.zap, relax.zap): the compiler's
cold self-build's write from about 235 M main-thread cycles in removeCode and asmRelax to about 120 M.
What is left:

- [x] asmRelax's layout (the paddings in order, the jumps' shifts after, on every processor)
- [x] the fixups' compaction in removeCode and asmRelax
- [ ] the code's copy in removeCode (a serial copy of the 14.5 MB, about 10 M cycles; relaxedCode's
  join of its pieces, about 8 M, is the same kind)
