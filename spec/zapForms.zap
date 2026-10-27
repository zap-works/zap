# 13.1.3 `zap fmt`'s shortest forms
#
# `zap fmt` also writes each thing the shortest way the language says it, where the two mean the same
# (the source of a test that `refuses` or `stops` keeps its forms, a GPU file all but the first
# two); each test below names one. The forms only types tell (a variant's type, a base, `??`, a
# widening, a move at the last use, a method call, an element loop) are the lint: `zap fmt` never
# checks, so the checks `zap test` makes anyway (its `check` and `tests` kinds, every test of a
# file run) note them in each file of the program they check, check the program again with them
# written (one after which it does not check is dropped, every one of a file that fails twice;
# the lowering made again for the patched files' functions alone) and keep them under the hash
# of the file's text (`build/cache/lint/`, beside the file for one under `build/`); a copy
# dropped only in the checked program's own file, as whether it may go rests on what the whole
# program's calls change. `zap fmt` writes a file's kept forms while its text is that one; `zap
# test --only check` fails as `lint` while a file under its paths has some, a line each saying
# `zap fmt applies it`. A file whose program does not check keeps its forms as written.

import fs
from fmtRun import formattedAs, isLaidOut, linted

# the lines of the formatted source that hold word
fn linesWith(source str, word str):
	linted(source).lines().filter(word in it).map(.copy())

test "a from-import is kept as written, its names in parentheses over several lines too":
	source = "from fs import stem, fileName as nameOf\nfrom json import (\n\tparse,\n\tKind\n)\nprint(stem(\"a\"))"
	expect linted(source) == source.replace("\t", ">")

test "fmt writes a method's field, a compound assignment and a lambda's parameter the short way":
	print(linted("""
		type Acc:
			total i64
			xs i64[]

			fn add(v i64):
				self.total = self.total + v
				self.xs[0] = self.xs[0] * (v + 1)
		a = Acc(
		total = total + 1
		)
		"""))
	prints """
		type Acc:
		>total i64
		>xs i64[]

		>fn add(v i64):
		>>total += v
		>>xs[0] *= v + 1
		a = Acc(
		>total = total + 1
		)
		"""
	print(linted("""
		mut x = 1
		x = x - 1 - 2
		x = x + 2 * 3
		x = x << 1
		x = x * f(x)
		x = x * 2 + 1
		x = 1 if x + 1 > 2 else 0
		mut ys = [1, 2]
		ys[x] = ys[x] + 1
		ys[f(x)] = ys[f(x)] + 1
		x = x + 1
		"""))
	prints """
		mut x = 1
		x = x - 1 - 2
		x += 2 * 3
		x <<= 1
		x *= f(x)
		x = x * 2 + 1
		x = 1 if x + 1 > 2 else 0
		mut ys = [1, 2]
		ys[x] += 1
		ys[f(x)] = ys[f(x)] + 1
		x += 1
		"""
	expect linted("print(g.map((k): k + 1).map((k i64): k))") ==
		"print(g.map(k: k + 1).map((k i64): k))"

test "fmt writes variants without unused values, a match of one case as an if, arms alike as one":
	print(linted("""
		fn show(o i64?, s Shape, b bool, n i64):
			match s:
				Circle(_): print(1)
				Rect(_, _): print(1)
				Point(): print(2)
				Ring(a, c): print(a + c)
			match s:
				Rect(_, _): print(1)
				_: pass
		"""))
	prints """
		fn show(o i64?, s Shape, b bool, n i64):
		>match s:
		>>Circle, Rect: print(1)
		>>Point: print(2)
		>>Ring(a, c): print(a + c)
		>if s is Rect:
		>>print(1)
		"""
	print(linted("""
		fn show(o i64?, s Shape, b bool, n i64):
			match o:
				v: print(v)
				none: pass
			match s:
				Ring(a, _) and a > 1.0: print(a)
				_: pass
			match b:
				false: print(0)
				true: pass
			match b:
				true: print(1)
				_: pass
			match n:
				7: print(n)
				_: pass
			match o:
				none: pass
				v: print(v)
		"""))
	prints """
		fn show(o i64?, s Shape, b bool, n i64):
		>if o is v:
		>>print(v)
		>if s is Ring(a, _) and a > 1.0:
		>>print(a)
		>if not b:
		>>print(0)
		>if b:
		>>print(1)
		>if n == 7:
		>>print(n)
		>if o is v:
		>>print(v)
		"""
	print(linted("""
		fn show(o i64?, s Shape, b bool, n i64):
			match s:
				Circle(r): pass
				_: print(0)
			match s:
				Rect(w, h): print(w)
				_:
					# nothing
					pass
		"""))
	prints """
		fn show(o i64?, s Shape, b bool, n i64):
		>match s:
		>>Circle(r): pass
		>>_: print(0)
		>match s:
		>>Rect(w, h): print(w)
		>>_:
		>>># nothing
		>>>pass
		"""
	print(linted("""
		fn show(o i64?, s Shape, b bool, n i64):
			match n:
				0: pass
				_: print(n)
			match n:
				0: pass
				v: print(v)
		"""))
	prints """
		fn show(o i64?, s Shape, b bool, n i64):
		>match n:
		>>0: pass
		>>_: print(n)
		>match n:
		>>0: pass
		>>v: print(v)
		"""

