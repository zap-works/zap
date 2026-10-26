---
size: L
---
# What the backend refuses or loses after the checker accepted it

(told at the check, never a
crash or a silent hole):
- [ ] A method whose result is `T ? E` crashes at run time (access violation in rt.strCopyRaw) when
  a `try` of a method of the same receiver sits inside an `if` and a value is returned after it:
  `fn pick(k i64, t i64) i64 ? str:` with `if e > 0: try inner(e)`, then `if e > 5: return e`
  and `t`; the writer keeps its first error in a field and its methods return plain values.
- [ ] A function returning `str?` as `xs.first.copy() if not xs.isEmpty else none` over a filtered
  list of windows, or as `(try said.lines().find(...)).copy()`, builds with no error and ends
  with "x64: function 'f' was referenced but never generated"; written as a `for` with an early
  return (a worktree's compiler building merged sources it had not seen gave it too, fixed by a
  seed bootstrap).
- [ ] `fn f(m str) T?: list.find(.name == m)` over a module list of structs: `backend-refused: ... an
  optional reference to T read`; written `(try list.find(...)).copy()`.
- [ ] `host = args.option("--host") ?? (benchHost() if benchHost() != "" else fail("..."))` checks
  but the backend refuses "a store of str" in a program's main; written `?? benchHost()` then
  `if host == "": fail(...)`.
- [ ] `if self.b is mut m: return mut ref m` with `b Box<T>?` and a `mut ref Box<T>` result checks,
  then the backend refuses "a reference to a value held in registers" (the box's word is
  loaded, its place in self.b not kept); a `mut ref T` result is the box's value and works.
  Node's part stays a none-or-one list (24 bytes, a box 8) until the seeds take that form.
- [ ] `extern "vulkan-1.dll" "vkUpdateDescriptorSets" fn updateSet(...)` beside the module's own
  `extern "vulkan-1.dll" fn vkUpdateDescriptorSets(...)` makes a Windows program that ends at its
  start with code 127 and no line (every engine example); written `extern loaded`, bound through
  vkGetDeviceProcAddr (rhi/vulkan/sets.zap).
