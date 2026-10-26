# 2.1 Fixed decisions
#
# The language is experimental and changes often. Each version is written as if the language had
# started that way. What goes is gone, with no compatibility kept: a syntax form, a behaviour, a
# std declaration, a command, an option, an environment word, the compiler's own code for any of
# them. Writing it gives the ordinary error, as for something that never existed (no error of its
# own, no hint, no rewrite, no test of it).
# Code in the old form is migrated once, when the change lands (a `zap fmt` rewrite or a script
# run over every repository), and the migration is then deleted.
#
# Blocks are indented: a line ending in `:` opens one, and its body is the lines below it indented
# one tab more (tabs, never spaces). A body of one statement may follow the `:` on the same line;
# `pass` is the empty body. No `;`: a newline ends a statement.

fn sign(n i64):
	if n < 0: return "negative"
	if n == 0:
		pass
	"not negative"

test "a block is the lines indented below its colon, or the rest of the line":
	expect sign == {-1: "negative", 0: "not negative"}

test "a semicolon does not join statements" refuses UnexpectedCharacter:
	x = 1; y = 2
	print(x + y)

# No `:` before types: the type follows the name after a space, everywhere (`id u32`,
# `users User[]`, `fn f() str[]`). A keyword starts each declaration that needs one (`fn`, `type`,
# `mut`, `import`); an immutable local needs none.

test "a type follows its name after a space" refuses ExpectedType:
	fn twice(x: i64) i64:
		x * 2
	print(twice(1))

# Names: functions and variables in camelCase, types in PascalCase, keywords lowercase. A declared
# function, type, method or top-level binding holds no `_` (the compiler makes its own names with
# it); an `extern` keeps the system's spelling. No name holds `__` past its start: `module__name`
# is a global name, past the module's privacy.
# A module's name is a name too: its source files and the dirs that hold them are camelCase
# (`irOwnOrigins.zap`, `jsonIndent/`), single words and abbreviations lowercase; no `_`, no `-`, no
# capital first letter, which `zap test`'s `limits` refuses.

test "a method named with '_' would be another type's method" refuses UnderscoreInName:
	type A:
		v i64

		fn b_c() i64:
			v
	print(A(1).b_c())

test "a name written with a module's prefix" refuses DoubleUnderscore:
	fn rt__fail(m str):
		print(m)
	rt__fail("x")

# Every name of the language, the std, the engine and the programs follows the same rules, short
# and saying what it is:
# - One word where the owner gives the context: `img.width`, `file.close()`, `json.Node`; a type's
#   name does not repeat its module's, as it is read `m.T` (`image.Image`, the module's own name,
#   stays).
# - A field for what is looked up, a method with `()` for what computes or acts: sizes, state and
#   properties are fields (`xs.len`, `xs.isEmpty`, `job.isDone`, `xs.byteSize`, `f.len`); a method
#   that only reads a field is that field.
# - A verb changes the value in place, its participle gives a new one: `sort()` and `sorted()`,
#   `reverse()` and `reversed()`, `trimmed()` (a str is never changed).
# - A `bool` is named `is`, `has` or `can` and a word (`isDone`, `hasAlpha`, `canWrite`), or a verb
#   of the third person (`contains`, `startsWith`); a function that acts and tells with a bool how
#   it went is named by what it does.
# - One word for each idea, everywhere: `len` a size, `count(p)` a count by a condition, `push`,
#   `insert` and `remove` on lists, `find(p)` by a condition and `indexOf(v)` by a value, `dir`
#   (never folder), `load` and `save` for files, `new` and `destroy` for the engine's resources.
# - A method before a free function (`q.rotate(v)`, `b.laneAny()`, `v.alignUp(8)`).
# - A value is made by calling its type, what it is made from said by named arguments:
#   `Grid(w, h)`, `Grid(w, h, fill = 0.0)`, `Grid(w, h, cells = xs)`; a conversion is a pair,
#   `x.toBits()` and `f32.fromBits(u)`, `x.toBytes()` and `T.fromBytes(b)`; text is read by
#   `T.parse(text)`, a `T?`.
# - Only the abbreviations every programmer reads: `len`, `min`, `max`, `id`, `dir`, `rgba`, `gpu`
#   and the like; any other word written whole.
# The compiler refuses what it can tell (compiler/syntax/names.zap): a public type beginning with its
# module's name and a capital, a public function giving a `bool` that changes nothing and does not
# say what holds, a method that only reads a field of its value, and the words refused (`folder`,
# `size` for a function of a value alone).

test "a bool's name says what holds" refuses BoolNameSpelling:
	pub fn empty(xs i64[]) bool:
		xs.len == 0
	print(empty([1]))

# keeps the line, and whether there is room for more
pub fn record(mut lines str[], line str) bool:
	lines.push(line.copy())
	lines.len < 10

