# Memory bugs tests/fuzz/memory.zap found, each kept as a test (freed memory is poisoned while tests
# run, and every block must be freed when they end). Where the bug was in a copy the compiler
# used to insert, the program now names the copy, and the implicit form is rejected.

fn keep(move xs i64[]):
	xs

fn keepThrough(move xs i64[]):
	ys = move xs
	ys

test "a lambda's result is a value, not a window into its temporary":
	f = (x str): ("{x}v3")[0..x.len + 2].copy()
	print(f("r"))
	prints "rv3"

test "a lambda's result that is a window into its temporary is rejected" refuses MoveOfPart:
	f = (x str): ("{x}v3")[0..x.len + 2]
	print(f("r"))

test "a pipeline lambda's result too":
	xs = ["ab", "c"]
	print(xs.map(("{it}!")[0..it.len + 1].copy()))
	prints "[\"ab!\", \"c!\"]"

test "a pipeline lambda's window is rejected too" refuses MoveOfPart:
	xs = ["ab", "c"]
	print(xs.map(x: ("{x}!")[0..x.len + 1]))

test "a variable moved into a parameter that is returned is freed once":
	l2 = [1]
	l1 = keep(l2)
	print(l1)
	prints "[1]"

test "a variable passed to a move parameter and used after gives a copy":
	l2 = [1]
	l1 = keep(l2.copy())
	print(l1)
	print(l2)
	prints """
		[1]
		[1]
		"""

test "a variable given to a move parameter is not used after" refuses UseAfterGiven:
	fn keep(move xs i64[]) i64[]:
		xs
	l2 = [1]
	l1 = keep(l2)
	print(l1)
	print(l2)

test "a move parameter bound to another name is not lost":
	print(keepThrough([2]))
	prints "[2]"

test "a closure made in a loop takes a value made in its iteration":
	s1 = "v1"
	s3 = "c"
	s2 = ""
	loop 2:
		s3 = (s3 + s3)[0..2 * s3.len].copy()
		own = s3.copy()
		f = (x str): (x + own)[0..x.len + own.len].copy()
		s2 = f(s1)
	print(s2)
	prints "v1cccc"

test "a closure made in a loop does not take what the next iteration reads" refuses ClosureTakesLoopValue:
	s1 = "v1"
	mut s3 = "c"
	mut s2 = ""
	loop 2:
		s3 = s3 + s3
		fs = [(x str): x + s3]
		s2 = fs[0](s1)
	print(s2)

fn keepIf(move v str, keep bool):
	if keep:
		print(v)

test "a move parameter the function does not give away is destroyed at its end":
	keepIf("a{1}", false)
	keepIf("b", true)
	prints "b"

test "a swap in a branch of a loop gives both values back at once":
	a = "a"
	b = "b"
	for i in [1, 2, 3, 4]:
		if i % 2 == 0:
			a, b = b, a
	print(a + b)
	prints "ab"

table = [3, 4, 5, 6]

test "a list constant read by index is freed after the read":
	s = 0
	for i in 0..4:
		s += table[i]
	print(s)
	prints "18"

# b: what an arm of ?:, ?? or match makes lives while the choice's value borrows it

type Rec:
	name str
	items str[]

fn make(s str):
	Rec(name = "{s}!", items = [s.copy(), "{s}2"] if s.len > 1 else [])

fn opt(s str) str?:
	if s.len > 1: return "{s}?"
	none

test "?: over a window into a temporary" for (c, want) in [(true, "ab"), (false, "xy")]:
	expect (" ab ".repeat(1).trimmed() if c else " xy ".repeat(1).trimmed()) == want

test "an optional reference ?? a temporary":
	empty str[] = []
	print(empty.first ?? "q".repeat(2))
	prints "qq"

test "an optional reference ?? a field of a temporary":
	empty str[] = []
	print(empty.first ?? make("q").name)
	prints "q!"

test "an empty optional place ?? a temporary":
	s2 = "v2"
	o str? = none
	print(o ?? "<{s2}>")
	prints "<v2>"

