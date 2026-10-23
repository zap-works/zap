# 3.2 Structs
#
# `type` declares both structs (a type with fields) and enums (a type with variants). A struct is
# made by calling its type's name: positional values fill the fields in declaration order, named
# ones fill their field, named after positional.

type Point:
	x i64
	y i64 = 7

type Pair<A, B>:
	left A
	right B

test "a struct made by its type's name, in every form":
	a = Point(1, 2)
	b = Point(x = 3)
	c = Point(4, y = 5)
	print("{a} {b} {c}")
	print("{Pair(1, "r")} {Pair<i64, str>(left = 2, right = "s")}")
	if a == Point(1, 2):
		print(true)
	prints """
		Point(x = 1, y = 2) Point(x = 3, y = 7) Point(x = 4, y = 5)
		Pair<i64, str>(left = 1, right = "r") Pair<i64, str>(left = 2, right = "s")
		true
		"""

# A local named like a field fills that field wherever it stands, so `field = field` is never
# written.

type Size:
	width i64
	height i64
	depth i64

fn show(s Size):
	"{s.width}x{s.height}x{s.depth}"

test "a local named like a field fills it":
	width = 2
	height = 3
	depth = 4
	expect show(Size(width, height, depth)) == "2x3x4"
	expect show(Size(depth, height, width)) == "2x3x4"
	expect show(Size(width, height, depth = 9)) == "2x3x9"
	expect show(Size(5, height, depth)) == "5x3x4"

# A field may have a default, an expression evaluated at each construction that leaves it out
# (written where the type is, reading no variable). A field without a default must be given; the
# error lists the missing ones.

type Format:
	size u16 = 40
	depth u8 = 24
	flags u32
	name str = "default"
	tags str[] = []

type Counted<T>:
	value T
	count i64 = 1

test "a field left out takes its default":
	print(Format(flags = 37))
	print(Format(flags = 1, depth = 8, name = "n"))
	print(Counted(value = "v").count)
	f = Format(flags = 0)
	f.tags.push("mine")
	print(Format(flags = 0).tags)
	prints """
		Format(size = 40, depth = 24, flags = 37, name = "default", tags = [])
		Format(size = 40, depth = 8, flags = 1, name = "n", tags = [])
		1
		[]
		"""

test "a field with no default must be given" refuses MissingFields("flags"):
	type Format:
		size u16 = 40
		flags u32
	print(Format(size = 1))

test "a default reads no variable" refuses DefaultReadsVariable:
	type P:
		x i64 = k
	fn make() P:
		k = 3
		P()
	print(make().x)

# A function `newX` whose body is only `X`'s literal of its parameters and of constants is an error:
# the literal says it where it is called, the constants as the fields' defaults.

test "a constructor that only writes the literal is not written" refuses LiteralOnlyFunction:
	type Point:
		x i64
		y i64
		z i64
	fn newPoint(x i64, y i64) Point:
		Point(x, y, z = 0)
	print(newPoint(1, 2))

# `Type(..base, field = value)` makes a value whose fields not named are `base`'s (`base` first, of
# the same type; CPU code only, a GPU file's structs have no update). `base` is evaluated once: a
# local not used again gives its fields away (plain data copies), a temporary is bound first; a
# `base` that owns memory and is used after is an error that asks for `..base.copy()`.

type Params:
	name str
	lit bool
	scale f32
	tags str[]

fn defaults():
	Params(name = "default", lit = true, scale = 1.0, tags = ["base"])

test "..base gives a literal the fields it leaves out":
	base = defaults()
	dark = Params(..base, lit = false)
	print(dark)
	print(Params(..defaults(), scale = 3.0))
	kept = defaults()
	other = Params(..kept.copy(), name = "copy")
	print("{other} {kept}")
	p = Pair(left = 1, right = "x")
	print(Pair(..p, right = "r"))
	prints """
		Params(name = "default", lit = false, scale = 1, tags = ["base"])
		Params(name = "default", lit = true, scale = 3, tags = ["base"])
		Params(name = "copy", lit = true, scale = 1, tags = ["base"]) Params(name = "default", lit = true, scale = 1, tags = ["base"])
		Pair<i64, str>(left = 1, right = "r")
		"""

test "a base used after it gave its fields" refuses UseAfterBase:
	type Params:
		name str
		lit bool
	base = Params(name = "x", lit = true)
	dark = Params(..base, lit = false)
	print(dark)
	print(base)

