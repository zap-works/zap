# What the compiler decides on its own without costing memory: a part of a local, an element of
# a list nothing reads again, a value given back in the same statement, a shared value counted,
# a background job's captures. Every case runs with freed memory poisoned and every block freed.

type Player:
	name str
	tags str[]
	hp i64

fn nameOf(move p Player):
	p.name   # p is owned and not read again: the name moves out

fn pick(k i64):
	names = ["ana", "bo", "cy"]
	names[k]   # the list ends here: the element moves out

fn grow(move xs str[]):
	ys = xs   # the parameter's value moves to the binding
	ys.push("more")
	ys

fn first(move xs str[]):
	xs[0]   # a move parameter is the function's own: its element moves out

fn step(move s str, e str):
	s + e

fn words(n i64):
	(0..n).map("w{it}")

type Bag:
	items str[]
	count i64

# changes only the count: a string of the bag's items may be read while it runs
fn countOne(mut b Bag, s str):
	b.count += 1
	print(s)

# the length of the text an optional holds: `n?` borrows it (the caller keeps the optional)
fn sizeOf(n str?) i64?:
	s = try n
	s.len

# a connection made for the call: a temporary the match binds
fn connect(i i64) str?:
	if i > 0: return "c{i}"
	none

fn send(s str, ch Channel<str>) bool:
	ch.send("{s}!")

test "a part of a local moves out at its last use":
	print(nameOf(Player(name = "ana", tags = [], hp = 1)))
	print(pick(1))
	p = Player(name = "z", tags = ["x", "y"], hp = 3)
	out = []
	out.push(p.tags)
	print(out[0])
	print(p.hp)   # another part is still there
	prints """
		ana
		bo
		["x", "y"]
		3
		"""

test "the elements of a temporary list or of a list not read again move out":
	out = []
	for w in words(3):
		out.push(w)
	parts = ["a", "b"]
	for part in parts:
		out.push(part)
	print(out)
	prints """
		["w0", "w1", "w2", "a", "b"]
		"""

type Batch:
	records Player[]

fn maybePlayer(i i64) Player?:
	if i < 0: return none
	Player(name = "the player who is numbered {i}", tags = ["the tag that is numbered {i}"], hp = i)   # long: a copy allocates

fn players(n i64) Player[]?:
	out = []
	for i in 0..n:
		p = try maybePlayer(i)   # the optional is a temporary: its value moves out
		out.push(p)
	out

fn batch(n i64) Batch?:
	Batch(records = try players(n))

test "a value unwrapped from a temporary, and a part of a temporary, move out uncopied":
	before = allocations()
	ps = (batch(4) ?? Batch(records = [])).records   # the field moves out of the temporary
	print("{ps.len} {ps[3].name.len} {allocations() - before}")
	prints "4 28 14"

test "extend moves a list of strings":
	xs = ["a"]
	xs.extend(["b", "c"])
	print(xs)
	prints """
		["a", "b", "c"]
		"""

test "a value given back in the same statement moves in a loop":
	s = "s"
	marks = ["!", "!", "!"]
	for m in marks:
		s = step(s, m)
	print(s)
	prints "s!!!"

test "move parameters are the function's own":
	print(grow(["a"]))
	print(first(["a", "b"]))
	prints """
		["a", "more"]
		a
		"""

test "a window of a window points into the first one's text":
	line = "  add milk  "
	title = line.trimmed()[..3]
	print(title)
	print(line.trimmed()[4..8])
	prints """
		add
		milk
		"""

test "a job takes what it captures, a shared channel is counted":
	done = Channel<str>()
	for i in 1..3:
		match connect(i):
			c:
				job = background((): send(c, done))
				while not job.isDone:
					sleepMs(1)
				print(job.tryReceive() ?? false)
			none: print("none")
	print(done.receive() ?? "?")
	print(done.receive() ?? "?")
	prints """
		true
		true
		c1!
		c2!
		"""

test "a list read after its elements were given away" refuses UseOfPartGiven:
	more = ["c"]
	mut out str[] = []
	for m in more:
		out.push(m)
	print(more)

test "a place lent to a call that changes another part is fine":
	b = Bag(items = ["a"], count = 0)
	b.countOne(b.items[0])
	prints "a"

test "unwrapping a borrowed optional borrows its value":
	print(sizeOf("abc") ?? -1)
	print(sizeOf(none) ?? -1)
	prints """
		3
		-1
		"""

type Entry:
	quick str
	full str

fn shown(label str, arg str):
	"{label}: {arg}"

test "an if that picks one of two borrowed places lends it":
	e = Entry(quick = "q", full = "f")
	print(shown("arg", e.quick if true else e.full))
	pick = e.quick if true else e.full
	print(pick.len)
	print(shown("arg", e.quick if false else e.full))
	prints """
		arg: q
		1
		arg: f
		"""

test "a str key of sortBy, minBy and maxBy is the element's, lent":
	words = ["pear", "apple", "fig", "banana"]
	print(words.sortedBy(it))
	print(words.minBy(it) ?? "")
	print(words.maxBy(it) ?? "")
	prints """
		["apple", "banana", "fig", "pear"]
		apple
		pear
		"""

type MapFacts:
	across bool[]
	saveAt {i64: i64[]} = {}

fn mapFacts(n i64):
	m {i64: i64[]} = {}
	m[n] = [n, n + 1]
	MapFacts(across = [true], saveAt = m)

fn savesIf(n i64, c bool) {i64: i64[]}:
	mapFacts(n).saveAt if c else {}

fn savesOf(n i64):
	mapFacts(n).saveAt

fn savesThrough(n i64):
	saves {i64: i64[]} = {}
	if n > 0:
		facts = mapFacts(n)
		saves = facts.saveAt
	saves

test "a map field of a call's result in a conditional moves out of the temporary":
	print(savesIf(3, true)[3])
	print(savesIf(3, false).len)
	print(savesOf(4)[4])
	prints """
		[3, 4]
		0
		[4, 5]
		"""

test "a map field of a local struct moves out at its last use":
	print(savesThrough(2)[2])
	print(savesThrough(0).len)
	prints """
		[2, 3]
		0
		"""