test "match over a temporary optional, the arm a window into it" for (s, want) in [
	("ab", "ab?"),
	("a", "none")
]:
	shown = match opt(s):
		v: v.trimmed()
		none: "none"
	expect shown == want

test "a choice of a place and a window into a temporary, read in place, either way":
	s2 = "q"
	lens = []
	texts = []
	for c in [true, false]:
		lens.push((s2 if c else ("{s2}xy")[0..3]).len)
		texts.push("[{s2 if c else ("{s2}xy")[0..3]}]")
	print("{lens[0]} {lens[1]}")
	print("{texts[0]} {texts[1]}")
	prints """
		1 3
		[q] [qxy]
		"""

# D: break and continue drop the temporaries of the statements they leave

fn names():
	["a{1}"]

test "break out of a match over a temporary":
	loop 1:
		if names().first is v:
			print(v)
			break
	prints "a1"

test "continue out of a match over a temporary number":
	loop 1:
		if names().len == 1:
			print(1)
			continue
	prints "1"

test "break out of an is over a temporary":
	loop 1:
		if names().first is v:
			print(v)
			break
	prints "a1"

test "?? continue over a call with a temporary argument":
	s1 = "-"
	loop 1:
		s1 = opt("v".upper()) ?? continue
	print(s1)
	prints "-"

test "while is over a temporary":
	n = 0
	while names().first is v and n < 3:
		_ = v
		n += 1
	print(n)
	prints "3"

type Sh:
	Word(w str)
	Pair(a str, b str)
	Empty
fn shape(s str) Sh:
	.Pair(s.upper(), "{s}!") if s.len > 2 else .Word(s.upper()) if not s.isEmpty else .Empty

test "break out of a match binding part of a temporary":
	loop 1:
		if shape("abc") is Pair(p, _):
			print(p)
			break
	loop 1:
		match shape("xy"):
			Pair(_, q): print(q)
			Word(w):
				print(w)
				continue
			Empty: pass
	loop 1:
		match shape("xyz"):
			Empty: pass
			_:
				break
	prints """
		ABC
		XY
		"""

# F: what the checker inserts in a generic's body (a some, a dereference) follows each instance

fn slot<T>(move v T) T?[]:
	out T?[] = []
	out.push(v)
	out

fn assign<T>(move v T) T?:
	o T? = none
	o = v
	o

fn give<T>(c bool, move v T) T?:
	if c: return v
	none

fn firstOr<T>(xs T[], d T) T:
	(xs.first ?? d).copy()

test "a generic pushing T into T?[], for two types":
	print(slot(2))
	print(slot("x"))
	prints """
		[some(2)]
		[some("x")]
		"""

test "a generic assigning T to T?, for two types":
	print(assign(2) ?? 0)
	print(assign("x") ?? "n")
	prints """
		2
		x
		"""

test "a generic returning T? for an optional T and a str":
	o i64? = 2
	print(give(true, o) ?? none ?? 0)
	print(give(true, "ab") ?? "n")
	prints """
		2
		ab
		"""

test "a generic reading xs.first ?? d, for a number and a str":
	print(firstOr([1], 0))
	print(firstOr(["a"], "b"))
	prints """
		1
		a
		"""

fn keepOpt<T>(move v T) T?:
	o T? = none
	o = v
	o

test "an optional T assigned to T? wraps it again":
	x str? = "a"
	print("{keepOpt(x)} {keepOpt(2)}")
	prints "some(some(\"a\")) some(2)"

# a choice of places and literals is a borrow of the place it picks, not a move

test "a choice of a field and a literal is only read":
	r = make("r")
	s1 = (r.name if r.name.len > 1 else "f")[0..2].copy()
	print(s1)
	print(r.name)
	s0 = "ab"
	s2 = (s0 if s0.len > 1 else "lit").copy()
	print("{s0} {s2}")
	prints """
		r!
		r!
		ab ab
		"""

imageDir = "zkate3/disc"

