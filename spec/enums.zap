# 3.3 Enums
#
# An enum lists its variants, each with values of its own or none. Variants are built positionally
# and taken apart with `match` or `is` (see *Match*). An enum has methods in its block, after its
# variants, as a struct does (`fn area() f64`, matching on `self`).

type Shape:
	Circle(radius f32)
	Rect(width f32, height f32)
	Point

	fn area():
		match self:
			Circle(r): 3.0 * r * r
			Rect(w, h): w * h
			Point: 0.0

type Color:
	Red
	Green
	Blue

	fn name():
		match self:
			Red: "red"
			Green: "green"
			Blue: "blue"

	fn next() Color:
		match self:
			Red: .Green
			Green: .Blue
			Blue: .Red

test "variants built positionally, taken apart by match and is, with methods":
	s = Shape.Circle(2.0)
	print("{s} {s.area()} {Shape.Rect(2.0, 3.0).area()} {Shape.Point}")
	if s is Circle(r):
		print(r)
	c = Color.Red
	print("{c.name()} {c.next().name()} {c.next().next().next() == .Red}")
	prints """
		Circle(2) 12 6 Point
		2
		red green true
		"""

# `e.Variant` is the value a variant of one value holds, as an optional: none when `e` holds another
# variant, and a reference into `e` unless the value copies freely. With `e is Variant` to test one,
# a variant's data reads as a field would (`?.`, `??`, `is x`), so a kind and the data each kind
# carries are one enum rather than a name and an optional field per kind.

type Weapon:
	damage i64
	twoHanded bool

type Gear:
	Blade(weapon Weapon)
	Arrows(damage i64)
	Tome(skill str)
	Coin

fn damageOf(g Gear):
	g.Blade?.damage ?? g.Arrows ?? 0

test "a variant's value read as an optional":
	bag Gear[] = [.Blade(Weapon(damage = 7, twoHanded = true)), .Arrows(2), .Tome("archery"), .Coin]
	print(bag.map(damageOf))
	print("{bag.count(it.Blade?.twoHanded ?? false)} {bag[2].Tome} {bag[3].Tome}")
	for g in bag:
		if g.Tome is skill: print("teaches {skill}")
		if g is Coin: print("a coin")
	prints """
		[7, 2, 0, 0]
		1 some("archery") none
		teaches archery
		a coin
		"""

test "a variant gives one value" refuses VariantValueCount:
	print(Shape.Rect(1.0, 2.0).Rect)

# `.Variant` (a leading dot, see *Operators*) is a variant of the enum its place expects: a
# parameter, a field, a declared binding, an assignment, a result, the other side of `==`, a list
# or a match whose type the place gives; the optional of an enum too.

type Wrap:
	Repeat
	Clamp
	Mirror

type Sampler:
	wrap Wrap
	scale f32

fn describe(w Wrap):
	match w:
		Repeat: "repeat"
		Clamp: "clamp"
		Mirror: "mirror"

fn after(w Wrap) Wrap:
	match w:
		Repeat: .Clamp
		Clamp: .Mirror
		Mirror: .Repeat

fn unit() Shape:
	.Rect(1.0, 1.0)

fn pick(round bool) Shape?:
	if round: return .Circle(1.0)
	none

test "a variant takes its enum from where it goes":
	print(describe(.Clamp))
	print(after(.Clamp).describe())
	s = Sampler(wrap = .Repeat, scale = 2.0)
	print(s)
	print(unit())
	print(pick(true) ?? .Point)
	print("{s.wrap == .Repeat} {.Mirror == s.wrap}")
	shapes Shape[] = [.Point, .Circle(2.0)]
	print(shapes)
	s.wrap = .Clamp
	w Wrap = .Mirror
	w = s.wrap
	print(w)
	prints """
		clamp
		mirror
		Sampler(wrap = Repeat, scale = 2)
		Rect(1, 1)
		Circle(1)
		true false
		[Point, Circle(2)]
		Clamp
		"""

# Where nothing expects the type (`s = Shape.Circle(2.0)`), or only a sibling gives it (the second
# element of a list without an expected type, an argument of a generic whose type an earlier one
# fixed), the type is written. A GPU file names its enums' variants with the type (`Wrap.Clamp`).

test "a sibling does not give the enum" refuses EnumUnknown("'.B' takes its enum from the place it goes to, and none is known here: write Letter.B"):
	type Letter:
		A
		B

	letters = [Letter.A, .B]
	print(letters)

test "a function without a declared result gives none to its variants" refuses EnumUnknown:
	type Letter:
		A
		B

	fn pick(second bool):
		return Letter.A if not second else .B

	print(pick(true))

test "a variant needs a place that gives its enum" refuses EnumUnknown:
	type Shape:
		Circle(radius f32)
		Point

	s = .Circle(1.0)
	print(s)

# A variant without values may be given an integer, `Add = 1` (negative or in hex too), as the
# codes of a file format or a protocol are. Then every variant has one, none carries values, and
# the integers are distinct. `op.value` is the integer (an i64) and `Op.from(n)` the variant that
# has it, an `Op?` that is none for any other. The integer is not stored: the tag stays the
# variant's number, the narrowest that holds them.

type Op:
	Add = 1
	Sub = 2
	Halt = -1
	Call = 0x100

	fn arity():
		match self:
			Add, Sub: 2
			Halt: 0
			Call: 1

test "a variant's integer, and the variant of an integer":
	print("{Op.Add.value} {Op.Halt.value} {Op.Call.value}")
	print(Op.from(2) ?? .Halt)
	print(Op.from(256)?.arity())
	print(Op.from(7))
	if Op.from(-1) is op:
		print("{op} {op.arity()}")
	ops Op[] = [.Add, .Call]
	print(ops.map(.value).sum())
	prints """
		1 -1 256
		Sub
		some(1)
		none
		Halt 0
		257
		"""

test "an integer of a variant is distinct" refuses EnumValueDuplicate:
	type Op:
		Add = 1
		Sub = 1

	print(Op.Add)

test "every variant has an integer or none does" refuses EnumValueMissing:
	type Op:
		Add = 1
		Sub

	print(Op.Add)

test "a variant with an integer carries nothing" refuses EnumValuePayload:
	type Op:
		Add(x i64) = 1
		Sub = 2

	print(Op.Sub)
