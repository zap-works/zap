# 4.3 References
#
# A reference is a borrow with a name: a value of type `ref T` (shared) or `mut ref T` (exclusive)
# that can sit in a variable, a parameter, a result, an optional, a struct field or a list or map.
# It never outlives what it points to, and the compiler proves it (4.4).
#
# `ref` is written in types only. A place is lent wherever the type asks for a read reference (a
# `ref T` result or parameter, a binding `r ref T = ...`, a reference field, an element of a
# `(ref T)[]`), so the place itself is written. A variable that already is a reference is passed
# on as it is. A binding without a type lends a place that owns memory and copies plain data; one
# typed `ref T` is never turned into a copy. `mut ref place` lends a place to be changed, the one
# form written before a value; its binding is never bound again, and a value assigned to it goes
# to the place (`r = mut ref xs[0]`, then `r = 5`).

type Monster:
	name str
	hp i64

type World:
	monsters Monster[]
	log str[]

	fn find(name str) ref Monster?:
		for i in 0..self.monsters.len:
			if self.monsters[i].name == name: return self.monsters[i]
		none

fn strongest(w World) ref Monster:
	best = 0
	for i in 1..w.monsters.len:
		if w.monsters[i].hp > w.monsters[best].hp:
			best = i
	w.monsters[best]

fn damage(mut m Monster, amount i64):
	m.hp -= amount

fn total(xs ref i64[]):
	t = 0
	for x in xs:
		t += x
	t

test "references borrow a place by name, pass it and return it without copies":
	w = World(
		monsters = [Monster(name = "slime", hp = 10), Monster(name = "orc", hp = 40)],
		log = []
	)
	s = w.strongest()
	print("{s.name} {s.hp}")
	m = mut ref w.monsters[0]
	damage(m, 3)
	damage(mut ref w.monsters[1], 15)
	print("{w.monsters[0].hp} {w.strongest().hp}")
	match w.find("orc"):
		o: print("found {o.name} with {o.hp}")
		none: print("no orc")
	xs = [1, 2, 3]
	r ref i64[] = xs
	print("{total(r)} {total(xs)} {r[2] + xs[1]}")
	prints """
		orc 40
		7 25
		found orc with 25
		6 6 5
		"""

test "a value assigned to a mut ref binding goes to its place":
	xs = [1, 2, 3]
	r = mut ref xs[1]
	r = 20
	r += 1
	expect xs == [1, 21, 3]

test "a reference never outlives its owner" refuses ReturnLocalRef:
	fn bad(xs i64[]) ref i64:
		x = 5
		x

	print(bad([1]))

test "a referenced place cannot change while the reference is used" refuses ChangeWhileBorrowed:
	mut xs = [1, 2]
	r ref i64 = xs[0]
	xs.push(3)
	print(r)

# A method's `ref` result borrows the field of its receiver that every result comes from
# (`self.parts[0].kids` borrows parts), so the receiver's other fields may change while it is
# used; a place it reaches is lent as one (`nodes[c].tags()[0]` as a `ref str`).

noKids i64[] = []

type Part:
	kids i64[] = []
	tags str[] = []

type Tree:
	hits i64 = 0
	parts Part[] = []

	fn kids() ref i64[]:
		if self.parts.isEmpty: return noKids
		self.parts[0].kids

	fn tags() ref str[]:
		self.parts[0].tags

fn visit(mut trees Tree[], at i64):
	for k in trees[at].kids():
		trees[k].hits += 1

fn firstTag(trees Tree[], at i64) ref str:
	trees[at].tags()[0]

test "a method's reference borrows the field its results come from":
	trees = [Tree(parts = [Part(kids = [1, 2, 1], tags = ["root"])]), Tree(), Tree()]
	visit(trees, 0)
	expect trees.map(.hits) == [0, 2, 1]
	expect firstTag(trees, 0) == "root"

test "that field cannot change while the result is used" refuses ChangeWhileRead:
	trees = [Tree(parts = [Part(kids = [1])]), Tree()]
	for k in trees[0].kids():
		trees[k].parts = []