fn findImageIn(dir str) str?:
	for name in ["b.txt", "a.iso"]:
		if name.endsWith(".iso"): return "{dir}/{name}"
	none

fn openImage(path str) i64 ? str:
	if path.len > 100: return "too long {path}"
	path.len

fn openGivenImage(given str?) i64 ? str:
	image = given ?? findImageIn(imageDir) ?? return "no disc image in {imageDir}"
	openImage(image)

test "a chain of ?? over a place binds a borrow of what it picks, the fallback kept while it is used":
	match openGivenImage(none):
		n: print(n)
		error: print(error)
	g str? = "x.iso"
	match openGivenImage(g):
		n: print(n)
		error: print(error)
	prints """
		17
		5
		"""

fn eatLen(move s str):
	s.len

test "a value given away in a range's bound is gone afterwards" refuses UseAfterGiven:
	fn eatLen(move s str) i64:
		s.len
	s = "abc".repeat(2)
	xs = (0..eatLen(s)).map(i: i * 2)
	print(xs.len)
	print(s)

test "a range's bounds are read like any value":
	s = "abc".repeat(2)
	d u8[] = [1, 3]
	at = 0
	xs = (0..eatLen(s)).map(it)
	ys = (0..d[at]).map(_: d[at + 1])
	print("{xs.len} {ys.len} {ys[0]}")
	prints "6 1 3"

type Holder:
	n i64
	items ref i64[]

type Tagged:
	k i64
	tag ref str

fn lists2():
	[[1, 2, 3], [4, 5]]

test "views a map makes keep its source and its captures alive":
	lists = lists2()
	hs = lists.map(Holder(n = .len, items = it))
	for h in hs:
		print("{h.n} {h.items}")
	more = lists2()
	direct = [Holder(n = 0, items = more[0])]
	print(direct[0].items)
	name = "abc".repeat(2)
	tags = [1, 2, 3].map(Tagged(k = it, tag = name))
	print(tags[2].tag)
	prints """
		3 [1, 2, 3]
		2 [4, 5]
		[1, 2, 3]
		abcabc
		"""

fn parts(s str):
	s.split(",")

fn ages(s str):
	s.split(",").map(Aged(name = .copy(), age = .len))

fn index(s str):
	m {str: str} = {}
	for w in s.split(","):
		m[w.copy()] = "v{w}"
	m

type Aged:
	name str
	age i64

test "an element found in a temporary list is used after the list":
	report = "a x\nzap b\nc"
	line = report.lines().find(.startsWith("zap")) ?? ""
	print(line)
	prints "zap b"

test "the lookups of a temporary list keep it alive with ?? and without":
	report = "a x,zap b,c"
	first = report.split(",").first ?? ""
	last = report.split(",").last ?? ""
	least = report.split(",").minBy(.len) ?? ""
	most = report.split(",").maxBy(.len) ?? ""
	found = report.split(",").find(.startsWith("zap"))
	print("{first}|{last}|{least}|{most}|{found}")
	prints "a x|c|c|zap b|some(\"zap b\")"

test "a temporary that borrows an argument is kept too":
	report = "a x,zap b,c"
	line = parts(report).first ?? ""
	name = ages(report).maxBy(.age)?.name ?? "none"
	value = index(report).get("c") ?? "none"
	print("{line}|{name}|{value}")
	prints "a x|zap b|vc"

test "a find after a filter of a temporary":
	line = "a x,zap b,c".split(",").filter(.len > 1).find(.startsWith("zap")) ?? ""
	print(line)
	prints "zap b"

test "an element found in a list borrows the list" refuses ChangeWhileBorrowed:
	mut xs = "a x,zap b,c".split(",")
	line = xs.find(.startsWith("zap")) ?? ""
	xs.clear()
	print(line)

# a slice x[a..b] stops unless 0 <= a <= b <= x.len, whatever x is and however the range is written

test "a string sliced from past its end stops the program" stops IndexOutOfBounds:
	t = "#".copy()
	part = t[2..len]
	print("[{part.trimmed()}]")

