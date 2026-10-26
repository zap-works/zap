---
size: L
---
# The checker refuses valid code

(each decided: accepted, or its message made to say what to
write):
- [ ] An enum's `.Variant` takes no enum from the expression around it: `[Kind.A, .B]` and
  `Kind.A if c else .B` (a function without a declared result) are `enum-unknown`; written with
  the type named or the result declared.
- [ ] `x bool?? = true` is refused: a value is wrapped in one optional layer, not two.
- [ ] `move nodes[e].nodePart().names[i]`, a place a method's `mut ref` result reaches, is
  `move-needs-place` (the lowering's place test, irIsPlaceNode, takes no call: the move would
  evaluate it twice); written through the field (`move nodes[e].part[0].names[i]`).
- [ ] `zap doc fs` lists `File.len()` as a method, but `file.len()` is `size-is-field`.
- [ ] From the agents' scripts (Python does these): `a = b = 0` is refused; no `reversed` of a range;
  `xs[..15]` stops past the end (`index-out-of-bounds`) where Python's `[:15]` takes what there
  is; a str sliced by byte can cut a UTF-8 character; `groupBy(it.0)` on tuples is
  `tuple-position` (a type declared for it).
- [ ] Misleading messages: `x ?? fail` ("'error' is a result's error"), `str[][]` ("expected
  ')'"), a lambda bound to a name ("cannot-infer-lambda-parameter", a wrong type suggested),
  `a ?? 0 < 3` read as `a ?? (0 < 3)`.