# `move` takes a value out of a place, evaluated once; a place a method's result reaches has a
# call in its path, so it is written through the field the call reads (`move trees[0].parts[0].tags[0]`).
test "a place reached through a call is no place to move from" refuses MoveNeedsPlace:
	mut trees = [Tree(parts = [Part(tags = ["a"])])]
	name = move trees[0].tags()[0]
	print(name)

test "a read reference does not change its value" refuses MutateThroughReadRef:
	mut xs = [1, 2]
	r ref i64[] = xs
	r.push(3)
	print(xs.len)

test "a reference to a reference" refuses RefToRef:
	fn f(x ref ref i64) i64:
		x
	print(f(1))

# A borrow lives until its last use, so a borrow not used again blocks nothing; the error names
# where the borrow is still used.

fn attack(mut world World, i i64, dmg i64):
	m = mut ref world.monsters[i]
	m.hp -= dmg
	dead = m.hp <= 0
	if dead:
		world.monsters.remove(i)

test "a borrow ends at its last use":
	world = World([Monster("a", 5), Monster("b", 9)], [])
	world.attack(0, 7)
	world.attack(0, 2)
	expect world.monsters.map(.hp) == [7]

test "a borrow still used blocks the change" refuses ChangeWhileBorrowed("still used at line 9"):
	type Monster:
		hp i64
	type World:
		monsters Monster[]
	fn broken(mut world World, i i64):
		m = mut ref world.monsters[i]
		_ = world.monsters.remove(i)
		m.hp = 0
	mut w = World([Monster(1)])
	broken(w, 0)

# Borrows are of parts: a borrow of `d.programs[i]` lets `d.frames` change, also across calls. The
# compiler knows what each function changes of its `mut` parameters (through the calls it makes), so
# a borrow of one field survives a call that changes others, and the error names what the call
# changes when it overlaps.

type Program:
	params u8[]
	name str

type Frame:
	used i64

type Device:
	programs Program[]
	frames Frame[]
	count i64

fn reserve(mut d Device, n i64):
	d.frames[0].used += n
	d.count += 1
	d.frames[0].used

fn deeper(mut d Device, n i64):
	d.reserve(n) + d.reserve(1)

test "a part borrowed across a call that changes other parts":
	d = Device(
		programs = [Program(params = [1, 2], name = "a")],
		frames = [Frame(used = 0)],
		count = 0
	)
	rec ref Program = d.programs[0]
	x = d.reserve(rec.params.len)
	y = d.deeper(0)
	expect x == 2
	expect y - x == 3
	expect rec.name == "a"

test "a call that changes the borrowed part" refuses ChangeWhileBorrowed:
	type Program:
		params u8[]
	type Device:
		programs Program[]
		count i64
	fn add(mut d Device):
		d.programs.push(Program(params = []))
	fn through(mut d Device):
		d.count += 1
		add(d)
	mut d = Device(programs = [Program(params = [1])], count = 0)
	rec ref Program = d.programs[0]
	through(d)
	print(rec.params.len)

# A name borrows the parts its uses read: after `x = f.fighters[k]`, `x.name` reads
# `f.fighters[].name` alone, so a change of another field of the element (`f.fighters[k].combo`,
# or a call that changes one) between the binding and that read needs no copy. A call given x
# reads what its body reads of that parameter, through the calls it makes in turn; so does a call
# that also changes x's owner (`f.chase(k, target)`). Any other use of x reads all of it (a copy,
# a print, a comparison, a function value given it). A read through x never sees a change.

type Fighter:
	name str
	combo i64
	struck {str: f32}

type Fight:
	fighters Fighter[]
	lines str[]

fn note(mut f Fight, line str):
	f.lines.push("> {line}")

fn strike(mut f Fight, k i64):
	f.fighters[k].struck["stamina"] = 1.0

fn swing(mut f Fight, k i64):
	x = f.fighters[k]
	f.fighters[k].combo += 1
	f.strike(k)
	f.note("{x.name} swings")

fn weightOf(x Fighter):
	n = 0
	for _ in x.name:
		n += 1
	n