test "a list sliced from past its end stops the program" stops IndexOutOfBounds:
	xs = [1]
	print(xs[2..len])

test "a byte list sliced past its end stops the program" stops IndexOutOfBounds:
	b = "ab".bytes()
	print(b[1..3])

test "a slice whose start is after its end stops the program" stops IndexOutOfBounds:
	s = "hello"
	print(s[3..2])

test "a slice from a negative start stops the program" stops IndexOutOfBounds:
	xs = [1, 2, 3]
	at = 0 - xs.len
	print(xs[at..2])

test "an inclusive slice past the end stops the program" stops IndexOutOfBounds:
	xs = [1, 2, 3]
	print(xs[1..=3])

test "a slice to the end from past the end stops the program" stops IndexOutOfBounds:
	s = "ab"
	print(s[3..])

test "a slice from the start past the end stops the program" stops IndexOutOfBounds:
	xs = ["a", "b"]
	print(xs[..3])

test "a window sliced past its own end stops the program" stops IndexOutOfBounds:
	xs = [1, 2, 3, 4]
	w = xs[1..3]
	print(w[1..3])

test "the first k of a sort past the end stops the program" stops IndexOutOfBounds:
	words = ["pear", "fig"]
	print(words.sortedBy(.len)[0..3])

test "slices at the edges are empty or whole":
	t = "#"
	xs = [1, 2]
	w = xs[..2]
	print("[{t[1..]}] [{t[0..]}] {xs[2..]} {xs[..0]} {w[1..=1]} {"ab".bytes()[0..=1]}")
	prints "[] [#] [] [] [2] [97, 98]"

type Named:
	name str
	xs i64[]

fn shown(s str):
	"<{s}>"

fn lengthOf(xs i64[]):
	xs.len

fn fallbacks(s1 str, p Named):
	o str? = none
	o2 str? = none
	local = "loc".copy()
	m = {"a": 1}
	om {str: i64}? = none
	print("{shown(o ?? s1)} {o ?? p.name} {(om ?? m).len}")
	loop 2:
		print(shown(o ?? o2 ?? local))
	print("{s1} {p.name} {local} {m.len}")

# `o ?? s1` with o none gave s1's value away though the checker only lent it (found 2026-10-16,
# 150 programs from seed 11)
test "a fallback to a variable leaves the variable":
	s1 = "v1".copy()
	o str? = none
	print("[{o ?? s1}]")
	print(s1)
	prints """
		[v1]
		v1
		"""

test "a fallback to a place leaves it, as an argument, in an interpolation or copied":
	s1 = "v1".copy()
	o str? = none
	xs = [1, 2, 3]
	ox i64[]? = none
	p = Named(name = "n".copy(), xs = [4])
	op Named? = none
	w = Named(name = (o ?? s1).copy(), xs = (ox ?? xs).copy())
	l = [(o ?? s1).copy(), (o ?? p.name).copy()]
	print("{shown(o ?? s1)} {lengthOf(ox ?? xs)} {(op ?? p).name} {w.name} {l}")
	print("{s1} {xs} {p.name}")
	fallbacks("v".copy(), Named(name = "pn".copy(), xs = [1]))
	prints """
		<v1> 3 n v1 ["v1", "n"]
		v1 [1, 2, 3] n
		<v> pn 1
		<loc>
		<loc>
		v pn loc 1
		"""

type Cells:
	xs i64[3]
	n i64

fn cellsChanged(c Cells):
	d = c
	d.xs[0] = 40
	d.n = 2
	c.xs[0] + c.n + d.xs[0] + d.n

test "a struct holding a fixed array copies when bound, from a local or a parameter":
	h = Cells(xs = [1, 2, 3], n = 1)
	kept = h
	other = h
	other.xs[0] = 9
	h.n = 5
	print("{h} {kept} {other.xs[0]} {h.cellsChanged()}")
	prints "Cells(xs = [1, 2, 3], n = 5) Cells(xs = [1, 2, 3], n = 1) 9 48"