test "a match whose arm does not read the name it binds stays a match":
	print(linted(r"""
		fn saved(r i64 ? str) bool:
			match r:
				error: return false
				_: pass
			match r:
				error: print(error)
				_: pass
			true
		"""))
	prints r"""
		fn saved(r i64 ? str) bool:
		>match r:
		>>error: return false
		>>_: pass
		>if r is error:
		>>print(error)
		>true
		"""

test "fmt writes a match of one pattern as an if: a string's captures tested with is":
	print(linted(r"""
		fn f(line str, xs i64[]):
			match line:
				"GET {path}" and path != "": print(path)
				_: pass
			match line:
				"GET": print(line)
				_: pass
			match xs:
				[x, ..] and x > 0: print(x)
				_: pass
		"""))
	prints r"""
		fn f(line str, xs i64[]):
		>if line is "GET {path}" and path != "":
		>>print(path)
		>if line == "GET":
		>>print(line)
		>if xs is [x, ..] and x > 0:
		>>print(x)
		"""

test "fmt rewrites a match an arm of another holds, and keeps the header's comment":
	print(linted("""
		fn f():
			match a(1):   # read once
				bytes: match d(bytes):
					g: img = g
					_: pass
				none: pass
		"""))
	prints """
		fn f():
		>if a(1) is bytes:   # read once
		>>if d(bytes) is g:
		>>>img = g
		"""

test "a guard of one jump fits on the if's line":
	print(linted("fn f(x i64) i64:\n\tif x > 1:\n\t\treturn 1\n\tif x > 2:\n\t\tprint(x)\n\t\treturn 2\n\tif x > 3:\n\t\treturn 3\n\telse:\n\t\treturn 4\n\t0\n"))
	prints """
		fn f(x i64) i64:
		>if x > 1: return 1
		>if x > 2:
		>>print(x)
		>>return 2
		>if x > 3:
		>>return 3
		>else:
		>>return 4
		>0
		"""

# a program whose forms only types tell (canon.zap), with `broken` added when it should not check
fn typed(broken bool):
	source = """
		type Shape:
			Circle(r f64)
			Point
		type Pos:
			x i64
			y i64
			z i64
		type Named:
			name str
			x i64
		fn area(s Shape) f64:
			match s:
				Circle(r): r * r
				Point: 0.0
		fn moved(p Pos) Pos:
			Pos(x = p.x + 1, y = p.y, z = p.z)
		fn renamed(n Named) Named:
			Named(name = "b", x = n.x)
		fn pick(o i64?, r i64 ? str) i64:
			a = match o:
				v: v
				none: 0
			b = match r:
				v: v
				error: error.len
			c = match r:
				v: v
				error: -1
			d = match o:
				v: v
				_: fail("none")
			a + b + c + d
		fn label(n i64?) i64 ? str:
			match n:
				v: v
				none: "none"
		s = Shape.Circle(1.0)
		print(area(Shape.Point) + area(s))
		print(moved(Pos(x = 1, y = 2, z = 3)))
		print(renamed(Named(name = "a", x = 1)))
		print(pick(1, 2))
		print(label(none))
		"""
	linted("{source}fn broken() i64:\n\t\"x\"\n" if broken else source)

test "fmt writes the forms only types tell where they mean the same: .Variant, ..base, ??":
	for line in typed(false).lines():
		if "Pos(" in line and "fn " not in line and "moved(" not in line or
			"Named(name" in line and "renamed(" not in line or " ?? " in line or
			"match n" in line or "v: v" in line or "none\"" in line or "Shape." in line or
			"area(" in line and "fn " not in line:
			print(line)
	prints """
		>Pos(..p, x = p.x + 1)
		>Named(name = "b", x = n.x)
		>a = o ?? 0
		>b = r ?? error.len
		>c = r ?? -1
		>d = o ?? fail("none")
		>match n:
		>>v: v
		>>none: "none"
		s = Shape.Circle(1.0)
		print(area(.Point) + s.area())
		"""

