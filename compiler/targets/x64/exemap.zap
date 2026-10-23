# The map that ZAP_RUN=map writes beside an executable (`prog.exe.map`, std/perf reads it),
# which names a program's addresses (ZAP_RUN's profile and disasm, zap test's size), and the
# unwind entries of its exception directory.

import fs
import perf

fn mapWord():
	TraceWord("map", "writes build/x.exe.map beside the executable: its functions' addresses")

# std/perf's readMap, or zap ended saying there is no map
fn functionsOf(exe str):
	perf.readMap(exe) ?? exit(1, "zap: no map of {exe} as it is built (a map of another build is refused): build it with ZAP_RUN=map")

# An entry of an executable's exception directory: the code [start, end) and its unwind
# information, as RVAs.
type UnwindEntry:
	start i64
	end i64
	info i64

# The entries of the executable's exception directory (x64.zap, asmWriteUnwind), in order: the
# code they leave out is a leaf's, its return address on top of the stack.
fn unwindEntries(exe str):
	b = fs.readBytes(exe) ?? fail("cannot read {exe}")
	pe = i64(b.u32le(60))
	directory = pe + 24 + 112 + 3 * 8   # PE32+: the optional header's data directory 3, the exceptions
	rva = i64(b.u32le(directory))
	sections = pe + 24 + i64(b.u16le(pe + 20))
	at = -1
	for k in 0..i64(b.u16le(pe + 6)):
		s = sections + 40 * k
		va = i64(b.u32le(s + 12))
		if rva >= va and rva < va + b.u32le(s + 8):
			at = b.u32le(s + 20) + rva - va   # in the file
	if at < 0: return []
	(0..i64(b.u32le(directory + 4)) / 12).map(unwindEntryAt(b, at + 12 * it))

# the entry whose 12 bytes are at `at`
fn unwindEntryAt(b u8[], at i64):
	UnwindEntry(start = b.u32le(at), end = b.u32le(at + 4), info = b.u32le(at + 8))

# the index of the entry (in order) that holds the RVA, or -1
fn unwindEntryOf(entries UnwindEntry[], rva i64):
	k = lastStartAtOrBefore(entries.len, rva, entries[it].start)
	k if k >= 0 and rva < entries[k].end else -1

# the first byte of the function named `name`
fn rvaOf(fns perf.MapFunction[], name str) i64?:
	if fns.find(.name == name) is f: return f.start
	none
