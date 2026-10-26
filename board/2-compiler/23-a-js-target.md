---
size: XL
check: zap test --target js spec/basics std/zapx; the board's page built for the browser
branch: jstarget
by: 704a3f6e-3fab-463a-9569-01d68ba36a46
---
# A JS target

`zap build --target js app.zapx` writes one ES module the browser (or node) runs, and `zap test
--target js <files>` runs test blocks under node, as `--target linux` runs them elsewhere (spec
13.1). The web speaks JS, so this is how Zap reaches it; std/zapx's hydration (runtime-8) stands on
it.

- [x] Where it starts: the checked tree (after the ownership check), so the output reads like the
  source and a browser's debugger is usable; one JS function a Zap function, the names kept.
- [x] Numbers: f64 native, f32 through Math.fround; i8..i32 and u8..u32 wrap exactly (`|0`,
  `>>>0`, masks); i64, u64 and n64 as JS numbers, exact up to 2^53, a checked run stopping past it
  (never a silent difference from native).
- [x] str: a JS string; byte indexes, slices and `bytes()` through the UTF-8 view the runtime
  keeps for strings that are not ASCII.
- [x] Values: structs as objects, lists as arrays, enums as `{tag, ...}`, matches as switches,
  maps as Map; a move passes the object (the source is dead), `.copy()` copies deeply; optionals
  and results as values or `none`.
- [x] The runtime's part for JS: what is written in Zap compiled by this target, a small prelude
  (runtime/js/) for the rest; `extern "js" fn` binds a JS function (the DOM, fetch, timers).
- [ ] spec/ and tests/ blocks that a browser program uses pass under `--target js`; what the
  target refuses (threads, files, raw memory) is an error at the check naming the target.

Decisions refined as the code showed (compiler/targets/js/):

- The ownership check runs on the lowered form, so genX64 lowers the program as Windows' x64 does
  and hands the tree to genJs in place of the image (`.mjs`: node reads it as a module, top-level
  await and all).
- A carrying enum is `{$tag: "Name", ...}`: a payload may be named `tag` (zapx's `Element`), and
  Zap's own JSON already writes `$tag`; a plain enum is its variant's number.
- Matches are if/else chains, or a labeled block each arm leaves when a guard may pass the value to
  the next arm: patterns nest and bind, which a switch does not take.
- A move empties its place (the value stays readable, as Zap's does); a mut parameter or receiver
  whose value is no JS object, or that the body assigns whole, goes in a box `{v}` written back
  after the call; `some(x)` of an optional of an optional is `{$some: x}`; a map keyed by structs
  or lists is the prelude's rt$KeyMap.
- What the target cannot write is refused per function as the module is linked: a build reaching it
  fails naming the target; a test reaching it is skipped saying why (as Windows' own tests are on
  Linux), its stop tests too.
- A file without a main is a module exporting its public functions: the board's page builds and,
  on the same board, renders byte for byte what the native build renders.

Left of the last item: the stops of tests needing integers past 2^53 (u64 hashes and bit cursors)
stop at run time instead of being refused; a struct with a drop function, `loadWord`, bits by raw
words are refused; tests/basics, std/zapx and spec's language sections pass, but `zap test
--target js spec` as a whole is not run (files, processes and threads are skipped test by test,
not judged). The prelude still holds JS copies of runtime functions whose Zap reads raw memory
(trims went back to the runtime's own; the rest wait for a runtime layer of their own, a `js/` dir
beside `linux/` read by systemDirsOf).
