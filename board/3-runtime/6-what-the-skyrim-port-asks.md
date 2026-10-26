---
size: M
priority: P1
---
# What the Skyrim port asks of the std

the `u32le(at + N)` offsets left in hkx/packFile.zap,
esm/file.zap, esm/condition.zap, lip.zap, fuz.zap, strings.zap and hkx/layouts.zap moved to
`T.fromBytesAt` (bsa.zap reads with it); std/archive, sources of files by key (a Data dir's
archives, loose files), from bsa.zap and install.zap (`installFind` walks every archive's keys a
call); pixel comparison against captures (skyrim's compare.zap) in std/image.
