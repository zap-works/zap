---
size: M
---
# A pipeline step may take ownership of a temporary list's elements

`m.keys().map(Row(name = it, n = m[it]))` stops with `move-of-borrowed` on `it`, though `keys()`
made the strs for this call alone. `map`, `filter` and the other steps lend each element of a
list, so a record built from them needs `.copy()` (a second copy of what no one else holds).
`for k in m.keys():` already moves its elements out of a temporary. It was met writing agent
scripts that mirror Python ones; the workaround is `.copy()` or that loop.

- [ ] make a step's `it` over a list that is a temporary (a call's result, a literal) owned, so a
  record, a `push` or a `move` parameter may take it (ownership checker in `compiler/ownership`);
  the example above compiles and a test in `tests/memory` runs it without `.copy()`
- [ ] state it where the spec describes pipelines (`spec/pipelines.zap`), with that example
