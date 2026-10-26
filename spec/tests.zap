# 12. Tests
#
# A test is a block in the file it tests, run by `zap test` and ignored by `zap build`. The checks
# are statements in the test's body; the header says how the block runs.

import fs
import regex

# `expect condition` is a statement in any function: the condition any `bool` expression, or parts
# joined by `and` of which some test a pattern (the names bound for the parts after). The condition
# is evaluated once, so a side may give a value away; the other side takes the type the comparison
# gives it (a literal next to an i32, none next to an optional, `.Variant(v)` next to an enum, in
# a list a value is looked for in too).

fn longer(move s str) i64?:
	s.len if s.len > 3 else none

fn small() i32:
	7

fn firstName(names str[]) ref str:
	names[0]

test "a moved value inside expect":
	x = "ab"
	expect longer(move x) == none
	y = "abcde"
	expect (longer(move y) ?? 0) == 5
	z = "xyz"
	expect none == longer(move z)

test "each side evaluated once":
	expect testTick() == 1
	expect testTick() < testTick()
	expect testTick() == 4
	expect small() == 7
	names = ["ana", "bia"]
	expect firstName(names) == "ana"
	expect names.len == 2

test "a variant takes its enum from the other side, its values too":
	expect find("a") == .Found(1)
	expect find("b") == .NotFound("b")
	expect find("a") in [.Found(1), .NotFound("a")]

test "expect is a statement of a program too" stops Failure("never"):
	x = args.len
	expect x == 0
	fail("never")

# `expect f == {input: output}` checks a function against a table (a map itself has no `==`): `f`
# called with each key, a tuple's parts its arguments, and compared with the key's value, each entry
# a check of its own whose failure names the call.

fn area(w i64, h i64):
	w * h

test "a function checked against a table of inputs and outputs":
	expect area == {(2, 3): 6, (0, 5): 0}
	expect i64.parse == {"42": 42, "x": none}
	next = (x i64): x + 1
	expect next == {1: 2}

# A failure reports the place, the condition as written and what its form says it was, and the test
# goes on: a comparison both sides, `v is Pattern` the value, `x in xs` the value and the list (`x
# in lo..hi` its ends), `a.isClose(b, t)` both sides, their difference and the tolerance, another
# method its receiver and arguments, `a and b` which part failed; a value too long is cut.
#
# Started with arguments, a test file's program runs its own top-level code instead of its tests, so
# a test can start it again as a child (`exePath()`), here to fail on purpose.

type Lookup:
	Found(count i64)
	NotFound(key str)

fn find(key str) Lookup:
	.Found(1) if key == "a" else .NotFound(key.copy())

fn twice(x f64):
	x * 2.0

if not args.isEmpty:
	xs = [3, 1, 2]
	words = ["ab", "cd"]
	if args[0] == "compare":
		expect xs.len + 1 == 3
	if args[0] == "pattern":
		expect find("zz") is Found
	if args[0] == "close":
		expect twice(0.1).isClose(0.3, 1e-9)
	if args[0] == "vectors":
		expect Vec2(1.0, 2.0).isClose(Vec2(1.0, 2.5), 0.1)
	if args[0] == "range":
		angle = 7.5
		expect angle in 0.0..tau
	if args[0] == "in":
		expect 4 in xs
	if args[0] == "method":
		expect words[0].startsWith("c")
	if args[0] == "and":
		expect xs.len == 3 and xs[0] < xs[1] and xs[2] == 2
	if args[0] == "andpattern":
		expect find("a") is Found(n) and n > 1
	if args[0] == "long":
		expect "x".repeat(400) == "y"
	if args[0] == "table":
		expect area == {(1, 1): 1, (2, 2): 5}
	if args[0] == "goes on":
		expect xs.len == 5
		expect xs.len == 1
	return

# what the program said on stderr when run with the argument, its places' line numbers shown as N
# (they move when a line above them does)
fn reportOf(argument str):
	said = Process.output("\"{exePath()}\" \"{argument}\"").out.trimmedEnd().replace("\r", "")
	(regex.compile(":[0-9]+: ") ?? fail("a line number's pattern")).replace(said, ":N: ")

test "a comparison shows both sides":
	print(reportOf("compare"))
	prints """
		    spec/tests.zap:N: expect xs.len + 1 == 3 failed
		        left: 4
		        right: 3
		"""

