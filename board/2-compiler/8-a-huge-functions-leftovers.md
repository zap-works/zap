---
size: L
---
# A huge function's leftovers

tools/hugeFnShape.zap writes one function of BotW's part 36's
shape (f881b6b8: a `while true` match whose first arm runs on, the memory's loads and stores and
the calls out inlined); its build at 16,000 lines is in size.baseline (5.8 s, 0.26 GB). From
8,000 to 64,000 lines its code phase grows about linearly (1.2 to 11.6 s, 0.18 to 0.91 GB, some
14 KB a line), and part 36 builds cold in 10 s (102 s before, the same bytes). Left: a liveness
walk's set is dense (irWalkFrom clears and fills a block's words, irCallFacts ors them at each
call: blocks or calls times the numbers over 64), and the passes' rest is the settle rounds'
facts and hashes (irFacts, irValueSpans, irBlockHash, 13% at 32,000 lines: step 2).
