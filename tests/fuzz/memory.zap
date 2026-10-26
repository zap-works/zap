# The memory model under random programs: each program moves, copies and borrows strings, lists
# and a struct through assignments, loops, branches, move out of places, tuple destructuring, closures,
# pipelines, a map, an optional and match, while with break, an early return from a loop,
# methods of the struct, and calls with read, mut and move parameters. Temporaries too: `?:` and
# `??` choosing between places, windows into temporaries and owned temporaries, `match` and
# `is` over temporaries (arms binding their parts), bindings kept borrowing from a temporary,
# `for` over a temporary list, `while x is v`, and `break`/`continue` leaving all of these (also
# `?? continue`, `?? break`), and generic functions instantiated for several types (numbers,
# str, a list, a struct, an optional, a reference), module variables (assigned, changed through
# a mut parameter, read), and values given away inside a range's bounds, an interpolation, a
# list literal or a nested call. A value given away moves
# when the program never reads its variable again before giving it a new value, and is copied
# with .copy() otherwise, so both are exercised. The fuzzer runs the same statements
# on plain values (value semantics: every variable holds its own value) to know what the program
# must print, then runs it as a test (fuzzRun): a crash, a different output or a block never
# freed is a failure, kept in build/fuzz/.
#
# The suite runs a few programs from a fixed seed; for a long hunt:
#
#   zap run tests/fuzz/memory.zap [count] [seed] [scale] [open]
#
# scale multiplies the count of every for loop (nested loops multiply it again): the values stay
# small, so a peak of memory over 64 MB is a leak and fails too. Forms that fail today for an open
# bug (TODO.md, tests/memory/openbugs.zap.txt) are left out unless the fourth argument is
# `open`, so a hunt finds new failures; `hitsOpenBug` lists them, to be removed with each fix.

import fuzzRun
import fs
import memFuzz

# ---------- running them ----------

a = args
count = i64.parse(a.first ?? "100") ?? 100
seed = (i64.parse(a[1]) ?? 1) if a.len > 1 else 1
memFuzz.scale = (i64.parse(a[2]) ?? 1) if a.len > 2 else 1
memFuzz.openBugs = a.len > 3 and a[3] == "open"
failed = fuzzMemory(count, seed)
print("{count - failed} of {count} programs right")

test "random programs keep the memory model: right output, nothing freed twice or left":
	print("{4 - fuzzMemory(4, 3)} of 4 programs right")
	prints "4 of 4 programs right"

# count random programs from seed built, run and compared; how many failed
fn fuzzMemory(count i64, seed i64):
	failed = 0
	for n in 0..count:
		memFuzz.rng = Random(seed + n)
		sts = memFuzz.genBlock(0, memFuzz.rng.next(4..=14))
		want = memFuzz.expected(sts)
		_ = fs.writeFile("{testDir()}mf.zap", memFuzz.program(sts, want))
		if not fuzzRun.passes("{testDir()}mf.zap", seed + n):
			failed += 1
	failed
