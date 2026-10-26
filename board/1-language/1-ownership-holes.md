---
size: L
---
# Ownership holes

- [ ] A list of structs with a field of type `i64[]?[]` had that field overwritten (met grouping the
  test files; 900 fuzzed programs of that shape ran right): reduce when it shows again.
- [ ] A lambda capturing a struct, then a later use of the struct: `read = (at i64, n i64):
  readRomImage(img, at, n)` then `romImageSize(img)` stops with `ownership-broken: v181
  (RomImage) read after it is consumed`; read `romImageSize` before the lambda.
- [ ] A plain `match` arm's binding is not tracked by the ownership check (an `is` binding is):
  giving it away and reading it after compiles. Tracking it the same way broke
  tests/memory/fuzzFound.zap (a window into the arm's value outlived it).
- [ ] A function with `move` parameters is accepted as a value of a `fn` type whose parameters are
  not, and the call through it hands the callee garbage (an engine.Program whose id indexes past
  the registry); written with borrowed parameters.
- [ ] `asks[k].types.extend(try grow(asks, ...))`, where grow pushes to asks, loses the extension
  (the place is taken before the call moves the list); make the value first, assign after.
- [ ] `expect f() == [u8(1)]` with `fn f() u8[]?`: `use-after-given` on the expect's own temporary
  (`$expect0r`), then `ownership-broken` after lowering; written `(f() ?? []) == [...]`.
- [ ] `__addr` of a fixed array's element inside a list gives a copy's address.
