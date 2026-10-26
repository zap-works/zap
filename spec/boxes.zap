# 4.7 Boxes
#
# `Box(v)` moves a value into a heap block of its own; the box is one pointer word that owns it and
# behaves as the value: fields and methods go through it, a read parameter of type `T` accepts a
# `Box<T>`, printing and JSON show the value, `copy()` copies it deeply.

type Point:
	x i64
	y i64

	fn sum():
		x + y

fn norm(p Point):
	p.x * p.x + p.y * p.y

test "a box behaves as the value":
	b = Box(Point(x = 3, y = 4))
	print("{b.x} {b.sum()} {norm(b)}")
	print(b)
	c = b.copy()
	print(c.y)
	boxes = []
	for i in 0..3:
		boxes.push(Box(Point(x = i, y = 0)))
	print(boxes)
	prints """
		3 7 25
		Point(x = 3, y = 4)
		4
		[Point(x = 0, y = 0), Point(x = 1, y = 0), Point(x = 2, y = 0)]
		"""

# A type may contain itself through a box: `type Tree { left Box<Tree>?  right Box<Tree>? }`; by
# value it would be infinitely large.

type Tree:
	value i64
	left Box<Tree>?
	right Box<Tree>?

fn leaf(v i64):
	Tree(value = v, left = none, right = none)

fn total(t Tree) i64:
	s = t.value
	if t.left is l:
		s += total(l)
	if t.right is r:
		s += total(r)
	s

fn depth(t Tree) i64:
	d = 0
	if t.left is l:
		d = depth(l)
	d + 1

test "a tree through boxes walks, copies and encodes like any value":
	t = Tree(
		value = 1,
		left = Box(Tree(value = 2, left = Box(leaf(4)), right = none)),
		right = Box(leaf(3))
	)
	print("{t.total()} {t.depth()} {t.total()}")
	json = t.toJson()
	print(json)
	print(Tree.fromJson(json)?.total() ?? -1)
	again = Tree.fromBytes(t.toBytes()) ?? leaf(0)
	print(again.depth())
	long = leaf(0)
	for i in 1..200:
		long = Tree(value = i, left = Box(long), right = none)
	print(long.depth())
	prints r"""
		10 3 10
		{"value":1,"left":{"value":2,"left":{"value":4,"left":null,"right":null},"right":null},"right":{"value":3,"left":null,"right":null}}
		10
		3
		200
		"""

# An optional box has no tag (0 is `none`), so that node is three words; `?.` and `??` read through
# it.

fn sumOf(n Box<Tree>?) i64:
	match n:
		node: node.value + sumOf(node.left) + sumOf(node.right)
		none: 0

# the subtree whose root holds v: the node is matched, so it is borrowed, and copied out
fn find(n Box<Tree>?, v i64) Box<Tree>?:
	match n:
		node:
			if node.value == v: return n.copy()
			find(node.left, v) ?? find(node.right, v)
		none: none

test "an optional box":
	t Box<Tree>? = Box(Tree(value = 1, left = Box(leaf(4)), right = none))
	print("{sumOf(t)} {t?.value ?? -1}")
	print("{find(t, 4)?.value ?? -1} {find(t, 9)?.value ?? -1}")
	empty Box<Tree>? = none
	print("{sumOf(empty)} {empty == none}")
	xs Box<Tree>?[] = [Box(leaf(5)), none, Box(leaf(6))]
	print(xs.sum(sumOf(it)))
	prints """
		5 1
		4 -1
		0 true
		11
		"""

# A box matched in its place is borrowed there, and a reference to it where one to its value is
# asked for is one to the value: a part kept apart in an optional box (one word) is reached and
# changed through methods, and a reference to a box reaches the value's fields.

type Extra:
	names str[] = []

type Item:
	kind i64
	extra Box<Extra>? = none

	mut fn extraPart() mut ref Extra:
		if self.extra is mut e: return mut ref e
		self.extra = Box(Extra())
		self.extraPart()

	fn names() ref str[]:
		if self.extra is e: return e.names
		noNames

noNames str[] = []

test "a box in an optional changed through a method":
	items = [Item(kind = 1), Item(kind = 2, extra = Box(Extra(names = ["x"])))]
	items[0].extraPart().names.push("a")
	items[1].extraPart().names.push("y")
	expect items[0].names() == ["a"]
	expect items[1].names() == ["x", "y"]
	boxes = [Box(Extra()), Box(Extra(names = ["q"]))]
	b = mut ref boxes[1]
	b.names.push("z")
	expect boxes[1].names == ["q", "z"]

test "a read parameter's box is not given back without its copy" refuses MoveOfBorrowed:
	type Node:
		value i64
		next Box<Node>?

	fn same(n Box<Node>?) Box<Node>?:
		n

	print(same(Box(Node(value = 1, next = none)))?.value ?? -1)

# Storing over a box (in a field, an element or a variable) drops the one it held; `move` empties
# the box's place.

type Held:
	b Box<i64>

type Slot:
	b Box<i64>?

test "move empties a box's place":
	s = Slot(b = Box(1))
	x = move s.b
	print("{x} {s.b}")
	prints "some(1) none"

test "a box stored over":
	s = Held(b = Box(1))
	s.b = Box(2)
	xs = [Box(3)]
	xs[0] = Box(4)
	expect s.b + xs[0] == 6
