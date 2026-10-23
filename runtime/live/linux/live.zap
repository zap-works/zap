# A live build's image on Linux (runtime/live/live.zap): a static ELF, so no import is bound; the
# new code's frames are not in the program's unwind table, so a report from inside it names the
# calls up to it.

# The ELF at p mapped beside the program, each loaded segment where its address puts it: where it
# is and its size; (0, 0) when there is no room
fn liveImage(live LiveBuilds, p i64) (i64, i64):
	headers = p + __ld64(p + 32)   # e_phoff
	count = __ld16(p + 56)   # e_phnum
	size = 0
	for k in 0..count:
		h = headers + 56 * k
		if __ld32(h) == 1:   # PT_LOAD: p_vaddr and p_memsz
			size = size.max(__ld64(h + 16) + __ld64(h + 40) - imageBase)
	base = live.liveReserve(size)
	if base == 0: return (0, 0)
	for k in 0..count:
		h = headers + 56 * k
		if __ld32(h) == 1:   # p_offset and p_filesz
			__memcpy(base + __ld64(h + 16) - imageBase, p + __ld64(h + 8), __ld64(h + 32))
	(base, size)

# the build written at base made runnable: pages written before they could run, which on arm64 the
# kernel makes the instruction cache see as it makes them executable
fn liveRunnable(base i64, size i64):
	_ = sysMprotect(base, wholePages(size), 7)   # PROT_READ | PROT_WRITE | PROT_EXEC
