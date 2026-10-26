---
size: M
branch: effnum
by: 05c1402a-077b-4bef-a22a-b65dbb8e7ce8
---
# Effects kept as numbers past their summary

The module variables' summaries are found by
the call graph's components (effects.zap's summarizeGlobals, Go's escape analysis's order) and
the parameters' over a worklist: FireRed's edit rebuild checks in 1.4 s (1.7 before). Left:
the summaries written into `c.effects` as texts keyed by "{fnd}:{param}" (0.3 s, 438,000
entries), hashed again as texts by layerFacts and keptEntry, and a component's paths copied to
each member's slot: kept as path numbers with each path's text hash, read as texts on demand.
