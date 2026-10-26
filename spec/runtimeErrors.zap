# 6.6 Runtime errors
#
# A program that stops on an error writes to stderr a stable code, the message, the place (function,
# file, line, column) with the line of source and a caret, and the calls that led there, and exits
# with code 3. The places come from a table the compiler writes into every executable, and the
# calls from the stack, walked by the system's unwinder over the unwind information (`.pdata`,
# `.xdata`) the compiler writes for every function, so they cost nothing until something fails.

import fs

# What the program `source` writes to stderr when it stops and its exit code, built from
# <name>.zap in the test's dir, which the report's paths leave out.
fn reportOf(name str, source str):
	dir = testDir()
	file = "{dir}{name}.zap"
	_ = fs.writeFile(file, source)
	Process.output("{zapPath()} build {file}")
	exe = builtExe(name)
	ran = Process.output(exe)
	_ = fs.deleteFile(exe)
	(withoutDir(ran.out, dir), ran.code)

test "the report: code, message, place, line of source and the calls that led there":
	said, code = reportOf(
		"reportcalls",
		"fn pick(xs i64[], k i64) i64:\n\txs[k]\n\nfn outer(n i64) i64:\n\tpick([1, 2, 3], n) + 1\n\nprint(outer(args.len + 7))\n"
	)
	expect code == 3
	expect "zap: error[index-out-of-bounds]: index out of bounds\n" in said
	expect "  at pick (reportcalls.zap:2:2)\n" in said
	expect "| \txs[k]" in said
	expect "  called from main (reportcalls.zap:5:2)\n" in said

# The errors, by the name a test gives them and the code the report shows; the numbers' own
# (`DivisionByZero`, `IntegerOverflow`, `ShiftOutOfRange`) are 3.1's.

test "an index out of bounds" stops IndexOutOfBounds:
	print([1, 2, 3][args.len + 7])

test "a range step that is not positive" stops RangeStep:
	for i in 0..10 step args.len:
		print(i)

test "fail names the call" stops Failure("the level is 9"):
	fn check(level i64):
		if level > 5:
			fail("the level is {level}")
	check(args.len + 9)

test "a recursion without end" stops StackOverflow:
	fn down(n i64) i64:
		down(n + 1) + 1
	print(down(0))

test "an invalid memory access in an extern" stops AccessViolation:
	extern fn lstrlenA(p i64) i32
	print(lstrlenA(args.len + 16))

test "an illegal instruction, or another fatal exception" stops Crash:
	extern fn RaiseException(code u32, flags u32, count u32, arguments i64)
	RaiseException(u32(args.len) + 0xC000001D, 1, 0, 0)

# `old-processor` stops a program started on a processor without x86-64-v3 (AVX2, FMA, BMI2).

# A block freed twice stops the program (`Failure`); a channel operation that can never complete stops
# it with `deadlock`.

test "a block freed twice" stops Failure("a block freed twice"):
	p = rtAlloc(50)
	rtFree(p)
	rtFree(p)

# A recursion shows its frame once with a count; a crash inside a function of the system shows that
# function, then the program's calls.

test "a recursion shows its frame once, and a system function its caller":
	deep, _ = reportOf(
		"reportrecursion",
		"fn down(n i64) i64:\n\tdown(n + 1) + 1\n\nprint(down(0))\n"
	)
	expect "times in a row]" in deep
	system, _ = reportOf(
		"reportsystem",
		"extern fn lstrlenA(p i64) i32\n\nfn bad(p i64) i32:\n\tlstrlenA(p)\n\nprint(bad(args.len + 16))\n"
	)
	expect "inside a function of the system" in system
	expect "  at lstrlenA\n  called from main (reportsystem.zap:4:2)\n" in system

# An inlined function has no frame: its place shows under its caller's name.

test "an inlined function's place shows under its caller's name":
	said, _ = reportOf(
		"reportinlined",
		"fn at(xs i64[], k i64) i64:\n\txs[k]\n\nk = args.len + 9\nprint(at([1, 2], k))\n"
	)
	expect "  at main (reportinlined.zap:2:2)\n" in said

# `ZAP_RUN=errors=json` writes each error, compile or run time, as one line of JSON: `{"error",
# "message", "file", "line", "col", "function", "source", "stack": [{"function", "file", "line",
# "col", "times"}]}` (`"error"` is the code: a compile error's, or `"compile"` for one without a
# name).

test "errors=json writes one line of JSON":
	env["ZAP_RUN"] = "errors=json"
	said, _ = reportOf("reportjson", "xs = [1, 2]\nprint(xs[args.len + 5])\n")
	env["ZAP_RUN"] = ""
	expect said.startsWith(
		"\{\"error\":\"index-out-of-bounds\",\"message\":\"index out of bounds\""
	)
	expect "\"stack\":[" in said
	expect said.count(10) == 1
	dir = testDir()
	_ = fs.writeFile("{dir}compilejson.zap", "x = 1\nx = \"a\"\nprint(x)\n")
	compiled = Process.output(
		"{zapPath()} build {dir}compilejson.zap",
		vars = ["ZAP_RUN=errors=json"]
	).out
	expect compiled.startsWith("\{\"error\":\"assign-type\"")