fn chase(mut f Fight, k i64, target Fighter):
	f.fighters[k].combo += target.weightOf()

fn swingAgain(mut f Fight, k i64):
	x = f.fighters[k]
	f.fighters[k].combo += 1
	f.chase(k, x)
	f.note("{x.name} swings again at {x.weightOf()}")

test "a call reads the parts its body reads":
	f = Fight(fighters = [Fighter(name = "orc", combo = 0, struck = {})], lines = [])
	f.swingAgain(0)
	print("{f.lines} {f.fighters[0].combo}")
	prints """
		["> orc swings again at 3"] 4
		"""

test "a borrow of an element's fields lets its other fields change":
	f = Fight(fighters = [Fighter(name = "orc", combo = 0, struck = {})], lines = [])
	f.swing(0)
	f.swing(0)
	print("{f.lines} {f.fighters[0].combo}")
	prints """
		["> orc swings", "> orc swings"] 2
		"""

test "a field read after it changed" refuses ChangeWhileBorrowed("still used at line 10"):
	type Fighter:
		name str
		combo i64
	type Fight:
		fighters Fighter[]
	fn swing(mut f Fight, k i64):
		x = f.fighters[k]
		f.fighters[k].combo += 1
		print("{x.name} {x.combo}")
	mut f = Fight(fighters = [Fighter(name = "orc", combo = 0)])
	f.swing(0)

test "a borrow used whole after a field changed" refuses ChangeWhileBorrowed:
	type Fighter:
		name str
		combo i64
	type Fight:
		fighters Fighter[]
	fn swing(mut f Fight, k i64):
		x = f.fighters[k]
		f.fighters[k].combo += 1
		kept = x.copy()
		print(kept.name)
	mut f = Fight(fighters = [Fighter(name = "orc", combo = 0)])
	f.swing(0)

# References dereference automatically: on field access, indexing, method calls, operators,
# interpolation and wherever the value is expected. `r.copy()` gives an owned value; moving out of
# a reference is an error. There is no pointer arithmetic and no null: absence is `ref T?`, one
# word as a reference is (the address, 0 for none: tests/memory/optionRef.zap).

fn upper(s str):
	s.upper()

test "a reference reads as its value":
	n i32 = 4
	r ref i32 = n
	words = ["ab", "cd"]
	w ref str = words[1]
	owned = w
	print("{r + 1} {upper(w)} {w.len} {w[0]} {owned}")
	prints "5 CD 2 99 cd"

# Lookups lend: `map.get(k)`, `xs.first`, `xs.last`, `xs.max()`, `xs.min()`, `xs.find(p)`,
# `xs.minBy(key)`, `xs.maxBy(key)` give `ref T?`. `??` on an optional reference to plain data
# gives the value; otherwise the result stays a reference, so its right side is referenced too and
# a temporary there lives to the end of the statement.

test "a lookup lends the element it finds instead of copying it":
	scores {str: i32} = {"a": 3}
	k = scores.get("a") ?? 0
	xs = [4, 9, 2]
	names = ["bo", "ana"]
	first = names.first ?? "{"no".repeat(2)}"
	expect k == 3
	expect (xs.max() ?? 0) == 9
	expect (xs.min() ?? 0) == 2
	expect (names.minBy(.len) ?? "-") == "bo"
	expect first == "bo"

test "a lookup keeps its list borrowed" refuses ChangeWhileBorrowed:
	mut names = ["bo", "ana"]
	f = names.find(.len > 2)
	names.clear()
	print(f ?? "-")

# A reference bound to a variable that points into a temporary keeps that temporary alive until the
# binding's last use: the temporary becomes a variable of its own, nothing is copied.

type Parsed:
	name str
	tags str[]

fn parse(text str):
	Parsed(name = text.upper(), tags = text.split(","))

test "a window, a field and an element of temporaries, kept while used":
	line = "  a\tb  ".repeat(2)
	w = line.replace("\t", "-").trimmed()
	n = parse("x,yy").name
	first = parse("p,q").tags.first ?? "none"
	last = parse("p,q").tags.last ?? "none"
	t = "{line}!".trimmedStart()
	h = "a\n# b".lines().find(.startsWith("#")) ?? ""
	print("[{w}] {n} {first} {last} {t.len} {h}")
	prints "[a-b    a-b] X,YY p q 13 # b"

