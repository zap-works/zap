# 6.5 Errors: `T ? E`
#
# `T ? E` is a `T` or an error `E`: an optional that says why the value is missing. It is the one
# spelling of a result, in a signature and anywhere else: `fn load(path str) Config ? fs.Error`,
# `fn save(path str, text str) ? fs.Error` when there is no value, a field `pending Config ?
# fs.Error`, `(Config ? fs.Error)[]`. Exactly one value type and one error type, no `Ok`/`Err` to
# write: a `T` or an `E` where `T ? E` is expected is wrapped. Several kinds of error are an enum
# used as the error type.

type FileError:
	NotFound
	Timeout
	Denied(who str)

fn readConfig(ok bool) str ? FileError:
	if ok: return "config-data"
	FileError.NotFound

fn loadAndUse(ok bool) str ? FileError:
	content = try readConfig(ok)   # try passes the error up
	"loaded: {content}"

fn describe(ok bool):
	match loadAndUse(ok):
		content: "ok: {content}"
		error: match error:
			NotFound: "err: not found"
			Timeout: "err: timeout"
			Denied(who): "err: denied to {who}"

test "a result is its value or its error, wrapped where it is expected":
	expect describe(true) == "ok: loaded: config-data"
	expect describe(false) == "err: not found"

# Everything an optional has works the same: `??` gives the value or its right side, which reads
# the error as `error`; `try` passes the error up; in a `match` the error's arm is `error:`, as
# `none:` is the optional's, and any other name binds the value; a variant of the error's enum
# (`Denied(who):`) tests the error, any other pattern the value.

fn opened(who str) i64 ? FileError:
	if who == "": return FileError.Denied("nobody")
	who.len

test "a variant of the error's enum tests the error, another pattern the value" for (who, want) in [
	("", "denied nobody"),
	("ana", "three"),
	("bo", "2")
]:
	shown = match opened(who):
		Denied(w): "denied {w}"
		error: "{error}"
		3: "three"
		n: "{n}"
	expect shown == want

fn parsed(text str) i64 ? str:
	match i64.parse(text):
		n: n
		none: "not a number: {text}"

fn doubled(text str) i64 ? str:
	n = parsed(text) ?? return "doubling failed ({error})"
	n * 2

test "?? gives a result's ok side, or the value made instead, which reads the error as error":
	a = parsed("42") ?? 0
	b = parsed("x") ?? -error.len
	c = parsed("y") ?? 0
	print("{a} {b} {c}")
	for t in ["42", "x"]:
		match doubled(t):
			n: print(n)
			error: print(error)
	prints """
		42 -15 0
		84
		doubling failed (not a number: x)
		"""

# A result's value may be an optional, written in parentheses (`(T?) ? E`): a `T` given is that
# optional's value, `none` its none, as anywhere a `T?` is wanted.
fn firstEven(xs i64[]) (i64?) ? str:
	if xs.isEmpty: return "empty"
	for x in xs:
		if x % 2 == 0: return x
	none

fn lastEven(xs i64[]) (i64?) ? str:
	if xs.isEmpty: return "empty"
	found i64? = none
	for x in xs:
		if x % 2 == 0: found = x
	if found == none: return none
	found ?? 0

test "a result of an optional gives a value, none and an error" for (xs, want) in [
	([1, 4, 6], "some(4) some(6)"),
	([1, 3], "none none"),
	([], "empty")
]:
	shown = match firstEven(xs):
		n: "{n} {lastEven(xs) ?? none}"
		error: error
	expect shown == want

test "a plain optional has no error to read" refuses ErrorOutsideFallback:
	o = i64.parse("1")
	print(o ?? error)

type Oops:
	Odd
	Small

fn half(n i64) i64 ? Oops:
	if n % 2 != 0: return Oops.Odd
	n / 2

fn quarter(n i64) i64 ? Oops:
	h = try half(n)
	try half(h)

fn noteLarge(n i64, mut log str[]) ? Oops:
	if try half(n) < 2: return Oops.Small
	log.push("large {n}")

fn firstTenfold(xs i64[]) i64?:
	v = try xs.first
	v * 10

fn magnitude(n i64) i64 ? Oops:
	(try half(n)).abs()

fn found(n i64) (i64?) ? Oops:
	if n < 0: return Oops.Small
	i64.parse("{n}")

type Pending:
	result i64 ? Oops

fn closeOdd(n i64, mut log str[]) ? Oops:
	if n % 2 != 0: return Oops.Odd

fn pushed(mut log str[], line str):
	log.push(line.copy())
	true

fn noted(n i64, mut log str[]) ? Oops:
	if n < 0: return Oops.Small
	pushed(log, "noted {n}")   # a last call with a value of its own: the result holds none

test "a result without a value ends in a statement":
	log = []
	closeOdd(3, log) ?? log.push("{error}")
	closeOdd(4, log) ?? log.push("{error}")
	noted(5, log) ?? log.push("{error}")
	noted(-1, log) ?? log.push("{error}")
	expect log.join(" ") == "Odd noted 5 Small"