test "a bool that tells how an action went is named by the action":
	log = []
	expect record(log, "a")
	expect "ab".endsWith("b")
	expect "ab".startsWith("a")

test "a method that only reads a field is that field" refuses GetterMethod:
	type Picture:
		w i64

		fn width() i64:
			w
	print(Picture(w = 2).width())

test "a size of a value alone is its len" refuses RefusedWord("size: len"):
	type Bag:
		items i64[]

		fn size() i64:
			items.len
	print(Bag(items = []).size())

# Unused variables are errors: a mistyped fresh name becomes a never-read variable and is caught.
# `_` is exempt.

test "a binding never read" refuses UnusedVariable:
	total = 1
	totl = total + 1
	print(total)

test "_ takes what is not wanted":
	[1, 2].pop()
	for _ in [1, 2]:
		print("x")
	prints """
		x
		x
		"""

# One way to give a result: the trailing expression of a body is the function's result (see
# *Functions*); `return` is for leaving early, and zap fmt writes a final `return v` as `v`.

# A size reads as a field; a method takes parentheses. What reads in constant time, allocates
# nothing and cannot fail is written without them: `len` and `isEmpty` of lists, strings, maps,
# fixed arrays, `Pool`, `Channel`, `Table` and any type whose method of that name takes nothing, a
# list's `first` and `last` (an optional each) and the program's arguments `args` (fixed while it
# runs, lent where it is read). A struct's own field of that name is the field. Anything else a
# value gives by computing is a method, always called with parentheses.

type Span:
	at i64
	len i64

test "the sizes of lists, strings, maps, fixed arrays and a std collection":
	xs = [1, 2, 3]
	m = {"a": 1}
	a i64[4] = [1, 2, 3, 4]
	print("{xs.len} {xs.isEmpty} {"hello".len} {"".isEmpty} {m.len} {m.isEmpty} {a.len}")
	h = Heap<i64>()
	h.push(3)
	print("{h.len} {h.isEmpty}")
	ys = ["ab", "c"]
	print("{ys.map(.len)} {ys.filter(.len > 1)}")
	prints """
		3 false 5 true 1 false 4
		1 false
		[2, 1] ["ab"]
		"""

test "a pool's and a channel's sizes":
	p = Pool<i64>()
	empty = p.isEmpty
	p.add(4)
	ch = Channel<str>()
	was = ch.isEmpty
	ch.send("a")
	expect empty
	expect p.len == 1
	expect not p.isEmpty
	expect was
	expect ch.len == 1
	expect not ch.isEmpty

test "a struct's own field of a size's name is that field":
	s = Span(at = 1, len = 7)
	o Span? = s
	os i64[]? = [1]
	expect s.len == 7
	expect o?.len == 7
	expect os?.len == 1

test "a size is not called" refuses SizeIsField("a size reads as a field: xs.len"):
	xs = [1, 2]
	print(xs.len())

test "a list's first and last read as fields, an optional each":
	xs = [3, 4, 5]
	e i64[] = []
	words = ["ab", "c"]
	print("{xs.first} {xs.last} {e.last} {e.first ?? -1} {words.first ?? ""}")
	prints "some(3) some(5) none -1 ab"

test "the program's arguments are a value":
	args.set(["x", "y z"])
	print("{args.len} {args.first ?? ""}")
	for a in args:
		print(a)
	mine = args.copy()
	mine.push("w")
	print(mine)
	prints """
		2 x
		x
		y z
		[\"x\", \"y z\", \"w\"]
		"""

test "a method is called with parentheses" refuses MethodNeedsCall:
	xs = [1]
	print(xs.parallel)

# A value made and dropped is an error: `xs.sortedBy(f)` alone sorts a copy no one sees (write
# `xs = xs.sortedBy(f)`), and so are a bare name and bare arithmetic. A call that does something (a
# function of the program, `push`, an extern) drops its result freely. A result (`T ? E`) is the
# exception: it is handled (`v = f() ?? ...`, a `match`) or dropped knowingly, `_ = f()`.

fn counted(mut xs i64[]):
	xs.push(1)
	xs.len

fn parsed(s str) i64 ? str:
	i64.parse(s) ?? return "not a number"

test "a call that does something drops its result freely; a result is dropped with _":
	xs = [2]
	counted(xs)
	_ = parsed("x")
	expect xs == [2, 1]

test "a sorted copy no one sees" refuses CopyIgnored:
	xs = [2, 1]
	xs.sortedBy(it)
	print(xs)

test "a result left unhandled" refuses ResultIgnored:
	fn half(n i64) i64 ? str:
		if n % 2 == 1: return "odd"
		n / 2
	half(4)

# One layout, the one `zap fmt` writes (13.1). Comments start with `#` and run to the end of the
# line; the comment lines right above a declaration document it (the language server shows them).