test "a window of a temporary keeps it alive as a variable of its own":
	before = liveBlocks()
	w = "abc".repeat(10)[1..5]
	kept = liveBlocks() == before + 1
	expect w.len == 4 and kept
	expect liveBlocks() == before

# Slices: a read reference to a `str` or a `T[]` is a window (a pointer and a length) into the
# original, no copy: a part is an index by a range. A slice `x[a..b]` unless `0 <= a <= b <= x.len`
# stops the program, as an index out of bounds; a prefix of at most `n` is `x[0..len.min(n)]`. With
# a step it is a new list of the elements picked. A window is accepted wherever a `str` or a list
# is read; storing it where an owned value is needed is a written `.copy()`.

type Line:
	text str

fn sumOf(xs i64[]):
	xs.sum()

test "a slice is a window over the elements of its range":
	xs = [1, 2, 3, 4, 5]
	s = "hello"
	print("{s[1..3]} {xs[..2]} {xs[3..]} {xs[1..=2]} {xs[..len.min(9)]}")
	print("{xs[.. step 2]} {xs[1.. step 2]}")
	kept = Line(text = s[..2].copy())
	print("{kept.text} {sumOf(xs[1..3])}")
	prints """
		el [1, 2] [4, 5] [2, 3] [1, 2, 3, 4, 5]
		[1, 3, 5] [2, 4]
		he 5
		"""

test "a window is not stored as an owned value" refuses MoveOfPart:
	type Line:
		text str
	s = "hello"
	print(Line(text = s[0..2]).text)

test "a slice past the end stops the program" stops IndexOutOfBounds:
	xs = [1, 2]
	print(xs[1..args.len + 3])

# Views: a struct with a reference among its fields borrows what its references borrow (inferred
# when it is built) and is checked like a reference: it cannot outlive its origin, and its origin
# cannot change while it is used. Its other fields may own what it makes of what it reads (a
# reader's tables beside the bytes it borrows): such a view moves and drops them as any struct
# does, and `.copy()` copies them and lends its references again. A view a call may fail to give
# (`Packfile ? str`, `Packet?`) borrows the same.

type Packet:
	bytes ref u8[]
	kind u8

type Target:
	m mut ref Monster
	dmg i64

fn parsePacket(buf u8[]):
	Packet(bytes = buf[1..], kind = buf[0])

fn apply(t Target):
	t.m.hp -= t.dmg

test "a view holds references to what it reads and changes":
	buf u8[] = [7, 1, 2, 3]
	pk = parsePacket(buf)
	print("{pk.kind} {pk.bytes.len} {pk.bytes[2]}")
	orc = Monster(name = "orc", hp = 30)
	t = Target(m = mut ref orc, dmg = 12)
	t.apply()
	view = Packet(bytes = buf, kind = 9)
	print("{orc.hp} {view.bytes.len}")
	prints """
		7 3 3
		18 4
		"""

test "a view's origin cannot change while it is used" refuses ChangeWhileBorrowed:
	type Packet:
		bytes ref u8[]
	mut buf u8[] = [1, 2]
	p = Packet(bytes = buf)
	buf.clear()
	print(p.bytes.len)

type Pointed:
	at i64
	name str

type Packfile:
	d ref u8[]
	pointers {i64: i64}
	objects Pointed[]

fn openPackfile(d u8[]) Packfile ? str:
	if d.len < 2: return "cut short"
	p = Packfile(d, pointers = {}, objects = [])
	p.pointers[0] = d[1]
	p.objects.push(Pointed(at = d[1], name = "root"))
	p

fn pointedAt(p Packfile, at i64):
	p.d[p.pointers.get(at) ?? 0]

fn rootName(bytes u8[]):
	p = openPackfile(bytes) ?? return "none"
	twin = p.copy()
	twin.objects[0].name = "copy"
	"{p.pointedAt(0)} {p.objects[0].name} {twin.objects[0].name} {twin.d.len}"

