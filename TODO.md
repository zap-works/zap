# TODO

## A. Rules

- **Only what is open, in the order it is done.** Steps are numbered 1 to N in that order, each
  naming the steps it needs; a step that lands is deleted, never marked done.
- **Checks.** Every check is `zap test` (spec 13.1), read by an agent; nothing is manual. A step is
  judged by the spec's goal, measured: the least time to compile, the most speed, the smallest
  executable, the least memory and the most memory safety. Each measure is kept in a baseline that
  only gets better, so a step that makes one worse fails unless it says why (`--update --slower
  "why"`, the reason in the baseline and in the diff).
- **Large batches, checks at the end.** As many steps as can go at once are done together (the
  independent ones side by side, each in a worktree of its own), with only the touched files'
  tests between changes; the whole `zap test` of the three repositories runs once, when the batch
  is merged, and what it finds is fixed in that same pass.
- **Groups.** The steps are grouped by what they touch: one agent takes a group, and the group's
  branch is tested once when it is merged.
- **Order**: the bugs first; then what the language and the engine owe the recompiled games
  (DKC, Lemmings, Prince of Persia, the SNES recompiler: compile time, checks, layout, the 2D
  frame); then the rest of the engine and the runtime; the benchmarks last. zap-engine and
  zap-projects only follow the language (each change's migration keeps them building and their
  tests passing) and are revised after everything here.
- **Bugs.** None is open. A new one gets a test in `tests/memory/openbugs.zap.txt` (the fuzzer's
  shrunk program, or a hand probe) before its fix; the fix moves the test to `fuzzfound.zap`.
  Checked runs (every test) give each block pages of its own, taken away when it is freed, so a use
  after free or a second free stops the program at once.
- **A migration or a refactor changes no code by surprise:** `zap run tools/golden.zap
  build/base.exe` after it says whether the compiler's own code differs from the build kept
  before (a dir after it for what the compiler does not exercise).
- **Each change keeps the language's rules** (checked indexes, exact floats unless asked,
  ownership) and the source plain: the compiler does the work, the program does not spell it out.
- **Benchmarks.** Every program keeps its problem's rule (tests/benchmarks/problems/problems.zap).
  One implementer writes every language's program as well as the language allows; Zap's edge is
  only that its compiler, runtime and std are ours. Rounds: the rivals optimized within the rules
  (the published entries the starting point, not the ceiling), then Zap made to win again through
  its compiler, runtime and std more than its programs. No overfitting: a change serves general
  programs and says what else it changes (the functions it touches in the compiler's self-build,
  zap-engine and zap-projects). A new problem comes with its C, C++ and Rust programs, its rule and
  its sizes, five at a time, under 1.00x before it is done.
