# 7.8 Vectors, matrices and tensors
#
# A list of numbers is a vector and a list of those a matrix: `+ - * /` work element by element
# between two of one type, `*` and `/` by a number of the element type, and `@` is matrix times
# matrix, matrix times vector or the dot product. `*` is always element by element and `@` always
# the product, on lists and on the geometry types alike: a reader knows what an operator does
# without the types.

import math
import tensor
import gpu

test "lists of numbers are vectors and matrices":
	a = [[1.0, 2.0], [3.0, 4.0]]   # a matrix: f64[,]
	b = [[5.0, 6.0], [7.0, 8.0]]
	c = a @ b   # matrix multiplication
	d = a + b   # element-wise
	e = a * 2.0   # scalar
	print(c)
	print(d)
	print(e)
	v = [1.0, 2.0, 3.0]
	w = [4.0, 5.0, 6.0]
	print(v + w)
	print(v * 2.0)
	print(v @ w)
	m = [[1.0, 0.0], [0.0, 1.0]]
	u = [7.0, 9.0]
	print(m @ u)
	prints """
		[[19, 22], [43, 50]]
		[[6, 8], [10, 12]]
		[[2, 4], [6, 8]]
		[5, 7, 9]
		[2, 4, 6]
		32
		[7, 9]
		"""

test "math on lists of any number":
	xs = [1, 2, 3]
	print(xs * 3 + xs)
	ys i32[] = [10, 20]
	print(ys / 10)
	print(xs @ xs)
	prints """
		[4, 8, 12]
		[1, 2]
		14
		"""

test "Vector is a list" refuses NotAListOfNumbers:
	v Vector = [1.0]
	print(v)

# A shape mismatch stops the program (on the geometry types, whose shapes are their types, it is a
# compile error). Concatenation is `extend` or `flatMap`, never `+`.

test "a shape mismatch stops the program" stops Failure("vector shape mismatch"):
	b = [1.0, 2.0, 3.0]
	if args.len > 5:
		b.pop()
	print([1.0, 2.0] + b)

test "lists are joined by extend or flatMap":
	xs = [1, 2]
	xs.extend([3])
	print("{xs} {[1, 2].flatMap([it, it * 10])}")
	prints "[1, 2, 3] [1, 10, 2, 20]"

# A number's methods (`abs`, `sqrt`, `floor`, `clamp`, `sin`...) work element by element on a list
# of numbers and give a list of the same type, as on a struct of numbers; a method the list has
# (`max()`, `sum()`) stays its own, and with an argument of the element type it is each element's.
# They are pipeline steps, run in one loop with the steps around them.

test "a float's methods on f64[]":
	xs = [1.0, 4.0, 9.0]
	expect xs.sqrt() == [1, 2, 3]
	expect [-1.5, 2.0, -0.5].abs() == [1.5, 2, 0.5]
	expect [1.2, 1.7, 2.5].round() == [1, 2, 3]
	expect [-0.5, 1.5, 1.0].clamp(0.0, 1.0) == [0, 1, 1]

test "a math method of a number applies to each number of an f32 list":
	xs f32[] = [1.0, 4.0, 9.0]
	print(xs.sqrt())
	ys f32[] = [0.5, 2.0]
	print(ys.min(1.0))
	prints """
		[1, 2, 3]
		[0.5, 1]
		"""

test "integers: abs, min, max and clamp with an argument":
	xs = [-3, 1, -2]
	expect xs.abs() == [3, 1, 2]
	expect xs.max(0) == [0, 1, 0]
	expect xs.abs().min(2).max(1) == [2, 1, 2]
	expect [-1, 1, 7].clamp(0, 2) == [0, 1, 2]

test "a chain of operators and a method in one expression":
	a = [3.0, 5.0]
	b = [4.0, 12.0]
	print((a * a + b * b).sqrt())
	print((a * a + b * b).sqrt().min(5.0).max())
	prints """
		[5, 13]
		some(5)
		"""

test "the runtime's float functions":
	expect [0.0, 1.0, 0.0].sin().round().abs() == [0, 1, 0]

test "the list's own with no argument":
	xs = [1.0, 4.0, 9.0]
	print(xs.max())
	print(xs.sum())
	prints """
		some(9)
		14
		"""

