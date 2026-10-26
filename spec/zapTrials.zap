# 13.1.3 `zap fmt`'s shortest forms: what a check of the body tells
#
# The forms below go where checking the body again without them gives it alike: a conversion, a
# fallback, a written type, result or `mut`; zap fmt writes a `pub` function's result. As the
# other forms only types tell, they are the lint's findings (13.1.3), made in a file whose program
# checks.

from fmtRun import linted

# An `f32(x)` of an integer of 16 bits or fewer goes where the place makes it an `f32` anyway
# (3.1); one beside a float literal, an `f64` on its own, stays.
test "fmt drops an f32 conversion the place makes":
	source = r"""
		b u8 = 3
		k f32 = 0.5
		y f32 = f32(b) * k
		z = f32(b) * 0.5
		v = Vec3(f32(b), 0.0, 1.0)
		print("{y} {z} {v}")
		"""
	print(linted(source))
	prints r"""
		b u8 = 3
		k f32 = 0.5
		y f32 = b * k
		z = f32(b) * 0.5
		v = Vec3(b, 0.0, 1.0)
		print("{y} {z} {v}")
		"""

# A `.copy()` goes where the program, checked again without it, ownership too, gives it alike: a
# borrow or a move serves (4.1); it stays where the value is used again after being given away.
test "fmt drops a copy a borrow or a move serves":
	source = r"""
		fn shout(s str):
			"{s}!"
		fn run():
			words = ["a", "b"]
			first = words[0].copy()
			print(shout(first.copy()))
			kept = words.copy()
			kept.push("c")
			print("{words} {kept}")
			last = words.copy()
			print(last)
		run()
		"""
	for line in linted(source).lines():
		if " = " in line and "words" in line: print(line)
	prints r"""
		>words = ["a", "b"]
		>first = words[0]
		>kept = words.copy()
		>last = words
		"""

# A file's import lines are the modules its prefixes read (8): one it reads and does not import is
# written after its imports, one it imports and never names goes.
test "fmt writes the import lines a file's prefixes read":
	print(linted("import json\nimport math\n\nprint(fs.dirOf(\"a/b\"))\nprint(json.intAt(\"[42]\", 1) ?? 0)\n"))
	prints """
		import json
		import fs

		print(fs.dirOf("a/b"))
		print(json.intAt("[42]", 1) ?? 0)
		"""

# `r ?? fail(error)` of a `str` error is `r ?? fail` (6.5).
test "fmt writes fail alone for a str error":
	source = r"""
		fn named(s str) i64 ? str:
			if s == "": return "empty"
			s.len
		print(named("ab") ?? fail(error))
		"""
	print(linted(source).lines().last ?? "")
	prints r"""
		print(named("ab") ?? fail)
		"""

# A binding's written type goes where the binding without it gives every value the same type (2.4),
# and stays where a value would change: `w u8 = 3` read as a literal elsewhere.
test "fmt drops a written type the uses give alike":
	source = r"""
		fn halved(x i32) i32:
			x / 2
		fn run():
			n i32 = 10
			n -= 2
			ok bool = false
			s str = "a"
			w u8 = 3
			print("{halved(n)} {ok} {s} {w + 250}")
		run()
		"""
	for line in linted(source).lines():
		if " = " in line and "(" not in line: print(line)
	prints r"""
		>n = 10
		>ok = false
		>s = "a"
		>w u8 = 3
		"""

# `x ?? return none` in a function whose result is an optional is `try x` (6.5).
test "fmt writes try for a none passed up":
	source = r"""
		fn half(n i64) i64?:
			if n % 2 == 1: return none
			n / 2
		pub fn quarter(n i64) i64?:
			h = half(n) ?? return none
			k = [half(h) ?? return none, 1]
			k.sum() + (half(n) ?? 0)
		fn eighth(n i64):
			q = quarter(n) ?? return none
			half(q)
		print((quarter(8) ?? 0) + (eighth(8) ?? 0))
		"""
	for line in linted(source).lines():
		if " = " in line and "(" in line: print(line)
	prints r"""
		>h = try half(n)
		>k = [try half(h), 1]
		>q = try quarter(n)
		"""