# A binding written with its type whose value names it (`mut team Pokemon[] = [Pokemon("Zapdos", 50)]`)
# loses the annotation; one the value does not tell by itself keeps it (a tuple, a number, an
# optional, a generic's arguments).
test "fmt drops a type the value written with a constructor already tells":
	source = "type Card:\n\tsuit str\n\trank i64\nmut hand Card[] = [Card(\"a\", 1)]\nx Card = Card(\"b\", 2)\ny Card? = Card(\"c\", 3)\nz i64 = 5\nprint(hand.len + x.rank + z)\nprint(y)\n"
	print(linted(source))
	prints """
		type Card:
		>suit str
		>rank i64
		mut hand = [Card("a", 1)]
		x = Card("b", 2)
		y Card? = Card("c", 3)
		z i64 = 5
		print(hand.len + x.rank + z)
		print(y)
		"""

test "fmt leaves the forms only types tell in a file that does not check":
	text = typed(true)
	for line in text.lines():
		if "Pos(x = p" in line or "area(Shape" in line:
			print(line)
	print(text.lines().count("match " in it))
	prints """
		>Pos(x = p.x + 1, y = p.y, z = p.z)
		print(area(Shape.Point) + area(s))
		6
		"""

test "a module file's forms come from the check of a program that imports it":
	if not onWindows():
		# the repository's lint is noted on Windows alone (lint.zap)
		eprint("skipped: the lint of zap test's check is Windows'")
		return
	dir = testDir()
	_ = fs.createDir("{dir}shapes")
	_ = fs.writeFile("{dir}shapes/shape.zap", "pub type Shape:\n\tCircle(r f64)\n\tPoint\n\npub fn area(s Shape) f64:\n\tmatch s:\n\t\tCircle(r): r * r\n\t\tPoint: 0.0\n\npub fn origin() f64:\n\tarea(Shape.Point)\n")
	_ = fs.writeFile("{dir}main.zap", "import shapes\n\nprint(shapes.origin())\n")
	before = isLaidOut("{dir}shapes/shape.zap")
	said = Process.output("{zapPath()} test --only check {dir}", vars = ["ZAP_RUN="]).out   # (a land runs with fixlint)
	after = isLaidOut("{dir}shapes/shape.zap")
	expect before
	expect "shape.zap:11:" in said and "zap fmt applies it" in said and "== failed: lint ==" in said
	expect not after

test "an entry named alone says the lint of the module files its check read":
	if not onWindows():
		eprint("skipped: the lint of zap test's check is Windows'")
		return
	dir = "lintpaths-spec-{processId()}/"   # (outside build/, whose files a check's reads leave out; a run's own)
	_ = fs.deleteTree(dir)
	_ = fs.createDir("{dir}shapes")
	_ = fs.writeFile("{dir}shapes/shape.zap", "pub type Shape:\n\tCircle(r f64)\n\tPoint\n\npub fn area(s Shape) f64:\n\tmatch s:\n\t\tCircle(r): r * r\n\t\tPoint: 0.0\n\npub fn origin() f64:\n\tarea(Shape.Point)\n")
	_ = fs.writeFile("{dir}main.zap", "import shapes\n\nprint(shapes.origin())\n")
	said = Process.output("{zapPath()} test --only check {dir}main.zap", vars = ["ZAP_RUN="]).out
	_ = fs.deleteTree(dir)
	expect "shape.zap:11:" in said and "== failed: lint ==" in said

test "fmt leaves a GPU file's forms as they are":
	print(formattedAs("messy.gpu.zap", "fn f(a f32) f32:\n\tx = a\n\tx = x + 1.0\n\tx\n"))
	prints """
		fn f(a f32) f32:
		>x = a
		>x = x + 1.0
		>x
		"""

test "a file fmt wrote is laid out":
	file = "{testDir()}again.zap"
	_ = fs.writeFile(file, "type Box:\n\tw i64\n\th i64\nfn grow(b Box) Box:\n\tBox(w = b.w + 1, h = b.h)\nmut n = 0\nn = n + 1\no i64? = n\nm = match o:\n\tv: v\n\tnone: 0\nmatch o:\n\tv: print(v)\n\t_: pass\nprint(grow(Box(w = m, h = 2)))\n")
	Process.output("{zapPath()} test --only check {file}")
	first = isLaidOut(file)
	zapFmt(file)
	second = isLaidOut(file)
	_ = fs.deleteFile(file)
	print("{first} {second}")
	prints """
		false true
		"""

test "every compound assignment is a statement, and every binary operator ending a line continues it":
	print(linted("mut m = 1\nfor x in [1, 2]: m &= x\ny = 2 **\n3\n\tz = m @\ny\n"))
	prints """
		mut m = 1
		for x in [1, 2]: m &= x
		y = 2 **
		>3
		>z = m @
		>>y
		"""

test "the naturals are written n32 and n64":
	print(
		linted("fn f(a i64 in 0.., b i32 in 0..) i64:\n\ta + i64(b)\nx i64 in 0..=5 = 3\nprint(f(x, 2))\n")
	)
	prints """
		fn f(a n64, b n32):
		>a + b
		x i64 in 0..=5 = 3
		print(f(x, 2))
		"""

