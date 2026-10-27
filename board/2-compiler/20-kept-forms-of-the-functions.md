---
size: L
priority: P2
---
# Scripts: more functions can keep their form between builds

Some functions never keep their lowered form in a kept stage, so every script's build lowers them
again. Three groups are left:

- functions with a lambda, named by a count (`$env:N` and `$lam:e:N`): the initializers of
  `threadsEnd` and `crashFilterSet` alone cost 1 ms of each build
- functions that plan a function's wrapper as a value or a callback (`$fnval:`, `$callback:`),
  named by their label's number in the form, which another build numbers otherwise. Naming them by
  key was tried and a form taken in another program's build crashed
- functions whose lowering checks an instance that makes nodes outside its own copy

- [ ] name the lambdas' functions by a stable key (the declaration and its position) and keep their
  forms in the stage (`compiler/targets/x64/keptEntry.zap`); a script's build timing no longer
  lowers `threadsEnd` or `crashFilterSet` initializers
- [ ] keep the wrappers (`$fnval:`, `$callback:`) by a key that every build agrees on, with a
  test that takes the form in a second program and runs it without the crash
- [ ] let a lowering that checks an instance keep its form once the instance's nodes are in the
  function's own copy; `zap test --only bench tests/scripts` shows the ratio
