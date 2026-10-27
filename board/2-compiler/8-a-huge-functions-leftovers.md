---
size: L
priority: P1
branch: compiler-8
by: bdb3b274-1d32-413f-8132-3dd4041acd2b
---
# A huge function builds in time and memory linear in its size

`tools/hugeFnShape.zap` writes one function of BotW's part 36's shape (a `while true` match whose
first arm runs on, the memory's loads and stores and the calls out inlined); its build at 16,000
lines is in `baselines/size.baseline` (5.8 s, 0.26 GB). From 8,000 to 64,000 lines its code phase
grows about linearly (1.2 to 11.6 s, 0.18 to 0.91 GB, some 14 KB a line), and the real part 36
builds cold in 10 s (102 s before, the same bytes). Two costs are left:

- [ ] a liveness walk's set is dense: `irWalkFrom` (`compiler/optimize/irOptValues.zap`) clears and
  fills a block's words, and `irCallFacts` (`compiler/targets/x64/irRegs.zap`) ors them at each
  call, costing blocks or calls times the value numbers over 64. Make the sets sparse; the code
  phase of `hugeFnShape.zap` at 64,000 lines falls below 11.6 s and 0.91 GB
- [ ] the optimizer's rest is the settle rounds' facts and hashes (`irFacts`, `irValueSpans`,
  `irBlockHash`, 13% at 32,000 lines): the work is compiler-2's
