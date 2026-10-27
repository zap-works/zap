---
size: L
priority: P1
---
# The optimizer's settle rounds cost less

`irSettle` (`compiler/optimize/irOpt.zap`) runs about thirty times a function whatever its size.
Each round finds its facts and block hashes again over the whole function (`irFacts`,
`irValueSpans`, `irBlockHash`), about 13% of the optimizer passes: the first cost on a translated
function's form (see `projects/recomp/switch/TODO.md`). A round visits most blocks (66%), so
counting incrementally did not pay.

- [ ] cut the number of rounds, stopping when a round changes nothing or when the function's size
  says the remaining rounds cannot help; `zap test --only size` shows the code phase of
  `tools/recompShape.zap` faster, with the executable byte for byte the same or smaller
- [ ] or make each round cheaper another way (not an incremental count); the same measure shows it
