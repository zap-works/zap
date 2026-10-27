---
size: M
priority: P2
---
# The std serves what the Skyrim port needs

The Skyrim port (`projects/skyrim`) still reads file offsets by hand and keeps its own helpers for
things that belong in the std. Three changes move that work into the std.

- [ ] replace the remaining `u32le(at + N)` offset reads with `T.fromBytesAt` (as `bsa.zap`
  already does) in `skyrim/hkx/packFile.zap`, `skyrim/esm/file.zap`, `skyrim/esm/condition.zap`,
  `skyrim/lip.zap`, `skyrim/fuz.zap`, `skyrim/strings.zap` and `skyrim/hkx/layouts.zap` (all under
  `projects/skyrim/skyrim/`); `zap test projects/skyrim` passes with the same output
- [ ] make `std/archive`, which gives files by key from a Data dir's archives and loose files, out
  of `bsa.zap` and `install.zap` (`installFind` walks every archive's keys on each call); skyrim
  uses it and a lookup no longer walks every archive
- [ ] move the pixel comparison against captures (`projects/skyrim/compare.zap`) into `std/image`;
  skyrim calls it from there and its comparisons give the same results
