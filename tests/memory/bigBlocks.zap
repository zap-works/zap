# The system counts the memory a program commits, touched or not, against it (zap test's cap of
# a test's process): a big block commits the pages its size needs, not the power of two it is
# reserved by, and a big list grows in place by a quarter instead of doubling what it commits.

import fs

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

# blocks just past a small one's size (the argument's, which the compiler does not see), each
# reserved as four times its pages, in a program of its own run unchecked (a test's blocks are
# checked, each on pages of its own: spec/tests.zap)
pastSmall = r"""
	size = i64.parse(args[0]) ?? 0
	before = memoryCommitted()
	blocks u8[,] = []
	for i in 0..2000:
		block u8[] = []
		block.reserve(size)
		block.push(u8(i & 255))
		blocks.push(move block)
	grown = memoryCommitted() - before   # (before blocks' last use, which drops them)
	print(blocks.len == 2000 and grown < 60_000_000)   # 40 MB
	"""

test "blocks past a small one's size commit about their size, not the room they may grow into":
	file = "{testDir()}pastsmall.zap"
	_ = fs.writeFile(file, pastSmall)
	expect Process.output("{zapPath()} build {file}").code == 0
	ran = Process.output("{builtExe("pastsmall")} 20000", vars = ["{runVariable().name}="])   # 128 KB reserved each
	print(ran.out.trimmed())
	prints "true"
