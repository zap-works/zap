# The runtime's names: a type's own functions (str.fromCode, i64.parse), streams as values
# (stdin, stdout, stderr), searching and counting, and the pipeline's groupBy, countBy, zip and mean.

if not args.isEmpty and args[0] == "echo":
	print(stdin.line() ?? "-")
	return

test "stdin and stdout are streams":
	print(Process.output("\"{exePath()}\" echo", input = "first line\nsecond\n").out.trimmed())
	stdout.write("no newline, ")
	stdout.print(42)
	prints """
		first line
		no newline, 42
		"""

fn upTo(n i64) Seq<i64>:
	i = 0
	while i < n:
		yield i
		i += 1

test "groupBy, countBy, zip and mean over a range, a Seq and the steps before them":
	print("{(0..5).countBy(it % 2)} {(0..10 step 3).groupBy(it % 2)} {(0..4).mean()}")
	print("{upTo(5).filter(it > 0).groupBy(it % 2)} {upTo(4).mean(it * 2)} {upTo(3).zip(["x", "y", "z", "w"])}")
	words = ["a", "bb", "cc", "ddd"]
	print("{words.filter(.len > 1).countBy(it)} {words.map(.len).countBy(it)} {words.filter(.len > 1).zip([1, 2])}")
	print("{words.filter(.len < 3).mean(.len)} {(0..0).mean()}")
	prints r"""
		{0: 3, 1: 2} {0: [0, 6], 1: [3, 9]} 1.5
		{0: [2, 4], 1: [1, 3]} 3 [(0, "x"), (1, "y"), (2, "z")]
		{"bb": 1, "cc": 1, "ddd": 1} {1: 1, 2: 2, 3: 1} [("bb", 1), ("cc", 2)]
		1.6666666666666667 NaN
		"""

test "a vector of one more lane":
	print("{Vec2(1.0, 2.0).withZ(3.0)} {Vec3(1.0, 2.0, 3.0).withW(1.0)}")
	prints "Vec3(x = 1, y = 2, z = 3) Vec4(x = 1, y = 2, z = 3, w = 1)"
