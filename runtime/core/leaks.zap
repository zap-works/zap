# Finding leaks (ZAP_RUN=leaks program.exe): every block allocated is noted with the return
# addresses of the calls that led to it (the stack walked by the system's unwinder, nearest
# first), a block freed is forgotten, and at exit the blocks never freed
# are listed on standard error, each call named from the table error traces read (errors.zap's
# placeOf). One thread's allocations at a time;
# for finding a leak, not for speed. The notes live in pages of their own (global slot 56),
# never in the heap they watch.

leakSlots = 1_048_576   # the table's entries: a block's address, its size, its frames
leakFrames = 6
leakWords = 8   # per entry
leakGone = -1   # an entry whose block was freed
leakWalkRoom = 32   # the return addresses a note's walk reads, its own frames among them

# slots: 56 the table, 57 room for the walk, 58 and 59 where the code starts and ends, 60 on
fn startLeakNotes():
	gset(slotLeakTable, allocPages(leakSlots * leakWords * 8))
	base = GetModuleHandleA(0)
	headers = base + __ld32(base + 60)   # the PE header, after the DOS one
	# the code: the first section, after the optional header
	code = headers + 24 + __ld16(headers + 20)
	gset(slotCodeStart, base + __ld32(code + 12))
	gset(slotCodeEnd, base + __ld32(code + 12) + __ld32(code + 8))
	gset(slotLeakWalk, allocPages(leakWalkRoom * 8))
	setLeakNotes(1)

fn leakIndex(p i64) i64:
	((p >> 4) ^ (p >> 24)) & (leakSlots - 1)

fn noteBlock(p i64, n i64):
	table = gv(slotLeakTable)
	i = leakIndex(p)
	while __ld64(table + i * leakWords * 8) > 0:
		i = (i + 1) & (leakSlots - 1)
	at = table + i * leakWords * 8
	__st64(at, p)
	__st64(at + 8, n)
	# the callers, each by its return address, from allocBlock's (reportLeaks leaves out the
	# runtime's own)
	walk = gv(slotLeakWalk)
	walked = returnsAfter(__returnAddress(), 1, walk, leakWalkRoom).min(leakFrames)
	k = 0
	while k < walked:
		ret = __ld64(walk + k * 8)
		if ret < gv(slotCodeStart) or ret >= gv(slotCodeEnd): break
		__st64(at + 16 + k * 8, ret - GetModuleHandleA(0))
		k += 1
	while k < leakFrames:
		__st64(at + 16 + k * 8, 0)
		k += 1

fn forgetBlock(p i64):
	table = gv(slotLeakTable)
	i = leakIndex(p)
	seen = 0
	while seen < leakSlots:
		v = __ld64(table + i * leakWords * 8)
		if v == p:
			__st64(table + i * leakWords * 8, leakGone)
			return
		if v == 0: return
		i = (i + 1) & (leakSlots - 1)
		seen += 1

# The blocks never freed, one line each: `zap leak: <size> bytes at f (file:line) < caller (file:line)
# < ...`, the nearest call first. A program ended
# by exit() leaves its functions' blocks held, as the system takes them back: only a program
# whose main returned is judged.
fn reportLeaks():
	setLeakNotes(0)   # the report's own blocks are not noted
	if not mainReturned():
		writeRaw(stderrHandle, "zap leaks: not judged: the program ended through exit(), its functions' blocks still held\n".bytes())
		return
	table = gv(slotLeakTable)
	count = 0
	for i in 0..leakSlots:
		at = table + i * leakWords * 8
		p = __ld64(at)
		if p > 0:
			# each call just before its return address
			calls = (0..leakFrames)
				.map(__ld64(at + 16 + it * 8))
				.filter(it != 0)
				.map(imageBase + it - 1)
			places = placesOf(calls)
			# from the program's call: the allocator's own frames (rtAlloc's) left out
			first = places.findIndex(not .function.startsWith("rt.")) ?? 0
			named = places[first..].map(c:
				c.function.copy() if c.file == "" else "{c.function} ({c.file}:{c.line})"
			)
			writeRaw(
				stderrHandle,
				"zap leak: {__ld64(at + 8)} bytes at {named.join(" < ")}\n".bytes()
			)
			count += 1
	writeRaw(stderrHandle, "zap leaks: {count} blocks never freed\n".bytes())
