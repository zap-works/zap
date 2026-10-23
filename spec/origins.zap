# 4.4 Origins
#
# Every reference has an origin, the owner it borrows from. Origins are inferred, never
# written. Inside a function the origin is the place that was lent; a function returning a
# reference takes its origin from its parameters, so the caller cannot change them while the
# result is used.

# from the only borrowed parameter (a number is copied, not borrowed)
fn nth(xs str[], i i64) ref str:
	xs[i]

type Monster:
	hp i64

# a `mut ref` result: from the only `mut` parameter
fn slot(mut ms Monster[], names str[]) mut ref Monster:
	mut ref ms[names.len]

test "the origin of a result is its borrowed parameter":
	ms = [Monster(hp = 1)]
	names = []
	s = slot(ms, names)
	s.hp += 4
	words = ["a", "b"]
	expect ms[0].hp == 5
	expect nth(words, 1) == "b"

test "the caller cannot change the origin while the result is used" refuses ChangeWhileBorrowed:
	fn nth(xs str[], i i64) ref str:
		xs[i]
	mut words = ["a", "b"]
	w = nth(words, 0)
	words.push("c")
	print(w)

# With no borrowed parameter, a returned read reference points into the module's own data (an
# element of a constant list) and may be kept anywhere. A string literal is program data too:
# `name if known else "?"` is a `ref str` when `name` is.

names = ["air", "grass", "stone"]

fn nameOf(kind i64) ref str:
	names[kind]

fn labelOf(name ref str, known bool) ref str:
	name if known else "?"

fn fallback(name ref str) ref str:
	"none" if name.isEmpty else name

test "a reference into a constant list outlives the call":
	n = nameOf(1)
	kept = [nameOf(2), nameOf(0)].map(.len)
	longest = nameOf(2)
	print("{n} {longest} {longest.len} {kept}")
	prints "grass stone 5 [5, 3]"

test "a string literal is lent where a ref str is expected":
	n = "ana"
	b = "bia"
	r ref str = "lit"
	print("{labelOf(n, true)} {labelOf(n, false)} {fallback("")} {fallback(b)} {r}")
	prints "ana ? none bia lit"

# Otherwise the body says it: what the function returns is followed back through references,
# fields, elements, receivers, arguments, both sides of a choice and the locals on the way, to the
# parameters it comes from. What cannot be followed counts as every borrowed parameter.

fn longer(a str, b str) ref str:
	a if a.len >= b.len else b

fn firstOfLeft(xs str[], ys str[]) ref str:
	xs[0]

test "the body names the parameters a result comes from":
	a = ["aa"]
	b = ["b"]
	r = firstOfLeft(a, b)
	b.push("c")
	expect r == "aa"
	expect b.len == 2
	expect longer("xx", "y") == "xx"

test "a choice points into both sides" refuses ChangeWhileBorrowed:
	fn longer(a str, b str) ref str:
		a if a.len >= b.len else b
	x = "xx"
	mut y = "y"
	l = longer(x, y)
	y = "zzz"
	print(l)

# A view takes its origin from its reference fields (4.3), a list of references from what went in
# (4.3).
