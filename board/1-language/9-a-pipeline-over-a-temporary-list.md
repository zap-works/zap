---
size: M
---
# A pipeline over a temporary list moves its elements

`m.keys().map(Row(name = it, n = m[it]))` stops with `move-of-borrowed` on `it`, though `keys()`
made the strs for this call alone: `map`, `filter` and the other steps lend each element of a list,
so a record built from them needs `.copy()` (a second copy of what no one else holds). `for k in
m.keys():` already moves its elements out of a temporary. Met writing agent scripts against
Python's; the workaround is `.copy()` or that loop.

- [ ] a step's `it` over a list that is a temporary (a call's result, a literal) is owned, so a
  record, a push or a `move` parameter may take it
- [ ] the spec says so where it states pipelines (spec/pipelines.zap)
