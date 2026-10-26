---
size: L
priority: P1
branch: runtime-2
by: 5ec31ec5-f468-4942-96cf-da626c40781c
---
# std/regex against Python's re

(a fuzz of random patterns): possessive quantifiers, `$` before
a trailing newline, an empty match right after a match, `(a*)*`'s group none where Python's is
""; `m.group("name")` is `m.named("name")` (no overloading by the argument's type); Unicode
classes missing. regexRedux's part is benchmarks-8.
