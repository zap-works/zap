# 5. Functions
#
# 5.1 Declarations
#
# The trailing expression of a body is the function's result; a trailing `if`/`else` or `match`
# gives its branches' trailing expressions, and one a branch of which gives nothing is a statement
# (the function gives nothing). `return` leaves early (zap fmt writes a final `return v` as `v`).

import fs

fn double(x i64):
	x * 2

fn sign(x i64):
	if x < 0:
		"negative"
	elif x == 0:
		"zero"
	else:
		"positive"

fn describe(v i64?):
	match v:
		n:
			if n > 100: return "big"
			"some {n}"
		none: "nothing"

fn pick(flag bool):
	match flag:
		true: 1
		false: 2

fn greet(name str):
	print("hello {name}")

test "a body's trailing expression is its result":
	expect double(21) == 42
	expect sign == {-3: "negative", 0: "zero", 9: "positive"}
	expect describe == {7: "some 7", 500: "big", none: "nothing"}
	expect pick == {true: 1, false: 2}
	greet("zap")
	prints "hello zap"

fn firstAbove(t i64) i64?:
	t if t > 0 else none

# a small function whose one expression is a match with an early return in an arm: called where
# it is (inlined), the return still leaves the function
fn bucket(t i64):
	match firstAbove(t):
		v:
			if v > 5: return 7
			-2
		none: -3

test "an early return in a match arm of a small function":
	expect bucket == {11: 7, 3: -2, -1: -3}

# A function may leave its result out: it has the type its `return`s and trailing expressions
# give, one type (never a value widened to meet another); `none` or an empty list or map takes the
# type the others give. A trailing expression that is no value gives nothing: a call of `()`, a
# call that changes an argument or its receiver (`push`'s index, `remove`'s element may go
# unused), a call after `return`s of nothing, a match whose arms give different types. The result
# is written where the body cannot tell it safely, an error asking for it: a function that calls
# itself, directly or through others, and gives a value; returns of different types; an integer
# widened to f64 (`a * 1.5` of an i64), a typo that would make a function and its callers float
# ones; an optional reference; only values whose place tells their type (`none`, `none if c else
# x`); a generic (its result is in its type parameters' terms). The body is checked once, when a
# caller first needs the result. A `pub` function's result is the module's contract, what `zap
# doc` prints and what lets a caller be checked without the body: zap fmt writes the one its body
# gives (`pub fn area(r f64): r * r` is `pub fn area(r f64) f64:`), and drops a written result of
# a function that is not `pub` where the body gives it alike.

fn tripled(x i64):
	x * 3

fn word(x i64):
	if x < 0:
		"negative"
	else:
		"other"

fn capped(x i64):
	if x > 9: return 9
	x

test "a function has the type its body gives":
	expect tripled(5) == 15
	expect word(-1) == "negative"
	expect capped(20) == 9
	expect capped(4) + 1 == 5

mut seen i64[] = []

fn remember(x i64):
	seen.push(x)   # push's index, a value that may go unused: nothing

test "a trailing call that changes its receiver gives nothing":
	remember(4)
	expect seen == [4]

fn logged(x i64):
	seen.push(x)
	x

pub fn noteSign(x i64):
	if x > 0:
		logged(x)
	else:
		print("not positive")

test "a trailing if/else a branch of which gives nothing gives nothing":
	noteSign(3)
	noteSign(-1)
	expect seen[len - 1] == 3
	prints "not positive"

test "a recursive function writes its result" refuses ResultRecursive:
	fn fact(n i64):
		if n < 2: return 1
		n * fact(n - 1)
	print(fact(5))

test "returns of different types are not widened" refuses ResultsDiffer:
	fn pick(c bool, b u8):
		if c: return 0
		b
	print(pick(true, 3))

test "an integer widened to f64 asks for the result" refuses ResultWidened:
	fn half(a i64):
		a * 1.5
	print(half(3))

test "a generic writes its result" refuses GenericResult:
	fn first<T>(xs T[]):
		xs[0]
	print(first([1, 2]))

# Every path of a function with a result type gives one: an `if` without `else`, a loop and a
# match that is not exhaustive do not count; a final `match` that returns in every arm does.

fn parity(n i64):
	match n % 2:
		0: return "even"
		_: return "odd"

test "a final match returning in every arm gives the result":
	expect parity == {2: "even", 3: "odd"}

test "an if without else leaves a path without a result" refuses MissingReturn:
	fn positive(n i64) i64:
		if n > 0: return n
	print(positive(1))

type Counter:
	n i64

test "a trailing call that changes its receiver after a return of a value" refuses TrailingCallActs:
	fn bump(mut c Counter) bool:
		c.n += 1
		c.n > 3
	fn tick(mut c Counter, step i64?):
		_ = step ?? return true
		c.bump()
	counter = Counter(n = 0)
	print(tick(counter, 2))

# A parameter may have a default after its type, and the parameters after it have defaults too. A
# call leaves defaulted parameters out or names them (`flipped = true`), named after positional, in
# any order. A default is an expression evaluated at each call that uses it, written where the
# function is: it sees the module's names, not the other parameters or the caller's.

white = "white"

fn quad(x f32, y f32, w f32 = 10.0, h f32 = 20.0, tint str = white):
	"{x} {y} {w} {h} {tint}"

type Pen:
	size i64

	fn line(length i64, dashed bool = false, color str = "black"):
		"{size} {length} {dashed} {color}"

fn pickOf<T>(move a T, move b T, first bool = true) T:
	if first: a
	else: b

mut made = 0

fn nextId():
	made += 1
	made

fn tagged(name str, id i64 = nextId()):
	"{name}{id}"