test "a pattern shows the value it got":
	print(reportOf("pattern"))
	prints """
		    spec/tests.zap:N: expect find("zz") is Found failed
		        value: NotFound("zz")
		"""

test "isClose shows both sides, their difference and the tolerance":
	print(reportOf("close"))
	print(reportOf("vectors"))
	prints """
		    spec/tests.zap:N: expect twice(0.1).isClose(0.3, 1e-9) failed
		        left: 0.2
		        right: 0.3
		        difference: -0.09999999999999998
		        tolerance: 1e-9
		    spec/tests.zap:N: expect Vec2(1.0, 2.0).isClose(Vec2(1.0, 2.5), 0.1) failed
		        left: Vec2(x = 1, y = 2)
		        right: Vec2(x = 1, y = 2.5)
		        difference: Vec2(x = 0, y = -0.5)
		        tolerance: 0.1
		"""

test "a range shows the value and its ends, a list the value and the list":
	print(reportOf("range"))
	print(reportOf("in"))
	prints """
		    spec/tests.zap:N: expect angle in 0.0..tau failed
		        value: 7.5
		        range: 0..6.283185307179586
		    spec/tests.zap:N: expect 4 in xs failed
		        value: 4
		        in: [3, 1, 2]
		"""

test "a method shows its receiver and its arguments":
	print(reportOf("method"))
	prints """
		    spec/tests.zap:N: expect words[0].startsWith("c") failed
		        receiver: ab
		        argument 1: c
		"""

test "parts joined by and name the one that failed":
	print(reportOf("and"))
	print(reportOf("andpattern"))
	prints """
		    spec/tests.zap:N: expect xs.len == 3 and xs[0] < xs[1] and xs[2] == 2 failed
		        part 2 of 3 failed
		        left: 3
		        right: 1
		    spec/tests.zap:N: expect find("a") is Found(n) and n > 1 failed
		        part 2 of 2 failed
		        left: 1
		        right: 1
		"""

test "a table's failure names the call":
	print(reportOf("table"))
	prints """
		    spec/tests.zap:N: expect area(2, 2) == 5 failed
		        left: 4
		        right: 5
		"""

test "a value too long is cut, and a failed expect goes on":
	expect "... (106 more bytes)" in reportOf("long")
	both = reportOf("goes on")
	expect "expect xs.len == 5 failed" in both and "expect xs.len == 1 failed" in both

# `a.isClose(b, tolerance)` is a method of `f32`, `f64`, the vectors, `Quat` and the matrices, for
# any code: whether each number of `a` differs from `b`'s by `tolerance` at most.

test "isClose compares each number within a tolerance":
	expect (0.1 + 0.2).isClose(0.3, 1e-12)
	expect not f32(1.0).isClose(f32(1.1), f32(0.01))
	expect Vec3(1, 2, 3).isClose(Vec3(1, 2, 3.05), 0.1)
	expect Mat2(1.0).isClose(Mat2(1.0, 0.0, 0.0, 1.001), 0.01)
	expect Quat(0, 0, 0, 1).isClose(Quat(0, 0, 0, 1), 0.0)

# `prints text` is a statement of a test, after the code that prints: what it wrote to stdout since
# the last `prints` equals `text` (each without one final newline). A test may have several, and
# what comes after the last goes to stdout; a long text may come from a file
# (`prints fs.readFile(path) ?? ""`). `zap test --update path` rewrites the text of each `prints`
# whose output differs and says how many it rewrote.

test "prints checks the output since the last check":
	print("a")
	prints "a"
	print("b")
	print("c")
	prints """
		b
		c
		"""
	_ = fs.writeFile("{testDir()}want.txt", "d\n")
	print("d")
	prints fs.readFile("{testDir()}want.txt") ?? ""

# `test "name" for x in cases:` is a table of cases, the header a `for` over a list (a literal or a
# variable): the body runs for each element, each a test of its own in the count, and a case that
# fails is reported with its index and its element while the others go on.

evens = [2, 4, 6]

test "a table of cases runs its body for each element" for (text, want) in [("1", 1), ("42", 42)]:
	expect (i64.parse(text) ?? 0) == want

test "a case may be one name" for n in evens:
	expect n % 2 == 0

# `refuses Name` after a test's name makes its block a program that the compiler must refuse with
# that error, the report's `error[name]` (`AssignImmutable` gives `error[assign-immutable]`): it
# comes after the file's declarations and is checked as the test file is (13.1), and it need not
# even lex. `refuses Name("text")` also asks the report to hold `text`. Every compile error has a
# name, in the table of `compiler/tools/doc/errornames.zap`, with the explanation `zap doc` prints;
# a name the compiler does not give is an error of the test file.