test "an argument of another type names both readings" refuses ListOrElementMethod:
	xs = [1.0, 2.0]
	ys = [3.0, 4.0]
	print(xs.max(ys))

# **Geometry types.** `Vec2`, `Vec3`, `Vec4` (of `f32`), `IVec2`..`IVec4` (of `i32`) and
# `UVec2`..`UVec4` (of `u32`: a texture's size, its texels, an integer texture's values),
# `Mat2`, `Mat3`, `Mat4` (column-major, `m[col * n + row]`) and `Quat` (a turn: the unit quaternion
# `x y z w`, a `vec4` in a shader) are the language's, the same on the CPU and in a shader; a
# program's own type of the same name hides one. A vector is a struct of numbers (*Structs*) and has
# all such a struct has; its letters may also be written `r g b a` or `s t p q`, and a swizzle of an
# `IVec` or a `UVec` is one of its own kind. `Vec2.withZ(z)`,
# `Vec3.withW(w)`, `Vec3.cross(o)` and `Vec3.refract(n, eta)` are a size's own. `Vec3(xs, at = 0)`
# is the vector of an `f32[]`'s numbers from `at` on (`Vec2`, `Vec4` and `Quat` too): a mesh's or
# a file's floats.

test "the vectors have the geometry methods and their parts by name":
	a = Vec3(1, 2, 3)
	b = Vec3(0, 1, 0)
	print(a.cross(b))
	print((a * 2.0 - 1.0).normalized().length())
	print(a.xy)
	print(a.reflect(b))
	c = Vec4(r = 1.0, g = 0.5, b = 0.25, a = 1.0)
	print(c.rgb)
	c.g = 0.75
	print("{c.r} {c.g} {c.bgr} {c.st}")
	print(a.zyx.withW(4.0).wzyx)
	prints """
		Vec3(x = -3, y = 0, z = 1)
		0.99999994
		Vec2(x = 1, y = 2)
		Vec3(x = 1, y = -2, z = 3)
		Vec3(x = 1, y = 0.5, z = 0.25)
		1 0.75 Vec3(x = 0.25, y = 0.75, z = 1) Vec2(x = 1, y = 0.75)
		Vec4(x = 4, y = 1, z = 2, w = 3)
		"""

test "a size's own methods":
	print("{Vec2(1, 2).withZ(3.0)} {Vec3(1, 2, 3).withW(4.0)}")
	print(Vec3(0, -1, 0).refract(Vec3(0, 1, 0), 1.0))
	print(IVec2(1, 2) + IVec2(3, 4))
	print("{IVec4(1, -2, 3, 4).wzx} {UVec3(7, 8, 9).zy * UVec2(2, 3)}")
	floats f32[] = [1, 2, 3, 4, 5]
	print("{Vec3(floats)} {Vec2(floats, at = 3)} {Vec4(floats, 1).w} {Quat(floats).w}")
	prints """
		Vec3(x = 1, y = 2, z = 3) Vec4(x = 1, y = 2, z = 3, w = 4)
		Vec3(x = 0, y = -1, z = 0)
		IVec2(x = 4, y = 6)
		IVec3(x = 4, y = 3, z = 1) UVec2(x = 18, y = 24)
		Vec3(x = 1, y = 2, z = 3) Vec2(x = 4, y = 5) 5 4
		"""

# A matrix is made from its n * n numbers column by column, from n column vectors, from one number
# (its diagonal) or from a matrix of another size (its upper left corner, the rest the identity's).
# `m @ o`, `m @ v` and `u @ v` are the products; `+ - * /` between two matrices of one size, or a
# matrix and an `f32`, work element by element (`Mat4 * Vec4` is an error, the shapes differ). A
# matrix has `transpose()`, `Mat3` also `determinant()` and `inverse()` (the identity when there is
# none), `Mat4` `applyPoint(p)` (a `Vec3`, or a `Vec2` of the plane, z 0), `applyDirection(d)`,
# `project(p)`, `determinant3()` and `inverseAffine()`.