test "a view owns what it makes of what it borrows":
	before = liveBlocks()
	print(rootName([5, 1, 9]))
	expect liveBlocks() == before
	prints "1 root copy 3"

test "a view that owns is checked like a reference" refuses ChangeWhileBorrowed:
	type Index:
		bytes ref u8[]
		offsets i64[]
	fn indexOf(bytes u8[]) Index ? str:
		if bytes.isEmpty: return "empty"
		Index(bytes, offsets = [0])
	mut buf u8[] = [1, 2]
	t = indexOf(buf) ?? return
	buf.clear()
	print(t.offsets.len)

# Lists and maps of references: a list element or map value may be a read reference, and a map key
# a `ref str`. The variable owns the list and borrows what goes in (`push`, `insert`, `m[k] = r`,
# `xs[i] = r`): those places cannot change while the list is used, an element read from it borrows
# the same places, and a list returned from a function points into its parameters only. Such a
# list lives in a variable: a struct field, a `mut` parameter or a kept closure cannot hold one.

type Node:
	text str
	n i64

fn namesOf(nodes Node[]):
	out (ref str)[] = []
	for node in nodes:
		out.push(node.text)   # lent, not copied
	out

fn longest(xs (ref str)[]) ref str:
	best = 0
	for i in 0..xs.len:
		if xs[i].len > xs[best].len:
			best = i
	xs[best]

test "a list of references borrows what its references point to":
	nodes = [Node(text = "fig", n = 1), Node(text = "apple", n = 2), Node(text = "kiwi", n = 3)]
	names = namesOf(nodes)
	print("{names} {("kiwi" in names)} {names.indexOf("apple")} {names.sorted()} {names.join("+")}")
	print(longest(names))
	byName {ref str: ref Node} = {}
	for node in nodes:
		byName[node.text] = node
	print("{byName["kiwi"].n} {"pear" in byName}")
	nodes.push(Node(text = "pear", n = 4))
	print(nodes.len)
	prints """
		["fig", "apple", "kiwi"] true some(1) ["apple", "fig", "kiwi"] fig+apple+kiwi
		apple
		3 false
		4
		"""

test "the places a list points into stay as they are while it is used" refuses ChangeWhileBorrowed:
	mut words = ["a", "b"]
	mut refs (ref str)[] = []
	refs.push(words[0])
	words.clear()
	print(refs)

test "a list made from a parameter keeps it borrowed in the caller" refuses ChangeWhileBorrowed:
	type Node:
		text str

	fn namesOf(nodes Node[]) (ref str)[]:
		out (ref str)[] = []
		for node in nodes:
			out.push(node.text)
		out

	mut nodes = [Node(text = "a")]
	names = namesOf(nodes)
	nodes.clear()
	print(names)

test "an element taken from the list borrows what it points to" refuses ChangeWhileBorrowed:
	mut words = ["a", "b"]
	mut refs (ref str)[] = []
	refs.push(words[0])
	first = refs[0]
	refs.clear()
	words.clear()
	print(first)

test "a list the caller owns takes no references" refuses CallerKeepsLocal:
	fn fill(mut out (ref str)[]):
		local = ["x"]
		out.push(local[0])

	mut refs (ref str)[] = []
	fill(refs)
	print(refs)

test "a list keeps no reference into a local of a block it outlives" refuses RefOutlivesLocal:
	mut out (ref i64)[] = []
	for i in 0..3:
		x i64 = i * 10
		out.push(x)
	print(out)

test "a kept closure cannot take a list of references" refuses ClosureKeepsReferences:
	fn keep(words str[]) fn() i64:
		refs (ref str)[] = []
		refs.push(words[0])
		(): refs.len

	f = keep(["a"])
	print(f())

test "a field cannot be a list of references" refuses FieldOfReferences:
	type Index:
		names (ref str)[]

	print(1)

test "a list element cannot be a mut reference" refuses MutRefNotAllowed:
	xs (mut ref str)[] = []
	print(xs.len)
