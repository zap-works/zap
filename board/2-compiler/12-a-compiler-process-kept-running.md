---
size: L
branch: server
by: 05c1402a-077b-4bef-a22a-b65dbb8e7ce8
blocked: a warm process only saves reads; it pays once the own module's check is kept per file
priority: P2
---
# The program's own module is checked per file and kept between builds

A compiler process kept running (Kotlin's and Gradle's daemons, Bazel's workers) would hold the
stages, nodes and types warm in memory, but measuring says it saves little by itself. Measured on
Windows, warm caches, the machine shared:

- `zap test compiler runtime std spec tests --only tests` (fresh): 407 s wall, 800 s of files' time,
  of which the programs' runs 597 s (the benchmarks and the spec files that start zaps); load 12 s,
  check 55 s, code 65 s, lint 47 s.
- A group's zap reads a test program's kept stages in about 10 ms (`keepFrom`, 55 builds 540 ms);
  holding them in memory (`keepRuntime` in `testListed`) cut it to 420 ms, as the copy of the
  checker costs most of a read: about 2 ms a build, under 0.1% of the run, for memory that grows
  with every chain a group reaches. Not done.
- An edited small program (5 std modules): 130 ms wall, its phases 40 ms (load 22 with the kept
  read), the rest the process (a hello.exe alone starts in 60 to 70 ms here). A server that
  `zap build` hands its work to still starts that process.
- The compiler edited (a comment): 3.8 to 7.5 s; load 0.5 to 0.8 s (its own files from the parse
  cache 0.3 to 0.5, the kept stages 30 ms, the IR shards 60 ms), check 1.6 to 3.8 s, code 1.1 to
  2 s, write 0.2 to 0.3 s. A warm process saves at most the load, about 12%, less the copies into
  a new program.

What would pay is the check of the program's own module, its larger part, kept per file between
builds (only the files edited and those that read their declarations checked again), which a watch
or a server then holds warm. The card is blocked until that exists; it overlaps compiler-3.

- [ ] keep the own module's check per file between builds: after editing one file of the compiler,
  `zap build` checks only that file and the files that read its declarations, and the check phase
  of the 3.8 to 7.5 s edit-and-rebuild above falls by most of its 1.6 to 3.8 s
- [ ] then hold the stages warm in a long-running process that `zap build` (or a watch) hands its
  work to, and compare an edited small program against the 130 ms above
