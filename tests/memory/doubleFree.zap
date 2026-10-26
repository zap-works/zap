# A block freed twice, or read after its free, stops the program, whatever its size: a checked
# run gives every block (up to its budget) pages of its own and takes them away when it is freed.

test "a large block freed twice stops the program" stops Failure("a block freed twice"):
	p = rtAlloc(5000)
	rtFree(p)
	rtFree(p)

test "a large block written after its free stops the program" stops AccessViolation:
	extern fn RtlMoveMemory(to i64, from u8[], n i64)
	p = rtAlloc(9000)
	rtFree(p)
	b u8[] = [1, 2, 3, 4, 5, 6, 7, 8]
	RtlMoveMemory(p + 8000, b, 8)
