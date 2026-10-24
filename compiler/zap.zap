# zap, the self-hosted compiler: entry point. The compiler is this program's parts, a dir each, by
# what they make (its commands are declared in driver/commands.zap).
#
#   zap test --only size    (the self-build: its time and peak memory in size.baseline)
parts driver, syntax, check, ir, optimize, ownership
parts collections, tensors, gpu, markup, targets, tools

preferHugePages()   # (the kept stages' nodes, read all over a list of megabytes)
runZap(args)

test "the ownership verifier of the intermediate form finds each kind of fault":
	for line in irOwnExamples():
		print(line)
	prints """
		dropped: clean
		never consumed: never consumed: it leaks where the function returns at b0:2
		moved, then dropped: clean
		moved as it is, then dropped: dropped once its bytes were moved out as they are (freed twice) at b0:3
		consumed twice: consumed again once its bytes were moved out as they are at b0:3
		begun twice: begun again while it owns a value (that one leaks) at b0:2
		read after a move: read after it is consumed at b0:3
		an address used after a drop: a borrow of it (v2) used after it is consumed at b0:5
		items used after a move: clean
		items used after a drop: a borrow of its memory (v1) used after it is dropped at b0:4
		consumed on one path: never consumed: it leaks where the function returns at b2:0
		named: a pass that loses the drop
		"""

test "a file starts while the peaks running and its own fit in the memory free":
	print("{fitsBeside(9, [], 1)} {fitsBeside(3, [5], 8)} {fitsBeside(3, [4, 2], 8)}")
	prints "true true false"

test "a file starts whatever its peak when nothing runs":
	print("{fitsBeside(9_000, [], 1)} {firstFitting([4, 7], [1, 1, 1, 1, 8_000, 1, 1, 9_000], [], 10) ?? -1}")
	prints "true 0"

test "a file waits while the peaks running leave no room, and the first that fits goes":
	peaks = [5, 5, 1]
	print(
		"{firstFitting([0, 1], peaks, [4], 6) ?? -1} {firstFitting([0, 1, 2], peaks, [4], 6) ?? -1}"
	)
	prints "-1 2"

test "a group whose zap ended holds no memory, a file handed or not":
	print("{holdsMemory(true, 0, 1)} {holdsMemory(false, 0, 1)} {holdsMemory(false, 1, 1)}")
	prints "false true false"

test "a group whose zap ended does not keep the next file from starting":
	ended = TestGroup(
		list = "",
		process = Process(handle = -1),
		files = [0],
		ended = 0,
		since = 0,
		closed = false,
		peak = 9_000
	)
	print("{ended.isGone()} {nextFitting([1], [9_000, 9_000], [ended], -1, 1) ?? -1}")
	prints "true 0"

test "the wait for memory says which file waits, the memory free and the files running":
	said = waitingLine("a/b.zap", 3_145_728, 2_097_152, ["c.zap", "d.zap"], [1_048_576, 2_097_152])
	print(said)
	prints "tests: waiting to start a/b.zap (3 MB; 2 MB free; c.zap 1 MB, d.zap 2 MB)"
	print(waitingLine("a/b.zap", 1_048_576, 0, [], []))
	prints "tests: waiting to start a/b.zap (1 MB; 0 MB free; no file running)"
