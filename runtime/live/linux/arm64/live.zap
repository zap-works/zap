# The reference of the code at field (rva in its build, whose data is at dataRva) led to the same
# place in the running program's state (runtime/live/live.zap): an adrp, whose page moves; the
# offset in the page, the add's after it, stays, both data at a multiple of 4 KB
fn liveFix(field i64, rva i64, dataRva i64, state i64):
	word = __ld32(field)
	pages = ((word >> 29) & 3) | (((word >> 5) & 0x7_FFFF) << 2)
	if pages >= 1 << 20:
		pages -= 1 << 21
	page = (((imageBase + rva) >> 12) << 12) + (pages << 12)   # where the build's own code reached
	moved = ((state + page - imageBase - dataRva) >> 12) - (field >> 12)
	__st32(field, (word & 0x9F00_001F) | ((moved & 3) << 29) | (((moved >> 2) & 0x7_FFFF) << 5))