test "fmt drops a conversion the place makes anyway, and keeps one it does not":
	source = """
		fn wide(a i64, f f64, u u8) i64:
			a + i64(f) + i64(u)
		b u8 = 7
		n i64 = 9
		mut total i64 = 0
		total += i64(b)
		_ = wide(i64(b), f64(b), u8(n))
		m = i64(b) * i64(b)
		k = i64(b) << 8 | i64(b)
		h = i64(b) if n > 0 else n
		xs u8[] = [u8(0), u8(n)]
		print(total + m + k + h + xs.len + wide(1, 2.0, u8(3)))
		"""
	for line in linted(source).lines():
		if not line.startsWith("fn ") and " u8 = " not in line and " i64 = " not in line:
			print(line)
	prints """
		>a + i64(f) + u
		total += b
		wide(b, b, u8(n))
		m = i64(b) * i64(b)
		k = i64(b) << 8 | b
		h = i64(b) if n > 0 else n
		xs u8[] = [0, u8(n)]
		print(total + m + k + h + xs.len + wide(1, 2.0, 3))
		"""

test "fmt drops a widening cast where the place gives the same type, an index and a shift count too":
	source = """
		fn total(a i64, b u8) i64:
			a + i64(b)
		fn pick(xs i64[], b u8, w i16) i64:
			xs[i64(b)] + xs[i32(w)] + xs[i64(b & 3)]
		fn shifted(n i64, b u8) i64:
			n << i64(b) | n >> u32(b) | n << i64(b & 7)
		b u8 = 7
		w i16 = 3
		n i64 = 9
		wide = n * u32(b) + u32(b) * n
		less = n >= u32(b)
		print(total(n, b) + pick([1, 2, 3, 4, 5, 6, 7, 8], b, w) + shifted(n, b) + wide)
		print(less)
		"""
	for line in linted(source).lines():
		if line.startsWith(">") or line.startsWith("print") or "wide =" in line or "less =" in line:
			print(line)
	prints """
		>a + b
		>xs[b] + xs[w] + xs[b & 3]
		>n << b | n >> b | n << (b & 7)
		wide = n * b + b * n
		less = n >= b
		print(total(n, b) + pick([1, 2, 3, 4, 5, 6, 7, 8], b, w) + shifted(n, b) + wide)
		print(less)
		"""

test "fmt keeps a widening cast where the type of the expression would change":
	source = """
		fn narrow(a i32, b u8, c u8, d u16) i64:
			x = a * i64(b)
			y = b * u16(c)
			z = u32(b) * u32(c)
			mode = i64(d & 7)
			k = 3 + i64(d)
			wrapped u8 = u8(d % 7)
			x + i64(y) + i64(z) + mode + k + wrapped
		print(narrow(3, 200, 200, 9))
		"""
	for line in linted(source).lines():
		if line.startsWith(">") and not line.startsWith(">x +"): print(line)
	prints """
		>x = a * i64(b)
		>y = b * u16(c)
		>z = u32(b) * u32(c)
		>mode = i64(d & 7)
		>k = 3 + i64(d)
		>wrapped u8 = d % 7
		"""

test "fmt drops a narrowing the checker proves, and keeps an operand's and an unproven one":
	source = r"""
		fn roll(r u64) u8:
			u8(1 + r % 9)
		r = u64(args.len) + 5
		n = args.len
		small u8 = 3
		a u8 = u8(r & 255)
		b u8 = u8(n)
		c = small + u8(r % 9)
		xs u8[] = [u8(r % 7), u8(n % 3)]
		print("{roll(r)} {a} {b} {c} {xs}")
		"""
	print(linted(source))
	prints r"""
		fn roll(r u64) u8:
		>1 + r % 9
		r = u64(args.len) + 5
		n = args.len
		small u8 = 3
		a u8 = r & 255
		b u8 = u8(n)
		c = small + u8(r % 9)
		xs u8[] = [r % 7, n % 3]
		print("{roll(r)} {a} {b} {c} {xs}")
		"""

test "fmt keeps the conversion in a list literal whose type str decides":
	source = """
		print(str([u8(27)]))
		print(str([u8(27), 65]))
		"""
	print(linted(source))
	prints """
		print(str([u8(27)]))
		print(str([u8(27), 65]))
		"""