# The same for a field, an index or a name: a place's value is lent, not copied out.
test "fmt writes try for a none passed up from a place":
	source = r"""
		type Slot:
			n i64?
		fn field(s Slot) i64?:
			v = s.n ?? return none
			v + 1
		fn index(xs (i64?)[]) i64?:
			v = xs[0] ?? return none
			v + 1
		fn name(o i64?) i64?:
			v = o ?? return none
			v + 1
		print((field(Slot(n = 1)) ?? 0) + (index([2]) ?? 0) + (name(3) ?? 0))
		"""
	for line in linted(source).lines():
		if " = " in line and "?" not in line: print(line)
	prints r"""
		>v = try s.n
		>v = try xs[0]
		>v = try o
		"""

# A function that is not `pub` drops a written result its body gives alike (5.1); it stays where
# the body gives another type on its own (a literal the result makes a u8), calls the function
# itself, widens an integer to f64, gives nothing at its end, or holds a conversion the written
# result lets go, and on a `pub` function.
test "fmt drops a written result the body gives alike":
	source = "fn double(x i64) i64: x * 2\nfn small() u8: 3\nfn fact(n i64) i64:\n\tif n < 2: return 1\n\tn * fact(n - 1)\nfn half(a i64) f64: a * 1.5\nfn take(mut xs i64[]) i64?: xs.pop()\npub fn shown(x i64) i64: x\nfn mk(\n\ta i64,\n\tb str = \"(\"\n) str: b\nmut ys = [1]\nprint(double(1) + i64(small()) + fact(3) + i64(half(2)) + (take(ys) ?? 0) + shown(1) + mk(1).len)\n"
	for line in linted(source).lines():
		if line.startsWith("fn") or line.startsWith("pub") or line.startsWith(")"): print(line)
	prints """
		fn double(x i64): x * 2
		fn small() u8: 3
		fn fact(n i64) i64:
		fn half(a i64) f64: a * 1.5
		fn take(mut xs i64[]) i64?: xs.pop()
		pub fn shown(x i64) i64: x
		fn mk(
		): b
		"""

# A `pub` function that leaves its result out gets the one its body gives written (5.1), its
# types named as the file names them.
test "fmt writes a pub function's result":
	source = "import fs\npub fn area(r f64): r * r\npub fn split(path str): fs.Error.Ended if path == \"\" else fs.Error.Denied\nprint(area(2.0))\nprint(split(\"\"))\n"
	for line in linted(source).lines():
		if line.startsWith("pub"): print(line)
	prints """
		pub fn area(r f64) f64: r * r
		pub fn split(path str) fs.Error: fs.Error.Ended if path == "" else fs.Error.Denied
		"""

# A method of a type's block that is not `pub` drops a written `mut` its body gives alike (5.2): it
# stays where the body changes the receiver only inside a lambda or by calls of the block's other
# methods (two that call each other would read it), where it changes nothing, and on a `pub` one.
test "fmt drops a written mut fn the body gives alike":
	source = """
		type W:
			n i64

			mut fn put(v i64):
				n = v

			mut fn both(v i64):
				put(v)

			mut fn keep():
				print(n)

			pub mut fn set(v i64):
				n = v

		w = W(n = 0)
		w.put(1)
		w.both(2)
		w.keep()
		w.set(3)
		"""
	for line in linted(source).lines():
		if "fn" in line: print(line.replace(">", ""))
	prints """
		fn put(v i64):
		mut fn both(v i64):
		mut fn keep():
		pub mut fn set(v i64):
		"""