test "matrices multiply each other and vectors with @":
	turn f32 = 0.5
	rot = Mat2(turn.cos(), turn.sin(), -turn.sin(), turn.cos())
	print(rot @ Vec2(1, 0))
	print((Mat2(2.0) @ Mat2(1, 2, 3, 4)).m)
	m = Mat2(1, 2, 3, 4)
	print((m @ m).m)
	big = Mat4(Vec4(1, 0, 0, 0), Vec4(0, 2, 0, 0), Vec4(0, 0, 3, 0), Vec4(4, 5, 6, 1))
	print(big @ Vec4(1, 1, 1, 1))
	print(Mat3(big) @ Vec3(1, 1, 1))
	print(Mat3(Vec3(1, 2, 3), Vec3(4, 5, 6), Vec3(7, 8, 9)).transpose().m)
	print(Mat4(Mat2(3.0)).m)
	print(big.inverseAffine().applyPoint(Vec3(5, 7, 9)))
	flat = Mat3(Vec3(2, 0, 0), Vec3(0, 4, 0), Vec3(1, 1, 1))
	print("{(flat.inverse() @ flat).m} {flat.determinant()} {Mat3(0.0).inverse().m}")
	prints """
		Vec2(x = 0.87758255, y = 0.47942555)
		[2, 4, 6, 8]
		[7, 10, 15, 22]
		Vec4(x = 5, y = 7, z = 9, w = 1)
		Vec3(x = 1, y = 2, z = 3)
		[1, 4, 7, 2, 5, 8, 3, 6, 9]
		[3, 0, 0, 0, 0, 3, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
		Vec3(x = 1, y = 1, z = 1)
		[1, 0, 0, 0, 1, 0, 0, 0, 1] 8 [1, 0, 0, 0, 1, 0, 0, 0, 1]
		"""

test "* is element by element on matrices, @ a vector's dot product":
	m = Mat2(1, 2, 3, 4)
	print((Mat2(2.0) * m).m)
	print((m * 2.0).m)
	print((m / 2.0).m)
	print((m + m - m * 2.0).m)
	print(Vec3(1, 2, 3) @ Vec3(4, 5, 6))
	print(IVec3(1, 2, 3) @ IVec3(1, 2, 3))
	prints """
		[2, 0, 0, 8]
		[2, 4, 6, 8]
		[0.5, 1, 1.5, 2]
		[0, 0, 0, 0]
		32
		14
		"""

test "a Mat4's own methods":
	m = Mat4(1.0)
	print("{m.applyDirection(Vec3(1, 2, 3))} {m.project(Vec3(1, 2, 3))} {m.applyPoint(Vec2(1, 2))} {m.determinant3()}")
	prints "Vec3(x = 1, y = 2, z = 3) Vec3(x = 1, y = 2, z = 3) Vec2(x = 1, y = 2) 1"

test "a matrix times a vector is not element by element" refuses ShapesDiffer:
	print(Mat4(1.0) * Vec4(1, 2, 3, 4))

test "a product needs matching shapes" refuses ProductOperands:
	print(Vec3(1, 2, 3) @ Vec2(1, 0))

# On fixed arrays of numbers, whose shapes are their types, `@` is the same products checked when
# compiling: `T[R, K] @ T[K, C]` a `T[R, C]`, `T[R, K] @ T[K]` a `T[R]`, `T[N] @ T[N]` a `T`. A
# struct whose one field is such an array (a program's matrix, `type Mat<R n64, C n64>: cells
# f32[R, C]`) multiplies as its array, into the struct of the product's shape (3.6).

type Square:
	m i64[2, 2]

test "products of fixed arrays":
	a f32[2, 3] = [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]]
	b f32[3, 2] = [[1.0, 0.0], [0.0, 1.0], [1.0, 1.0]]
	v f32[3] = [1.0, 0.0, 1.0]
	print("{a @ b} {a @ v} {v @ v}")
	s = Square(m = [[1, 1], [0, 1]])
	print(s @ s @ s)
	prints """
		[[4, 5], [10, 11]] [4, 10] 2
		Square(m = [[1, 3], [0, 1]])
		"""

test "a product of fixed arrays needs sizes that meet" refuses ProductShapes:
	a f32[3, 2] = [[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]]
	print(a @ a)

# `q @ r` is the product of two quaternions, the turn `r` then `q` (in a shader too); `* + - /`
# work on a `Quat` field by field. The formulas over these types are `std/math`'s, written in the
# type's form (`Mat4.perspective(...)`, `Quat.about(axis, angle)`, `q.rotate(v)`): a function of the
# standard library that takes a module's or a language type first is called on the value, one that
# gives a language type on the type.