type BoxedNode:
	v i64
	name str

fn boxedIf(i i64) Box<BoxedNode>?:
	Box(BoxedNode(v = i, name = "n{i}")) if i > 0 else none

test "an if's box arm is the result's, not dropped when the if ends":
	print("{boxedIf(5)?.v} {boxedIf(0)?.v}")
	if boxedIf(2) is n:
		print(n.name)
	prints """
		some(5) none
		n2
		"""

test "a window into an element of a list made in the function is returned" refuses ReturnTemporaryRef:
	fn firstWord(s str) ref str:
		s.split(" ")[0].trimmed()
	print(firstWord("zap is short"))

test "a text replaced in place in a block with no room for its NUL writes no byte past it":
	bytes = []
	for i in 0..32:
		bytes.push('a' + u8(i % 26))
	texts = []
	for i in 0..8:
		texts.push("{i}".repeat(32))   # blocks of the same size, beside it
	s = str(move bytes)
	after = "z".repeat(32)
	s = s.replace("ab", "AB")
	print("{s.len} {s[..4]} {texts.all(.len == 32 and it[0] != 0)} {after[0] == 'z'}")
	prints "32 ABcd true true"

type Chain:
	End
	Link(next Box<Chain>)

	fn links() i64:
		match self:
			End: 0
			Link(next): 1 + next.links()

type HeldThing:
	id i64

	mut fn drop():
		print("released {id}")

test "a type that holds itself through a box, beside a type with a drop function, checks":
	c = Chain.Link(Box(Chain.Link(Box(Chain.End))))
	h = HeldThing(id = 1)
	print("{h.id} {c.links()}")
	prints "1 2"

# found by the ownership verifier of the intermediate form (compiler/ownership/irown.zap)
type Pending:
	file str
	line i64

type Errors:
	pending Pending[]
	cur str
	file str

fn note(mut e Errors, line i64):
	if e.pending.any(p:
		p.line == line and p.file == (e.file if e.cur == "" else e.cur)
	):
		return
	e.pending.push(Pending(file = (e.file if e.cur == "" else e.cur).copy(), line))

test "a lambda's test inside a condition drops what it makes at each element":
	e = Errors(pending = [], cur = "", file = "main.zap")
	for name in ["a", "b", "c", "a"]:
		e.cur = "{name}.zap"
		e.note(1)
	print(e.pending.map(.file))
	prints "[\"a.zap\", \"b.zap\", \"c.zap\"]"

# A system thread starts a while after CreateThread: a program that ended before its pool's
# workers (or its background threads) ran dropped the records they read their closures from, and
# about one run in four stopped with an access violation after its output. Each worker now counts
# itself in before its first step returns, and the program's end takes the pool's and the jobs'
# locks for good before it drops the module variables, so a worker woken late waits there.

if not args.isEmpty and args[0] == "workers":
	counter = Atomic(0)
	squares = (0..100).parallel().map(i:
		counter.add(1)
		i * i
	)
	firsts = 0
	for v in (0..10_000).parallel().map(i: [i, i * i]):
		firsts += v[1]
		if v[0] == 3: break
	job = background((): 5)
	while not job.isDone:
		sleepMs(1)
	print("{counter.load()} {squares[99]} {firsts} {job.tryReceive() ?? 0}")
	return

test "a program that ends right after its first parallel step and background job":
	failed = 0
	loop 60:
		if Process.output("\"{exePath()}\" workers").code != 0:
			failed += 1
	print(failed)
	prints "0"

type ZeroHandle:
	id i64

	mut fn drop():
		zeroReleased += 1

mut zeroReleased = 0

fn zeroHandles():
	hs = (0..3).map(ZeroHandle(id = it))
	hs.len

test "a value of a type with a drop function whose fields are all zero is dropped":
	print("{zeroHandles()} {zeroReleased}")
	prints "3 3"

