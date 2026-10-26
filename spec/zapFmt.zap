# 13.1.2 `zap fmt`

import fs
from fmtRun import formatted, isLaidOut, linted

# `zap fmt` gives every file under its paths one layout (`zap fmt .` lays out the repository, as a
# change of syntax and its rewrite ship); `--check` lists the
# files that would change and exits with 1. A statement's indentation is its meaning and stays (four spaces become a tab), a
# line continuing an expression is one tab more, a line inside brackets one past the line that
# opened them, a line starting with `.` (a chain's step) one past the line its chain goes on from,
# no trailing spaces, at most one blank line and none right after a line that opens a block, one
# final newline; comments and `"""` strings stay as written. A line fits in 100 columns (a tab
# counts four): one that does not is broken at its outermost place first, then inward. A string
# literal is never broken, nor a line long only through its comment. A file found laid out is
# known by the hash of its text, the lint's findings kept for it (13.1.3) and the zap, and not
# laid out again while they are the same; the others are laid out on every processor at once, and
# fmt never checks a program (the whole repository in a second or two, after a change of the zap
# too). The tabs are shown as `>`.

test "a file laid out":
	print(formatted("x = 1   \nif x > 0 and\nx < 5:\n\t\tprint(x)\n\n\n\n\trows = (0..3).map(i:\n\t\ti * 2\n)\n\tprint(rows)\n\n"))
	prints """
		x = 1
		if x > 0 and
		>x < 5:
		>>print(x)

		>rows = (0..3).map(i:
		>>i * 2
		>)
		>print(rows)
		"""

test "four spaces are a tab":
	print(formatted("    x = 1\n    if x > 0:\n        print(x)\n"))
	prints """
		x = 1
		>if x > 0:
		>>print(x)
		"""

test "a step's lambda that hands its parameter to a function of the file is that function":
	print(linted("fn double(x i64) i64: x * 2\nfn add(a i64, b i64) i64: a + b\nprint([1].map(x: double(x)).sum() + [2].map(x: add(x, 1)).sum() + [3].map(x: print(x)).len)\n"))
	prints """
		fn double(x i64): x * 2
		fn add(a i64, b i64): a + b
		print([1].map(double).sum() + [2].map(add(it, 1)).sum() + [3].map(x: print(x)).len)
		"""

test "a lambda that reads its parameter as a value is its body, with it (or .field) for the parameter":
	print(linted("type P:\n\tname str\n\tage i64\nfn by(ps P[], key fn(P) i64) P[]: ps.sortedBy(key)\nps = [P(name = \"a\", age = 3)]\nprint(ps.filter(p: p.age > 2).map(p: p.name.len + p.age).sum())\nprint(by(ps, p: p.age * 2).map(p: [1, 2].filter(q: q > p.age).len))\nprint(ps.map(p: [p.age].map(q: q + 1).sum()))\nprint([1, 2].map(x: x +\n\t1))\n"))
	prints """
		type P:
		>name str
		>age i64
		fn by(ps P[], key fn(P) i64): ps.sortedBy(key)
		ps = [P(name = "a", age = 3)]
		print(ps.filter(.age > 2).map(.name.len + .age).sum())
		print(by(ps, .age * 2).map(p: [1, 2].filter(it > p.age).len))
		print(ps.map([.age].map(it + 1).sum()))
		print([1, 2].map(x: x +
		>>1))
		"""

test "a lambda that calls a method of its parameter is that method's function, in a generic too":
	source = "type P:\n\tage i64\nfn old(p P) bool: p.age > 30\nfn olds<T>(xs T[], f fn(T) bool) i64: xs.filter(x: f(x)).len\nfn ages<T Hash>(xs T[]) i64: xs.map(x: x.hash()).len\nps = [P(age = 40)]\nprint(ps.filter(p: p.old()).len + olds(ps, p: p.old()) + ages([1]))\n"
	print(linted(source))
	prints """
		type P:
		>age i64
		fn old(p P): p.age > 30
		fn olds<T>(xs T[], f fn(T) bool) i64: xs.filter(x: f(x)).len
		fn ages<T Hash>(xs T[]) i64: xs.map(.hash()).len
		ps = [P(age = 40)]
		print(ps.filter(.old()).len + olds(ps, .old()) + ages([1]))
		"""

test "the source of a test that refuses is laid out and kept as written":
	print(formatted("test \"t\" refuses MethodNeedsCall:\n\tfn h():\n\t\txs = [1]\n\t\tprint(xs.len\n\t)\nfn f():\n    g()\n"))
	prints """
		test "t" refuses MethodNeedsCall:
		>fn h():
		>>xs = [1]
		>>print(xs.len
		>>)
		fn f():
		>g()
		"""

test "a file keeps its line endings":
	file = "{testDir()}crlf.zap"
	_ = fs.writeFile(file, "if true:\r\n\tprint(1)\r\n")
	laid = isLaidOut(file)
	_ = fs.writeFile(file, "if true:\r\n    print(1)   \r\n")
	messy = isLaidOut(file)
	Process.output("{zapPath()} fmt {file}")
	text = fs.readFile(file) ?? ""
	_ = fs.writeFile(file, "if true:\n\tprint(1)\n")
	plain = isLaidOut(file)
	_ = fs.deleteFile(file)
	print("{laid} {messy} {plain}")
	print(text.replace("\r", "<CR>").replace("\t", ">").trimmedEnd())
	prints """
		true false true
		if true:<CR>
		>print(1)<CR>
		"""