test "..base comes first" refuses BaseFirst:
	type Point:
		x i64
		y i64
	p = Point(x = 1, y = 2)
	print(Point(x = 3, ..p))

# A struct cannot contain itself by value (directly, through `T?` or through another struct); it may
# through a list, a map or a `Box` (see *Boxes*).

type Tree:
	value i64
	kids Tree[]
	byName {str: Tree}
	parent Box<Tree>?

test "a struct contains itself through a list, a map or a Box":
	leaf = Tree(value = 2, kids = [], byName = {}, parent = none)
	t = Tree(value = 1, kids = [leaf], byName = {}, parent = none)
	expect t.kids[0].value == 2

test "a struct does not contain itself by value" refuses TypeContainsItself:
	type Node:
		value i64
		next Node?
	print(1)

# **Defined types.** `type Name = T` is a type of its own over T: T's layout and operations, and
# never a value of T, nor T a value of it, so a type's index given where a node's is expected is an
# error. T is any type (a number, a struct, a list, `Grid<T>`), read where it is declared; a defined
# type takes no type parameters. A range type (`type Percent = i64 in 0..=100`, 3.1) names its range
# instead.

type Color:
	r f32
	g f32

type Paint = Color
type Hue = Paint
type Ids = i64[]
type Label = str
type Meters = f64
type NodeId = n32
type Image = Grid<u8>

fn half(m Meters):
	m / 2.0

fn brightness(p Paint):
	p.r + p.g

fn shout(l Label):
	Label("{l}!")

fn nodeName(id NodeId):
	"node {id}"

test "a defined type takes no type parameters" refuses GenericDefinedType:
	type Pair<T> = (T, T)

# Conversions: `Name(x)` makes one from a T, from another type over the same T, or from a number as
# `T(x)` converts it (`NodeId(i)` stops the program where `n32(i)` would); `T(name)` reads it back.
# A conversion to the type the value has is an error (3.1). A struct's literal by the name is one of
# the type, and a literal where it is expected is one.

test "a defined type over a struct, a list and a str":
	p = Paint(r = 1.0, g = 2.0)
	q = Paint(0.5, 0.5)
	c = Color(p)
	h = Hue(p)
	ids Ids = [1, 2, 3]
	l Label = "hey"
	m Meters = 2.0
	img = Image(3, 2, fill = 7)
	expect p.r + q.g == 1.5
	expect p.brightness() == 3
	expect c.g == 2
	expect Paint(h).r == 1
	expect ids.len == 3
	expect ids.sum() == 6
	expect l.shout() == "hey!"
	expect m == 2
	expect img.width == 3
	expect img.height == 2
	expect img[1, 1] == 7

test "a natural's conversion stops outside it" stops IntegerOverflow:
	type NodeId = n32
	n = args.len - 5
	print("{NodeId(n)}")

test "a defined type converts from its base or a number" refuses DefinedConversion:
	type Meters = f64
	print("{Meters("1")}")

# Operations: between two of its values, or one and a literal, an operation gives the type where T's
# gives T, else what T's gives. With a value of T, or of another type, it is an error that asks for
# `Name(x)`: a value is never widened into it or out of it.

test "a defined type over a number":
	m = Meters(3.0)
	total = m + Meters(1.5) * 2.0
	expect total == 6
	expect total.half() == 3
	expect f64(total) == 6
	expect m < total
	expect -m == -3

test "a defined type over a natural":
	id = NodeId(7)
	next = id + 1
	at = next
	at *= 2
	print("{nodeName(next)} {n32(at)} {i64(id)} {next - id}")
	ids = []
	ids.push(id)
	names {NodeId: str} = {}
	names[id] = "seven"
	print("{ids} {names[NodeId(7)]}")
	first = 0 if ids.len > 5 else ids[0]
	print(nodeName(first))
	prints """
		node 8 16 7 1
		[7] seven
		node 7
		"""

test "a defined type is not its base" refuses ArgumentType:
	type NodeId = n32
	fn g(i i64) i64:
		i
	print("{g(NodeId(3))}")

test "a defined type and its base do not mix" refuses DefinedMixed:
	type Meters = f64
	f f64 = 2.0
	print("{Meters(1.0) + f}")

# Methods: its own are written with its name and T does not have them. T's methods it has too, and
# they give what they give on T, since nothing says which keep the unit.

test "a method of the base gives the base":
	m = Meters(3.0)
	root = m.sqrt()
	low = m.min(1.0)
	expect root > 1.7
	expect low == 1