test "fmt drops the move of a field at its owner's last use, and keeps an early one":
	source = """
		type G:
			order str[]
			clips str[]
		type Rig:
			order str[]
			clips str[]
		fn pack(move g G) Rig:
			Rig(order = move g.order, clips = move g.clips)
		fn early() Rig:
			g = G(order = ["a"], clips = ["b"])
			order = move g.order
			g.clips.push("c")
			Rig(order, clips = move g.clips)
		print(pack(G(order = ["p"], clips = ["q"])).order)
		print(early().clips)
		"""
	for line in linted(source).lines():
		if "g." in line and "G(" not in line and "push" not in line:
			print(line)
	prints """
		>Rig(order = g.order, clips = g.clips)
		>order = move g.order
		>Rig(order, clips = g.clips)
		"""

test "a call of a function taking its first argument's type first is that value's method":
	source = "type V:\n\tx i64\n\nfn scaled(v V, k i64) i64:\n\tv.x * k\n\nfn norm(v V) i64:\n\tv.x.abs()\n\nv = V(x = -2)\nprint(scaled(v, 3) + norm(v))\nprint(norm(V(x = 4)))\n"
	for line in linted(source).lines():
		if line.startsWith("print"): print(line)
	prints """
		print(v.scaled(3) + v.norm())
		print(norm(V(x = 4)))
		"""

test "a byte test is the byte's method":
	for line in linted(
		"c = '5'\nword = \"ab\"\nprint(isDigit(c) or isAlpha(word[0]))\n"
	).lines():
		if "print" in line: print(line)
	prints """
		print(c.isDigit() or word[0].isAlpha())
		"""

test "a method's receiver keeps its conversion":
	for line in linted(
		"n = 4\nprint(f64(n).sqrt() + 1.0)\nprint(u8(55).isDigit())\n"
	).lines():
		if "sqrt" in line or "isDigit" in line: print(line)
	prints """
		print(f64(n).sqrt() + 1.0)
		print(u8(55).isDigit())
		"""

test "a list's written type goes when its first use would tell it":
	source = "mut xs i64[] = []\nxs.push(1)\nmut ys u8[] = []\nys.push(1)\nn = 2\nmut zs f64[] = []\nzs.push(n)\nmut ws str[] = []\nws = [\"a\"]\nprint(xs.len + ys.len + zs.len + ws.len)\n"
	for line in linesWith(source, "= []"): print(line)
	prints """
		mut xs = []
		mut ys u8[] = []
		mut zs f64[] = []
		mut ws = []
		"""

test "a list's written type stays where its first use takes its type from it":
	source = "fn f(n i64) i64?[,]:\n\trows i64?[,] = []\n\trows.push([n])\n\tparts (i64, i64?)[] = []\n\tparts.push((n, none))\n\trows\nprint(f(1).len)\n"
	for line in linesWith(source, "= []"): print(line)
	prints """
		>rows i64?[,] = []
		>parts (i64, i64?)[] = []
		"""

test "a list's written type stays where its first use widens a narrower value":
	source = "vs i32[] = [1, 2]\nmut xs i64[] = []\nxs.extend([vs[0], vs[1]])\nmut ys i64[] = []\nys = [vs[0]]\nmut zs i32[] = []\nzs.extend([vs[0]])\nprint(xs.len + ys.len + zs.len)\n"
	for line in linesWith(source, "= []"): print(line)
	prints """
		mut xs i64[] = []
		mut ys i64[] = []
		mut zs = []
		"""

test "_ = goes from a call that gives no result":
	source = "fn push(mut xs i64[], v i64) i64:\n\txs.push(v)\n\txs.len\nfn parse(s str) i64 ? str:\n\tmatch i64.parse(s):\n\t\tv: v\n\t\tnone: \"not a number\"\nmut xs = [2]\n_ = push(xs, 1)\n_ = parse(\"1\")\n_ = xs.sortedBy(x: x)\nprint(xs.len)\n"
	for line in linted(source).lines():
		if "push(xs" in line or "parse(\"" in line or "sortedBy" in line: print(line)
	prints """
		push(xs, 1)
		_ = parse("1")
		_ = xs.sortedBy(it)
		"""

test "a loop over a count alone is loop n":
	for line in linted(
		"n = 2\nfor _ in 0..n:   # n rounds\n\tprint(1)\nfor i in 0..n:\n\tprint(i)\n"
	).lines():
		if "0..n" in line or "loop" in line: print(line)
	prints """
		loop n:   # n rounds
		for i in 0..n:
		"""

test "a range ending at x + 1 includes x":
	for line in linted("n = 2\nm = 1\nfor i in 1..n + 1:\n\tprint(i)\nfor j in (0..n + 1 step 2):\n\tprint(j)\nfor k in 0..n + m:\n\tprint(k)\n").lines():
		if "for " in line: print(line)
	prints """
		for i in 1..=n:
		for j in (0..=n step 2):
		for k in 0..n + m:
		"""

