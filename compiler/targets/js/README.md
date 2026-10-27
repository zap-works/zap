# The JS target

`zap build|run|test --target js` writes one ES module from the checked tree and runs it under node.

## How it maps Zap

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