test "the base does not have the defined type's methods" refuses NoMethod:
	type Meters = f64
	fn half(m Meters) Meters:
		m / 2.0
	x f64 = 4.0
	print(x.half())

# **Bits types.** `type Name bits u8:` (or `u16`, `u32`, `u64`) lays its fields out in that
# integer, each naming where it lies, the lowest bit 0: a `bool` its one bit (`n bool = 7`), an
# unsigned integer a range of bits, its end left out (`mode u8 = 0..3`), the type holding the range
# and no wider than the base. It is a defined type over the integer: in memory, in its bytes, in
# JSON and in print it is the integer, `Name(x)` makes one of it and `u8(s)` reads it back. `s.n`
# reads a field and `s.mode = 3` writes it in place, through a `mut ref` and in a field or an
# element too; a literal names its fields (a name like a field's fills it, as in a struct's), one
# left out 0. Fields that share a bit, or one past the width, are errors. A read is a shift and a mask, a write a mask and an or (`x.bits(from, count)`,
# `x.withBits(from, count, v)`, 3.1).

type Status bits u8:
	n bool = 7
	v bool = 6
	z bool = 1
	c bool = 0

type BgMode bits u8:
	mode u8 = 0..3
	bg3High bool = 3
	large u8 = 4..8

type Cpu:
	p Status = Status(n = true)
	a u16

fn setCarry(s mut ref Status):
	s.c = true

test "a bits type's fields read and written in place":
	s = Status(n = true, z = true)
	print("{s} {s.n} {s.v} {s.z} {u8(s)}")
	s.v = true
	s.n = false
	m = BgMode(0x5A)
	print("{s} {m.mode} {m.bg3High} {m.large}")
	m.large = 3
	m.mode += 1
	cpu = Cpu(a = 1)
	cpu.p.z = true
	ps = [Status(1), Status(n = true)]
	ps[0].v = true
	setCarry(mut ref ps[1])
	z = true
	print("{m} {cpu.p} {ps} {Status(z, c = true)}")
	prints """
		130 true false true 130
		66 2 true 5
		59 130 [65, 129] 3
		"""

test "a bits type's bytes and JSON are its integer's":
	s = Status(c = true, n = true)
	cpu = Cpu(p = s, a = 2)
	print(s.toBytes())
	print(cpu.toJson())
	print("{Status.fromBytes([3])} {Cpu.fromJson(cpu.toJson())}")
	prints r"""
		[129]
		{"p":129,"a":2}
		some(3) some(Cpu(p = 129, a = 2))
		"""

test "two fields of a bits type share no bit" refuses BitsOverlap:
	type Mode bits u8:
		low u8 = 0..4
		mid u8 = 3..6
	print(Mode(low = 1))

test "a bits type's field lies inside its width" refuses BitsOutside:
	type Wide bits u8:
		top u8 = 6..10
	print(Wide(top = 1))

test "a bool field is one bit, an integer one a range" refuses BitsField:
	type Mode bits u8:
		level u8 = 3
	print(Mode(level = 1))

# **Structs of numbers.** A struct whose fields are all one number type has `+ - * /` field by field
# between two of them, and with a number of the fields' type on either side between it and every
# field. Any other struct has none of these, and the error says so.

type Vec2:
	x f32
	y f32

type Cell:
	col i64
	row i64

test "field by field, and a number on either side":
	a = Vec2(x = 1.0, y = 2.0)
	b = Vec2(x = 3.0, y = 5.0)
	print("{a + b} {b - a} {a * b} {b / a}")
	print("{a * 2.0} {0.5 * b} {(a + b) * 0.5}")
	print("{a + 0.5} {3.0 - 2.0 * a} {2.0 / a} {a - 1.0}")
	c = Cell(col = 3, row = 4)
	print(c + c * 2)
	prints """
		Vec2(x = 4, y = 7) Vec2(x = 2, y = 3) Vec2(x = 3, y = 10) Vec2(x = 3, y = 2.5)
		Vec2(x = 2, y = 4) Vec2(x = 1.5, y = 2.5) Vec2(x = 2, y = 3.5)
		Vec2(x = 1.5, y = 2.5) Vec2(x = 1, y = -1) Vec2(x = 2, y = 1) Vec2(x = 0, y = 1)
		Cell(col = 9, row = 12)
		"""

test "a struct of mixed fields has no arithmetic" refuses NoArithmetic:
	type M:
		x i64
		name str
	m = M(x = 1, name = "a")
	print(m + m)

