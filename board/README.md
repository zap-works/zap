# The board

The plan of the language, the runtime, the std, the engine, the tools and the projects, as one
card a step. The board's tool is zaplink (projects/zaplink); its page follows main's checkout and
every branch's worktree as they change.

## A card

`board/<order>-<area>/<n>-<slug>.md`: its id is `<area>-<n>` (`compiler-9`). The areas are taken
in their dirs' order and a card in its number's order; an area's README.md says what holds for
all of it.

```
---
needs: [compiler-5, language-1]
size: M
check: zap test --only size; recompshape's peak under 0.40 GB
---
# Names interned as numbers

What is left and why, as the step is done; its parts as a checklist:

- [x] the lexer numbers each identifier once
- [ ] the checker's lookups by number
```

- `needs`: the cards that land first. `size`: an agent's hours, S 1, M 4, L 12, XL 30.
  `check`: the measure that says it is done. `blocked`: why it waits, when it does.
  `branch` and `by` (the agent's session): written by `take` in the branch's copy only; the page
  shows the session by its name and whether it is busy.
- A card holds no date and no status: where it stands is read from git. Its checklist is its
  progress, ticked in the branch's copy as the work goes.
- A card that lands is deleted in the branch that did it (`git rm`, in the branch's last commit),
  never marked done. A new step is a new card, numbered after the area's last.

## Lanes

- **Ready**: every card it needs has landed. **Backlog**: one it needs is still open.
- **Doing**: a branch took it. **Review**: its branch deleted it and waits for the land.
- **Blocked**: its `blocked` says why. A landed card is gone, so no lane holds it.
- A branch at work that took no card shows in Doing under the area `no-card`.

The page filters by area (a project is an area): a row of its table, or `?area=skyrim`.

The hours left are the open cards' sizes times the landed cards' hours over their estimates
(from `take` to the deletion).

## The tool

    zap run projects/zaplink/zaplink.zap board next                       the first Ready card
    zap run projects/zaplink/zaplink.zap board take <id>... [--branch b]  zap branch new b, "Take <ids>"
                                          [--by session]  (Claude Code's session by default)
    zap run projects/zaplink/zaplink.zap board check                      front matter and needs
    zap run projects/zaplink/zaplinkd.zap                                 the daemon and its page

An agent runs `next` (or is given its cards), `take` in main's checkout, works in the worktree
`take` names, ticks the checklist as it goes, and deletes the card in its last commit; the
coordinator lands the branch. A bug of the language met in a project is a card of `language` with
its workaround.

## Rules

- **Order across areas,** as the dirs number them: the language's bugs first; then the compiler
  (compile time, script builds and the code it emits) and the runtime and std cards they need;
  then the engine; the benchmarks last; tooling whenever a card needs it; then the projects, the
  recompilers first. An area's README.md opens with its title and one paragraph saying what it
  holds, which the page shows.
- **Groups.** An agent takes the cards of one area that touch the same files, in a worktree of its
  own; the group's branch is tested once when merged. Independent groups go side by side, with only
  the touched files' tests between changes; the whole `zap test` runs once per merged batch, and
  what it finds is fixed in that same pass.
- **Checks.** Every check is `zap test` (spec 13.1), read by an agent; nothing is manual. A step is
  judged by the spec's goal, measured: the least time to compile, the most speed, the smallest
  executable, the least memory and the most memory safety. Each measure is kept in a baseline that
  only gets better; a step that makes one worse fails unless it says why (`--update --slower
  "why"`, the reason in the baseline and in the diff).
- **Bugs.** A new one gets a test in `tests/memory/openbugs.zap.txt` (the fuzzer's shrunk program or
  a hand probe) before its fix; the fix moves the test to `fuzzFound.zap`. Checked runs give each
  block pages of its own, taken away when it is freed, so a use after free or a second free stops
  the program at once. A bug met in a project is a card of `language` with its workaround.
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

## Tried and not achieved

Each with what was measured, so it is not tried again without a new reason.

- Vulkan's minUniformBufferOffsetAlignment instead of 256 for the parameters ring: cycles a frame
  1.015, GPU time the same. Direct3D 12's single-texture tables pointed at each texture's own view
  instead of copied into the ring: no gain (2-6% of the frame). `readStorage` read one frame late:
  the stall is 0.02 ms a frame and no program reads back each frame.
- A list's growth storing back and reading again only its own header (irSyncSet): on AArch64 havlak's
  `predecessors` lost x9..x14 and x0..x5 for its twelve header words, which no lost register
  survives across the call, and spilled them (cycles 1.013); kept on x64 alone.
- 32-bit constants (`mov` and `movk`) and doubles held in a register before a loop on AArch64
  (irHeldConstants): none in the hot loops of fasta, havlak, lru, binaryTrees, mandelbrot or nbody
  (cycles 0.992 to 1.000); kept, as a loop that has them saves instructions.
- LSE atomics on linux-arm64 (Android keeps the ldaxr/stlxr loops, as phones may lack ARMv8.1), once
  thought most of httpJson's 5.4x: user cycles 0.99, wall time the same. `jobsBlocked` counted only
  when jobs are queued was left: a job queued after an uncounted wait began would not get the thread
  it needs.
- AArch64's own register set (irArmPools: x0..x7 and x28 added, v22..v31 for floats where no vector
  is 32 bytes): cycles 0.98 to 1.00, not the 10-30% guessed; kept as the base for further arm64
  allocator work. A spill cost per position: binaryTrees 1.29x slower. LLVM's spill weight
  normalization with the loop splits: havlak 1.025x against 0.990 with the cost per 64 positions.
- dijkstra's binary heap, or the hole taken to the bottom then sifted up: 1.24x to 1.32x slower than
  the 4-ary heap taken from the top with the children picked by value. Dead frame-store elimination
  over the emitted code: about 1% on raytrace, and objects split over several slots make it unsafe.
- Maps: a compact ordered map (dense entries, an index of small integers) cut wordFreq's memory 169
  to 146 MB but its time 1.6x to 2.0x; a larger table load (0.9) only by tuning to one input; lru's
  removed cells marked empty as Swiss tables do doubled its time; removing a key as hashbrown does
  1.12x slower (lru's lookups mostly miss); `m[k] = v` and `m.add` finding the key and the cell by
  one probe 1.07x slower on kNucleotide; `m.get` probing directly even. The cell's prefetch in
  findCell is worth 13% on lru.
- No change: inlined parameters held in r10/r11 until the body's first call; allocation counters
  only when asked; the f64 fields of a struct local in xmm registers from a loop's entry (raytrace:
  the inlined `hit`'s temporaries lost theirs); coroPrimeSieve's spin tuned (100 pauses on x64, 1000
  yields on arm64: the spin costs cycles more than time). Slower: fully unrolling small constant
  loops.
- irmergeupdates (two turns a step of `xs[w] op= v`): found only in nsieve, 4%; removed, nsieve won
  another way. The other passes found only in their benchmark (carry chains, jammed nests, f64
  pairs, the affine unroll) stay as rules of shapes any program can have.
- Inlining sudoku's `choose` into `solve`: 0.94 on x64, 1.10 on arm64. A runtime body inside a loop
  inlined past 24 nodes: brainfudge's loop 2% slower when `push` went in. A body that gives a
  reference to its own local (listBytes) inlined: its window pointed at an emptied local; such a
  body is never inlined.
- The guarded check-free loop copy (irGuards.zap's, LLVM's IRCE) for sudoku's `sc[c]` and `sr[rr]`,
  brainfudge's `tape[head]` and `ops[pc]`: their indexes are read from memory and no test before a
  loop bounds what the loop reads (a scan costs more than the 4 to 9 checks of a call). What paid
  instead: `while pc < ops.len` and `ops[pc]` as one unsigned comparison (irFuseBelow).
- Small aggregates in registers (spec 14.2: up to four leaves spread): on raytrace and nbody the hot
  code is inlined and the same (cycles 1.000 and 0.999); it reaches the runtime's calls of five or
  more words (strSort 0.992 on arm64) and the engine's Quat and Vec3 operations.
- Not transferable: Bend/HVM2 (parallel, 5x slower a thread), Vale's generational references,
  Austral's linear types (ownership gives it), Carbon (no codegen yet), copy-and-patch JITs (no
  interpreter tier here).

## What performance already has

What landed, so a step does not redo it; the details are in git's history.

- Loops and integers: constant `/` and `%` as imul and shift; checks ahead of a loop or dropped by
  range facts and dominators (irRanges, irGuards); `while i < xs.len` with `xs[i]` one comparison;
  affine recurrences, carry chains and short loops unrolled, nests jammed (irJam); plain loops
  vectorized, FMA, f64 pairs (irPairs); frame slots in registers through call-free loops.
- Inlining: loop-free or plain-parameter bodies up to 48 nodes in a loop, call-free runtime bodies
  up to 28 and the tiny ones at any depth, one level of recursion, hot bodies up to 240.
- Maps probed 16 bytes at a time with the cell prefetched; merge sort prefetching eight ahead;
  sums and reduces of maps and filters in their loop; derived JSON decoders matching a key where it
  lies; bounded channels a lock-free ring; arenas for statement temporaries.
- The compiler's own speed: a cold self-build from 33.8 s and 566 MB to about 7 s and 205 MB (the
  IR's passes one walk each, each type made once, a generic instance's body checked once, effects
  summarized by a worklist, the parse and the IR cached per file and function); a function of 40,000
  blocks from 13.6 s and 5 GB to 4.7 s and 444 MB. No walk over the whole program per function:
  the held code's undo, the frame slots' dead stores and fills (a table of 1,000 rows held a build
  0.7 s alone); the move and take checks share one origins fixpoint; effects' paths numbered; an
  imported module's index, so a kept one is never parsed; `ZAP_RUN=phases` tells the whole build.
