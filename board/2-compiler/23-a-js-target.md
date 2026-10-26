---
size: XL
check: zap test --target js spec/basics std/zapx; the board's page built for the browser
branch: jstarget
---
# A JS target

`zap build --target js app.zapx` writes one ES module the browser (or node) runs, and `zap test
--target js <files>` runs test blocks under node, as `--target linux` runs them elsewhere (spec
13.1). The web speaks JS, so this is how Zap reaches it; std/zapx's hydration (runtime-8) stands on
it.

- [ ] Where it starts: the checked tree (after the ownership check), so the output reads like the
  source and a browser's debugger is usable; one JS function a Zap function, the names kept.
- [ ] Numbers: f64 native, f32 through Math.fround; i8..i32 and u8..u32 wrap exactly (`|0`,
  `>>>0`, masks); i64, u64 and n64 as JS numbers, exact up to 2^53, a checked run stopping past it
  (never a silent difference from native).
- [ ] str: a JS string; byte indexes, slices and `bytes()` through the UTF-8 view the runtime
  keeps for strings that are not ASCII.
- [ ] Values: structs as objects, lists as arrays, enums as `{tag, ...}`, matches as switches,
  maps as Map; a move passes the object (the source is dead), `.copy()` copies deeply; optionals
  and results as values or `none`.
- [ ] The runtime's part for JS: what is written in Zap compiled by this target, a small prelude
  (runtime/js/) for the rest; `extern "js" fn` binds a JS function (the DOM, fetch, timers).
- [ ] spec/ and tests/ blocks that a browser program uses pass under `--target js`; what the
  target refuses (threads, files, raw memory) is an error at the check naming the target.
