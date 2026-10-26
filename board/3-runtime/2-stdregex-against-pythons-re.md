---
size: L
priority: P1
---
# std/regex against Python's re

(a fuzz of random patterns): possessive quantifiers, `$` before
a trailing newline, an empty match right after a match, `(a*)*`'s group none where Python's is
""; `m.group("name")` is `m.named("name")` (no overloading by the argument's type); Unicode
classes missing. regexRedux's part is benchmarks-8.
