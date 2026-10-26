---
size: M
---
# pidigits 1.02x to 1.04x against C over GMP

whose limb loops are hand-written assembly. Left:
a scratch limb buffer kept between steps, the 64x64 to 128 product a single `mul`. (Commit
7c1d8ce7 of bench1, not in main, measures 0.87x with a multiword product's factor loaded into
rax and carries chained: measure again once it lands.)