test "the number has the fields' type" refuses StructScalarType:
	type V:
		x f32
	v = V(x = 1.0)
	n = [1, 2].len
	print(v + n)

# The number methods work field by field where the struct has no method of that name: an argument is
# a struct of the same type or a number spread over the fields, the float ones on floats only. `-v`
# negates every field.

type Vec3:
	x f32
	y f32
	z f32

test "a number's methods field by field, a number spread over the fields":
	v = Vec3(-1.5, 2.25, 4.0)
	o = Vec3(0.0, 3.0, 1.0)
	print("{v.floor()} {v.fract()}")
	print("{v.min(o)} {v.clamp(0.0, 1.0)}")
	print("{v.lerp(o, 0.5)} {v.clamp(o, Vec3(1.0, 2.0, 3.0))}")
	print("{Cell(-3, 4).abs().max(Cell(5, 0))} {-Vec3(1, 0, -2)} {-Cell(3, -4)}")
	prints """
		Vec3(x = -2, y = 2, z = 4) Vec3(x = 0.5, y = 0.25, z = 0)
		Vec3(x = -1.5, y = 2.25, z = 1) Vec3(x = 0, y = 1, z = 1)
		Vec3(x = -0.75, y = 2.625, z = 2.5) Vec3(x = 0, y = 2, z = 3)
		Cell(col = 5, row = 4) Vec3(x = -1, y = 0, z = 2) Cell(col = -3, row = 4)
		"""

test "a float's method on a struct of integers" refuses FloatMethod:
	type C:
		a i64
	print(C(a = 1).floor())

# `a @ b` is the dot product (`a.dot(b)` is an error), and a struct of floats has a vector's
# methods: `length()`, `distance(o)`, `normalized()` (zero staying zero), `reflect(n)`.

test "a struct of floats is a vector":
	a = Vec3(3, 0, 4)
	b = Vec3(0, 1, 0)
	print("{a @ b} {a.length()} {a.distance(b)} {a.normalized()} {a.reflect(b)} {Vec3(0, 0, 0).normalized()}")
	prints "0 5 5.0990195 Vec3(x = 0.6, y = 0, z = 0.8) Vec3(x = 3, y = 0, z = 4) Vec3(x = 0, y = 0, z = 0)"

# Indexing goes in field order (`v[0]` is `v.x`): past the last field the program stops, and a
# literal index is checked when compiling.

fn sum(v Vec3):
	s = 0.0
	for a in 0..3:
		s += v[a]
	s

test "a struct of one number type is read and written by index":
	v = Vec3(x = 1.0, y = 2.0, z = 3.0)
	for a in 0..3:
		v[a] += 10.0
	print("{v.x} {v.y} {v.z} {v[1]}")
	v[2] = 0.5
	p = Cell(4, 5)
	p[1] *= 3
	print("{v.z} {p} {v.sum()}")
	prints """
		11 12 13 12
		0.5 Cell(col = 4, row = 15) 23.5
		"""

test "an index past the fields stops the program" stops IndexOutOfBounds:
	type Vec3:
		x f32
		y f32
		z f32
	v = Vec3(x = 1.0, y = 2.0, z = 3.0)
	print(v[args.len + 3])

# When its fields have one-letter names, two to four of them read together are a swizzle: `v.zx` is
# the module's `Vec2(x = v.z, y = v.x)` (`Vec2`..`Vec4` of the same number type, declared where the
# struct is), as a shader reads its vectors. Any value has them, evaluated once.

type Rgba:
	r f32
	g f32
	b f32
	a f32

fn make():
	Vec3(x = 1.0, y = 2.0, z = 3.0)

test "a swizzle reads one-letter fields together":
	v = Vec3(x = 1.0, y = 2.0, z = 3.0)
	print("{v.xy} {v.zxx}")
	c = Rgba(r = 0.5, g = 0.25, b = 1.0, a = 1.0)
	print(c.rgb)
	held = [v]
	print(held[0].yz)
	print(make().zy)
	o = Vec3(x = 0.5, y = 0.5, z = 0.5)
	print("{(v - o).xz} {(v * 2.0).zyx}")
	prints """
		Vec2(x = 1, y = 2) Vec3(x = 3, y = 1, z = 1)
		Vec3(x = 0.5, y = 0.25, z = 1)
		Vec2(x = 2, y = 3)
		Vec2(x = 3, y = 2)
		Vec2(x = 0.5, y = 2.5) Vec3(x = 6, y = 4, z = 2)
		"""
