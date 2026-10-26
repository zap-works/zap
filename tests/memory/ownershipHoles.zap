# Ownership holes once met in projects (board/1-language), each kept as a test: an optional
# compared with a value it may hold, a function or a closure as a value, a list grown under a
# call that extends one of its elements.

fn heldBytes(full bool) u8[]?:
	[u8(1), u8(2)] if full else none

test "an optional compared with a list it may hold reads the list, never takes it":
	xs = [u8(1), u8(2)]
	print("{heldBytes(true) == xs} {heldBytes(false) == xs} {heldBytes(true) != xs} {xs == heldBytes(true)}")
	print(xs)
	prints """
		true false false true
		[1, 2]
		"""

test "an expect of an optional against a list literal":
	expect heldBytes(true) == [u8(1), u8(2)]

fn countOf(move xs i64[]) i64:
	xs.len

type Bag:
	Full(xs i64[])
	Spent

test "a match arm's binding given away is not read after" refuses UseOfPartGiven:
	b = Bag.Full([1, 2, 3])
	match b:
		Full(xs):
			print(countOf(xs))
			print(xs.len)
		Spent:
			pass

type Parcel:
	id i64
	label str

fn opened(move p Parcel) i64:
	p.id + p.label.len

fn callOn(f fn(Parcel) i64, p Parcel) i64:
	f(p)

test "a function taking its parameter by move is no function value" refuses MoveParameterAsValue:
	p = Parcel(id = 7, label = "seven")
	print(callOn(opened, p))

type Asked:
	types i64[]

fn grownAsks(mut asks Asked[], n i64) i64[]?:
	asks.push(Asked(types = []))
	[n, n + 1]

fn extendFirst(mut asks Asked[]) bool?:
	asks[0].types.extend(try grownAsks(asks, 5))
	true

test "an element's list extended by a call that grows the list holding it":
	asks = [Asked(types = [0])]
	_ = extendFirst(asks)
	print("{asks[0].types} {asks.len}")
	prints "[0, 5, 6] 2"

type Rom:
	bytes u8[]
	name str

fn readRom(r Rom, at i64, n i64) u8[]:
	r.bytes[at..at + n].copy()

fn romSize(r Rom) i64:
	r.bytes.len

fn usedReader(read fn(i64, i64) u8[]) i64:
	read(0, 2).len

test "a lambda written at the call borrows what it captures, read after":
	r = Rom(bytes = [1, 2, 3, 4], name = "rom")
	print(usedReader((at i64, n i64): readRom(r, at, n)) + romSize(r))
	prints "6"

test "a closure bound to a name takes what it captures" refuses UseAfterCapture:
	r = Rom(bytes = [1, 2, 3, 4], name = "rom")
	read = (at i64, n i64): readRom(r, at, n)
	print(usedReader(read) + romSize(r))