test "try takes the value or returns the error":
	odd = match quarter(6):
		error: "{error}"
		v: "{v}"
	print("{quarter(8) ?? -1} {odd}")
	log = []
	noteLarge(8, log) ?? log.push("{error}")
	noteLarge(2, log) ?? log.push("{error}")
	print(log.join(" "))
	print("{firstTenfold([1]) ?? -1} {firstTenfold([]) == none}")
	print(magnitude(-6) ?? 0)
	prints """
		2 Odd
		large 8 Small
		10 true
		3
		"""

test "a result is a type anywhere: a field, a list's element, an optional on its value's side":
	p = Pending(result = half(6))
	print(p.result ?? -1)
	results = [half(4), half(3)]
	print(results.map(r: match r:
		n: "{n}"
		error: "{error}"
	).join(" "))
	print("{found(7) ?? none ?? -1} {found(-1) ?? 5 ?? -1}")
	prints """
		3
		2 Odd
		7 5
		"""

test "a result's value and error are of two types" refuses ResultSidesAlike:
	fn f() str ? str:
		"x"

test "an optional on a result's value side is in parentheses" refuses OptionalResultParentheses:
	fn f() i64? ? Oops:
		none

test "a match on a result names its error's arm error" refuses UnreachableArm:
	fn half(n i64) i64 ? str:
		if n % 2 != 0: return "odd"
		n / 2
	match half(3):
		v: print(v)
		e: print(e)

# `a ?? b` is `a`'s value or `b`; when `b` is an optional of the same type, the result is that
# optional (`find(left) ?? find(right)`).

fn find(xs i64[], v i64) i64?:
	for i, x in xs:
		if x == v: return i
	none

test "?? with an optional on its right gives an optional":
	left = [1, 2]
	right = [3, 4]
	expect (find(left, 4) ?? find(right, 4)) == 1
	expect (find(left, 9) ?? find(right, 9)) == none

# `a ?? fail("why")` stops the program with the reason, and `a ?? fail` alone with `a`'s error
# (its text when the error is not a `str`); `a ?? return` (with a value when the function has a
# result), `a ?? break`, `a ?? continue` and `a ?? exit(n)` leave. What leaves stands for a value
# of any type, a function's last statement too.

fn firstAbove(xs i64[], least i64) i64:
	for x in xs:
		if x > least: return x
	fail("none above {least}")

test "a function's last statement may stop the program":
	expect firstAbove([3, 40], 10) == 40

test "it stops when reached" stops Failure("none above 50"):
	print(firstAbove([3, 40], 50))

test "?? fail stops with the error" stops Failure("Odd"):
	print(half(4) ?? fail)
	print(half(3) ?? fail)

test "?? fail after an optional has no error to stop with" refuses ErrorOutsideFallback:
	print(i64.parse("x") ?? fail)

# `try` passes an error up only from a function whose result can carry it; in one whose result is
# an optional, `try x` of an optional passes its `none` up (`firstTenfold` above), which zap fmt
# writes for `x ?? return none`; a result the body gives is found with its tries.

fn parsedTwice(text str):
	n = try i64.parse(text)
	i64.parse("{n * 2}")

test "try of an optional in a function whose result the body gives":
	expect parsedTwice("21") == 42 and parsedTwice("x") == none

# `try` binds as a unary operator: `(try f(x)).abs()` calls the method on the value. `s = try n`
# on a place the function does not own (a parameter, a field) borrows the value inside; giving that
# value away is an error (`try move p.field` takes it out).

type Pet:
	name str?

fn named(p Pet) str?:
	n = try p.name
	"{n}!"

fn takeName(mut p Pet) str?:
	try move p.name

test "try on a borrowed place borrows the value; try move takes it out":
	p = Pet(name = "rex".repeat(1))
	expect (p.named() ?? "-") == "rex!"
	expect (p.takeName() ?? "-") == "rex"
	expect p.name == none

test "try gives away a value it only borrows" refuses TryMovesBorrowed:
	type Pet:
		name str?
	fn shout(p Pet) str?:
		return try p.name
	print(shout(Pet(name = "a".repeat(2))) ?? "")

# `try` takes a field or an index as it takes a call (`try t.slot`, `try t.slots[i]`), and zap fmt
# writes it for a place's `?? return none` as for a call's.

type Tray:
	slot i64 ? Oops
	slots (i64 ? Oops)[]

fn slotPlus(t Tray, i i64) i64 ? Oops:
	a = try t.slot
	b = try t.slots[i]
	a + b

test "try takes the value of a field or an index as of a call":
	t = Tray(slot = 1, slots = [10, Oops.Small])
	expect (t.slotPlus(0) ?? 0) == 11
	expect (t.slotPlus(1) ?? -1) == -1

# `try`, `?.` and `??` are the only error and absence operators; `?` is left to the types (`T?`,
# `T ? E`), and `|` is only the bitwise or. There is no `catch` (the word is an error naming the
# three ways) and no exception: an error is a value, taken with `try`, `??` or `match`.