test "parameters left out take their defaults, named arguments go to their place":
	print(quad(1.0, 2.0))
	print(quad(1.0, 2.0, 3.0))
	print(quad(1.0, 2.0, tint = "red", h = 5.0))
	print(quad(y = 4.0, x = 3.0))
	p = Pen(size = 2)
	print(p.line(5))
	print(p.line(5, color = "blue"))
	print(pickOf("a", "b", first = false))
	prints """
		1 2 10 20 white
		1 2 3 20 white
		1 2 10 5 red
		3 4 10 20 white
		2 5 false black
		2 5 false blue
		b
		"""

test "a default is evaluated at each call that uses it":
	expect tagged == {"a": "a1", "b": "b2", ("c", 9): "c9", "d": "d3"}

test "a parameter with no default must be given" refuses MissingArgument:
	fn f(a i64, b i64 = 2) i64:
		a + b
	print(f(b = 3))

test "named arguments come after positional ones" refuses ValueAfterNamed:
	fn f(a i64, b i64) i64:
		a - b
	print(f(a = 1, 2))

test "a default does not see the other parameters" refuses UnknownVariable:
	fn scaled(x i64, k i64 = x) i64:
		x * k
	print(scaled(2))

# A file's top-level statements are its program: they run top to bottom and make the function
# `main` (which tests still call); `fn main` itself is not declared. A file with no statement is a
# library. Under `zap test`, main does not run: the module's bindings get their values before the
# tests, in their order.

test "main is not declared" refuses MainDeclared:
	fn main():
		print(1)

test "a file of declarations alone has no program to build" refuses NoEntryPoint:
	fn helper() i64:
		1

# A top-level binding no declaration mentions is main's own; one a function reads is the module's,
# and so is a `mut` one a function assigns (`name = v` there changes it, read by the statements):
# a constant when its value is a literal, else assigned where it stands, in order with the
# statements, so its value may come from `args` or a file. A statement that reads such a binding
# before the line that assigns it, itself or through the functions it calls by name, is an error
# naming both lines.

greeting = "hi"
names = "ana bia".split(" ")   # computed and read by a function: assigned here, before the tests

fn first():
	names[0].copy()

test "a module binding a function reads":
	expect greeting == "hi"
	expect first() == "ana"

# An immutable computed binding taken whole is a value of one's own, as a constant is. This file's
# program (the statements below, run when the file is started with an argument) has its bindings
# assigned where they stand and read there by the functions it calls.

type Roster:
	byName {str: i64}
	names str[]

roster = Roster(byName = { "ana": 1 }, names = "ana bia".split(" "))
fn countOf(r Roster):
	r.names.len + r.byName["ana"]

mut visits = 0   # assigned by a function, read by the statements alone

fn visit():
	visits = 2

if not args.isEmpty:
	visit()
	print("{args[0]} {roster.countOf()} {first()} {visits}")
	return

# what this file's program prints when started with the argument
fn programSays(argument str):
	Process.output("\"{exePath()}\" \"{argument}\"").out.trimmedEnd().replace("\r", "")

test "a computed binding taken whole is a value of its own":
	mine = roster
	mine.names.push("cid")
	print("{mine.names} {roster.names} {roster.countOf()}")
	print(programSays("cid"))
	prints r"""
		["ana", "bia", "cid"] ["ana", "bia"] 3
		cid 3 ana 2
		"""

test "a computed binding is read after the line that assigns it" refuses ReadBeforeAssigned:
	fn show():
		print(words.len)

	show()
	words = "a b".split(" ")
	show()

# A module's variables get their values before the program runs, each after the ones its initializer
# reads (directly or through the functions it calls), whichever file of the module holds each; two
# that read each other in a circle are an error.

# a program of a module of two files, run: what it prints, or the errors
fn moduleOf(name str, first str, second str, main str):
	dir = "{testDir()}{name}/"
	_ = fs.createDir("{dir}m")
	_ = fs.writeFile("{dir}m/a.zap", first)
	_ = fs.writeFile("{dir}m/b.zap", second)
	_ = fs.writeFile("{dir}main.zap", main)
	said = Process.output("{zapPath()} run {dir}main.zap").out
	withoutDir(said.replace("\r", "").trimmedEnd(), dir)

test "a module variable is computed after the variables of other files its initializer reads":
	print(
		moduleOf(
			"order",
			"pub doubled = base.map(it * 2)\nfn plus(n i64) i64:\n\tn + offset\npub shifted = [1, 2].map(plus)\n",
			"pub base = [1, 2, 3]\npub offset = 10\npub table = doubled.map(it + 1)\n",
			"import m\n\nprint(\"\{m.doubled} \{m.table} \{m.shifted}\")\n"
		)
	)
	prints "[2, 4, 6] [3, 5, 7] [11, 12]"

test "a module's local named as a function of the program is not a read of it":
	print(
		moduleOf(
			"local",
			"pub x = count()\n\nfn count() i64:\n\tat = 2\n\tat + 1\n",
			"pub y = 1\n",
			"import m\n\nfn at() i64:\n\tm.x\n\nprint(at())\n"
		)
	)
	prints "3"

test "module variables whose initializers read each other have no order":
	print(
		moduleOf(
			"circle",
			"pub x = y.len\n",
			"pub y = [x.len]\n",
			"import m\n\nprint(m.x)\n"
		)
	)
	prints "m/a.zap:1:5: error[init-cycle]: the value of 'x' is computed from itself: its initializer reads, directly or through the functions it calls, a module variable whose initializer reads 'x' back\n   1 | pub x = y.len\n     |     ^\nzap: type checking failed"
