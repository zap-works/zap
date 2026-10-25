# TODO

## A. Rules

- **Only what is open.** Steps are numbered 1 to N within their area in the order they are done,
  each naming the steps it needs (`Compiler 3` is area Compiler, step 3); a step that lands is
  deleted, never marked done. A project's own steps are in projects/<name>/TODO.md.
- **Order across areas:** the Language's bugs first; then compile time (Compiler) and the scripts
  (Scripts, with the Runtime and std steps they need); then the Recompilers; then the Engine; the
  Benchmarks last; Tooling whenever a step needs it. zap-engine and zap-projects only follow the
  language (each change's migration keeps them building and passing) and are revised after
  everything here.
- **Groups.** An agent takes the steps of one area that touch the same files, in a worktree of its
  own; the group's branch is tested once when merged. Independent groups go side by side, with only
  the touched files' tests between changes; the whole `zap test` runs once per merged batch, and
  what it finds is fixed in that same pass.
- **Checks.** Every check is `zap test` (spec 13.1), read by an agent; nothing is manual. A step is
  judged by the spec's goal, measured: the least time to compile, the most speed, the smallest
  executable, the least memory and the most memory safety. Each measure is kept in a baseline that
  only gets better; a step that makes one worse fails unless it says why (`--update --slower
  "why"`, the reason in the baseline and in the diff).
- **Bugs.** A new one gets a test in `tests/memory/openbugs.zap.txt` (the fuzzer's shrunk program or
  a hand probe) before its fix; the fix moves the test to `fuzzfound.zap`. Checked runs give each
  block pages of its own, taken away when it is freed, so a use after free or a second free stops
  the program at once. A bug met in a project goes to Language with its workaround.
- **A migration or a refactor changes no code by surprise:** `zap run tools/golden.zap
  build/base.exe` says whether the compiler's own code differs from the build kept before it (a dir
  after it for what the compiler does not exercise). **Each change keeps the language's rules**
  (checked indexes, exact floats unless asked, ownership) and the source plain: the compiler does
  the work, the program does not spell it out.
- **Benchmarks.** Every program keeps its problem's rule (tests/benchmarks/problems/problems.zap).
  One implementer writes every language's program as well as the language allows; Zap's edge is only
  that its compiler, runtime and std are ours. Rounds: the rivals optimized within the rules, then
  Zap made to win again through its compiler, runtime and std more than its programs. No
  overfitting: a change serves general programs and says what else it changes. A new problem comes
  with its C, C++ and Rust programs, rule and sizes, five at a time, under 1.00x before it is done.
- **Measuring.** Tests run on this machine; performance on the arm64 host over ssh (`arm64` in
  ZAP_SETUP), arm64 Linux with a production site beside it: every run there is under `nice -n 19`,
  two cores and a memory and time limit. A change is decided by the counters (`--ab`: instructions,
  cycles, cache and branch misses), which a loaded machine does not move, so A/Bs run side by side;
  time at the end of a batch, one run at a time under the machine's lock.

## B. Steps

### 1. Language

Each bug gets its test in openbugs.zap.txt before the fix. Each was met in a project; the
workaround it uses until the fix follows the semicolon.

1. **Ownership holes:**
   - A list of structs with a field of type `i64[]?[]` had that field overwritten (met grouping the
     test files; 900 fuzzed programs of that shape ran right): reduce when it shows again.
   - A lambda capturing a struct, then a later use of the struct: `read = (at i64, n i64):
     readRomImage(img, at, n)` then `romImageSize(img)` stops with `ownership-broken: v181
     (RomImage) read after it is consumed`; read `romImageSize` before the lambda.
   - A plain `match` arm's binding is not tracked by the ownership check (an `is` binding is):
     giving it away and reading it after compiles. Tracking it the same way broke
     tests/memory/fuzzfound.zap (a window into the arm's value outlived it).
   - A function with `move` parameters is accepted as a value of a `fn` type whose parameters are
     not, and the call through it hands the callee garbage (an engine.Program whose id indexes past
     the registry); written with borrowed parameters.
   - `asks[k].types.extend(try grow(asks, ...))`, where grow pushes to asks, loses the extension
     (the place is taken before the call moves the list); make the value first, assign after.
   - `expect f() == [u8(1)]` with `fn f() u8[]?`: `use-after-given` on the expect's own temporary
     (`$expect0r`), then `ownership-broken` after lowering; written `(f() ?? []) == [...]`.
   - `__addr` of a fixed array's element inside a list gives a copy's address.
2. **What the backend refuses or loses after the checker accepted it** (told at the check, never a
   crash or a silent hole):
   - A method whose result is `T ? E` crashes at run time (access violation in rt.strCopyRaw) when
     a `try` of a method of the same receiver sits inside an `if` and a value is returned after it:
     `fn pick(k i64, t i64) i64 ? str:` with `if e > 0: try inner(e)`, then `if e > 5: return e`
     and `t`; the writer keeps its first error in a field and its methods return plain values.
   - A function returning `str?` as `xs.first.copy() if not xs.isEmpty else none` over a filtered
     list of windows, or as `(try said.lines().find(...)).copy()`, builds with no error and ends
     with "x64: function 'f' was referenced but never generated"; written as a `for` with an early
     return (a worktree's compiler building merged sources it had not seen gave it too, fixed by a
     seed bootstrap).
   - `fn f(m str) T?: list.find(.name == m)` over a module list of structs: `backend-refused: ... an
     optional reference to T read`; written `(try list.find(...)).copy()`.
   - `host = args.option("--host") ?? (benchHost() if benchHost() != "" else fail("..."))` checks
     but the backend refuses "a store of str" in a program's main; written `?? benchHost()` then
     `if host == "": fail(...)`.
   - `extern "vulkan-1.dll" "vkUpdateDescriptorSets" fn updateSet(...)` beside the module's own
     `extern "vulkan-1.dll" fn vkUpdateDescriptorSets(...)` makes a Windows program that ends at its
     start with code 127 and no line (every engine example); written `extern loaded`, bound through
     vkGetDeviceProcAddr (rhi/vulkan/sets.zap).
3. **Module bindings and names:**
   - A module binding that is not `mut` and is set by a call (`pub value = made()`, in a module
     other than main's) runs its initializer at every read, not once (spec 5): `made()` counting its
     calls reads 1, then 2; `pub run = "/tmp/zap-oracle-{clockMs()}"` gave four names in one run;
     written `mut`, assigned once.
   - A local assignment named like a module variable writes the module's, silently (`shown =` in
     recomp's compose.zap rewrote output.zap's buffer index): refuse it or tell it as a shadow.
   - A test in a module's second file sees only that file (a test in std/image beside image.zap
     could not name `Image`): it sees its module.