# A map moved out of a place leaves zero bytes there, which are no map: a read before the place
# gets a value again is refused, a read after reads the value put back.
type MovedIndex:
	at {str: i64} = {}

type MovedHolder:
	idx MovedIndex = MovedIndex()

fn putBack(mut h MovedHolder):
	h.idx.at["x"] = 1
	saved = move h.idx
	n = saved.at.len
	h.idx = saved
	n + (h.idx.at.get("x") ?? -1)

test "a map field moved out is not read until it gets a value again" refuses UseAfterPartGiven:
	type Index:
		at {str: i64} = {}
	type Holder:
		idx Index = Index()
	fn probe(mut h Holder) i64:
		h.idx.at["x"] = 1
		saved = move h.idx
		r = h.idx.at.get("x") ?? -1
		h.idx = saved
		r + (h.idx.at.get("x") ?? -1)
	mut h = Holder()
	print(probe(h))

test "a map field moved out and put back reads as before":
	h = MovedHolder()
	print(h.putBack())
	prints "2"

type HeldNoisy:
	id i64

	mut fn drop():
		print("drop {id}")

type NoisyHolder:
	n HeldNoisy? = none

fn heldId(h NoisyHolder):
	if h.n is n: return n.id
	-1

fn readTwice():
	h = NoisyHolder(n = HeldNoisy(id = 7))
	print(h.heldId())
	print(h.heldId())

test "a value with a drop function read through `is` in its place is lent, dropped once":
	readTwice()
	prints """
		7
		7
		drop 7
		"""

# a hand probe: the walk's first jump was written in the block before the receiver's call
type LentInst:
	a i64
	b i64
	args i64[] = []

	fn reads() Seq<i64>:
		for v in args:
			yield v
		if a >= 0: yield a
		if b >= 0: yield b

type LentHolder:
	insts LentInst[]

fn at(h LentHolder, i i64) ref LentInst:
	h.insts[i]

test "a generator over a value lent by a ref result":
	h = LentHolder(insts = [LentInst(a = 3, b = 4), LentInst(a = 5, b = -1, args = [7])])
	n = 0
	for i in 0..2:
		for r in h.at(i).reads():
			n += r
	print(n)
	prints "19"

# A temporary made in a loop's body, given to a function that takes it apart twice (an inlined
# call matching its parameter, then a match of its own): the inlined match moved the field out of
# the caller's temporary, and the second read it empty (found by std/zapx's render).
type TwiceRead:
	A(tag str, n i64)
	B(text str)

fn firstIsZz(t TwiceRead):
	match t:
		A(tag, _): tag == "zz"
		B: false

fn twiceShown(t TwiceRead):
	if t.firstIsZz():
		print("z")
	match t:
		A(tag, _): tag.copy()
		B(s): s.copy()

test "a loop's temporary taken apart twice keeps its fields":
	for a in [1]:
		print(TwiceRead.A("nav", a).twiceShown())
	prints "nav"

# A call tried in place and given up (a moved list parameter after an f64 one) left the f64's
# type on vreg numbers the call made instead took again: the items of a list mapped into the
# moved argument read as a number, so the list died before the map read its elements (found by
# the site (projects/site), `bars.map(.barRow(...))` as the last use of bars).
type ChartBar:
	name str
	value f64
	detail str
	loss bool

fn chartBar(row (str[]), cols i64[], rivals str[]):
	ChartBar(name = row[0].copy(), value = 0.0, detail = row[cols[0]].copy(), loss = rivals.len > 9)

fn chartBars(table ChartTable, cols i64[]):
	table.rows[1..].map(chartBar(it, cols, []))

type ChartRow:
	loss bool
	name str
	detail str

type ChartBlock:
	intro str
	title str
	tie str
	tieShare str
	rows ChartRow[]

fn chartRow(b ChartBar, axisMax f64, kind str, words ChartWords):
	ChartRow(
		loss = b.loss,
		name = b.name.copy(),
		detail = b.detail.copy()
	)