- **Measuring.** Tests run on this machine; performance is measured on the arm64 host over ssh
  (`arm64` in ZAP_SETUP naming it in the user's environment),
  arm64 Linux, a production site beside it: the runner keeps every run there under `nice -n 19`,
  two cores and a memory and time limit. A change is decided by the counters (`--ab`:
  instructions, cycles, cache and branch misses), which a loaded machine does not move, so A/Bs
  run side by side; time at the end of a batch, one run at a time under the machine's lock.

## B. Steps

### State at the stop

Every session stopped, nothing but main. A project's leftovers are in its own TODO.md
(projects/<name>/TODO.md); the ones set aside (firered, ai, excel1) too, each at an intermediate
state that works, and come back here when picked up again. Left in tooling: a queue of branches
landed in one suite (`zap branch land`); `__addr` of a fixed array's element inside a list gives a
copy's address. **Priority: step 2's large-program build** (a recompiled Switch game takes half an
hour to build, every change).

### 1. Bugs and what the test kind's time left

Left:
1. In a list of structs, a field of type `i64[]?[]` was overwritten (met while grouping the test
   files; 900 fuzzed programs of that shape ran right): reduced when it shows again, its test in
   tests/memory/openbugs.zap.txt, then fixed.
2. A real Vulkan run on Linux: no machine here has libvulkan (the container and the arm64 host lack it);
   the loaded libraries' calls and callbacks are tested with libc (tests/io/libthreads.zap).
3. The lint's check again (canon.zap verifyNotes) still loads the whole program again for each
   round (about 0.9 s).
4. The lint notes `.copy()` as droppable in a lambda's result, `romFiles((at, n): rom[at..at +
   n].copy())` with `read fn(i64, i64) u8[]`, and `zap fmt` drops it; the program then fails in the
   callee (`head = read(0, 0x50)`: move-of-part), so verifyNotes does not take the note back (met
   in projects/recomp/switch/package/tests/package.zap, written there without the slice).
5. A shift whose count is an expression takes the shifted value's type into it: `hi << (w - n)`
   with `hi u64` and `w, n i64` is refused (mixed-types), while `k = w - n` then `hi << k` is
   accepted; spec 3.1 says a shift count may be any integer (met in recomp.switch's cpu/integer.zap,
   written with a local).
6. `zap fmt <dir>` does not reach a fixed point in one run: after it, `zap test --only check` still
   listed lint notes (`fixed(c, ` is `c.fixed(`, a type dropped) that a second and third run
   applied (met on projects/recomp/switch, a dir of several modules importing each other).
7. A lambda that captures a struct and a later use of that struct: `read = (at i64, n i64): readRomImage(img, at, n)`
   then `romImageSize(img)` stops the build with `ownership-broken: v181 (RomImage) read after it is
   consumed` (met in projects/recomp/switch/package/tests/package.zap; worked around by reading
   `romImageSize` before the lambda).
8. A test runs in a job that kills a process past 4096 MB committed (driver.zap testMemoryMb), and
   a guest memory is one `zeros(span)`: Breath of the Wild's boot (heap request 3.26 GB) cannot run in
   `zap test` (out of memory in newProcess); `zap run projects/recomp/switch/tools/run.zap` runs it. A
   test of the game's boot waits for guest pages committed as they are touched.
9. `zap doc fs` lists `File.len()` as a method, but a call `file.len()` is refused (`size-is-field`):
   it is `file.len` (met in projects/recomp/switch/package/romfsimage.zap).
10. A computed `pub` binding of a library module (no statements of its own) is evaluated at every
   read, not once: `pub run = "/tmp/zap-oracle-{clockMs()}"` gave four different names in one run
   of tools/armoracle.zap, so gdb failed to find its own file (met in recomp.switch's oracle/gdb.zap;
   now a `pub mut` the tool assigns once).
11. The lint notes a call written `addExact(x.exactOf(), y.exactOf())` as `x.exactOf().addExact(`
   that `zap fmt` does not apply, though it applies other calls' (a function whose first parameter
   is a struct taken from a call of the same line); written by hand in cpu/float.zap.
12. The compiler holds about 6 KB per line of a program at its peak: 357,000 lines of
   `c.x[1] = c.x[2] + u64(7)` in 3,000 functions peak at 2.1 GB (`ZAP_TRACE=memstats`), 1.9 GB of
   it before the IR passes (the parse, the check and the lowering kept whole). A recompiled Switch
   game is 19 million such lines (BotW's 141,000 functions), so it cannot be built on a 16 GB
   machine. Such a program is built as several now (`zap build --loadable`, loadBuild, spec
   13.1): recomp.switch builds BotW as 131 parts of 1.6 GB each (its NOTES). Left: the memory per
   line itself. Reproduced by a generated file of N functions of 117 such lines each.
13. `host = args.option("--host") ?? (benchHost() if benchHost() != "" else fail("..."))` checks but
    the backend refuses it ("a store of str", in a program's main); written as `?? benchHost()`
    then `if host == "": fail(...)` (met in recomp.switch's tools/armoracle.zap and eden.zap).
14. A function whose value is a loop's `return` and whose last statement is `fail(...)` is refused
    (`return-mismatch: expected Vec2, got ()`): `fail` is not a value of the return type (met in
    recomp.switch's controls/pad.zap test helper; written with a placeholder value).
15. A plain `match` arm's binding is not tracked by the ownership check (an `is` binding is, since
   isgiven): giving it away and reading it after compiles; tracking it the same way broke
   tests/memory/fuzzfound.zap (a window into the arm's value outlived it).
16. `x bool?? = true` is refused: a value is wrapped in one optional layer, not two.
17. The engine's frame-cost changes (step 9: sorted draws, ring sizing, sprite batch, silent
   voices, skinning passes) landed without a `zap test --only shots` run: run it once.
18. The seeds still know ZAP_RUNTIME, not ZAP_RUN's `runtime=`: compiler/driver/seeds.zap sets it
   when it builds with a seed. Once the seeds are promoted (`zap build --seeds`), that line goes.
19. A local assignment whose name is a module variable's writes the module's, silently (`shown =`
   in recomp's compose.zap rewrote output.zap's buffer index): refused or told, as a shadow.
20. A test in a module's second file sees only that file (a test in std/image beside image.zap
   could not name `Image`): it sees its module.
21. `zap fmt <dir>` does not apply the lint's forms only types tell to write, which `zap test`
   reports as "zap fmt applies it": applied by hand on the phone-look land.
22. Small functions called a pixel at a time are not inlined (recomp's layerColor,
   combineWindows, the colour math's channels): seen in the profile, worked around by hand.
23. A method whose result is `T ? E` crashes at run time (access violation in rt.strCopyRaw) when
   a `try` of a method of the same receiver sits inside an `if` and a value is returned after it:
   `fn pick(k i64, t i64) i64 ? str:` with `if e > 0: try inner(e)` then `if e > 5: return e` and
   `t` (met in recomp.switch's shaders/flow.zap; the writer now keeps its first error in a field
   and its methods return plain values).
24. `i32(v) < 0` with `v u32` is refused as `comparison-decided` ("a n32 is never below 0"), though
   spec 3.1 says a sign change of the same width keeps the bits and `i32(v)` is -2 for 0xFFFFFFFE
   at run time; written `v >> 31 != 0`, or `i32.wrap(v) < 0` (met in recomp.switch's
   shaders/maxwell/maxwell.gpu.zap and integer.zap).
25. `expect f() == [u8(1)]` with `fn f() u8[]?` fails to compile: `use-after-given` on the
   expect's own temporary (`$expect0r`) and `ownership-broken` after lowering (met in
   recomp.switch's tests/maxwell.zap; written `(f() ?? []) == [...]`).
26. `u32(i32(x).abs())` with `x u32` is refused as `conversion-round-trip` ("u32 has abs itself"),
   but a signed abs and u32's abs differ for every x of bit 31 set (met in recomp.switch's shaders
   translating I2I's abs; written as a GPU function `absSigned`).
27. The lint's `x = f() ?? return none` is `x = try f()` says "zap fmt applies it", but three fmt
   runs leave it (met in recomp.switch's textures/decode.zap; written by hand).
28. A function whose parameters are `move` is accepted as a value of a `fn` type whose
   parameters are not, and the call through it hands the callee garbage (an engine.Program whose
   id indexes past the registry; met in recomp.switch's render ShaderTable.setParams; written
   with borrowed parameters).
29. `fn f(m str) T?: list.find(.name == m)` (a module list of structs) passes the checker and
   stops in the backend: `backend-refused: the intermediate form cannot take it: an optional
   reference to T read`, and the function is never generated (met in compiler/shader's
   textures.zap; written `(try list.find(...)).copy()`).
30. An enum's `.Variant` takes no enum from the expression around it: `[Kind.A, .B]` and
   `Kind.A if c else .B` (a function without a declared result) are `enum-unknown` (met in
   recomp.switch's shaders/emit.zap and texture.zap; written with the type named, or the result
   declared).
31. A module's binding that is not `mut` and is set by a call (`pub value = made()` in a module
   other than main's) runs its initializer at every read, not once where it stands (spec 5):
   `made()` counting its calls reads 1, then 2 (met in recomp.switch's cpu/memory.zap, whose
   window was reserved again at each use and refused the second time; written `mut`).
32. A small method's cold path is inlined into every caller with what it formats:
   recomp.switch's `Memory.index` noting a fault as `"{n} bytes at {at:x}..."` put the message's
   formatting and a 1.5 KB frame, zeroed at each entry, into every translated function (190 bytes
   of x64 a guest instruction, 90 without it); written with the fault kept as numbers
   (Memory.faultAt) and formatted where it is read.
33. `extern "vulkan-1.dll" "vkUpdateDescriptorSets" fn updateSet(...)` beside the module's own
   `extern "vulkan-1.dll" fn vkUpdateDescriptorSets(...)` makes a Windows program that ends at its
   start with code 127 and no line (every engine example, d3d12 too); written `extern loaded`,
   bound through vkGetDeviceProcAddr (rhi/vulkan/sets.zap).
34. `asks[k].types.extend(try grow(asks, ...))`, where grow pushes to asks, loses the extension
   (a list of structs of a text and a list: the place is taken before the call moves the list):
   a value made first and assigned after (keptir.zap's keptPlanOf does).
35. A function returning `str?` as `xs.first.copy() if not xs.isEmpty else none` over a filtered
   list of windows, or as `(try said.lines().find(...)).copy()`, builds with no error, and the
   build ends with "x64: function 'f' was referenced but never generated" (the backend's refusal
   is not told; met in compiler/tools/branch/worktrees.zap's ignoredOutsideBuild; written as a
   `for` with an early return). The same message came from the switch worktree's compiler
   building merged sources it had not seen (numberLiteralLength), fixed by a seed bootstrap.

### 2. Compile time and executable size

**Priority: a large program's build.** BotW recompiled (projects/recomp/switch) is 18.9 million
lines of Zap for 7.7 million guest instructions, built as 131 loadable parts (`zap build
--loadable`): about 15 s and 1.6 GB a part, 26 to 36 minutes for the whole with two at a time,
and again after any change. SavageWindRecomp builds the same game as 552 MB of C with clang -O1,
12 jobs, in 17 to 19 minutes and 2.9 GB in all: the code is as large, the compiler is not as
heavy. In the order they pay:
1. Memory per line: about 10 KB at the peak, so a 16 GB machine builds two parts at once where a
   C compiler builds a dozen. Find what holds it (the checked tree, the IR, the per-function
   passes' copies) and keep what a part needs, not the whole program's at once.
2. Modules checked and lowered once: each part imports the modules its code reaches (cpu,
   arm64) and checks and lowers them again, 131 times a build. Keep a module's checked and
   lowered form (by the hash of its sources and the compiler) and reuse it across the parts of
   a build and across builds: the separate compilation a large program needs.
3. Lowering on every processor (below): on a large program the serial lowering is the largest
   phase left.

The compiler builds in about 7 s single-threaded: lowering and codegen per function in parallel
(`.parallel()` over the functions, the writer sequential). `.text` is 9.5 MB for 4,590
functions: identical generic instances and derived drops merged by a hash of their bodies (LLVM's
MergeFunctions), the panic paths out of line (a lead of 18), functions laid out by the call graph
hot-first from the bench's counts. Measured by `--only size` (`build`, `exe`, `functions`).
The recompiled games are the case that matters most (projects/recomp/snes): DKC is about 4,000
small generated functions and dispatch matches of 1,300 to 2,700 integer arms, 13 to 23 MB a game,
rebuilt on every fix. Its shape is measured by `--only size` through tools/recompshape.zap (2,700
translated functions, 1,280 interpreter ones, a 14 MB exe; its header's `writes:` line). Where a
cold build of it goes, by processor time: about 65% the per-function passes (already on every
processor), the rest the main thread alone: lowering 45% of it, checking 23%, parsing 10%,
emitting 8% (measured before inlined bodies were copied: a body lowered alike at two calls of a
function is copied at the rest, irbodies.zap, a cold build 33 s to 25 s). So on an idle
machine the build waits on the serial lowering and checking, on a loaded one on the passes. Left:
- the lowering and the check per function on every processor. The passes already run as jobs
  while the round's lowering goes on (irpipe.zap), so a cold build waits on the serial lowering
  (on recompshape's program 61 s of 100 s, 4,089 functions none over 0.2 s; `ZAP_RUN=lowershared`
  counts what each adds to the shared state: most add nothing). The lowering no longer writes the
  nodes (its decisions wait in g.irMarks until irOwnSettle), but the checker calls it reaches
  still do (readBody's kept bodies, resolveTypeOrNumber's cache of a type node's type, an
  instance checked) and write about 20 module variables: typeIndex and typesMet (tyOnce),
  dropsHeld, waitingBodies, the kept stages' asks (typesPast, spansAsked), the phase cycles, and
  on resolveType's rare paths (a derived type's text parsed, an instance checked) the errors'
  state and prints, the source caches and hashes, numberBodies, shaderCalls and the lint's notes
  (formNotes, noting, importUses). The parallel effect check judges every path, not the one
  taken, so a `.parallel()` body needs the checker's answers through lookup-only chains, or a
  stop-and-redo path (the function lowered again on the main thread) from about 190 call sites.
  The ways out: lookup-only copies of the chains the lowering reaches (sizeOf, resolveType,
  isPlainType and their callees), days of work; the same for functions without type parameters
  alone, reading the types cached on the nodes, fewer chains; parts as processes that load and
  check the program and send back their lowered forms renamed as kept forms are, no shared state
  but a process's memory each. It pays for a single large program; a build cut in parts (BotW's)
  already fills every processor with its parts.
- a large program's memory per line, so a 16 GB machine builds many parts at once: a cold build
  of recompshape's program (240,000 lines) peaks at 0.71 GB (`ZAP_RUN=phases` prints each
  phase's memory). The checked tree is most of it: 0.49 GB once loaded, 1.9 M nodes of over 200
  bytes each (five lists, two texts and seven words a node, most of them empty), then 0.12 GB the
  code phase holds over it. Next: a node of about 64 bytes (kind, place and flags in narrow fields, the lists and the
  second text in side tables as DeclPart holds a declaration's parts), then the checker's
  per-function tables freed once a function's code is made. The recompiled BotW's parts build
  only on recomp.switch's branch (`--loadable`, std's cipher): measured there once it lands.
- the settle rounds (irSettle, some thirty a function whatever its size) find their facts and
  block hashes again over the whole function each round: about 13% of the passes; the passes
  change only the blocks they visit, but a round's visit is most blocks (66%), so an incremental
  count did not pay;
- what the modules kept checked and lowered (spec 14.2) leave: recompshape's program, its cpu and
  game modules kept, builds after an edit of its entry in 1.9 s instead of 11.4 (check 2.5 s to
  0.12, code 7.3 to 0.23), now mostly its load (1.0 s, 0.9 before: the game stage's kept state
  decoded whole, as step 18 says of rt/core's) and its write; the compiler gains nothing, its code
  being its entry's parts. Left: a module after the first with a GPU file is checked each build
  (a shader's link reads the program's declarations, which a kept stage takes out), and a kept
  module is still parsed (from build/cache/parse/) though only its imports and reads are needed,
  as a std module's index (stdindex.zap) gives them.

### 3. What the registers by uses left

Block counts are guessed by branches, an innermost loop's integers and floats are vregs of their
own (irloopsplit.zap), a read-only copy shares its source's register or slot and copies between
spilled vregs share one slot (arm64 cycles: sudoku 1.015, lru 0.993, havlak 0.996, binarytrees
0.988). Left: havlak's `numbering` and `predecessors` are even per function, and still spill
with AArch64's own set (25 integer registers, but x0..x7 only for vregs no call or scratch-using
instruction meets, so what lives across a call has x19..x28 alone); loops around an inner loop are
not split.

### 4. What the Skyrim port asks of the language

Landed: `?.` calls and clears on a mutable optional, `e.Variant` reads a variant's value as an
optional. Left to zap-6b: skyrim's `Item` (a `kind` and about 8 kind-specific fields) as an enum
with payloads, the conversion now mechanical (`item.weapon` is `item.kind.Weapon`).

### 5. What the Skyrim port asks of the std

1. The other readers moved to `T.fromBytesAt` (bsa.zap reads with it): the `u32le(at + N)`
   offsets left in hkx/packfile.zap, esm/file.zap, esm/condition.zap, lip.zap, fuz.zap,
   strings.zap and hkx/layouts.zap.
2. std/archive: sources of files by key (a Data dir's archives, loose files), from bsa.zap and
   install.zap; `installFind` walks every archive's keys a call.

### 6. What the Skyrim port asks of the engine

1. One up axis: physics, navmesh and particles are Z-up, the scene and renderer Y-up; skyrim
   converts at the seam (`yUp` in game/cell.zap:60, `skyrimPoint` in sound/scene.zap:31, 17
   uses, cast.zap:62's root node to turn the skeleton).
2. A pose of N layers: engine/scene/skin.zap:45's `Pose{clip, from, blend}` blends two clips;
   `Pose.layers {clip, time, weight, mask}[]` with a mask a bone, `turned` a bool[] (skin.zap:235
   is a linear search a node); game/graph.zap:325 drops the layers past two and finds clips by
   name a frame.
3. A state machine for behaviour graphs (engine/scene/statemachine.zap): game/graph.zap's 469
   lines and skyrim/hkx/graph.zap are generic but `moveStart`/`Speed`; node state in 9 parallel
   maps (graph.zap:34-45), `reached = {}` and `queue.remove(0)` a frame, bounds found by name.
4. One skinning and pose: actor/skinning.zap (CPU, `boneWorld @ skinToBone` again a call, the
   Part copied to change positions) and actor/pose.zap repeat skin.zap:207-239's `poseWorlds`;
   hkx/spline.zap is a B-spline beside engine/scene/curve.zap.
5. DDS prepared for the GPU in the engine (game/textures.zap:98-125: BC kept only at multiples of
   4 and not sRGB though render.zap:141 has Bc1Srgb/Bc3Srgb, cube faces decoded to RGBA8, no
   mips made); goes with the assets step.
6. An audio bus (engine/audio/bus.zap): categories with inherited volume, distance curves,
   ducking, crossfade and music by priority, from game/sound/book.zap:49-123 and music.zap.
7. engine/swf's AVM1: bindings resolved once and `player.on("CloseMenu", fn)` (interface/hud.zap
   builds `"{base}.Set{name}MeterPercent"` a frame; each menu compares names).
8. Pixel comparison against captures (skyrim's compare.zap) in std/image.

### 7. What the recompilers ask of the language, the std and the engine

Read from projects/recomp (snes, x64, touch); each item names what the code does today and the
form that removes it. The project moves to each form in the same change (migration), measured
by tools/recompshape.zap (`--only size`), the games' frame checks and the bench.

1. **A module's state declared once.** Each part of the console lists its variables three times:
   declared, zeroed in `<part>PowerOn()` and written and read in `<part>Fields(f)` (29 such
   functions, 156 lines of `x = f.int(x)`). A `state:` block of a module holds module variables
   as `mut` declarations do (the names stay bare in the module's code), and the compiler derives
   for it `reset()` (every variable to its initial expression), `toBytes()` and `fromBytes()`
   (spec 7.7's layout, nested values and lists included), reached as the module's `state`:
   `console.state.reset()`, `console.state.toBytes()`, `console.state = ConsoleState.fromBytes(r)`.
   What a load rebuilds (line buffers, fetched tiles) stays outside the block. savestate.zap's
   StateFile goes; a save state in memory is a copy of the value (rewind, netplay).
2. **The dispatcher as a state machine (compiler).** A translated function is `loop:` over
   `match pc:` of 1,300 to 2,700 integer arms (emit.zap), each jump `pc = K` then `continue`,
   and each call followed by `if cpu.ret == A`. Two rewrites in iropt: a `continue` whose loop
   begins with a `match` on a variable the arm just assigned a constant jumps to that constant's
   arm (or to `_`), the match skipped; a sparse integer match whose keys share high bits (the
   addresses of one bank, `widths << 24 | address`) switches on the low bits of a two-level table
   (bank, then dense) instead of a comparison chain. Measured by the games' cycles a frame and
   the exe size (step 2's shape).
3. **The interpreter on number parameters, not texts.** interpret.zap writes 1,280 functions,
   one an opcode in each widths (`i{op}{widths}`), from the same translation as the games'
   code. No new syntax: a number parameter (spec 3.6) carries the widths as the bits e, m, x,
   `fn lda<W u8>(at u32) u32`, each instance folded as literals would be, and the step's match
   names the instances (`0x0A9 | 3 << 8: lda<3>(at)`); the body of each opcode is written once in
   Zap, by hand or by the translator, and the translated code calls the same bodies
   (`cpu.adc<W>(operand)`) where today it copies their text. The project's change (snes/
   interpret.zap, emitops.zap), the Switch recompiler's forms (its cpu/forms.zap is written from
   forms/ the same way) after it; the compiler only checked: instances of one body merged (step
   2) and `W & 2 != 0` folded in each instance (`disassembly`). Measured by the interpreter's
   function count and the exe size.
4. **A word's bytes.** 44 `lo | (u16(hi) << 8)` and six functions of cpu.zap that differ only by
   the wrap of the address (bank 0 or the 24 bits). On the integer types: `u16.from(lo, hi)`,
   `u32.from(lo, hi)` (two u16) and `u32.fromBytes(b0, b1, b2, b3)`; `w.low` and `w.high` (each
   half as the half-width type, readable and assignable: `w.high = v`); `w.bytes()` a fixed array
   of its bytes, little-endian. Lists already read a word at an offset (`u16.fromBytesAt`).
5. **Code written as code, not strings.** emit.zap, emitops.zap and interpret.zap build Zap
   source with `put(depth, "...")`, `hex(v, digits)` and tabs counted by hand; x64 and the
   Switch recompiler write the same way. std/codegen: a `Source` that keeps the indentation
   (`s.line("cpu.push8(v)")`, `s.block("if cpu.c:")` opening one level until the block's end,
   `s.temp("v")` naming temporaries), prints integers in the form fmt writes (`{k:#08X}`), and
   gives the text fmt would give, so an emitted program is already formatted. In the compiler:
   a `match` on string literals and `x in [...]` of literals (144 matches on the mnemonics,
   `i.name in pushes`) compiled as one switch on the length and the bytes, no string
   comparisons; measured by the translator's time on DKC.
6. **The 2D frame in the engine.** compose.zap decides each pixel of each layer by a call and
   several tests, `withBrightness` divides three times a pixel, and the windows are tested a
   pixel at a time though they are x ranges; DKC's, Lemmings' and Prince of Persia's frames do
   the same in their own words. engine/tiles: `Layer` (a tilemap of entries, 2, 4 or 8 bits a
   pixel, scroll, two priorities, a mosaic), `Sprites` (placed, priority, palette), `Windows`
   (per layer: x ranges and their logic, resolved to spans once a line), a `Blend` (the sub
   screen or a fixed colour, add or subtract, halved, by layer) and `Palette` (15-bit entries, a
   brightness table of 16 by 32). `composeLine(layers, sprites, windows, blend, out u16[])`
   merges by priority in `Simd<16, u16>` (the highest priority's colour taken by masks), the
   window spans cutting the loop's ranges rather than tested a pixel. The SNES keeps its register
   decoding and feeds the engine's structures; mode 7 and high resolution are its own layers
   through the same merge. Measured by frames a second headless (140 today, NOTES "Left" 2) and
   the frame checks against Mesen 2 unchanged.
7. **The memory map as a page table.** console/memory.zap's `read8` decodes the bank, asks the
   coprocessor and `cartridge.isRomAddress` at every byte; x64/memory.zap keeps 4 KB pages in a
   map behind a last-page cache. engine/memorymap: one `u8[]` holding every memory (ROM, work
   RAM, battery RAM in turn) and two fixed tables of the page's offset into it (reads, writes;
   -1 a page a function answers: the registers, the open bus, a coprocessor, ROM for writes), the
   page 8 KB for the SNES's 24 bits (2,048 entries) and two levels for x64's 48 (the top 36 bits
   a map to a table of 4 KB pages, the last table cached). `read8` is a table load, an add and an
   index, the slow path a call. Both recompilers and the Switch one read through it. Measured by
   the games' cycles a frame.

### 8. rhi inside the engine

`rhi/` is the engine's GPU layer (one device over Vulkan and Direct3D 12) and nothing outside
engine/ imports it: engine/render, engine/scene, engine.zap and one of its tests. It moves to
`engine/gpu/` (`import engine.gpu`; its core/, vulkan/ and d3d12/ with it), so the root holds the
language (compiler, runtime, std, spec, tests, tools), the engine and the projects. The name says
what it is where rhi is Unreal's word; `std/gpu`, compute without a window, becomes `std/compute`
so the two names tell them apart. A layout change and its migration in one: the imports, the
land's dir rules and spec 13's words for them (zapbranch names rhi/ beside engine/),
compiler/driver/modules.zap's note, AGENTS.md and the engine's README; `zap test engine` and the
projects' shots prove nothing else moved.

### 9. The engine's per-frame costs

Each measured by frame time (`projects/examples/stress`, `--bench N`, `--case boxes|sprites|crowd`,
`--unsorted`): `readBuffer` and `readStorage` on `waitIdle` (a readback ring read one frame late,
once a program reads back each frame); HDR and MSAA targets in RGBA16F (R11G11B10F, a transient
MSAA target, reverse-Z). For the phone, where the fragment is the bottleneck: lights by cluster
(skyrim's `paramsOf` sends every light and each fragment walks `lightCount`; a tiled or clustered
list per depth slice), shadows of lights that do not move made once and kept (the inn's, when
step 5 of skyrim's milestones adds them), an `f16` type in the shaders' language for colours,
normals and uvs (Mali's `mediump` doubles the throughput), and `Frames` with a target rate and
pacing (vsync, `VK_GOOGLE_display_timing`) so a phone does not heat and lose its clock.

### 10. Assets compressed

Every image reaches the GPU as RGBA8 (gltf.zap, render.zap) though `TextureFormat` has BC1..BC7;
a skinned vertex is 22 floats (88 bytes); a sound is kept as f32. `zap prepare` encodes BC7 (BC1
for opaque, BC5 for normals) with the mips into the prepared file; vertices keep position in f32
and normal, tangent and uv in snorm16 or f16, joints in u8 and weights in unorm8 (about 40
bytes); sounds in i16, converted in `resample`. No Android GPU reads BC: the rhi gains the
ASTC formats (4x4 and 6x6, sRGB too), `prepare` writes a target's formats (BC on Windows and
Linux, ASTC on Android, transcoded from the game's BC1 and BC3 in skyrim's textures.zap, which
today keeps them and decodes the rest to RGBA8), and the prepared file holds one set per target
it was made for. Measured by `--only size` and the projects' memory, `--only shots` unchanged.

### 11. Passes kept in the tile

Each pass, resolve and compute stage declares what it uses (rhi/core/barriers.zap), and both
backends derive their barriers and layouts from it. On a tile-based GPU (every Android one) what
leaves the tile costs the whole screen of bandwidth, so the same declarations make subpasses: a
pass that reads only its own pixel of the one before (skyrim's scene, then its grading) stays in
the tile (VK_KHR_dynamic_rendering_local_read, the pixel read as an input attachment, nothing
stored between); depth and the MSAA target are transient when no later use reads them (a
TextureDesc flag the engine sets: TRANSIENT_ATTACHMENT in LAZILY_ALLOCATED memory where the device
has it, depth stored DONT_CARE, the samples resolved by the pass's resolve attachment rather than
vkCmdResolveImage, which desktops gain too); bloom runs at a quarter of the screen and the eye's
adaptation is a compute reduce, not a chain of screen passes (these two change the pictures:
their shots kept with `--update` once looked at). No GPU here is tiled or has lazily allocated
memory: measured by `ZAP_RUN=gputime` on the examples and the projects on Android.

### 12. GPU-driven drawing

Nothing in engine/ culls: every mesh is submitted by a CPU draw (scene/mesh.zap, scene/model.zap).
An `Aabb` per mesh and a `Frustum` from the camera; a compute pass culls by frustum and by a
two-pass HiZ occlusion test, compacts the survivors into `DrawCommands`, and one counted
`drawIndirect` per material draws them (the indirect path and `setDrawCount` already exist).
Skins posed only when visible and by a distance LOD. Measured by `gputime` and frame time on
skyrim and minecraft. Needs 13.

### 13. Entities as columns

A lead of 18 made an engine API: a `Transforms` store in columns (struct of arrays) with a
dirty-flagged hierarchy, uploaded in one write, and the entity sets of the projects walked by
`.parallel()` over the columns (Unity's DOTS, Bevy); a per-frame arena reset between frames.
Measured on skyrim's crowd and minecraft, and skyrim's particles (`particles.push` per particle,
`shakes` and the quads' `out` pushed each frame) and physics (`bodyPairs` and the manifolds in
lists, each pair's SAT in turn) as columns walked by `.parallel()`, which is what a phone's small
cores can take. Needs 11.

### 14. The phone's window

An app runs on the emulator (`zap run --target android-x64 --apk`, spec 13.1), the engine's GPU in
its window (Vulkan 1.3; the emulator's `-gpu host` gives it, `swiftshader_indirect` only 1.2).
Left: devices of Vulkan 1.1 and 1.2 (dynamic rendering, synchronization2 and the extended
dynamic state from their extensions, or render passes); the images turned by the GPU
(pre-rotation) rather than by the system; the input queue read on a thread of its own, so a
program whose frame lasts seconds (recomp.switch's deko_basic) is not stopped as not responding;
an end that closes the activity instead of ending the process; a crash inside an app reported
with Zap's stack, at once rather than after the run's time limit. It and the phone items of 12, 13 and 14 are what skyrim's
milestone 15 (Android) stands on, in that order: without the window and ASTC nothing is
measured there; the tile items then decide its frame rate.
### 15. The allocator

runtime/core/corealloc.zap, each measured by `peak` and the allocation benchmarks (binarytrees,
wordfreq, httpjson): big blocks rounded to a power of two (up to half the commit idle) rounded to
steps of 1.25x instead; the 2..4 KB classes losing 7 to 25% of a 16 KB page's tail given 64 KB
pages; the 4 MB chunk committed whole at a thread's first allocation reserved and committed 64 KB
at a time, an emptied chunk decommitted; a cached big block memset whole on reuse, `readFile`'s
buffer zeroed before the read overwrites it, both raw for callers that write the bytes; the map's
table one block (header, marks, cells) instead of three. (Drops already come at the last use and
a freed block goes to the next allocation of its size: peaks are data still in use, the
compiler's 154 MB loaded, 262 MB checked, 312 MB generating code.)

### 16. The runtime's hot small paths

Measured on the benchmarks that touch them: `{x:.2}` through an exact bignum (num.zap's
fmtFixed) given a wide-multiply path for `dec <= 17`; bytesHash's serial FNV chain given four
lanes for keys of 32 bytes or more (rapidhash); an interpolation of 22 bytes or fewer built in the
frame, no block; stdout's buffer reserved at first use, stderr written without a block per line, a
pipe read straight into the list's spare capacity; `programArgs` parsed on first use; a channel's
wait on `WaitOnAddress` with no 10 ms timeout; `background` jobs on the pool, not a thread each.

### 17. Leads

Each to measure (one at a time, A/B) and to fire beyond its benchmark:
- Alias facts from ownership (rustc's `noalias`): a store through one owned list cannot alias a
  load from another or from a `self` field, so loads live across it and leave loops; memory
  versions per block (LLVM's MemorySSA) make the cross-block reuse cheap once split by owner.
- Layout (.NET 10): every panic path out of line, a loop's blocks contiguous.
- Loops: i32 counters widened to i64 (no extension per round), an `i * stride` index as a stepped
  pointer (RyuJIT); fill and copy loops to the runtime's wide copies (LoopIdiomRecognize); `while`
  loops with an early exit vectorized by an exit mask (GCC 16).
- irpairs grown into an SLP vectorizer over stores and reductions, with identity lanes for a
  missing twin (LLVM 22): the engine's vec3 and matrix code by the same path as raytrace's.
- Inlining: the limits stand at 40 nodes for the program's own bodies and for runtime bodies
  called outside a loop in a function with no loop (irlowerfunction.zap), 24 for a runtime body
  inside a loop. `ZAP_RUN=irinline` names a body refused for its size.
- The compiler's own time: the ownership pass's snapshots of every variable at each branch
  (`snapshotMoved`); checkEffects' addChanged (effects.zap), quadratic in a body's changed paths,
  8% of a check.
- The suite's other kinds (check 174 s warm, cold about 415 s at --jobs 2 with the lint verifying
  inside the checking zap): build beside dups, limits and check. The tests kind is step 1.
- Memory: a box or list made and dropped in one function, never moved out, in the frame (.NET 10's
  escape analysis); a drop followed by an allocation of the same size class reuses the block
  (Koka's Perceus, Lean 4's functional-but-in-place); drops at the last use rather than the
  scope's end (Mojo, Nim's ARC), irowntake run again after inlining (Swift's OSSA); allocation
  entries per size class known at the call site (Go 1.27).
- Effects: `nothrow` and `terminates` beside purity.zap's pure (Julia): no panic path in the
  caller, invariant pure calls out of loops.
- One table of rewrites (pattern, condition, replacement) read by iropt and by fold (Cranelift's
  rules, its e-graph a larger step); tiling and interchange beside irjam, chosen by a small cost
  model, nests versioned by size (Halide, Futhark) for matmul and the tensor kernels.
- For the engine, not a benchmark: a struct-of-arrays type transform and a per-frame arena reset
  (Odin, Jai).

### 18. zap run in place of Python for the agents' scripts

The agents' throwaway scripts (searches, counts, reports, file shuffles) are written in Python
today; `zap run file.zap` is to be the quicker and the plainer choice. A run of an unchanged file
starts the executable it kept; an edited one is built again from the runtime and std kept
checked, lowered and as machine code (spec 14.2), their functions' bodies read from the kept file
only when the build lowers, inlines or instantiates one. The goal is measured by the scripts bench
(`zap test --only bench tests/scripts`, spec 13.1): eleven scripts on fixed inputs, Zap edited
over Python in bench.baseline, each process started directly (a shell's own start hides the
difference); the work is to lower those ratios.
The bench runs on the arm64 machine (arm64 in ZAP_SETUP, two processors): there Python's runs take
21 to 54 ms, Zap's unchanged 3 to 24, an edited table.zap's 39 ms are about load 7 (the kept
stages' nodes 3: 9,400 of their 38,700 decoded), check 6, code 13 and write 2, and csvsum.zap's 51
about load 7, check 7, code 22 (main and its passes most of it). Left:
1. Further under python's time:
   - main lowered, its ownership checked and its registers allocated each build, its calls
     inlined (4 to 10 ms there), and its form written for the IR cache's key and looked up there
     (irMadeReady, 2 ms of csvsum.zap's);
   - the instances the program's check recorded checked in the check phase (5% of csvsum.zap's
     build): put off to the code, where a taken form skips them, they are recorded in another
     order, and so the executable's functions laid out; those the program's code inlines checked
     again (irInstanceCall's askChecked); those that call a function the program's check derived
     (a sort of tuples calls `$cmpN`, named by count: sortSpan, mergeFrom, listSortByKeys) lowered
     with the derived ones each build;
   - the kept stage's declarations decoded whole each build (3 ms of 9,400 nodes: their texts and
     lists allocated one by one; read in parts on two processors it did not pay, the allocations
     contend), and the checker's tables after them (newChecker's indexes, 1 ms);
   - the kept code placed, about 4 ms for 150 to 200 functions (each one's form record read, its
     asks made again, its code placed); the backend's functions that move an IrMade zero frames of
     7 to 37 KB at each call (irShip, irPipeDrain, irKeptForm, irEmitMade: the slots of their
     temporaries not shared);
   - the kept forms of the functions with a lambda (an environment's function and a lambda's body
     are named by count: `$env:N`, `$lam:e:N`; the initializers of `threadsEnd` and
     `crashFilterSet`) and of those whose lowering checks an instance that makes nodes outside its
     copy;
   - the effects of the kept stages' functions summarized again each build (findEffects: 2 ms of
     a small build), and their facts read whole (1 ms);
   - some 700 calls a build to map memory (mmap 110, munmap 213, mprotect 381): a big block is
     mapped, its ends cut off, its header page and its pages committed apart;
   - on Windows, every look at a file costs about 50 us (GetFileAttributesEx; a dir's listing
     100), and a new executable's first start 8 ms more than its next (the antivirus reads it): a
     loader that maps it as data took 4.6 ms off (measured with a throwaway C one);
   - the backend's merge of the same code (its signatures made once, 1 ms), the jumps'
     relaxation and the executable's writing (1 ms each).
2. What eleven agent scripts written in both (grep, loc, json, csv, replace, todo, diff, git log,
   numstat, a TSV sum, the walk) found Zap lacking against Python:
   - a map's value changed in place by key (`stats[ext][0] += 1` with a default), as Counter and
     defaultdict do; a text key needs `.copy()`;
   - maps walk in hash order (Python's in insertion order): a sort's ties print differently;
   - `groupBy(it.0)` on tuples refused (`tuple-position`): a type declared for it;
   - `zap doc runtime` lists `T[].contains` and `T[].repeat`, a call of them is `no-method`;
   - misleading messages: `x ?? fail` ("'error' is a result's error"), `str[][]` ("expected ')'"),
     a lambda bound to a name ("cannot-infer-lambda-parameter", a wrong type suggested),
     `a ?? 0 < 3` read as `a ?? (0 < 3)`;
   - fs.walk's paths carry the dir, its doc says "path from dir"; no copy of a dir (copytree);
   - a record built from `keys()`' strs needs `.copy()` (`move-of-borrowed`);
   - `a = b = 0` refused; no `reversed()` of a range; `xs[..15]` stops past the end where
     Python's `[:15]` takes what there is; a str sliced by byte can cut a UTF-8 character.

### Later: what less to write left

The cuts landed and the old forms are gone from the compiler. Left:
1. About 56 `?? return none` and 6 `?? fail(error)` stay in files fmt's lint never sees, since no
   check reaches them on Windows (engine/post, scene, render and swf, rhi/d3d12, std/gpu, the
   Linux dirs, tests/programs/parts): each reached by a check, then `zap fmt .` again.

### 19. arm64's code as good as x64's

Measured on the arm64 host (cycles against the best of C, C++ and Rust, `--full`): revcomp 5.64,
httpjson 5.35, knucleotide 2.82, fasta 2.80, havlak 2.35, fannkuchredux 2.28, nbody 2.15,
regexredux 1.93, lru 1.83, binarytrees 1.53, sudoku 1.42, mandelbrot 1.31, base64 1.26,
strsort 1.25, jsonrecords 1.20, pidigits 1.20, exprtree 1.19, brainfudge 1.07, spectralnorm 1.06,
nsieve 1.04, raytrace 1.01; under 1.00: wordfreq 0.65, matmul 0.79, dijkstra 0.89,
coroprimesieve 0.95. Left, worst first:
- fasta: drawRounds' loop makes its constants at each turn, its multiplier and addend (a `mov`
  each: AArch64's mul and add of a register take no such immediate) and `% im`'s magic number and
  divisor (a `mov` and a `movk` each, a64DivByConstant); writeRandom's `draws[at..]` window is
  written to its frame slot and read back each round.
- httpjson: `parseHead` 21% of the samples; havlak: Finder_collapse 33%, numbering 25%.

Suggested by a review of the gaps, ranked (general passes unless said):
- Before attacking the 5x ratios: Linux's cycles leave out the kernel (std/perf/linux/perf.zap:31)
  where Windows' include it, so syscall-heavy problems read worse on arm64; check wall time too.

### 20. Every problem under 1.00x

Twenty-five problems, every one under 1.00x against the best of C, C++ and Rust at `--full`, the
rivals improved within the rules as Zap is; `bench.baseline` recorded again then (it still holds
the ratios against the old rivals). Geometric means: Zap's time 0.71x C's, 0.80x C++'s,
0.80x Rust's; memory 0.83x, 0.74x, 0.72x; tokens: C 2.16x Zap's, C++ 2.35x, Rust 2.10x, Python
1.06x. Over 1.00x (cycles, `--fresh all`, one problem at a time on Windows), the
others under:
- lru about 1.5x (Rust): findCell's 56 instructions a miss against Rust's 20, list headers and
  locals spilled (step 3), the map's probes (step 26).
- httpjson about 1.21x (Rust, cycles): its messages are views of the connection's buffer now;
  its peak memory went from 0.87x to 1.07x Rust's with them (bench1, being looked at).
- coroprimesieve 1.34x (C++): its division loop, about 14 instructions a prime against C++'s 5,
  and two hyperthreads sharing a core's divider.
- sudoku about 1.2x (C): the spills of `choose`'s outer counters (step 3); its i8 count's check
  is under 1%.
- havlak about 1.21x (C, `--full`, cycles): headers now leave loops and integers keep
  registers across calls on x64; left, a growth call reloads every held header, values split at
  loop boundaries, arm64's allocation across calls (step 3).
- Under since the last list: brainfudge 0.92x, pidigits 0.87x (bench1's 7c1d8ce7, next batch);
  mandelbrot 0.97x, at the multiply ports' limit like its rivals.
Suggested by the review: httpjson's Rust rival does not parse HTTP (head end, `starts_with("GET
/plaintext ")`, the id at offset 13; httpjson.rs:89): the rival parses headers as Zap does, or
both scan alike, and http.zap's headEnd and byteIndex go through the vector `byteIndexIn`.
havlak: `irSplitLoop` (irloopsplit.zap, vectors only) for integers live across calls, and
`listPushRaw` with the growth in a cold call returning the header. sudoku: the panic stub out of
line and store-to-load forwarding in `sr[rr] += 1; if sr[rr] != 1`. coroprimesieve: u32 in the
Zap program (C++'s int is never negative) drops the -1 check; measure with each thread on a core
of its own, since two hyperthreads share a divider.

### 21. nsieve won without irmergeupdates

irmergeupdates went (a narrow shape worth 4%); nsieve, 0.97x with it, measured again
and won another way. The other passes found only in their benchmark (the carry chains, the jammed
nests, the f64 pairs, the affine unroll) stay as rules of shapes any program can have.

### 22. havlak and brainfudge

- brainfudge 1.06x C++'s before `pc < ops.len` and `ops[pc]` became one comparison (0.952x
  cycles on arm64): the checks of `tape[head]` and `head += arg` left, which C++'s program does
  not make and no range or guard proves (C).
- havlak 1.11 to 1.25x C's, varying with its large lists made each run: the invariants hoisted and
  then spilled in `predecessors` (step 3), bounds checks, list headers read through memory.

### 23. httpjson

1.35x Rust's cycles. Left: the allocations of each parsed request (the strings of the start line
and the headers), the threads' wake-ups on the loopback, one send per batch of pipelined responses,
TCP_NODELAY, a reused read buffer, and a sampler that follows the jobs to see the rest.

### 24. pidigits

1.02x to 1.04x against C over GMP, whose limb loops are hand-written assembly. Left: a scratch limb
buffer kept between steps, the 64x64 to 128 product a single `mul`.

### 25. regexredux

0.89x time against Rust, 1.02x memory, 1.66x cycles: the counts scan at 1.4 ns a byte on every
core, Rust's Teddy at 0.6. The substitutions are the critical path, one core: about 55 ns a match,
the call chain of a locate (skip, anchored scan, two builder appends). Left: a vector scan for the
pattern's first bytes or longest literal before the automaton, a byte shift on `Simd<32, u8>` for
a nibble-table prefilter, the five substitutions in one pass. Not in std/regex yet: Unicode classes.

### 26. Maps found once

lru is at Rust's 1.6x, findCell 46% of its time, memory-bound: Zap's table holds 266k cells for
100k keys (a third full) where hashbrown's holds 131k (three quarters), and `put` probes for the
miss, then for the set, then the open cell. Left, each measured by A/B (no perf counters on
Windows): the probe set against hashbrown's, a power-of-two size with a mask instead of `homeOf`'s
multiply-high (then triangular probing), the integer hash one multiply, the removed marks'
rebuilds (3% of lru).


### Set aside

Steps left at a working state, taken up again when a project or a measure asks for them.

1. **A function written once runs on the CPU and the GPU.** Found by FireRed: its layers are drawn
   on the CPU because a shader's function cannot take a storage buffer as an argument and CPU code
   cannot call a `.gpu.zap` function, so one renderer cannot serve both. A plain function over
   buffers (`u32[]`, a `Grid`) is callable from CPU code and from a kernel alike, its buffers
   passed as storage on the GPU; then FireRed's PPU draws its layers on the GPU with the same code
   its CPU path runs (frame hashes the same).
2. **One table decoder for the recompilers.** Excel's 68000 (`excel1/m68k`) and FireRed's ARM and
   Thumb (`firered`) are each a text table of bits and templates read by a decoder of their own:
   one decoder, in the engine or the std, reads all three tables, and both recompilers share its
   common form.
3. **Constants computed when compiling.** A top-level constant whose value calls only pure
   functions (no I/O, no `args`, no module variable) computed by the compiler and stored in the
   executable's data; the others still made before `main`. No new syntax, no macros. Set aside:
   the tables that qualify cost well under a millisecond at start (mario's `sineTable`, 5,120
   sines, and `arctanTable`, 1,025; std/digest's `crcTable`; excel1's opcode `matchers`;
   ragnarok's JPEG `idctTable`, made per image today but writable at the top as it is), and stored
   in the executable they make it larger (mario by about 28 KB), against the spec's smallest
   executable. Comes back when a table costs time worth measuring at start.
4. **Open questions of the language**, decided later, with real code: borrows the origin rules
   miss (each case found gets a stronger inference rule); `decimal` and
   `char` (an exact `decimal` for money, annotated once, `price decimal = 19.99`, its literals
   following, mixing it with `f64` an error; and a `char` type).

## C. Tried and not achieved

Each with what was measured, so it is not tried again without a new reason.
- A program's parameters aligned in the ring by Vulkan's minUniformBufferOffsetAlignment instead
  of 256 (the stress example's 4000 boxes, 144-byte parameters): CPU cycles a frame 1.015, GPU
  time 0.261 and 0.260 ms; not kept (Direct3D 12's constant buffers need 256 anyway).
- Direct3D 12's single-texture tables pointed at each texture's own shader-visible view (copied
  once when it is made) instead of copied into the frame's ring per change: the stress example's
  boxes 1.054 unsorted, 1.091 sorted (cycles a frame, no gain); textureTables was 2-6% of the frame.
- `readStorage` read one frame late: no program reads back each frame; a stall measured 0.02 ms a
  frame on the compute example's 1000 numbers (at most the frame's GPU time).
- A list's growth storing back and reading again only its own header (irSyncSet), the other
  headers kept in their registers across it: on AArch64 havlak's `predecessors` lost x9..x14 and
  x0..x5 for its twelve header words (live across the call, which no lost register survives there)
  and spilled them, instructions 1.067, cycles 1.013; kept on x64 alone (havlak cycles 0.978 and
  1.061 in two runs, fasta 1.002 and 0.973: Windows' cycles move 6% between runs). fasta's pushes
  already held ptr, len and cap in registers on both.
- 32-bit constants of a `mov` and a `movk`, and doubles past fmov's immediate, held in a register
  before a loop on AArch64 (irHeldConstants): none in the hot loops of fasta, havlak, lru,
  binarytrees, mandelbrot or nbody (arm64 cycles 0.992 to 1.000); kept, as a loop that has them
  saves the instructions at each turn.
- LSE atomics on linux-arm64 (ldaddal, casal; Android keeps the ldaxr/stlxr loops, as phones may
  lack ARMv8.1) were thought most of httpjson's 5.4x: httpjson's user cycles 0.99, its wall time
  the same; coroprimesieve 0.985, fasta 0.984. Kept. `jobsBlocked` counted only when jobs are
  queued was left: blockingBegin runs only beside a system call (ppoll, a futex wait), and a job
  queued after an uncounted wait began would not get the thread it needs.
- AArch64's own register set (irArmPools: x0..x7 and x28 added, v22..v31 for floats where no
  vector is 32 bytes) instead of x64's numbering: arm64 cycles havlak 0.987, fasta 0.981, lru
  0.980, fannkuchredux 1.002, nbody 1.000, binarytrees 1.004, not the 10-30% the review guessed;
  kept, as it is the base the allocator's further arm64 work needs.
- dijkstra's heap binary, or taking the hole to the bottom then sifting up (Rust's way): slower
  than the 4-ary heap taken from the top with the children picked by value (binary 1.24x to
  1.32x; 4-ary 1.67 to 1.79 s).
- Dead frame-store elimination over the emitted code: about 1% on raytrace, and objects split over
  several slots make it unsafe without knowing which slots one object spans.
- A compact ordered map (dense entries, an index of small integers): wordfreq's memory 169 to 146
  MB, but its time 1.6x to 2.0x (the index, then the entry, then the key's bytes).
- Inlined parameters held in r10/r11 until the body's first call: no measured change.
- The f64 fields of a struct local a loop only reads (raytrace's `eye`, `dir`) in xmm registers
  from the loop's entry: 1.6 to 2.3 s, the inlined `hit`'s own temporaries lost their registers.
- Allocation counters only when asked: the two increments of the fast paths cost nothing
  measurable.
- A larger table load (0.9): it would fit wordfreq's keys in half the cells, but only by tuning to
  that one input.
- Fully unrolling small constant loops: mandelbrot slower.
- lru's removed cells: marked empty as Swiss tables do, the table stayed 7/8 full and the time
  doubled; marked empty only when no probe needs it (vectorized), with or without a 3/4 load
  limit, slower than today's.
- Removing a key as hashbrown does: 1.12x slower on lru (a smaller table, a miss's probe longer:
  lru's lookups mostly miss).
- `m[k] = v` and `m.add` finding the key and the cell to add it in by one probe: even on lru,
  1.07x slower on knucleotide (its keys mostly found).
- `m.get` probing directly, with no `cellOf` and `valueAt` between: even (the tiny bodies go inline
  at any depth instead). The cell's prefetch in findCell is worth 13% on lru.
- irmergeupdates (two turns a step of `xs[w] op= v`): found only in nsieve, 4%; removed.
- A spill cost per position: binarytrees 1.29x slower.
- LLVM's spill weight normalization (uses over the interval's length plus 25 instructions) with
  the loop splits: havlak 1.025x cycles on arm64 against 0.990 with the cost per 64 positions.
- Inlining sudoku's `choose` into `solve` (Rust's #[inline(always)]): 0.94 on x64, 1.10 on arm64.
- A runtime body inside a loop inlined past 24 nodes: brainfudge's loop 2% slower when `push` went
  in.
- Inlining a body that gives a reference to its own local (listBytes): its window pointed at an
  emptied local (std/image's crop read zeros); such a body is never inlined.
- coroprimesieve's spin: 100 pauses on x64 and 1000 yields on arm64 measured both ways; the spin
  costs cycles more than time.
- The guarded check-free loop copy (irguards.zap's, LLVM's IRCE) for sudoku's `sc[c]` and
  `sr[rr]`, brainfudge's `tape[head]` and `ops[pc]`: their indexes are read from memory (u16s of
  `m.cols`, `m.rows`; a head moved by amounts of `ops`), and no test before a loop bounds what the
  loop reads (a scan of the tables costs more than the 4 to 9 checks of a call). nsieve's
  `count += 1` was already proven by its counted loop. What paid instead: `while pc < ops.len`
  and `ops[pc]` as one unsigned comparison (irranges.zap's irFuseBelow), brainfudge 0.898x
  instructions and 0.952x cycles on arm64, sudoku and nsieve even.
- Small aggregates in registers (spec 14.2: up to four leaves spread, the words past a class's
  registers on the stack) measured on raytrace and nbody: their hot code is inlined and the same
  (arm64 cycles 1.000 and 0.999); it reaches the runtime's calls of five or more words (strsort
  0.992 on arm64, 0.999 on x64) and the engine's Quat and Vec3 operations of seven to twelve floats.
- Studied and not transferable: Bend/HVM2 (parallel, 5x slower a thread), Vale's generational
  references, Austral's linear types (ownership gives it), Carbon (no codegen yet), copy-and-patch
  JITs (no interpreter tier here).

## D. What performance already has

A summary of what landed, so a step does not redo it; the details are in git's history.
- Integers and loops: a u32 `/` or `%` by a constant as one imul and shift; a bit test as `bt`;
  checks ahead of a loop (widened counters and their arithmetic too), a counter's `i + 1` below its
  type's top unchecked, a check its dominator made dropped, a load or operation of the previous
  block reused; an i32's `+ - *` one 32-bit operation and `jo`; affine recurrences eight turns a
  step, carry chains unrolled, nests writing rows jammed two at a time (irjam), `it / n` and
  `it % n` of a counter carried; loops of four turns or fewer unrolled; a loop's step block laid
  out before its top; range facts through the flow (irranges) and a counted loop's checks proven
  or tested once before a copy without them (irguards); `while i < xs.len` and the `xs[i]` its
  turn starts with one unsigned comparison.
- Vectors and floats: plain loops vectorized; an FMA on its accumulator's register with a load as
  its memory operand; vector spills chosen by cost per stretch, a vector live across a call a vreg
  of its own in a loop that calls nothing, carried vectors weighed twice; 16-byte vectors in
  callee-saved xmm registers across calls; `v.lane(k)` of a constant one instruction; f64 pairs on
  both lanes of a register (irpairs); loads as the operand that uses them.
- Inlining: a function of plain parameters, or a body with no loop, called in a loop expanded up to
  48 nodes (its own small calls too); call-free runtime bodies up to 28 nodes and the tiny ones at
  any depth; one level of a recursion; hot bodies up to 240.
- Registers and frames: a frame slot's words in registers through loops that call nothing; slots
  written whole before a read not zeroed, stores no way reads gone, copies up to 32 bytes by words,
  frames zeroed 32 bytes a step; a store read back is the stored value; vregs hold registers only in
  the stretches they live (lifetime holes).
- Allocation: an arena's statement temporaries freed with the region, closed regions' chunks
  reused, a box's block the arena's next bytes; `x ?? return` of a place lends its box; a big block
  grown in place cached, a reused block's tail zeroed as it grows.
- Maps: probes 16 bytes at a time (a mirror group past the end), the key's cell prefetched, any
  size from 16, rebuilt past 7/8 half again as large, `m.add` inlined, `m.reserve(n)`; a sort's
  first k walking a map's cells in place.
- Strings and sorting: strCmp one call (words byte-swapped), `ordCompare` of strs one pass, a merge
  prefetching keys eight ahead in a room of an eighth, `(ref str)[]` sorted in place, a sort by a
  key's parts made again at each comparison (a stable merge, 32 KB of room, longer pairs split by
  rotation); `bytes.extend("{x}".bytes())` with no str between; byteIndex and count 64 bytes a step.
- Pipelines: a sum or reduce of maps and filters run in their loop; `fill(n, x)` of one byte a
  fill; byte tables of `fill(256, x)` unchecked.
- JSON: a derived decoder matches a key where it lies (the field expected next first), keeps plain
  fields as values with a `seen` mask, reads them by the runtime's functions directly.
- Threads and I/O: a channel spins a few microseconds, then waits on its lock's condition; bounded
  channels a lock-free ring (Vyukov's); a connected socket blocks in the system; a producer job
  feeding the main thread through a small channel; big map keys one task each beside the small
  ones' parts, sharing the L3.
- The compiler's own speed: a cold self-build from 33.8 s and 566 MB to about 7 s and 205 MB (the
  IR's passes one walk each, each type made once, a generic instance's body checked once, effects
  summarized by a worklist, the parse and the IR cached per file and function); a function of
  40,000 blocks from 13.6 s and 5 GB to 4.7 s and 444 MB (liveness, name lookups, settle rounds
  looking only at the blocks changed).
