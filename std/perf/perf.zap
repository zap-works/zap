# A program's run as the processor counts it (Linux's perf_event_open): its instructions, cycles,
# cache and branch misses, read when it ends, and the addresses where every so many of its
# instructions or cycles were sampled, named by the map ZAP_RUN=map writes beside its
# executable. Every thread of the program and every program it starts counts with it. Windows
# counts nothing here (its cycles are std/compare's, QueryProcessCycleTime).

import fs

# the processor's counts of a run (0: not counted)
pub type Counts:
	instructions i64 = 0
	cycles i64 = 0
	cacheMisses i64 = 0
	branchMisses i64 = 0

# A counted run: its exit code (-1 when it did not start, 128 + n when signal n ended it),
# whether it was stopped at its time limit or its memory limit, its wall time, its processor time (user and system,
# every thread's), its peak resident memory, its counts, and the addresses its samples stopped at.
pub type CountedRun:
	code i64
	overTime bool = false
	overMemory bool = false
	seconds f64 = 0.0
	processorSeconds f64 = 0.0
	peakBytes i64 = 0
	counts Counts = Counts()
	addresses i64[] = []

# Runs a command line (split as Process.output splits it, the program found on the PATH) with
# stdin from inputPath and stdout to outPath ("" for either: this program's), refused memory past
# limitMb (0: no limit; its writable memory is capped) and killed past limitSeconds (0: none), counted
# from its first instruction; with samplePeriod > 0 sampled instead, every that many instructions
# (or cycles when sampleCycles). Linux's alone: Windows runs nothing (-1).
pub fn runCounted(
	line str,
	inputPath str,
	outPath str,
	limitMb i64 = 0,
	limitSeconds f64 = 0.0,
	samplePeriod i64 = 0,
	sampleCycles bool = false
) CountedRun:
	_ = line
	_ = inputPath
	_ = outPath
	_ = limitMb
	_ = limitSeconds
	_ = samplePeriod
	_ = sampleCycles
	CountedRun(code = -1)

# whether runs are counted here: Linux's with the processor's counters open to a user's program
pub fn canCount() bool:
	false

# ---------- the map of an executable ----------

# A function of an executable by its map: the offset of its first byte from where the executable
# is loaded (an RVA: the address less rt.imageBase), and its name
pub type MapFunction:
	start i64
	name str

# The functions of the map beside the executable (`prog.exe.map`: the executable's hash, then a
# line per function, its RVA and its name), by their first byte; none without a map, or with one
# of another build, whose addresses would name other functions.
pub fn readMap(exe str) MapFunction[]?:
	lines = (fs.readFile("{exe}.map") ?? return none).lines()
	if lines.isEmpty or lines[0] != mapHead(exe): return none
	fns = []
	for line in lines[1..]:
		parts = line.trimmed().split(" ")
		if parts.len == 2 and i64.parse(parts[0]) is start:
			fns.push(MapFunction(start, name = parts[1]))
	fns.sortedBy(.start)

# a map's first line: the hash of the executable it names the functions of
pub fn mapHead(exe str) str:
	"exe {(fs.readFile(exe) ?? "").hash()}"

# the index of the function whose code holds the RVA (the last one starting at or before it), or
# -1 before the first
pub fn functionAtRva(fns MapFunction[], rva i64) i64:
	rt.lastStartAtOrBefore(fns.len, rva, fns[it].start)

# the samples in each function's own code, by the functions' indexes (an address outside the
# executable's code counts in none)
pub fn samplesByFunction(fns MapFunction[], addresses i64[]) i64[]:
	counts = zeros(fns.len)
	for address in addresses:
		rva = address - rt.imageBase
		if rva >= 0 and rva < 268_435_456:
			f = functionAtRva(fns, rva)
			if f >= 0:
				counts[f] += 1
	counts

test "a map of another build of its executable is refused":
	exe = "{testDir()}x.exe"
	_ = fs.writeFile(exe, "one build")
	_ = fs.writeFile("{exe}.map", "{mapHead(exe)}\n4096 main\n8192 other\n")
	fns = readMap(exe) ?? []
	print(fns.map(.name))
	print(
		samplesByFunction(fns, [rt.imageBase + 5000, rt.imageBase + 9000, rt.imageBase + 9001, 7])
	)
	_ = fs.writeFile(exe, "the next build")
	print(readMap(exe) == none)
	prints """
		["main", "other"]
		[1, 2]
		true
		"""

test "a run is counted from its first instruction and sampled where the processor counts":
	run = runCounted("sh -c \"exit 3\"", "", "")
	print("{(run.code == 3) != onWindows()} {(run.counts.instructions > 0) == canCount()}")
	busy = "sh -c \"i=0; while [ $i -lt 30000 ]; do i=$((i+1)); done\""
	sampled = runCounted(busy, "", "", samplePeriod = 100_003)
	print((not sampled.addresses.isEmpty) == canCount())
	stopped = runCounted("sh -c \"sleep 5\"", "", "", limitSeconds = 0.3)
	print(stopped.overTime != onWindows())
	prints """
		true true
		true
		true
		"""
