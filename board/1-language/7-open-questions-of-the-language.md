---
size: L
blocked: set aside until a project or a measure asks for it
priority: P3
---
# The language's open design questions are decided with real code

Three design points were left undecided on purpose, to be settled when real code needs them
instead of by guessing now. The rules they touch are in `spec/origins.zap`, `spec/numbers.zap` and
`spec/literals.zap`.

- [ ] borrows that the origin rules miss: each case found in real code becomes a test in
  `tests/memory/` and a stronger inference rule in `compiler/ownership`, so the test then passes
- [ ] a `decimal` type for exact money values: annotated once (`price decimal = 19.99`), its
  literals following that annotation, and mixing it with `f64` an error; `spec/numbers.zap` states
  it and a test in `tests/numbers` covers the arithmetic and the error
- [ ] a `char` type: decide it against a program that needs it, then state it in `spec/numbers.zap`
  and test it in `tests/text`