fn chartOf(intro str, title str, tie str, axisMax f64, move rows ChartRow[]):
	ChartBlock(
		intro = "",
		title = "",
		tie = tie.copy(),
		tieShare = "",
		rows
	)

fn chartBlock(table ChartTable, cols i64[], intro str, title str, words ChartWords):
	bars = table.chartBars(cols)
	axisMax = 1.2
	chartOf(intro, title, words.tie, axisMax, bars.map(.chartRow(axisMax, "bar", words)))

fn chartBlocks(words ChartWords, source ChartSource):
	found = []
	for t in source.tables.filter(.name == "speed"):
		found.push(
			t.chartBlock([3], "", "", words)
		)
	found

type ChartTable:
	name str
	rows (str[])[]

type ChartSource:
	tables ChartTable[]

type ChartWords:
	chartGuide str
	timeChart str
	tie str

test "a list's last use mapped into a moved argument after an f64 one keeps its elements while mapped":
	words = ChartWords(chartGuide = "g", timeChart = "t", tie = "tie")
	source = ChartSource(
		tables = [
			ChartTable(
				name = "speed",
				rows = [
					["name", "ms", "MB", "time C"],
					["nbody", "1246", "3.4", "0.96x"],
					["worst", "", "", "0.98x"]
				]
			)
		]
	)
	for b in words.chartBlocks(source):
		for r in b.rows:
			print("{r.name} {r.detail}")
	prints """
		nbody 0.96x
		worst 0.98x
		"""

# `x ?? fail(...)`, `x ?? return` and a match whose other arms leave, on a place, lend the place's
# value: a result's was copied into a temporary the binding owned, so a value with a drop function
# was dropped where the block ended while its place still held it, and again with the place
type Archived:
	held HeldNoisy
	name str

fn archived(id i64) Archived ? str:
	if id < 0: return "no archive"
	Archived(held = HeldNoisy(id), name = "archive {id}")

fn readArchive(go bool):
	r = archived(1)
	if go:
		a = r ?? fail
		b = match r:
			x: x
			error:
				print(error)
				return
		print("{a.name} {b.held.id}")
	match r:
		x: print("still {x.name}")
		error: print(error)

fn printArchive(r Archived ? str, go bool):
	if go:
		a = r ?? return
		print(a.name)
	match r:
		x: print("still {x.name}")
		error: print(error)

fn readArchives():
	xs = [archived(2), archived(-1)]
	for r in xs:
		a = r ?? continue
		print(a.name)
	print((xs[0] ?? fail).name)

fn readOptional(o Archived?, go bool):
	if go:
		a = o ?? fail("none")
		print(a.name)
	if o is x: print("still {x.name}")

test "a `??` or a match of a place whose other arms leave lends its value, dropped once":
	readArchive(true)
	printArchive(archived(3), true)
	readArchives()
	readOptional(Archived(held = HeldNoisy(4), name = "archive 4"), true)
	prints """
		archive 1 1
		still archive 1
		drop 1
		archive 3
		still archive 3
		drop 3
		archive 2
		archive 2
		drop 2
		archive 4
		still archive 4
		drop 4
		"""

fn chooseArchive(move r Archived ? str):
	a = r ?? Archived(held = HeldNoisy(9), name = "archive 9")
	print(a.name)

test "a choice that would copy a value with a drop function out of its place takes it":
	chooseArchive(archived(5))
	prints """
		archive 5
		drop 5
		"""

test "a choice that would copy a value with a drop function its place still reads is refused" refuses UseOfPartGiven:
	r = archived(6)
	a = r ?? Archived(held = HeldNoisy(9), name = "archive 9")
	print(a.name)
	match r:
		x: print(x.name)
		error: print(error)

fn shownOptional(s str?):
	a = s ?? fail("none")
	print(a)
	if s is x: print("still {x}")

test "a `??` of an optional parameter reads it in place":
	shownOptional("a str long enough to own its bytes on the heap")
	prints """
		a str long enough to own its bytes on the heap
		still a str long enough to own its bytes on the heap
		"""