test "a text joined with + that has a literal in it is one interpolation, and str(n) in it is braces":
	source = r"""
		line = "dir"
		n = 7
		print("cmd /c \"" + line + "\"")
		print("x = " + str(n) + " and " + "{n}")
		print(line + " and " + str(n))
		print(str(n))
		mut out = line + line
		out += "<" + line + ">"
		long = "a " +
			line +
			" b"
		print(long)
		print(str(n + 1) + r"{x\}")
		print(("big" if n > 1 else "small") + "!")
		print((out + "!").len)
		"""
	print(linted(source))
	prints r"""
		line = "dir"
		n = 7
		print("cmd /c \"{line}\"")
		print("x = {n} and {n}")
		print("{line} and {n}")
		print(str(n))
		mut out = line + line
		out += "<{line}>"
		long = "a {line} b"
		print(long)
		print("{n + 1}\{x\\\}")
		print("{"big" if n > 1 else "small"}!")
		print(("{out}!").len)
		"""

test "integer literals of five digits or more are grouped":
	for line in linted("a = 1000000 + 0xFFFFFFFF + 0b10100001 + 12345\nb = 1234 + 1234567.5 + 0xFFFF\nprint(a + b)\n").lines():
		if " = " in line: print(line)
	prints """
		a = 1_000_000 + 0xFFFF_FFFF + 0b1010_0001 + 12_345
		b = 1234 + 1234567.5 + 0xFFFF
		"""

test "a final return goes":
	for line in linted("fn twice(x i64) i64:\n\treturn x * 2\nprint(twice(1))\n").lines():
		if "x * 2" in line: print(line)
	prints """
		>x * 2
		"""

test "a chain of equalities is in a list":
	source = "k = 1\nif k == 1 or k == 2 or k == 3: print(k)\n"
	for line in linted(source).lines():
		if "if " in line: print(line)
	prints """
		if k in [1, 2, 3]: print(k)
		"""

test "an operator's value given first is the receiver in parentheses; a chain an else follows":
	for line in linted("import tensor\n\nfn twice(x tensor.Tensor, k f32) tensor.Tensor:\n\tx * k\n\na = tensor.zeros([2])\nb = twice(a + a, 2.0)\nn = b.count()\nj = 7 if n == 1 or n == 2 or n == 3 else 0\nprint(j)\n").lines():
		if "b =" in line or "j =" in line: print(line)
	prints """
		b = (a + a).twice(2.0)
		j = 7 if n in [1, 2, 3] else 0
		"""

test "a chain of equalities going on below is in for the part on one line":
	source = "k = 1\nif k == 1 or k == 2 or k == 3 or\n\tk == 4:\n\tprint(k)\n"
	for line in linted(source).lines():
		if "k ==" in line or " in [" in line: print(line)
	prints """
		if k in [1, 2, 3] or
		>k == 4:
		"""

test "a tuple is taken apart and given without parentheses":
	source = "(a, b) = (1, 2)\n(a, b) = (b, a)\nt = (3, 4)\nu (i64, i64) = (5, 6)\nprint(a + b)\nprint(t)\nprint(u)\n"
	for line in linesWith(source, " = "): print(line)
	prints """
		a, b = 1, 2
		a, b = b, a
		t = 3, 4
		u (i64, i64) = (5, 6)
		"""

test "a field named by its own local is the name alone":
	source = "type Size:\n\twidth i64\n\theight i64\n\tdepth i64\nfn show(s Size) str:\n\t\"\{s.width}x\{s.height}x\{s.depth}\"\nwidth = 2\nheight = 3\ndepth = 4\nprint(show(Size(width = width, height = height, depth = depth)))\nprint(show(Size(height, width, depth)))\n"
	for line in linesWith(source, "Size("): print(line)
	prints """
		print(show(Size(width, height, depth)))
		print(show(Size(height, width, depth)))
		"""

test "a string of escaped braces is raw":
	source = r"""
		x = 1
		a = "\{x\}"
		b = "{x}\n"
		print(a + b)
		"""
	for line in linted(source).lines():
		if "a = " in line or "b = " in line: print(line)
	prints r"""
		a = r"{x}"
		b = "{x}\n"
		"""

test "a list's own length inside its brackets is len":
	for line in linted("type P:\n\titems i64[]\nxs = [1, 2, 3]\nys = [4, 5, 6]\np = P(items = [7, 8])\nprint(xs[xs.len - 1] + p.items[p.items.len / 2] + ys[xs.len - 1])\n").lines():
		if "print(" in line: print(line)
	prints """
		print(xs[len - 1] + p.items[len / 2] + ys[xs.len - 1])
		"""

test "only the indexed list's own length is len, not one of a name ending alike or nested deeper":
	for line in linted(
		"t = [1, 2, 3]\nit = [0]\nu = [0, 1]\nprint(t[it.len + 1] + t[u[t.len - 3]])\n"
	).lines():
		if "print(" in line: print(line)
	prints """
		print(t[it.len + 1] + t[u[t.len - 3]])
		"""