test "q @ r is the product of quaternions, * field by field":
	i = Quat(1, 0, 0, 0)
	j = Quat(0, 1, 0, 0)
	print(i @ j)
	print(j @ i)
	print(Quat(1, 2, 3, 4) * 2.0)
	expect Quat(1, 2, 3, 4).xyz.y == 2
	prints """
		Quat(x = 0, y = 0, z = 1, w = 0)
		Quat(x = 0, y = 0, z = -1, w = 0)
		Quat(x = 2, y = 4, z = 6, w = 8)
		"""

test "quaternions field by field, and std/math's formulas":
	q = Quat(1, 2, 3, 4)
	print("{q + q} {q - q} {q / 2.0}")
	turned = Quat.about(Vec3(0, 0, 1), pi / 2.0).rotate(Vec3(1, 0, 0))
	expect turned.isClose(Vec3(0, 1, 0), 1e-6)
	expect Mat4.perspective(1.0, 1.0, 0.1, 10.0).m[0].isClose(1.8304877, 1e-6)
	prints "Quat(x = 2, y = 4, z = 6, w = 8) Quat(x = 0, y = 0, z = 0, w = 0) Quat(x = 0.5, y = 1, z = 1.5, w = 2)"

test "a function of the standard library its type's form serves is not called free" refuses TypeFormCall("'rotate' of the standard library is written q.rotate(...)"):
	import math
	q = Quat(0, 0, 0, 1)
	print(math.rotate(q, Vec3(1, 0, 0)))

# **SIMD types.** `Simd<N, T>` holds `N` lanes of the number type `T` in one register, the lane
# count a number type argument (3.6). The sizes the processor has are the ones it takes: `Simd<4,
# f64>`, `Simd<8, f32>`, `Simd<8, i32>`, `Simd<4, i64>`, `Simd<32, u8>` (256 bits) and `Simd<16,
# u8>` (128 bits). `Simd<4>(a, b, c, d)` builds one from its lanes (all literals: a constant) and
# `Simd<4>(x)` repeats a value; the element type is the one written, else the expected type's, else
# the values'.

fn scaled(v Simd<4, f64>, k f64):
	v * k

test "a Simd is built from its lanes or from one value for all of them":
	a = Simd<4>(1.0, 2.0, 3.0, 4.0)
	print(scaled(a + Simd<4>(0.5), 2.0))
	print((a * a).sum())
	print(Simd<8>(1, 2, 3, 4, 5, 6, 7, 8))
	d = Simd<8>(0.5)
	print(d)
	print((Simd<16, u8>(15) & Simd<16>(7)).lane(0))
	print(Simd<4, i64>(3) + Simd<4>(1, 2, 3, 4))
	print(Simd<32, u8>(1).sum())
	x = 2.5
	print(Simd<4>(x).lane(2))
	prints """
		[3, 5, 7, 9]
		30
		[1, 2, 3, 4, 5, 6, 7, 8]
		[0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5]
		7
		[4, 5, 6, 7]
		32
		2.5
		"""

test "vectors in lists and register arrays":
	vs = [Simd<4>(1.0), Simd<4>(2.0)]
	print(vs)
	zr Simd<4, f64>[4] = fill(4, Simd<4>(0.0))
	for k in 0..4:
		zr[k] += Simd<4>(f64(k))
	print(zr[3].lane(0))
	prints """
		[[1, 1, 1, 1], [2, 2, 2, 2]]
		3
		"""

test "a vector type the table lacks" refuses NoSuchVector:
	x = 2.0
	print(Simd<8>(x))

# A number beside a vector stands for itself in every lane (`v * 0.5`). A vector is plain data and,
# in a loop that makes no call, lives in a `ymm` register.

fn showLanes(v Simd<4, f64>):
	"{v.lane(0)} {v.lane(1)} {v.lane(2)} {v.lane(3)}"

