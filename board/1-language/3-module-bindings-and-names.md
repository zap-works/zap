---
size: M
priority: P0
branch: language-3
by: e2d29be7-f464-4edd-91de-5d2ce3333e0e
---
# Module bindings and names

- [ ] A local assignment named like a module variable writes the module's, silently (`shown =` in
  recomp's compose.zap rewrote output.zap's buffer index): refuse it or tell it as a shadow.
- [ ] A test in a module's second file sees only that file (a test in std/image beside image.zap
  could not name `Image`): it sees its module.