4. **The checker refuses valid code** (each decided: accepted, or its message made to say what to
   write):
   - `i32(v) < 0` with `v u32` is `comparison-decided` ("a n32 is never below 0"), though spec 3.1
     says a sign change of the same width keeps the bits (`i32(0xFFFFFFFE)` is -2); written
     `v >> 31 != 0` or `i32.wrap(v) < 0`.
   - `u32(i32(x).abs())` with `x u32` is `conversion-round-trip` ("u32 has abs itself"), but a
     signed abs and u32's differ for every x with bit 31 set; written as a GPU function `absSigned`.
   - A function whose value is a loop's `return` and whose last statement is `fail(...)` is
     `return-mismatch: expected Vec2, got ()` (`fail` is not a value of the return type); written
     with a placeholder value.
   - An enum's `.Variant` takes no enum from the expression around it: `[Kind.A, .B]` and
     `Kind.A if c else .B` (a function without a declared result) are `enum-unknown`; written with
     the type named or the result declared.
   - `x bool?? = true` is refused: a value is wrapped in one optional layer, not two.
   - A narrow integer compared in a condition with an `is` binding stays narrowed past it: with `k`
     a `u8`, `if k == 3 and f() is v:` then `elif k == 3:` then `elif k == 4:` is
     `literal-outside-range` ("4 lies outside u8 in 3..=3"); written with the binding typed
     (`k i64 = nodes[s].kind`, irlowerlet.zap).
   - A method's `ref` result is taken as the whole receiver's: `for s in nodes[e].sub():` refuses a
     change of any other part of the arena in the body (`change-while-read`), where a loop over the
     field borrowed the field alone; `return nodes[c].names()[0]` as a `ref str` is
     `return-mismatch` ("got str"); `move nodes[e].nodePart().names[i]` is `move-needs-place`;
     written as an index loop, and through the field (`nodes[c].part[0].names[0]`).
   - A box in an optional cannot be changed through: `if self.b is mut m: return mut ref m` with
     `b Box<T>?` gives a `mut ref Box<T>`, whose fields are `type-has-no-fields`, and `return m.f`
     after `is m` is `return-local-ref`; Node's part is a none-or-one list (24 bytes, a box 8).
   - `zap doc fs` lists `File.len()` as a method, but `file.len()` is `size-is-field`.
   - From the agents' scripts (Python does these): `a = b = 0` is refused; no `reversed` of a range;
     `xs[..15]` stops past the end (`index-out-of-bounds`) where Python's `[:15]` takes what there
     is; a str sliced by byte can cut a UTF-8 character; `groupBy(it.0)` on tuples is
     `tuple-position` (a type declared for it).
   - Misleading messages: `x ?? fail` ("'error' is a result's error"), `str[][]` ("expected
     ')'"), a lambda bound to a name ("cannot-infer-lambda-parameter", a wrong type suggested),
     `a ?? 0 < 3` read as `a ?? (0 < 3)`.
5. **Skyrim's `Item` as an enum with payloads** (zap-6b): its `kind` and about 8 kind-specific
   fields become variants; the conversion is mechanical (`item.weapon` is `item.kind.Weapon`).

### 2. Compiler

Now: BotW recompiled (projects/recomp/switch) is 14.1 million lines of Zap in 131 loadable parts
(`zap build --loadable`); a cold part peaks at 0.7 GB and costs about 35 processor-seconds, nearly
all IR passes, so a 16 GB machine saturates at four parts at once (the game 25 minutes cold, about a
minute with the IR cache warm). The SNES recompiler matters most (DKC: about 4,000 small generated
functions and dispatch matches of 1,300 to 2,700 integer arms, 13 to 23 MB a game, rebuilt on every
fix; tools/recompshape.zap measures it): a cold build is 65% per-function passes (on every
processor), the rest the main thread alone (lowering 45% of it, checking 23%, parsing 10%, emitting
8%). The executable size's open items are Recompilers 4 and 5.

1. **Memory per line**, so a 16 GB machine builds many parts at once. A node is 96 bytes (kind,
   place and ival narrow; its text, kids and part, the none-or-one NodePart holding the rare lists,
   the second text and the origin, syntax/node.zap). recompshape's program (240,000 lines) peaks at
   0.52 GB (`zap test --only size`; 0.70 before): the tree 0.29 GB once loaded (1.94 M nodes),
   36 MB more after the check, then 124 MB the code phase holds over it. That is not the checker's
   per-function tables (mutParams 9,300 entries, fnEffects 4,700, the rest fewer) but the
   assembler's (841,000 labels and 747,000 fixups at two and four words each, debugLines' 2 M
   words, 8 MB of code, each grown by doubling) and the jobs' forms in flight. Next: a node's kids
   out of it (1.09 M nodes have some, 1.8 M ids in all, each list 24 bytes in the node and a heap
   block): a span into one list of ids beside the arena, for about 64 bytes a node; the
   assembler's tables in narrow fields (fixups' kind a byte, places and targets i32). The part's
   accessors made the compiler's .text 4% larger (12.5 to 13.0 MB). Before the node shrank,
   357,000 lines of `c.x[1] = c.x[2] + u64(7)` in 3,000 functions peaked at 2.1 GB
   (`ZAP_TRACE=memstats`); a generated file of N functions of 117 such lines reproduces it. BotW's
   parts build only on recomp.switch's branch: measure there once it lands. BotW's part 36
   (f881b6b8, one function of 33,045 lines) peaked at 1.25 GB cold for Windows (0.71 GB at the
   check's end); for linux-arm64 it ran out of memory in the register allocator's live ranges
   (irregs.zap's irFlush, under irAllocateIntervals) before liveness kept sparse rows, and is not
   built there yet.
2. **The settle rounds** (irSettle, some thirty a function whatever its size) find their facts and
   block hashes again over the whole function each round: about 13% of the passes, the first cost on
   a translated function's form (projects/recomp/switch/TODO.md). A round visits most blocks (66%),
   so an incremental count did not pay: fewer rounds, or cheaper ones another way.
3. **The kept stages' leftovers** (spec 14.2). With cpu and game modules kept, recompshape's program
   rebuilds after an edit of its entry in 1.9 s instead of 11.4, now mostly its load (1.0 s; Scripts
   3) and write. Left: a module after the first with a GPU file is checked each build (a shader's
   link reads the program's declarations, which a kept stage takes out); a kept module is still
   parsed (from build/cache/parse/) though only its imports and reads are needed, as a std module's
   index (stdindex.zap) gives them.
4. **Cold paths and small calls in generated code.** A small method's cold path is inlined into every
   caller with what it formats: recomp.switch's `Memory.index` noting a fault as `"{n} bytes at
   {at:x}..."` put the formatting and a 1.5 KB frame, zeroed at each entry, into every translated
   function (190 bytes of x64 a guest instruction, 90 without it); written with the fault kept as
   numbers (Memory.faultAt) and formatted where it is read. And small functions called a pixel at a
   time are not inlined (recomp's layerColor, combineWindows, the colour math's channels: worked
   around by hand).
5. **The lowering and the check per function on every processor,** for a single large program (a
   build cut in parts already fills every processor). The passes already run as jobs while the
   round's lowering goes on (irpipe.zap), so a cold build waits on the serial lowering (recompshape:
   61 s of 100 s, 4,089 functions none over 0.2 s; `ZAP_RUN=lowershared` counts what each adds to
   the shared state: most add nothing). The lowering no longer writes the nodes, but the checker
   calls it reaches still do and write about 20 module variables (typeIndex and typesMet,
   dropsHeld, waitingBodies, the kept stages' asks, the errors' state, the lint's notes...). The
   parallel effect check judges every path, not the one taken, so a `.parallel()` body needs
   lookup-only copies of the checker's chains (sizeOf, resolveType, isPlainType and their callees:
   days of work), or a stop-and-redo path from about 190 call sites; or parts as processes that
   load and check the program and send back their lowered forms renamed as kept forms are.
6. **Leads in codegen,** each measured alone by A/B and fired beyond its benchmark:
   - Alias facts from ownership (rustc's `noalias`): a store through one owned list cannot alias a
     load from another or from a `self` field, so loads live across it and leave loops; memory
     versions per block (LLVM's MemorySSA) make cross-block reuse cheap once split by owner.
   - Loops: i32 counters widened to i64; an `i * stride` index as a stepped pointer; fill and copy
     loops to the runtime's wide copies; `while` loops with an early exit vectorized by an exit
     mask (GCC 16); a loop's blocks contiguous (.NET 10).
   - irpairs grown into an SLP vectorizer over stores and reductions, with identity lanes for a
     missing twin (LLVM 22): the engine's vec3 and matrix code by the path raytrace's takes.
   - Inlining limits: 40 nodes for the program's own bodies and for runtime bodies called outside a
     loop in a function with no loop (irlowerfunction.zap), 24 inside a loop (`ZAP_RUN=irinline`).
   - A box or list made and dropped in one function in the frame (.NET 10's escape analysis); a drop
     followed by an allocation of the same size class reusing the block (Koka's Perceus); irowntake
     run again after inlining (Swift's OSSA); `nothrow` and `terminates` beside purity.zap's pure.
   - One table of rewrites read by iropt and by fold (Cranelift's rules); tiling and interchange
     beside irjam, chosen by a small cost model, nests versioned by size (Halide, Futhark).
   - The compiler's own time: the ownership pass's snapshots of every variable at each branch
     (`snapshotMoved`); checkEffects' addChanged (effects.zap), quadratic, 8% of a check.
7. **arm64's code as good as x64's** (Benchmarks 2 lists the ratios it moves). Left: havlak's
   `numbering` and `predecessors` still spill with AArch64's own set (x0..x7 only for vregs no call
   or scratch-using instruction meets, so what lives across a call has x19..x28 alone); loops
   around an inner loop are not split; fasta's drawRounds loop makes its constants at each turn (its
   multiplier and addend, a `mov` each since AArch64's mul and add take no such immediate; `% im`'s
   magic number and divisor, a `mov` and a `movk` each, a64DivByConstant) and writeRandom's
   `draws[at..]` window is written to its frame slot and read back each round.
8. **A huge function's leftovers.** tools/hugefnshape.zap writes one function of BotW's part 36's
   shape (f881b6b8: a `while true` match whose first arm runs on, the memory's loads and stores and
   the calls out inlined); its build at 16,000 lines is in size.baseline (5.8 s, 0.26 GB). From
   8,000 to 64,000 lines its code phase grows about linearly (1.2 to 11.6 s, 0.18 to 0.91 GB, some
   14 KB a line), and part 36 builds cold in 10 s (102 s before, the same bytes). Left: a liveness
   walk's set is dense (irWalkFrom clears and fills a block's words, irCallFacts ors them at each
   call: blocks or calls times the numbers over 64), and the passes' rest is the settle rounds'
   facts and hashes (irFacts, irValueSpans, irBlockHash, 13% at 32,000 lines: step 2).

### 3. Runtime and std

1. **What agent scripts lack against Python** (eleven scripts written in both: grep, loc, json,
   csv, replace, todo, diff, git log, numstat, a TSV sum, the walk; the language's part is
   Language 4):
   - A map's value changed in place by key with a default for a missing one, as Counter and
     defaultdict do: `stats["a"][0] += 1` works on a present key, `m["x"] += 1` on a missing one
     stops (`the key is not in the map`); a text key needs `.copy()`.
   - Maps walk in hash order (Python's in insertion order), so a sort's ties print differently (a
     compact ordered map was tried: Tried).
   - `zap doc runtime` lists `T[].contains` and `T[].repeat`, but a call of them is `no-method`.
   - `fs.copytree` (a copy of a dir) is missing.
   - A record built from `keys()`' strs needs `.copy()` (`move-of-borrowed`).
2. **std/regex against Python's re** (a fuzz of random patterns): possessive quantifiers, `$` before
   a trailing newline, an empty match right after a match, `(a*)*`'s group none where Python's is
   ""; `m.group("name")` is `m.named("name")` (no overloading by the argument's type); Unicode
   classes missing. regexredux's part is Benchmarks 8.
3. **The allocator** (runtime/core/corealloc.zap), each measured by `peak` and the allocation
   benchmarks (binarytrees, wordfreq, httpjson): big blocks rounded to a power of two (up to half
   the commit idle) rounded to steps of 1.25x instead; the 2..4 KB classes losing 7 to 25% of a
   16 KB page's tail given 64 KB pages; the 4 MB chunk committed whole at a thread's first
   allocation reserved and committed 64 KB at a time, an emptied chunk decommitted; a cached big
   block memset whole on reuse and `readFile`'s buffer zeroed before the read overwrites it, both
   raw for callers that write the bytes; the map's table one block (header, marks, cells) instead
   of three. Peaks are data still in use (the compiler's 154 MB loaded, 262 MB checked, 312 MB
   generating code).
4. **The runtime's hot small paths,** measured on the benchmarks that touch them: `{x:.2}` through
   an exact bignum (num.zap's fmtFixed) given a wide-multiply path for `dec <= 17`; bytesHash's
   serial FNV chain given four lanes for keys of 32 bytes or more (rapidhash); an interpolation of
   22 bytes or fewer built in the frame; stdout's buffer reserved at first use, stderr written
   without a block per line, a pipe read straight into the list's spare capacity; `programArgs`
   parsed on first use; a channel's wait on `WaitOnAddress` with no 10 ms timeout; `background` jobs
   on the pool, not a thread each.
5. **Maps found once.** lru is at Rust's 1.6x, findCell 46% of its time, memory-bound: Zap's table
   holds 266k cells for 100k keys (a third full) where hashbrown's holds 131k (three quarters), and
   `put` probes for the miss, then for the set, then the open cell. Each measured by A/B (no perf
   counters on Windows): the probe set against hashbrown's; a power-of-two size with a mask instead
   of `homeOf`'s multiply-high (then triangular probing); the integer hash one multiply; the removed
   marks' rebuilds (3% of lru). lru's other half is Benchmarks 3.
6. **What the Skyrim port asks of the std:** the `u32le(at + N)` offsets left in hkx/packfile.zap,
   esm/file.zap, esm/condition.zap, lip.zap, fuz.zap, strings.zap and hkx/layouts.zap moved to
   `T.fromBytesAt` (bsa.zap reads with it); std/archive, sources of files by key (a Data dir's
   archives, loose files), from bsa.zap and install.zap (`installFind` walks every archive's keys a
   call); pixel comparison against captures (skyrim's compare.zap) in std/image.

### 4. Scripts against Python

The agents' throwaway scripts (searches, counts, reports, file shuffles) are written in Python;
`zap run file.zap` is to be the quicker and the plainer choice. An unchanged file starts the
executable it kept (0.1 to 0.4 of Python's time); an edited one is built again from the runtime and
std kept checked, lowered and as machine code (spec 14.2), their functions' bodies read from the
kept file only when the build lowers, inlines or instantiates one. The goal is the scripts bench
(`zap test --only bench tests/scripts`): eleven scripts on fixed inputs, Zap edited over Python in
bench.baseline, each process started directly; under 1.00 is the goal. Now: jsonq 1.74, table 1.57,
csvsum 1.51, count 1.43, todo 1.16, loc 1.14, replace 1.13, grep 1.10, gitstat 1.02, gitlog 0.93,
diff 0.26. On the arm64 host (two processors) Python's runs take 21 to 54 ms, Zap's unchanged 3 to
24; an edited table.zap's 34 ms are load 7 (the kept stages' nodes 3: 9,400 of their 38,700
decoded), check 6, code 11, write 1; jsonq.zap's 50 are load 7, check 8, code 21 (main 4, its
derived JSON readers 5 and their passes). A profile of a build's stacks as a tree (stacks by callers under chosen roots) and the derived
functions named by their text rather than their count were begun and reverted unfinished.
The scripts' own gaps are Language 4 and Runtime and std 1. The steps, worst first:

1. **main each build:** lowered, its ownership checked and its registers allocated, its calls
   inlined (2 to 10 ms there: loc.zap's main 9, half of it the ownership check's origins), and its
   form written for the IR cache's key and looked up (irMadeReady, 2 ms of csvsum.zap's).
2. **Derived functions lowered each build,** named by count except an equality's or an order's of
   built-in types: the readers of the program's own types (jsonq.zap's `$unjson`, 4 ms, the
   runtime's jsonChar and jsonCharSpaced inlined at each call) and the printing of a kept stage's
   type (`$str` and `$fmt` of fs's error, in every script).
3. **The kept stage's decode:** its declarations decoded whole each build (3 ms of 9,400 nodes:
   texts and lists allocated one by one; read in parts on two processors it did not pay, the
   allocations contend) and the checker's tables after them (newChecker's indexes, 1 ms); the game
   stage of Compiler 3 is the same.
4. **Instances checked in the check phase** (5% of a small build): put off to the code, where a
   taken form skips them (they are then recorded in another order, so the executable's functions
   are laid out differently); those the program's code inlines are checked again
   (irInstanceCall's askChecked).
5. **The kept code placed:** about 4 ms for 150 to 200 functions (each form record read, its asks
   made again, its code placed); the backend's functions that move an IrMade zero frames of 7 to
   37 KB at each call (irShip, irPipeDrain, irKeptForm, irEmitMade: their temporaries' slots are not
   shared).
6. **Kept forms of the functions with a lambda** (named by count, `$env:N` and `$lam:e:N`; the
   initializers of `threadsEnd` and `crashFilterSet`, 1 ms of each build), of those that plan a
   function's wrapper as a value or a callback (`$fnval:`, `$callback:`, named by their label's
   number in the form, which another build numbers otherwise; named by key instead, a form taken in
   another program's build crashed), and of those whose lowering checks an instance that makes nodes
   outside its copy.
7. **The smaller costs:** effects of the kept stages' functions summarized again each build
   (findEffects, 2 ms of a small build) and their facts read whole (1 ms); some 1,900 page faults a
   build (fresh big blocks, lists grown into new pages, kept files read into buffers; the heap's
   chunks on huge pages took 160 off; 130 mmaps); on Windows every look at a file costs about 50 us
   (a dir's listing 100) and a new executable's first start 8 ms more than its next (the antivirus
   reads it; a loader that maps it as data took 4.6 ms off); the backend's merge of the same code
   (its signatures made once, 1 ms), the jumps' relaxation and the executable's writing (1 ms each).
### 5. Engine

1. **Run `zap test --only shots` once:** the per-frame costs of step 6 that landed (sorted draws,
   ring sizing, sprite batch, silent voices, skinning passes) went in without it.
2. **rhi inside the engine.** `rhi/` is the engine's GPU layer (one device over Vulkan and Direct3D
   12) and nothing outside engine/ imports it. It moves to `engine/gpu/` (`import engine.gpu`), so
   the root holds the language, the engine and the projects; `std/gpu`, compute without a window,
   becomes `std/compute` so the two names tell them apart. A layout change with its migration in
   one: the imports, the land's dir rules and spec 13's words for them, compiler/driver/modules.zap's
   note, AGENTS.md and the engine's README; `zap test engine` and the projects' shots prove nothing
   else moved.
3. **Skyrim's seams** (each measured by skyrim's frame or the duplicate code it removes):
   - One up axis: physics, navmesh and particles are Z-up, the scene and renderer Y-up; skyrim
     converts at the seam (`yUp` in game/cell.zap, `skyrimPoint` in sound/scene.zap, 17 uses).
   - A pose of N layers: skin.zap's `Pose{clip, from, blend}` blends two clips; `Pose.layers {clip,
     time, weight, mask}[]` with a mask a bone (`turned` a bool[], a linear search a node today);
     game/graph.zap drops the layers past two and finds clips by name a frame.
   - A state machine for behaviour graphs (engine/scene/statemachine.zap): game/graph.zap's 469
     lines and skyrim/hkx/graph.zap are generic but `moveStart`/`Speed`; node state in 9 parallel
     maps, `reached = {}` and `queue.remove(0)` a frame, bounds found by name.
   - One skinning and pose, after the pose layers: actor/skinning.zap (CPU, `boneWorld @
     skinToBone` again a call, the Part copied to change positions) and actor/pose.zap repeat
     skin.zap's `poseWorlds`; hkx/spline.zap is a B-spline beside engine/scene/curve.zap.
   - An audio bus (engine/audio/bus.zap): categories with inherited volume, distance curves,
     ducking, crossfade and music by priority, from game/sound/book.zap and music.zap.
   - engine/swf's AVM1: bindings resolved once and `player.on("CloseMenu", fn)` (interface/hud.zap
     builds `"{base}.Set{name}MeterPercent"` a frame; each menu compares names).
4. **The phone's window.** An app runs on the emulator (`zap run --target android-x64`, spec
   13.1), the engine's GPU in its window, on Vulkan 1.2 too (render passes and pipelines holding
   their states where the extensions are missing; `swiftshader_indirect` is 1.2 without dynamic
   rendering, extended dynamic state, push descriptors, descriptor indexing or drawIndirectCount;
   engine/tests/examples.zap runs the examples there and with `vulkan=1.2` on the PC). Left:
   - the examples under `-gpu host` (1.3 on the emulator): not run since the 1.2 paths landed;
   - Vulkan 1.1: the compiler writes SPIR-V 1.5 (compiler/shader/spirv.zap), which needs 1.2; a
     1.1 device needs SPIR-V 1.3 (the entry points' interfaces only inputs and outputs);
   - texture arrays without descriptor indexing: the sprite batch draws one texture a batch there,
     but recomp.switch's translated shaders read `Texture[]` and stop at `newProgram`;
   - pre-rotation: the swapchain is made IDENTITY and the compositor turns it (device.zap's
     `turned`); currentTransform in the swapchain with the projection turned (the screen's passes,
     their viewport and scissor) saves the compositor's pass;
   - an end that closes the activity (ANativeActivity_finish) instead of ending the process.
   With step 5 it is what skyrim's milestone 15 (Android) stands on; the tile steps then decide its
   frame rate.
5. **Assets compressed.** Every image reaches the GPU as RGBA8 though `TextureFormat` has BC1..BC7; a
   skinned vertex is 22 floats (88 bytes); a sound is kept as f32. `zap prepare` encodes BC7 (BC1
   for opaque, BC5 for normals) with the mips into the prepared file; vertices keep position in f32
   and normal, tangent and uv in snorm16 or f16, joints in u8, weights in unorm8 (about 40 bytes);
   sounds in i16. No Android GPU reads BC (the emulator's SwiftShader reads both BC and ASTC LDR,
   so it can check either): the rhi gains the ASTC formats (4x4 and 6x6, sRGB too, with a feature
   query beside `rhi.textureArrays` and `rhi.countedDraws`), an ASTC encoder in std/image/astc
   (checked by its decoder and the oracle's digests),
   `prepare` writes a target's formats (BC on Windows and Linux, ASTC on Android, transcoded from
   the game's BC1 and BC3 in skyrim's textures.zap), and the prepared file holds one set per target.
   DDS reaches the GPU prepared too (game/textures.zap keeps BC only at multiples of 4 and not sRGB
   though render.zap has Bc1Srgb/Bc3Srgb, decodes cube faces to RGBA8, makes no mips). Measured by
   `--only size` and the projects' memory, `--only shots` unchanged.
6. **The per-frame costs,** each measured by frame time (`projects/examples/stress`, `--bench N`,
   `--case boxes|sprites|crowd`, `--unsorted`): `readBuffer` and `readStorage` on `waitIdle` (a
   readback ring read one frame late, once a program reads back each frame); HDR and MSAA targets
   in RGBA16F (R11G11B10F, a transient MSAA target, reverse-Z). For the phone, where the fragment is
   the bottleneck: lights by cluster (skyrim's `paramsOf` sends every light and each fragment walks
   `lightCount`), shadows of lights that do not move made once (the inn's, when skyrim's milestone 5
   adds them), an `f16` type in the shaders' language for colours, normals and uvs (Mali's
   `mediump` doubles the throughput), and `Frames` with a target rate and pacing (vsync,
   `VK_GOOGLE_display_timing`) so a phone does not heat and lose its clock.
7. **Passes kept in the tile** (needs 4 and 5 to measure). Each pass, resolve and compute stage
   declares what it uses (rhi/core/barriers.zap), and both backends derive their barriers and
   layouts from it. On a tile-based GPU (every Android one) what leaves the tile costs the whole
   screen of bandwidth, so the same declarations make subpasses: a pass that reads only its own
   pixel of the one before (skyrim's scene, then its grading) stays in the tile
   (VK_KHR_dynamic_rendering_local_read); depth and the MSAA target are transient when no later use
   reads them (TRANSIENT_ATTACHMENT in LAZILY_ALLOCATED memory where the device has it, depth stored
   DONT_CARE, the samples resolved by the pass's resolve attachment rather than vkCmdResolveImage,
   which desktops gain too); bloom at a quarter of the screen and the eye's adaptation a compute
   reduce (these two change the pictures: their shots kept with `--update` once looked at). No GPU
   here is tiled or has lazily allocated memory: measured by `ZAP_RUN=gputime` on Android.
8. **Entities as columns** (needs 7). A `Transforms` store in columns (struct of arrays) with a
   dirty-flagged hierarchy, uploaded in one write, and the projects' entity sets walked by
   `.parallel()` over the columns (Unity's DOTS, Bevy), with a per-frame arena reset (Odin, Jai).
   Measured on skyrim's crowd and minecraft, skyrim's particles (`particles.push` per particle,
   `shakes` and the quads' `out` pushed each frame) and physics (`bodyPairs` and the manifolds in
   lists, each pair's SAT in turn): what a phone's small cores can take.
9. **GPU-driven drawing** (needs 8). Nothing in engine/ culls: every mesh is submitted by a CPU draw
   (scene/mesh.zap, scene/model.zap). An `Aabb` per mesh and a `Frustum` from the camera; a compute
   pass culls by frustum and by a two-pass HiZ occlusion test, compacts the survivors into
   `DrawCommands`, and one counted `drawIndirect` per material draws them (the indirect path and
   `setDrawCount` exist); skins posed only when visible and by a distance LOD. Measured by
   `gputime` and frame time on skyrim and minecraft.

### 6. Recompilers

What projects/recomp (snes, x64, touch) asks of the language, the std and the engine: what the code
does today and the form that removes it. The project moves to each form in the same change
(migration), measured by tools/recompshape.zap (`--only size`), the games' frame checks and the
bench.

1. **A word's bytes** (std, integer types). 44 `lo | (u16(hi) << 8)` and six functions of cpu.zap
   that differ only by the wrap of the address (bank 0 or the 24 bits). On the integer types:
   `u16.from(lo, hi)`, `u32.from(lo, hi)` (two u16), `u32.fromBytes(b0, b1, b2, b3)`; `w.low` and
   `w.high` (each half as the half-width type, readable and assignable); `w.bytes()` a fixed array
   of its bytes, little-endian. Lists already read a word at an offset (`u16.fromBytesAt`).
2. **Code written as code, not strings** (std/codegen; compiler). emit.zap, emitops.zap and
   interpret.zap build Zap source with `put(depth, "...")`, `hex(v, digits)` and tabs counted by
   hand; x64 and the Switch recompiler write the same way. A `Source` that keeps the indentation
   (`s.line("cpu.push8(v)")`, `s.block("if cpu.c:")` opening one level until the block's end,
   `s.temp("v")` naming temporaries), prints integers as fmt writes them (`{k:#08X}`) and gives the
   text fmt would give. In the compiler: a `match` on string literals and `x in [...]` of literals
   (144 matches on the mnemonics) compiled as one switch on the length and the bytes; measured by
   the translator's time on DKC.
3. **A module's state declared once** (compiler). Each part of the console lists its variables three
   times: declared, zeroed in `<part>PowerOn()` and written and read in `<part>Fields(f)` (29 such
   functions, 156 lines of `x = f.int(x)`). A `state:` block of a module holds module variables as
   `mut` declarations do (the names stay bare in the module's code), and the compiler derives for it
   `reset()`, `toBytes()` and `fromBytes()` (spec 7.7's layout, nested values and lists included),
   reached as the module's `state`: `console.state.reset()`, `console.state =
   ConsoleState.fromBytes(r)`. What a load rebuilds (line buffers, fetched tiles) stays outside the
   block. savestate.zap's StateFile goes; a save state in memory is a copy of the value (rewind,
   netplay).
4. **The dispatcher as a state machine** (compiler). A translated function is `loop:` over `match
   pc:` of 1,300 to 2,700 integer arms (emit.zap), each jump `pc = K` then `continue`, each call
   followed by `if cpu.ret == A`. Two rewrites in iropt: a `continue` whose loop begins with a
   `match` on a variable the arm just assigned a constant jumps to that constant's arm, the match
   skipped; a sparse integer match whose keys share high bits (one bank's addresses, `widths << 24 |
   address`) switches on the low bits of a two-level table (bank, then dense) instead of a
   comparison chain. Measured by the games' cycles a frame and the exe size.
5. **The interpreter on number parameters, not texts** (project change, after 2). interpret.zap
   writes 1,280 functions, one an opcode in each widths (`i{op}{widths}`), from the same translation
   as the games' code. No new syntax: a number parameter (spec 3.6) carries the widths as the bits
   e, m, x, `fn lda<W u8>(at u32) u32`, each instance folded as literals would be, and the step's
   match names the instances (`0x0A9 | 3 << 8: lda<3>(at)`); each opcode's body is written once, by
   hand or by the translator, and the translated code calls the same bodies (`cpu.adc<W>(operand)`)
   where today it copies their text. The compiler is only checked: instances of one body merge and
   `W & 2 != 0` folds in each instance. The Switch recompiler's forms (cpu/forms.zap) follow.
   Measured by the interpreter's function count and the exe size.
6. **The 2D frame in the engine** (engine/tiles). compose.zap decides each pixel of each
   layer by a call and several tests, `withBrightness` divides three times a pixel, and the windows
   are tested a pixel at a time though they are x ranges; DKC's, Lemmings' and Prince of Persia's
   frames do the same in their own words. `Layer` (a tilemap of entries, 2, 4 or 8 bits a pixel,
   scroll, two priorities, a mosaic), `Sprites`, `Windows` (per layer: x ranges resolved to spans
   once a line), a `Blend` (sub screen or fixed colour, add or subtract, halved, by layer) and
   `Palette` (15-bit entries, a brightness table of 16 by 32); `composeLine(layers, sprites,
   windows, blend, out u16[])` merges by priority in `Simd<16, u16>`, the window spans cutting the
   loop's ranges. The SNES keeps its register decoding and feeds the engine's structures; mode 7 and
   high resolution are its own layers through the same merge. Measured by frames a second headless
   (140 today) and the frame checks against Mesen 2 unchanged.
### 7. Benchmarks

Twenty-five problems, every one under 1.00x against the best of C, C++ and Rust at `--full`, the
rivals improved within the rules as Zap is; `bench.baseline` is recorded again then (it holds the
ratios against the old rivals). Now, geometric means: Zap's time 0.71x C's, 0.80x C++'s, 0.80x
Rust's; memory 0.83x, 0.74x, 0.72x; tokens: C 2.16x Zap's, C++ 2.35x, Rust 2.10x, Python 1.06x.
Ratios below are cycles (`--fresh all`, one problem at a time on Windows) unless said.

1. **Measure alike.** Linux's cycles leave out the kernel (std/perf/linux/perf.zap:31) where
   Windows' include it, so syscall-heavy problems read worse on arm64: check wall time too before
   attacking the 5x ratios. httpjson's Rust rival does not parse HTTP (`starts_with("GET
   /plaintext ")`, the id at offset 13; httpjson.rs:89): the rival parses headers as Zap does, or
   both scan alike, and http.zap's headEnd and byteIndex go through the vector `byteIndexIn`.
2. **arm64's ratios** (arm64 host, `--full`), worst first: revcomp 5.64, httpjson 5.35, knucleotide
   2.82, fasta 2.80, havlak 2.35, fannkuchredux 2.28, nbody 2.15, regexredux 1.93, lru 1.83,
   binarytrees 1.53, sudoku 1.42, mandelbrot 1.31, base64 1.26, strsort 1.25, jsonrecords 1.20,
   pidigits 1.20, exprtree 1.19, brainfudge 1.07, spectralnorm 1.06, nsieve 1.04, raytrace 1.01;
   under 1.00: wordfreq 0.65, matmul 0.79, dijkstra 0.89, coroprimesieve 0.95. Needs Compiler 7;
   httpjson's `parseHead` is 21% of its samples, havlak's Finder_collapse 33% and numbering 25%.
3. **lru about 1.5x (Rust)** (needs Runtime and std 5): findCell's 56 instructions a miss against
   Rust's 20, list headers and locals spilled (Compiler 7), the map's probes.
4. **httpjson 1.21x to 1.35x Rust's** (two measurements): its messages are views of the
   connection's buffer now (peak memory 0.87x to 1.07x Rust's with them). Left: the allocations of
   each parsed request (the start line's and the headers' strings), the threads' wake-ups on the
   loopback, one send per batch of pipelined responses, TCP_NODELAY, a reused read buffer, and a
   sampler that follows the jobs.
5. **coroprimesieve 1.34x (C++):** its division loop, about 14 instructions a prime against C++'s
   5, and two hyperthreads sharing a core's divider. u32 in the Zap program (C++'s int is never
   negative) drops the -1 check; measure with each thread on a core of its own.
6. **havlak 1.11x to 1.25x C's** (1.21x at `--full`), varying with its large lists made each run:
   the invariants hoisted and then spilled in `predecessors`, bounds checks, list headers read
   through memory, a growth call reloading every held header, values split at loop boundaries,
   arm64's allocation across calls (Compiler 7). Ideas: `irSplitLoop` (irloopsplit.zap, vectors
   only) for integers live across calls; `listPushRaw` with the growth in a cold call returning the
   header.
7. **sudoku about 1.2x (C):** the spills of `choose`'s outer counters (Compiler 7); the panic stub
   out of line and store-to-load forwarding in `sr[rr] += 1; if sr[rr] != 1`.
8. **regexredux** (needs Runtime and std 2): 0.89x time against Rust, 1.02x memory, 1.66x cycles.
   The counts scan at 1.4 ns a byte on every core, Rust's Teddy at 0.6; the substitutions are the
   critical path, one core: about 55 ns a match, the call chain of a locate (skip, anchored scan,
   two builder appends). Left: a vector scan for the pattern's first bytes or longest literal before
   the automaton, a byte shift on `Simd<32, u8>` for a nibble-table prefilter, the five
   substitutions in one pass.
9. **pidigits 1.02x to 1.04x against C over GMP,** whose limb loops are hand-written assembly. Left:
   a scratch limb buffer kept between steps, the 64x64 to 128 product a single `mul`. (Commit
   7c1d8ce7 of bench1, not in main, measures 0.87x with a multiword product's factor loaded into
   rax and carries chained: measure again once it lands.)
10. **brainfudge** was 1.06x C++'s before `pc < ops.len` and `ops[pc]` became one comparison (0.952x
    on arm64, 0.92x in bench1): left are the checks of `tape[head]` and `head += arg`, which C++'s
    program does not make and no range or guard proves. mandelbrot 0.97x is at the multiply ports'
    limit like its rivals.
11. **Record `bench.baseline` again** at `--full` with the improved rivals, and check every problem
    under 1.00x.

### 8. Tooling

1. **`zap fmt` and the lint** (each written by hand where met):
   - `zap fmt <dir>` does not reach a fixed point in one run: `zap test --only check` still listed
     lint notes (`fixed(c, ` is `c.fixed(`, a type dropped) that a second and third run applied
     (projects/recomp/switch, a dir of several modules importing each other).
   - It does not apply: `addExact(x.exactOf(), y.exactOf())` noted as `x.exactOf().addExact(`; the
     forms only types tell to write ("zap fmt applies it"); `x = f() ?? return none` noted as
     `x = try f()`, left by three runs.
   - The lint notes `.copy()` as droppable in a lambda's result, `romFiles((at, n): rom[at..at +
     n].copy())` with `read fn(i64, i64) u8[]`, and `zap fmt` drops it; the program then fails in
     the callee (`head = read(0, 0x50)`: move-of-part), so verifyNotes does not take the note back.
   - The lint's import form flips with the set of entry files checked together: `zap test
     engine/audio --only check` says `import engine.audio.mdct` in engine/audio/xwma/window.zap is
     to be dropped, a land's `check engine projects/recomp` on the file without it says it is to be
     added. The file uses `mdct.`; a judgment of an import must not depend on the other entries.
   - About 56 `?? return none` and 6 `?? fail(error)` stay in files the lint never sees, since no
     check reaches them on Windows (engine/post, scene, render and swf, rhi/d3d12, std/gpu, the
     Linux dirs, tests/programs/parts): each reached by a check, then `zap fmt .` again.
2. **The check's time.** canon.zap's verifyNotes loads the whole program again for each round
   (about 0.9 s). The suite's kinds: check 174 s warm, cold about 415 s at --jobs 2 with the lint
   verifying inside the checking zap; build beside dups and limits; the tests kind's time is left.
3. **The seeds' `ZAP_RUNTIME`:** they know it, not ZAP_RUN's `runtime=` (compiler/driver/seeds.zap
   sets it when it builds with a seed): that line goes once the seeds are promoted.
4. **A real Vulkan run on Linux:** no machine here has libvulkan (the container and the arm64 host
   lack it); the loaded libraries' calls and callbacks are tested with libc (tests/io/libthreads.zap).

### Set aside

Steps left at a working state, taken up again when a project or a measure asks for them; the
projects set aside (firered, ai, excel1) have their leftovers in their own TODO.md.

1. **A function written once runs on the CPU and the GPU.** Found by FireRed: its layers are drawn
   on the CPU because a shader's function cannot take a storage buffer as an argument and CPU code
   cannot call a `.gpu.zap` function. A plain function over buffers (`u32[]`, a `Grid`) callable
   from CPU code and from a kernel alike, its buffers passed as storage on the GPU; then FireRed's
   PPU draws its layers on the GPU with the same code its CPU path runs (frame hashes the same).
2. **One table decoder for the recompilers.** Excel's 68000 (`excel1/m68k`) and FireRed's ARM and
   Thumb (`firered`) are each a text table of bits and templates read by a decoder of their own:
   one decoder, in the engine or the std, reads all three tables.
3. **Constants computed when compiling.** A top-level constant whose value calls only pure functions
   (no I/O, no `args`, no module variable) computed by the compiler and stored in the executable's
   data; no new syntax, no macros. The tables that qualify cost well under a millisecond at start
   (mario's `sineTable` and `arctanTable`, std/digest's `crcTable`, excel1's opcode `matchers`,
   ragnarok's JPEG `idctTable`) and stored in the executable make it larger (mario by about 28 KB),
   against the spec's smallest executable: it comes back when a table costs time worth measuring.
4. **Open questions of the language,** decided later with real code: borrows the origin rules miss
   (each case found gets a stronger inference rule); `decimal` (an exact type for money, annotated
   once, `price decimal = 19.99`, its literals following, mixing it with `f64` an error) and `char`.

## C. Tried and not achieved

Each with what was measured, so it is not tried again without a new reason.

- Vulkan's minUniformBufferOffsetAlignment instead of 256 for the parameters ring: cycles a frame
  1.015, GPU time the same. Direct3D 12's single-texture tables pointed at each texture's own view
  instead of copied into the ring: no gain (2-6% of the frame). `readStorage` read one frame late:
  the stall is 0.02 ms a frame and no program reads back each frame.
- A list's growth storing back and reading again only its own header (irSyncSet): on AArch64 havlak's
  `predecessors` lost x9..x14 and x0..x5 for its twelve header words, which no lost register
  survives across the call, and spilled them (cycles 1.013); kept on x64 alone.
- 32-bit constants (`mov` and `movk`) and doubles held in a register before a loop on AArch64
  (irHeldConstants): none in the hot loops of fasta, havlak, lru, binarytrees, mandelbrot or nbody
  (cycles 0.992 to 1.000); kept, as a loop that has them saves instructions.
- LSE atomics on linux-arm64 (Android keeps the ldaxr/stlxr loops, as phones may lack ARMv8.1), once
  thought most of httpjson's 5.4x: user cycles 0.99, wall time the same. `jobsBlocked` counted only
  when jobs are queued was left: a job queued after an uncounted wait began would not get the thread
  it needs.
- AArch64's own register set (irArmPools: x0..x7 and x28 added, v22..v31 for floats where no vector
  is 32 bytes): cycles 0.98 to 1.00, not the 10-30% guessed; kept as the base for further arm64
  allocator work. A spill cost per position: binarytrees 1.29x slower. LLVM's spill weight
  normalization with the loop splits: havlak 1.025x against 0.990 with the cost per 64 positions.
- dijkstra's binary heap, or the hole taken to the bottom then sifted up: 1.24x to 1.32x slower than
  the 4-ary heap taken from the top with the children picked by value. Dead frame-store elimination
  over the emitted code: about 1% on raytrace, and objects split over several slots make it unsafe.
- Maps: a compact ordered map (dense entries, an index of small integers) cut wordfreq's memory 169
  to 146 MB but its time 1.6x to 2.0x; a larger table load (0.9) only by tuning to one input; lru's
  removed cells marked empty as Swiss tables do doubled its time; removing a key as hashbrown does
  1.12x slower (lru's lookups mostly miss); `m[k] = v` and `m.add` finding the key and the cell by
  one probe 1.07x slower on knucleotide; `m.get` probing directly even. The cell's prefetch in
  findCell is worth 13% on lru.
- No change: inlined parameters held in r10/r11 until the body's first call; allocation counters
  only when asked; the f64 fields of a struct local in xmm registers from a loop's entry (raytrace:
  the inlined `hit`'s temporaries lost theirs); coroprimesieve's spin tuned (100 pauses on x64, 1000
  yields on arm64: the spin costs cycles more than time). Slower: fully unrolling small constant
  loops.
- irmergeupdates (two turns a step of `xs[w] op= v`): found only in nsieve, 4%; removed, nsieve won
  another way. The other passes found only in their benchmark (carry chains, jammed nests, f64
  pairs, the affine unroll) stay as rules of shapes any program can have.
- Inlining sudoku's `choose` into `solve`: 0.94 on x64, 1.10 on arm64. A runtime body inside a loop
  inlined past 24 nodes: brainfudge's loop 2% slower when `push` went in. A body that gives a
  reference to its own local (listBytes) inlined: its window pointed at an emptied local; such a
  body is never inlined.
- The guarded check-free loop copy (irguards.zap's, LLVM's IRCE) for sudoku's `sc[c]` and `sr[rr]`,
  brainfudge's `tape[head]` and `ops[pc]`: their indexes are read from memory and no test before a
  loop bounds what the loop reads (a scan costs more than the 4 to 9 checks of a call). What paid
  instead: `while pc < ops.len` and `ops[pc]` as one unsigned comparison (irFuseBelow).
- Small aggregates in registers (spec 14.2: up to four leaves spread): on raytrace and nbody the hot
  code is inlined and the same (cycles 1.000 and 0.999); it reaches the runtime's calls of five or
  more words (strsort 0.992 on arm64) and the engine's Quat and Vec3 operations.
- Not transferable: Bend/HVM2 (parallel, 5x slower a thread), Vale's generational references,
  Austral's linear types (ownership gives it), Carbon (no codegen yet), copy-and-patch JITs (no
  interpreter tier here).

## D. What performance already has

What landed, so a step does not redo it; the details are in git's history.

- Loops and integers: constant `/` and `%` as imul and shift; checks ahead of a loop or dropped by
  range facts and dominators (irranges, irguards); `while i < xs.len` with `xs[i]` one comparison;
  affine recurrences, carry chains and short loops unrolled, nests jammed (irjam); plain loops
  vectorized, FMA, f64 pairs (irpairs); frame slots in registers through call-free loops.
- Inlining: loop-free or plain-parameter bodies up to 48 nodes in a loop, call-free runtime bodies
  up to 28 and the tiny ones at any depth, one level of recursion, hot bodies up to 240.
- Maps probed 16 bytes at a time with the cell prefetched; merge sort prefetching eight ahead;
  sums and reduces of maps and filters in their loop; derived JSON decoders matching a key where it
  lies; bounded channels a lock-free ring; arenas for statement temporaries.
- The compiler's own speed: a cold self-build from 33.8 s and 566 MB to about 7 s and 205 MB (the
  IR's passes one walk each, each type made once, a generic instance's body checked once, effects
  summarized by a worklist, the parse and the IR cached per file and function); a function of 40,000
  blocks from 13.6 s and 5 GB to 4.7 s and 444 MB.