test "a number beside a vector is in every lane":
	p = Simd<4>(0.0, 1.5, 2.5, 3.5)
	print(showLanes(p))
	x = 2.0
	q = Simd<4>(x, x + 1.0, 4.0, -1.0)
	print(showLanes(q))
	print(showLanes(p * 2.0))
	print(showLanes(0.5 * q + 1))
	print(showLanes((p - 1.5) / 2))
	acc = Simd<4>(0.0, 0.0, 0.0, 0.0)
	for i in 0..3:
		acc += p * f64(i)
	print(showLanes(acc))
	w = Simd<8>(1, 2, 3, 4, 5, 6, 7, 8)
	print((w * 3 + 1).lane(7))
	k i32 = 10
	print((w + k).sum())
	f = Simd<8>(0.5, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0)
	print((f * 2.0).lane(0))
	big = Simd<4>(1, 2, 3, 4) + 1_000_000_000_000
	print(big.lane(3))
	prints """
		0 1.5 2.5 3.5
		2 3 4 -1
		0 3 5 7
		2 2.5 3 0.5
		-0.75 0 0.5 1
		0 4.5 7.5 10.5
		25
		116
		1
		1000000000004
		"""

# Operators work lane by lane: `+ -` on all, `*` on floats and `Simd<8, i32>`, `/` on floats, `& |
# ^` on integers. `xs.loadN(i)` and `xs.storeN(i, v)` move N consecutive elements of a list,
# bounds-checked; `lane(i)` is one lane, `sum()` all lanes added in the element's arithmetic
# (integers wrap); `min(w)` and `max(w)` go lane by lane; `eqMask`, `ltMask`, `leMask`, `gtMask` and
# `geMask` give an integer with bit i set where lane i compares true.

type Lanes:
	a Simd<4, f64>
	b Simd<4, f64>

fn scaleBy(v Simd<4, f64>, k f64):
	v * Simd<4>(k)

test "Simd<4, f64>: lanes, loads, stores and masks":
	xs = [1.0, 4.0, 9.0, 16.0, 25.0, 36.0, 49.0, 64.0]
	v = xs.load4(0)
	w = xs.load4(4)
	s = v + w
	print("{s.lane(0)} {s.lane(1)} {s.lane(2)} {s.lane(3)} sum {s.sum()}")
	r = v.sqrt()
	print("{r.lane(0)} {r.lane(1)} {r.lane(2)} {r.lane(3)}")
	d = (w - v) / Simd<4>(2.0)
	print("{d.sum()} {d.max(v).sum()} {d.min(v).sum()}")
	print("{v.ltMask(w)} {v.gtMask(w)} {v.leMask(v)} {w.geMask(v * Simd<4>(2.0))}")
	out f64[] = zeros(8)
	out.store4(0, scaleBy(v, 10.0))
	out.store4(4, w * w)
	print(out)
	p = Lanes(a = v, b = w)
	q = p
	print("{(q.a + q.b).sum()} {p.a.lane(3)}")
	acc = Simd<4>(0.0)
	for i in 0..1000:
		acc += Simd<4>(f64(i))
	print("{acc.lane(0)} {acc.sum()}")
	prints """
		26 40 58 80 sum 204
		1 2 3 4
		72 72 30
		15 0 15 15
		[10, 40, 90, 160, 625, 1296, 2401, 4096]
		204 16
		499500 1998000
		"""

