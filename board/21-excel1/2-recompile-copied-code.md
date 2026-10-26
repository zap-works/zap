---
size: L
blocked: set aside
---
# Recompile code copied into RAM at run time

The p-code dispatcher and the code Excel copies into RAM before running it stay interpreted
(56% of the instructions of the About run): recompile code copied at run time by the bytes it
was copied from, then measure the recompiled run against the interpreted one.