test "zap test --update keeps the line endings":
	file = "{testDir()}update.zap"
	_ = fs.writeFile(file, "test \"a\":\r\n\tprint(1)\r\n\tprint(2)\r\n\tprints \"0\"\r\n")
	Process.output("{zapPath()} test --only tests --update {file}")
	text = fs.readFile(file) ?? ""
	_ = fs.deleteFile(file)
	print(text.replace("\r", "<CR>").replace("\t", ">").replace("\"\"\"", "<Q>").trimmedEnd())
	prints """
		test "a":<CR>
		>print(1)<CR>
		>print(2)<CR>
		>prints <Q><CR>
		>>1<CR>
		>>2<CR>
		>><Q><CR>
		"""

test "strings that hold strings in their interpolations keep the brackets and comments apart":
	print(formatted("if true:\n\tx = \"a \{f(\"(\")} b\"\n\ty = \"\{f(\"x # y\")}\" + \"z\"\n\tc = \"\{'\"'}\"\nprint(1)\n"))
	prints r"""
		if true:
		>x = "a {f("(")} b"
		>y = "{f("x # y")}" + "z"
		>c = "{'"'}"
		print(1)
		"""

# ---------- lines past 100 columns ----------

test "a long chain of calls breaks before each step, the steps one tab in":
	print(formatted("longer = words.filter(w: w.len > 2).map(w: w + \"!\").filter(w: w.startsWith(\"applesauce\")).sortedBy(w: w.len)\nprint(longer)\n"))
	prints """
		longer = words
		>.filter(w: w.len > 2)
		>.map(w: w + "!")
		>.filter(w: w.startsWith("applesauce"))
		>.sortedBy(.len)
		print(longer)
		"""

test "a long call's arguments go one a line, the closing bracket on its own, the comment with the first":
	print(formatted("rect = Rect(x = origin.x + offset.x, y = origin.y + offset.y, width = size.width * scale, height = size.height * scale)   # the frame\n"))
	prints """
		rect = Rect(   # the frame
		>x = origin.x + offset.x,
		>y = origin.y + offset.y,
		>width = size.width * scale,
		>height = size.height * scale
		)
		"""

test "a lambda whose body does not fit takes the block form":
	print(formatted("scores = words.map(w: w.len * 2 + w.len * 3 + w.len * 4 + w.len * 5 + w.len * 6 + w.len * 7 + w.len * 8)\ntotal = words.reduce(0, (acc, w): acc + w.len * 2 + w.len * 3 + w.len * 4 + w.len * 5 + w.len * 6 + w.len * 7)\n"))
	prints """
		scores = words.map(w:
		>w.len * 2 + w.len * 3 + w.len * 4 + w.len * 5 + w.len * 6 + w.len * 7 + w.len * 8
		)
		total = words.reduce(0, (acc, w):
		>acc + w.len * 2 + w.len * 3 + w.len * 4 + w.len * 5 + w.len * 6 + w.len * 7
		)
		"""

test "a long condition breaks after its loosest operator, the body of a long statement goes below":
	print(formatted("if words.len > 2 and words[0] == \"alpha\" and words[1] == \"be\" and words[2] == \"gamma\" and words[3] == \"delta\" and words[4] == \"epsilon\": print(\"ok\")\nmessage = words.join(\", \") + \" and the rest of a long line that keeps going on and on until it is past the limit\"\n"))
	prints """
		if words.len > 2 and words[0] == "alpha" and words[1] == "be" and words[2] == "gamma" and
		>words[3] == "delta" and words[4] == "epsilon":
		>print("ok")
		message = words.join(", ") +
		>" and the rest of a long line that keeps going on and on until it is past the limit"
		"""

test "a string literal is never broken: a line too long because of one stays":
	print(formatted("print(\"a string literal is never broken, however long it is: this one goes well past the hundredth column\")\nerrorAt(c, line, col, \"a message stays with its call when it would not fit on a line of its own either, as this one would not\")\n"))
	prints """
		print("a string literal is never broken, however long it is: this one goes well past the hundredth column")
		errorAt(c, line, col, "a message stays with its call when it would not fit on a line of its own either, as this one would not")
		"""

test "a literal going on below keeps its opener, its elements one a line, and a chain's receiver keeps its parentheses":
	print(formatted("names = [(\"alpha\", \"the first letter\"), (\"beta\", \"the second letter\"), (\"gamma\", \"the third letter\"),\n\t(\"delta\", \"the fourth letter\"), (\"epsilon\", \"the fifth letter\")]\nxs = (0..n)\n\t.map(i: i * 2)\n\t.filter(i: i > 2)\n"))
	prints """
		names = [
		>("alpha", "the first letter"),
		>("beta", "the second letter"),
		>("gamma", "the third letter"),
		>("delta", "the fourth letter"), ("epsilon", "the fifth letter")]
		xs = (0..n)
		>.map(i: i * 2)
		>.filter(i: i > 2)
		"""

test "breaking lines is idempotent":
	source = "longer = words.filter(w: w.len > 2).map(w: w + \"!\").filter(w: w.startsWith(\"a\")).sortedBy(w: w.len)\nprint(describe(words[0], words[1], words[2], words[3], words[4], words[5], words[6], words[7], words[8], words[9]))\nif words.len > 2 and words[0] == \"alpha\" and words[1] == \"be\" and words[2] == \"gamma\" and words[3] == \"delta\" and words[4] == \"epsilon\": print(\"ok\")\npairs = words.map(w: (w.copy(), w.len * 2 + w.len * 3 + w.len * 4 + w.len * 5 + w.len * 6 + w.len * 7 + w.len * 8))\n"
	once = formatted(source)
	print(once == formatted("{once.replace(">", "\t")}\n"))
	prints """
		true
		"""