test "the 256-bit family shares one vocabulary":
	floats = [
		f32(1.5),
		f32(2.0),
		-f32(3.0),
		f32(4.25),
		f32(0.5),
		f32(6.0),
		f32(7.0),
		-f32(8.0)
	]
	a = floats.load8(0)
	two = Simd<8>(f32(2.0))
	b = a * two + a
	print(b)
	print(b.sum())
	print(a.lane(3))
	print(a.min(two))
	print(a.max(two))
	print(a.gtMask(two))
	print(a.leMask(two))
	print((a / two).lane(1))
	prints """
		[4.5, 6, -9, 12.75, 1.5, 18, 21, -24]
		30.75
		4.25
		[1.5, 2, -3, 2, 0.5, 2, 2, -8]
		[2, 2, 2, 4.25, 2, 6, 7, 2]
		104
		151
		1
		"""

	ns i32[] = [1, -2, 3, -4, 5, -6, 7, -8, 9]
	n = ns.load8(1)
	m = n * n - Simd<8>(3)
	print(m)
	print(m.sum())
	print(n.min(Simd<8>(0)))
	print(n.max(Simd<8>(0)))
	print(n.eqMask(m))
	print(n.ltMask(Simd<8>(0)))
	print(n.geMask(Simd<8>(0)))
	print((n & Simd<8>(255)).lane(0))
	zero i32 = 0
	out = fill(10, zero)
	out.store8(2, m)
	print(out)
	prints """
		[1, 6, 13, 22, 33, 46, 61, 78]
		260
		[-2, 0, -4, 0, -6, 0, -8, 0]
		[0, 3, 0, 5, 0, 7, 0, 9]
		0
		85
		170
		254
		[0, 0, 1, 6, 13, 22, 33, 46, 61, 78]
		"""

	ls = [10_000_000_000, -5, 7, 3]
	w = ls.load4(0)
	x = w + Simd<4>(1)
	print(x)
	print(x.sum())
	print(w.min(Simd<4>(5)))
	print(w.max(Simd<4>(5)))
	print(w.gtMask(Simd<4>(5)))
	print((w ^ w).sum())
	prints """
		[10000000001, -4, 8, 4]
		10000000009
		[5, -5, 5, 3]
		[10000000000, 5, 7, 5]
		5
		0
		"""

	bytes = []
	for i in 0..40:
		bytes.push(u8.wrap(i * 7))
	u = bytes.load32(4)
	v = u + Simd<32>(200)
	print(v.lane(0))
	print(v.lane(31))
	print(u.min(Simd<32>(100)).lane(20))
	print(u.max(Simd<32>(100)).lane(1))
	print(u.eqMask(u))
	print(u.sum())
	bytes.store32(8, v)
	print(bytes[8])
	print(bytes[39])
	prints """
		228
		189
		100
		100
		4294967295
		16
		228
		189
		"""

test "a load past the end stops the program" stops IndexOutOfBounds:
	xs f64[] = [1.0, 2.0, 3.0, 4.0]
	print(xs.load4(args.len + 1).sum())

test "no division of integer lanes" refuses NoLaneOperator:
	print(Simd<8, i32>(6) / Simd<8>(2))

# `Simd<4, f64>` also has `sqrt()`, `spread(i)` (one lane repeated), `sums4(b, c, d)` (four
# horizontal sums packed) and `rsqrtEstimate()` (the hardware's 12-bit `1/sqrt`).

test "Simd<4, f64>'s own":
	s = Simd<4>(4.0, 9.0, 16.0, 25.0)
	print("{s.sqrt()} {s.spread(2)} {s.sums4(s, s, s)}")
	expect s.rsqrtEstimate().lane(0).isClose(0.5, 0.001)
	prints "[2, 3, 4, 5] [16, 16, 16, 16] [54, 54, 54, 54]"

# `Simd<16, u8>` has `shuffle(idx)` (byte `v[idx[i] & 15]`, 0 when the index's high bit is set),
# `blend(w, mask)` (`w` where the mask byte's high bit is set) and `eqBytes(w)` (0xFF where bytes
# agree).

fn hex(v Simd<16, u8>):
	digits = "0123456789abcdef"
	s = ""
	for i in 0..16:
		b = v.lane(i)
		s = s + digits[b / 16..b / 16 + 1] + digits[b % 16..b % 16 + 1]
	s

test "Simd<16, u8>: bytes, shuffles and blends":
	xs u8[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19]
	v = xs.load16(0)
	w = xs.load16(4)
	print(hex(v))
	print(hex(w))
	print(hex(v + w))
	print(hex(w - v))
	print(hex(v & Simd<16>(3)))
	print(hex(v | Simd<16>(128)))
	print(hex(v ^ w))
	rev u8[] = [15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0]
	print(hex(w.shuffle(rev.load16(0))))
	zeroTop u8[] = [0, 1, 2, 3, 128, 128, 128, 128, 4, 5, 6, 7, 255, 255, 255, 255]
	print(hex(w.shuffle(zeroTop.load16(0))))
	sel = (v & Simd<16>(1)).eqBytes(Simd<16>(1))   # odd lanes
	print(hex(sel))
	print(hex(v.blend(w, sel)))
	prints """
		000102030405060708090a0b0c0d0e0f
		0405060708090a0b0c0d0e0f10111213
		0406080a0c0e10121416181a1c1e2022
		04040404040404040404040404040404
		00010203000102030001020300010203
		808182838485868788898a8b8c8d8e8f
		040404040c0c0c0c040404041c1c1c1c
		131211100f0e0d0c0b0a090807060504
		040506070000000008090a0b00000000
		00ff00ff00ff00ff00ff00ff00ff00ff
		000502070409060b080d0a0f0c110e13
		"""
	print("{v.eqMask(w)} {v.eqMask(v)} {(v & Simd<16>(8)).eqMask(Simd<16>(8))} {w.gtMask(v)} {v.gtMask(w)}")
	print("{v.lane(0)} {v.lane(15)} {w.lane(3)} {(v + w).lane(10)}")
	out u8[] = zeros(20)
	out.store16(2, w.shuffle(rev.load16(0)))
	print(out)
	acc = Simd<16>(0)
	loop 10:
		acc += v
	print(hex(acc))
	letters = "ACGTacgtACGTacgt"
	lo = letters.bytes().load16(0) & Simd<16>(31)
	print(hex(lo))
	prints """
		0 65535 65280 65535 0
		0 15 7 24
		[0, 0, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 0, 0]
		000a141e28323c46505a646e78828c96
		01030714010307140103071401030714
		"""

