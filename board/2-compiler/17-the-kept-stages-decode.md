---
size: M
priority: P2
---
# Scripts: a kept stage is read into memory faster

A script's build decodes the kept stage's declarations whole each time (3 ms for 9,400 nodes: texts
and lists allocated one by one) and then builds the checker's tables over them (`newChecker`'s
indexes, 1 ms). Reading it in parts on two processors did not pay, because the allocations
contend. The game stage of compiler-3 pays the same cost.

- [ ] decode a kept stage with fewer allocations (one block for the texts, lists sliced out of
  one buffer; `compiler/driver`, where `keepFrom` reads the stage); a script's build timing shows
  the decode below 3 ms
- [ ] build `newChecker`'s indexes lazily or store them in the stage; the same timing shows the 1
  ms gone