test "a loop over indexes that only reads the elements is a loop over them":
	for line in linted("items = [1, 2]\nwords = [\"a\"]\nmut total = 0\nfor i in 0..items.len:\n\ttotal += items[i]\nfor i in 0..words.len:\n\tprint(\"\{i} \{words[i]}\")\nfor i in 0..words.len:\n\tprint(words[i] + words[0])\nprint(total)\n").lines():
		if "for " in line or "total +=" in line or "print(" in line and "total" not in line:
			print(line)
	prints r"""
		for item in items:
		>total += item
		for i, word in words:
		>print("{i} {word}")
		for i in 0..words.len:
		>print(words[i] + words[0])
		"""

test "a loop over indexes stays when its element is a name bound before, its list's owner changes, or it goes over a map":
	source = r"""
		type Bag:
			items i64[]
		xs = [1, 2]
		mut last = 0
		for i in 0..xs.len:
			last = xs[i]
		mut bag = Bag(items = [1, 2])
		for i in 0..bag.items.len:
			item = bag.items[i]
			bag = Bag(items = [item])
		mut counts {i64: i64} = {}
		counts[0] = 5
		for i in 0..counts.len:
			count = counts[i]
			print(count)
		print("{last} {bag.items}")
		"""
	for line in linted(source).lines():
		if line.startsWith("for "): print(line)
	prints """
		for i in 0..xs.len:
		for i in 0..bag.items.len:
		for i in 0..counts.len:
		"""

test "a loop over a mut list's indexes that changes its elements is a loop over them":
	source = "type P:\n\thp i64\nmut ps = [P(hp = 1)]\nfor i in 0..ps.len:\n\tps[i].hp += 1\nmut ns = [1]\nfor i in 0..ns.len:\n\tns[i] = ns[i] * 2\nprint(\"\{ps[0].hp} \{ns}\")\n"
	for line in linted(source).lines():
		if line.startsWith("for ") or line.startsWith(">"): print(line)
	prints """
		>hp i64
		for mut p in ps:
		>p.hp += 1
		for i in 0..ns.len:
		>ns[i] *= 2
		"""

test "the circle's constants are written pi and tau":
	for line in linted(
		"print(3.14159265358979 * 2.0 + 6.2831853 + 3.14159 + 3.1415)\n"
	).lines():
		if "print(" in line: print(line)
	prints """
		print(pi * 2.0 + tau + 3.14159 + 3.1415)
		"""

test "the mathematical forms that exist are written":
	for line in linted("x = 0.5\ny = 2.0\nlo = 1.0\nhi = 3.0\na = 90.0\nb = 1.0\nc = x.max(0.0).min(1.0)\nd = y.min(hi).max(lo)\ne = a * pi / 180.0 + pi / 180.0 * 45.0 + (a + b) * (pi / 180.0)\nf = b * 180.0 / pi - a / b * pi / 180.0\nprint(\"\{c} \{d} \{e} \{f}\")\n").lines():
		if "c = " in line or "d = " in line or "e = " in line or "f = " in line: print(line)
	prints """
		c = x.clamp(0.0, 1.0)
		d = y.min(hi).max(lo)
		e = a.radians() + pi / 180.0 * 45.0 + (a + b).radians()
		f = b.degrees() - a / b * pi / 180.0
		"""

test "a split at newlines is the text's lines":
	source = "t = \"a\\nb\"\nparts = t.split(\"\\n\")\nfor p in t.split(\",\"):\n\tprint(p)\nprint(parts.len + \"x.split(\\\"\\\\n\\\")\".len)\n"
	for line in linesWith(source, "parts"): print(line)
	prints r"""
		parts = t.lines()
		print(parts.len + "x.split(\"\\n\")".len)
		"""

test "a lambda whose value fills a field by its name keeps its name":
	source = "type P:\n\tkind i64\n\tranges ref i64[]\nrs = [[1], [2]]\nps = rs.map(ranges: P(kind = 0, ranges))\nprint(ps.len)\n"
	for line in linesWith(source, "ps = "): print(">{line}")
	prints """
		>ps = rs.map(ranges: P(kind = 0, ranges))
		"""

test "a long parameter list breaks between parameters, not inside a type's arguments":
	source = "type Animation:\n\tframes i64\nfn step(first i64, second i64, third i64, anims \{i64: Animation}, fourth i64, fifth i64, sixth i64, seventh i64) bool:\n\tfirst + second + third + fourth + fifth + sixth + seventh + anims.len > 0\nprint(step(1, 2, 3, \{}, 4, 5, 6, 7))\n"
	for line in linted(source).lines():
		if r"anims {" in line: print(line)
	prints r"""
		>anims {i64: Animation},
		"""