test "a compile error is refused by its name" refuses AssignImmutable:
	fn f(x i64):
		x = 2

test "and by a part of its message" refuses UnterminatedString("unterminated"):
	print("never closed)

test "a misspelt compile error" refuses UnknownCompileError:
	test "t" refuses AssignImutable:
		x = 1

# `stops Name` makes the block a program of its own that must stop on that error (*Runtime
# errors*), after the file's declarations as a `refuses` block's (13.1); `stops Failure("message")`
# also asks for its message.

test "a program's failure is expected by its message" stops Failure("the level is 9"):
	fail("the level is {args.len + 9}")

test "a misspelt runtime error" refuses UnknownRuntimeError:
	test "t" stops IndexOutOfBound:
		x = 1

# In a test's body, `refuses Name:` and `stops Name:` are such blocks too, each a case of its own
# in the count whose failure names its line, so neighbouring programs that fail alike are one test.
# The test's other statements run as a test of their own.

test "neighbouring programs that fail alike":
	refuses AssignImmutable:
		fn f(x i64):
			x = 2
	refuses AssignImmutable:
		fn g(xs i64[], n i64):
			n = xs.len
	stops Failure("empty"):
		fail("empty")
	expect "alike".len == 5

# `stdin.feed(text)`: the rest of the test reads `text` as stdin; `args.set(list)`: the rest sees
# `list` as its command line (`args`); `testTick()`: 1 at the test's first call, then 2, 3, for an
# argument whose evaluations the test counts; `testDir()`: the dir of the running test for the files
# it writes, its own, ending with `/`, made empty at the first call and removed with what it holds
# when the test ends; `testFileDir()`: the same for what the file's tests share (made once, a
# repository each test resets), removed when they all ended; `zapPath()`: the zap a test runs, the
# working dir's `build/zap` with `exeSuffix()`;
# `builtExe(stem)`: the executable `zap build` wrote for a source of that stem (in the test's dir,
# 13.1).

test "a test's input, arguments and dir":
	stdin.feed("""
		Ana
		21
		""")
	print("{stdin.line() ?? ""} {stdin.line() ?? ""}")
	args.set(["x", "y z"])
	print("{args.len} {args[1]}")
	dir = testDir()
	_ = fs.writeFile("{dir}a.txt", "hi")
	print("{dir.endsWith("/")} {fs.readFile("{dir}a.txt") ?? ""}")
	prints """
		Ana 21
		2 y z
		true hi
		"""

# A file's tests run as one program, checked (`ZAP_RUN=memcheck`): every block gets pages of its
# own, taken away when it is freed, so a use after free or a second free stops the program at once
# (while the blocks in use hold less than the runtime's `guardBudget`; past it, a block comes from
# the heap); after the tests every block the program allocated must have been freed. The program of a test that `stops` runs checked too.

test "a block read after its free stops a test at once" stops AccessViolation:
	extern fn RtlMoveMemory(to u8[], from i64, n i64)
	p = rtAlloc(50)
	rtFree(p)
	b u8[] = [0, 0, 0, 0, 0, 0, 0, 0]
	RtlMoveMemory(b, p, 8)
	print(b[0])

# A test that listens asks for port 0 and passes `listener.port()` on to a child it starts
# (`Process.start("\"{exePath()}\" client {listener.port()}")`), so tests running side by side never
# share a port.
#
# `tests/fuzz/` tests the compiler with programs generated from a fixed seed: `checker.zap` mangles
# the test programs (the compiler must answer without crashing), `memory.zap` moves, copies and
# borrows values through loops, branches, closures and parameters, `layout.zap` puts structs of
# every field width in tuples, lists, maps, optionals and enum payloads, `modules.zap` gives types
# of the same name to several modules, `order.zap` checks that logged calls in the forms the
# compiler takes apart run once each, in the order written, and `divisions.zap` divides values of
# each width by a constant and by the same number in a variable. Each knows what its programs must print,
# runs each as a test of that text (`tests/fuzz/fuzzrun/`) and keeps a failing one in `build/`. The
# suite runs a few of each, as every test of random samples does (`tests/numbers/shortest.zap`'s
# doubles); `zap run tests/fuzz/layout.zap 300 7` hunts longer from seed 7.
