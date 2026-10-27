---
size: M
priority: P2
---
# What agent scripts lack against Python

(eleven scripts written in both: grep, loc, json,
csv, replace, todo, diff, git log, numstat, a TSV sum, the walk; the language's part is
language-4):
- [ ] A map's value changed in place by key with a default for a missing one, as Counter and
  defaultdict do: `stats["a"][0] += 1` works on a present key, `m["x"] += 1` on a missing one
  stops (`the key is not in the map`); a text key needs `.copy()`.
- [ ] Maps walk in hash order (Python's in insertion order), so a sort's ties print differently (a
  compact ordered map was tried: Tried).
- [ ] `zap doc runtime` lists `T[].contains` and `T[].repeat`, but a call of them is `no-method`.
- [ ] `fs.copytree` (a copy of a dir) is missing.
- [ ] A record built from `keys()`' strs needs `.copy()` (`move-of-borrowed`).