# The forms only types tell are checked again with the notes applied (the texts that replace the
# files', nothing built); a rewrite after which the program does not check is not made.
test "a copy the ownership needs stays as written":
	source = "fn keep(xs i64[]) i64[]:\n\txs.copy()\n\nprint(keep([1]).len)\n"
	expect linted(source).lines()[1] == ">xs.copy()"

# a form the lint would note but whose rewrite does not check is not noted (each costs a check again)
test "a function named dot of a struct of numbers is no method, a map's key keeps its conversion":
	source = r"""
		fn dot(a Vec3, b Vec3):
			a.x * b.x + a.y * b.y + a.z * b.z
		fn name(m {i64: str}, w u8[]) str:
			k = w.u32le(0)
			m.get(i64(k)) ?? "none"
		v = Vec3(1.0, 2.0, 3.0)
		print(dot(v, v))
		print(name({1: "a"}, [1, 0, 0, 0]))
		"""
	for line in linted(source).lines():
		if "dot(" in line and "fn " not in line or "m.get" in line: print(line)
	prints """
		>m.get(i64(k)) ?? "none"
		print(dot(v, v))
		"""

test "a function whose result is found keeps the conversion of its returned value":
	source = """
		fn flags(w u8[]):
			at = w.len
			if at == 0: return 0
			i64(w[at - 1])
		print(flags([1]))
		"""
	for line in linted(source).lines():
		if "i64(" in line: print(line)
	prints """
		>i64(w[at - 1])
		"""

test "a variant written short keeps the result written that gives it its enum":
	source = """
		type Value:
			Undefined
			Obj(id i64)
		fn pick(x i64?) Value:
			y = x ?? return Value.Undefined
			Value.Obj(y)
		print(pick(1))
		"""
	for line in linted(source).lines():
		if "fn pick" in line or "Undefined" in line and "return" in line: print(line)
	prints """
		fn pick(x i64?) Value:
		>y = x ?? return .Undefined
		"""

test "a tuple a result function returns keeps its variants qualified, as the result gives them no enum":
	source = """
		type Value:
			Undefined
			Obj(id i64)
		type Thrown:
			value Value
		fn find(x i64) i64?:
			x if x > 2 else none
		fn pick(x i64) (Value, i64) ? Thrown:
			if x > 5:
				k = find(x) ?? return (Value.Undefined, 0)
				return (Value.Obj(k), 1)
			(Value.Undefined, 2)
		print(pick(7) is none)
		"""
	for line in linted(source).lines():
		if "Value." in line: print(line)
	prints """
		>>k = find(x) ?? return (Value.Undefined, 0)
		>>return (Value.Obj(k), 1)
		>(Value.Undefined, 2)
		"""

test "a conversion stays where a constant beside it would take the narrower type":
	source = """
		first = 6
		fn skill(body u8[], at i64) i64:
			s = i64(body[at]) - first
			if s >= 0 and s < 4: return s
			0
		print(skill([7], 0))
		"""
	for line in linted(source).lines():
		if "i64(" in line: print(line)
	prints """
		>s = i64(body[at]) - first
		"""

# an index loop whose element goes to a `mut` parameter, or whose changed element is matched with a
# binding pattern, stays: its `for x in xs` rewrite would not check (each costs a check again)
test "an index loop keeps its form where its element is lent to a mut parameter or matched":
	source = """
		type Shape:
			Dot(n i64)
			Box(w i64)
		fn bump(mut s Shape):
			s = .Dot(1)
		fn run(mut shapes Shape[]):
			for k in 0..shapes.len:
				bump(shapes[k])
			for f in 0..shapes.len:
				if shapes[f] is Dot(p):
					shapes[f] = .Box(p)
		mut xs Shape[] = [.Dot(0)]
		run(xs)
		print(xs.len)
		"""
	for line in linted(source).lines():
		if " in " in line: print(line)
	prints """
		>for k in 0..shapes.len:
		>for f in 0..shapes.len:
		"""
