# The system counts the memory a program commits, touched or not, against it (zap test's cap of
# a test's process): a big block commits the pages its size needs, not the power of two it is
# reserved by, and a big list grows in place by a quarter instead of doubling what it commits.

test "a big block made for a size commits about that size":
	before = memoryCommitted()
	room u8[] = []
	room.reserve(600_000_000)   # reserved as a gigabyte
	grown = memoryCommitted() - before
	print(room.len == 0 and grown < 700_000_000)
	prints "true"

test "a big list pushed past a power of two commits about its length":
	before = memoryCommitted()
	bytes u8[] = []
	for i in 0..300_000_000:   # past 256 MB, which doubled is 512
		bytes.push(u8(i & 255))
	grown = memoryCommitted() - before
	print(bytes.len == 300_000_000 and bytes[299_999_999] == 255 and grown < 420_000_000)
	prints "true"
