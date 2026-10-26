---
size: M
priority: P0
branch: language-3
by: 1e356d34-454a-44a7-a2b8-3fe822a181c8
---
# Module bindings and names

- [ ] A local assignment named like a module variable writes the module's, silently (`shown =` in
  recomp's compose.zap rewrote output.zap's buffer index): refuse it or tell it as a shadow.
- [ ] A test in a module's second file sees only that file (a test in std/image beside image.zap
  could not name `Image`): it sees its module.