test "a tuple alone gives its variants no enum":
	source = "type Kind:\n\tA\n\tB\npairs = [(Kind.A, 1), (Kind.B, 2)]\nfor (_, n) in pairs:\n\tprint(n)\n"
	for line in linesWith(source, "pairs = "): print(">{line}")
	prints """
		>pairs = [(Kind.A, 1), (Kind.B, 2)]
		"""

test "a test's header that opens its source stays one line, however long":
	header = "test \"a block freed twice stops the program, whatever its size\" stops Failure(\"a block freed twice\"):"
	expect linted("{header}\n\tp = 1\n").startsWith(header)

test "a conversion that tells a list, a tuple, a map, a box or a result its type stays":
	source = r"""
		fn f(x i16) i64[]:
			values = []
			values.push(i64(x))
			values
		fn g(x i16) i64:
			i64(x)
		a i16 = 3
		xs = [i64(a), i64(a)]
		ys = [[i64(a)]]
		t = i64(a), 2
		m = {i64(a): i64(a)}
		b = Box(i64(a))
		ks = [a].map(x:
			if x > 1:
				return i64(x)
			i64(x) + 1
		)
		print("{f(3)} {g(a)} {xs} {ys} {t} {m} {b} {ks}")
		"""
	for line in linted(source).lines():
		if "i64(" in line: print(line)
	prints r"""
		>values.push(i64(x))
		xs = [i64(a), i64(a)]
		ys = [[i64(a)]]
		t = i64(a), 2
		m = {i64(a): i64(a)}
		b = Box(i64(a))
		>if x > 1: return i64(x)
		>i64(x) + 1
		"""

test "fmt writes the shortest form" for (written, becomes) in [
	("xs = [1]\nprint(xs.len == 0)\nprint(xs.len > 0)\n", "xs = [1]\nprint(xs.isEmpty)\nprint(not xs.isEmpty)"),
	("fn f(x i64) i64: x\na = 1\nb = 2\nprint(f((a + b)))\n", "fn f(x i64): x\na = 1\nb = 2\nprint(f(a + b))"),
	("print([1].map((x): x + 1))\n", "print([1].map(it + 1))"),
	("x = 2.0\nprint(x.max(0.0).min(1.0))\n", "x = 2.0\nprint(x.clamp(0.0, 1.0))"),
	("xs = [1, 2, 3]\nprint(xs[1..xs.len])\nprint(xs[0..2])\n", "xs = [1, 2, 3]\nprint(xs[1..])\nprint(xs[..2])"),
	("xs = [1, 2, 3]\nprint(xs[1..len])\nprint(xs[0..=1])\n", "xs = [1, 2, 3]\nprint(xs[1..])\nprint(xs[0..=1])"),
]:
	expect linted(written) == becomes

# `T.parse(args.first ?? "d") ?? d` is `arg(i, d)` where the result keeps its type (an i64 for an
# integer default, an f64 for one with a point); a new binding of another type writes it
# (`size i32 = arg(0, 100)`), another place and a default the text differs from keep the long
# form, and so does a file that names `arg` itself.
test "fmt writes arg(i, default) where the type stays":
	source = "n = i64.parse(args.first ?? \"100\") ?? 100\nm = i64.parse(args[2] if args.len > 2 else \"10000\") ?? 10_000\nf = f64.parse(args.first ?? \"1.5\") ?? 1.5\nsize = i32.parse(args.first ?? \"7\") ?? 7\nmut k = u8.parse(args.first ?? \"3\") ?? 3\nother = i64.parse(args.first ?? \"5\") ?? 6\nreal = f64.parse(args.first ?? \"2\") ?? 2\nprint(n + m + size + other + i64(f + real) + i64(k))\n"
	print(linted(source))
	prints """
		n = arg(0, 100)
		m = arg(2, 10_000)
		f = arg(0, 1.5)
		size i32 = arg(0, 7)
		mut k u8 = arg(0, 3)
		other = i64.parse(args.first ?? "5") ?? 6
		real f64 = arg(0, 2)
		print(n + m + size + other + i64(f + real) + k)
		"""

test "fmt keeps the long form of an argument in a file that names arg":
	source = "arg = 3\nn = i64.parse(args.first ?? \"100\") ?? 100\nprint(n + arg)\n"
	expect linted(source) == source.trimmedEnd()

test "a conversion stays when the empty list's written type goes, as the push would tell the narrow type":
	print(linted("""
		fn total(xs i64[]) i64:
			xs.sum()
		a u8 = 200
		mut ys i64[] = []
		ys.push(i64(a))
		print(total(ys))
		"""))
	prints """
		fn total(xs i64[]):
		>xs.sum()
		a u8 = 200
		mut ys = []
		ys.push(i64(a))
		print(total(ys))
		"""