# The compiler never fuses `x * y + z` on its own: a program gives the same bits on every processor.
# The types and their instructions come from one table (`compiler/optimize/vecs.zap`, `vecgen.zap`).

# A `tensor.Tensor` (`std/tensor`) holds numbers of any rank, row-major: its `shape` and its
# numbers, on the CPU or on the GPU (`t.gpu()`, `t.toCpu()`; `std/gpu` runs the kernels, Vulkan
# compute without a window). Every operation is Zap: on the CPU loops, on the GPU kernels of the
# module's `.gpu.zap` files built by `compute(...)` (11), the same functions of one number
# (`tensor.activation`, the runtime's `halfValue`) compiled for both. The GPU's tensors stay there until
# read (`toList`, `item`); two tensors on two sides stop the program.

# The math operators take tensors as they take grids (7.10), and are their methods: `a + b`,
# `a - b`, `a * b`, `a / b` number by number (`add`, `sub`, `mul`, `div`; a shape that is a suffix
# of the other's repeats over its leading dimensions), `a @ b` the product of matrices (`matmul`:
# `[..., m, k] @ [k, n]`, or two batches `[b, m, k] @ [b, k, n]`), with a number `a * k`, `k * a`
# (`scaled`), `a / k` (`divided`), `k / a` (`dividing`), `a + k`, `k + a` (`shifted`), `a - k`
# (`subtracted`), `k - a` (`subtractedFrom`), and `-a` (`neg`). Anything else is
# OperatorUndefined.

test "the operators on tensors, a bias repeated over a batch":
	x = tensor.fromList([2, 3], [1.0, 2.0, 3.0, 4.0, 5.0, 6.0])
	w = tensor.fromList([3, 2], [1.0, 0.0, 0.0, 1.0, 1.0, 1.0])
	b = tensor.fromList([2], [0.5, -0.5])
	y = x @ w + b
	print("{y.shape} {y.toList()}")
	expect (2.0 * y - 1.0).relu().toList() == [8, 8, 20, 20]
	prints """
		[2, 2] [4.5, 4.5, 10.5, 10.5]
		"""

# On the GPU a tensor's numbers are f32, or, for weights `linear` reads (x times the transpose of
# w: a layer of a row per output, as GGUF and PyTorch store them), halves (`.F16`, `.BF16`) or
# GGUF's blocks of 32 integers sharing a scale (`.Q8`, `.Q4`): `w.gpu(.Q4)`. The kernels read
# them as the CPU's functions say (the runtime's `halfValue`, `tensor.bfloatValue`), and `toCpu` gives the numbers
# they stand for.
# Blocks multiply their inputs quantized as llama.cpp quantizes them, each 32 as Q8_0
# (`t.blockQuantized()` shows the numbers they read).

test "weights stored as halves and as blocks give their numbers back":
	w = tensor.fromList([1, 32], (0..32).map(f32(it) * 0.25 - 4.0))
	print("{halfValue(halfBits(0.1))} {tensor.bfloatValue(tensor.bfloatBits(0.1))}")
	if gpu.available():
		print(w.gpu(.F16).toCpu().toList() == w.toList())
		x = tensor.full([2, 32], 1.0).gpu()
		print(x.linear(w.gpu(.Q8)).toList().map((it * 100.0).round() / 100.0))
	else:
		print("true")
		print("[-4, -4]")
	prints """
		0.099975586 0.100097656
		true
		[-4, -4]
		"""
