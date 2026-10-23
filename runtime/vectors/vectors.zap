# The vectors and matrices of the language, the same on the CPU and in a shader: Vec2..Vec4 of
# f32, IVec2 and IVec3 of i32 (a texture's size), and Mat2..Mat4, column-major (m[col * n + row]),
# laid out as a shader reads them. A vector is a
# struct of numbers, so it has what every such struct has: + - * / field by field and with a
# number on either side, -v, the number methods field by field (floor, min, clamp, lerp...),
# a @ b (the dot product), length, distance, normalized, reflect, and swizzles (v.xy, c.rgb); its
# letters may also be written r g b a or s t p q. A matrix has + - * / element by element too;
# m @ o and m @ v are its products. Below are what one size has alone, and the products.

pub type Vec2:
	x f32
	y f32

	# whether each field of the two differs by tolerance at most (as a float's isClose)
	fn isClose(o Vec2, tolerance f32) bool:
		(x - o.x).abs() <= tolerance and (y - o.y).abs() <= tolerance

	# a Vec3 of this and z
	fn withZ(z f32) Vec3:
		Vec3(x, y, z)

pub type Vec3:
	x f32
	y f32
	z f32

	fn isClose(o Vec3, tolerance f32) bool:
		Vec2(x, y).isClose(Vec2(o.x, o.y), tolerance) and (z - o.z).abs() <= tolerance

	# the direction square to both, its length the area they span (right-handed)
	fn cross(o Vec3) Vec3:
		Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)

	# a Vec4 of this and w (a point's w is 1, a direction's 0)
	fn withW(w f32) Vec4:
		Vec4(x, y, z, w)

	# this (length 1) bent through the surface of normal n going into a medium `eta` times as
	# dense; zero when it is wholly reflected
	fn refract(n Vec3, eta f32) Vec3:
		d = n @ self
		k = 1.0 - eta * eta * (1.0 - d * d)
		Vec3(0.0, 0.0, 0.0) if k < 0.0 else self * eta - n * (eta * d + k.sqrt())

pub type Vec4:
	x f32
	y f32
	z f32
	w f32

	fn isClose(o Vec4, tolerance f32) bool:
		Vec3(x, y, z).isClose(Vec3(o.x, o.y, o.z), tolerance) and (w - o.w).abs() <= tolerance

pub type IVec2:
	x i32
	y i32

pub type IVec3:
	x i32
	y i32
	z i32

pub type Mat2:
	m f32[4]

	# whether each element of the two differs by tolerance at most
	fn isClose(o Mat2, tolerance f32) bool:
		lanesClose(m, o.m, tolerance)

	fn transpose() Mat2:
		Mat2([m[0], m[2], m[1], m[3]])

pub type Mat3:
	m f32[9]

	fn isClose(o Mat3, tolerance f32) bool:
		lanesClose(m, o.m, tolerance)

	fn transpose() Mat3:
		Mat3([m[0], m[3], m[6], m[1], m[4], m[7], m[2], m[5], m[8]])

	# negative when the matrix mirrors (its triangles' winding turns round)
	fn determinant() f32:
		m[0] * (m[4] * m[8] - m[7] * m[5]) - m[3] * (m[1] * m[8] - m[7] * m[2]) +
			m[6] * (m[1] * m[5] - m[4] * m[2])

	# the identity when there is none (the determinant 0)
	fn inverse() Mat3:
		d = determinant()
		if d == 0.0: return Mat3(1.0)
		k = 1.0 / d
		Mat3(
			[
				(m[4] * m[8] - m[7] * m[5]) * k,
				(m[7] * m[2] - m[1] * m[8]) * k,
				(m[1] * m[5] - m[4] * m[2]) * k,
				(m[6] * m[5] - m[3] * m[8]) * k,
				(m[0] * m[8] - m[6] * m[2]) * k,
				(m[3] * m[2] - m[0] * m[5]) * k,
				(m[3] * m[7] - m[6] * m[4]) * k,
				(m[6] * m[1] - m[0] * m[7]) * k,
				(m[0] * m[4] - m[3] * m[1]) * k
			]
		)

pub type Mat4:
	m f32[16]

	fn isClose(o Mat4, tolerance f32) bool:
		lanesClose(m, o.m, tolerance)

	fn transpose() Mat4:
		r f32[16]
		for col in 0..4:
			for row in 0..4:
				r[row * 4 + col] = m[col * 4 + row]
		Mat4(r)

	# the point p moved by this matrix and divided by its w (where a projection puts it, -1..1)
	fn project(p Vec3) Vec3:
		w = m[3] * p.x + m[7] * p.y + m[11] * p.z + m[15]
		applyPoint(p) / w

	# the point p moved by this matrix (w 1, the result not divided: an affine matrix's); a Vec2 p is a
	# point of the plane, z 0, and gives a Vec2
	fn applyPoint(p Vec3) Vec3:
		Vec3(
			m[0] * p.x + m[4] * p.y + m[8] * p.z + m[12],
			m[1] * p.x + m[5] * p.y + m[9] * p.z + m[13],
			m[2] * p.x + m[6] * p.y + m[10] * p.z + m[14]
		)

	# the direction d turned and scaled by this matrix, not moved
	fn applyDirection(d Vec3) Vec3:
		Vec3(
			m[0] * d.x + m[4] * d.y + m[8] * d.z,
			m[1] * d.x + m[5] * d.y + m[9] * d.z,
			m[2] * d.x + m[6] * d.y + m[10] * d.z
		)

	# the determinant of the 3 x 3 part
	fn determinant3() f32:
		Mat3(self).determinant()

	# The inverse of an affine matrix (a 3 x 3 part and a move, the last row 0 0 0 1); the
	# identity when the 3 x 3 part has none (its determinant 0).
	fn inverseAffine() Mat4:
		part = Mat3(self)
		if part.determinant() == 0.0: return Mat4(1.0)
		inv = Mat4(part.inverse())
		t = inv.applyDirection(Vec3(m[12], m[13], m[14]))
		r = inv.m
		r[12] = -t.x
		r[13] = -t.y
		r[14] = -t.z
		Mat4(r)

# A turn: the unit quaternion x y z w (glTF's order), a vec4 in a shader. q @ r is the turn r
# then q (their product); + - * / work field by field as on a vector.
pub type Quat:
	x f32
	y f32
	z f32
	w f32

	fn isClose(o Quat, tolerance f32) bool:
		Vec4(x, y, z, w).isClose(Vec4(o.x, o.y, o.z, o.w), tolerance)

fn lanesClose<N n64>(a f32[N], b f32[N], tolerance f32) bool:
	for i in 0..N:
		if (a[i] - b[i]).abs() > tolerance: return false
	true

# Vec2(xs, at = 0), Vec3, Vec4, Quat (the checker calls these): the numbers of a list of floats
# from `at` on, in the fields' order (a mesh's floats, a file's)
fn vec2Of(xs f32[], at i64 = 0) Vec2:
	Vec2(xs[at], xs[at + 1])

fn vec3Of(xs f32[], at i64 = 0) Vec3:
	Vec3(xs[at], xs[at + 1], xs[at + 2])

fn vec4Of(xs f32[], at i64 = 0) Vec4:
	Vec4(xs[at], xs[at + 1], xs[at + 2], xs[at + 3])

fn quatOf(xs f32[], at i64 = 0) Quat:
	Quat(xs[at], xs[at + 1], xs[at + 2], xs[at + 3])

# t.applyPoint(p) of a point of the plane: p moved by t (z 0, w 1)
fn mat4ApplyPoint2(t Mat4, p Vec2) Vec2:
	Vec2(t.m[0] * p.x + t.m[4] * p.y + t.m[12], t.m[1] * p.x + t.m[5] * p.y + t.m[13])

# ---------- the products, a @ o and a @ v (the checker calls these) ----------

fn mat2TimesMat(a Mat2, o Mat2) Mat2:
	Mat2(
		[
			a.m[0] * o.m[0] + a.m[2] * o.m[1],
			a.m[1] * o.m[0] + a.m[3] * o.m[1],
			a.m[0] * o.m[2] + a.m[2] * o.m[3],
			a.m[1] * o.m[2] + a.m[3] * o.m[3]
		]
	)

# a @ b of fixed arrays of numbers, the shapes met (the checker's arrayProduct)
fn arrayDot<N n64, T Num>(a T[N], b T[N]) T:
	s = a[0] * b[0]
	for i in 1..N:
		s += a[i] * b[i]
	s

fn arrayTimesVector<R n64, K n64, T Num>(a T[R, K], v T[K]) T[R]:
	out T[R]
	for r in 0..R:
		out[r] = arrayDot(a[r], v)
	out

fn arrayTimesArray<R n64, K n64, C n64, T Num>(a T[R, K], b T[K, C]) T[R, C]:
	out T[R, C]
	for r in 0..R:
		for c in 0..C:
			s = a[r][0] * b[0][c]
			for k in 1..K:
				s += a[r][k] * b[k][c]
			out[r][c] = s
	out

fn mat2TimesVec(a Mat2, v Vec2) Vec2:
	Vec2(a.m[0] * v.x + a.m[2] * v.y, a.m[1] * v.x + a.m[3] * v.y)

fn mat3TimesMat(a Mat3, o Mat3) Mat3:
	r f32[9]
	for col in 0..3:
		for row in 0..3:
			r[col * 3 + row] = a.m[row] * o.m[col * 3] + a.m[3 + row] * o.m[col * 3 + 1] +
				a.m[6 + row] * o.m[col * 3 + 2]
	Mat3(r)

fn mat3TimesVec(a Mat3, v Vec3) Vec3:
	Vec3(
		a.m[0] * v.x + a.m[3] * v.y + a.m[6] * v.z,
		a.m[1] * v.x + a.m[4] * v.y + a.m[7] * v.z,
		a.m[2] * v.x + a.m[5] * v.y + a.m[8] * v.z
	)

fn mat4TimesMat(a Mat4, o Mat4) Mat4:
	r f32[16]
	for col in 0..4:
		o0, o1, o2, o3 = o.m[col * 4], o.m[col * 4 + 1], o.m[col * 4 + 2], o.m[col * 4 + 3]
		for row in 0..4:
			r[col * 4 + row] = a.m[row] * o0 + a.m[4 + row] * o1 + a.m[8 + row] * o2 +
				a.m[12 + row] * o3
	Mat4(r)

fn mat4TimesVec(a Mat4, v Vec4) Vec4:
	Vec4(
		a.m[0] * v.x + a.m[4] * v.y + a.m[8] * v.z + a.m[12] * v.w,
		a.m[1] * v.x + a.m[5] * v.y + a.m[9] * v.z + a.m[13] * v.w,
		a.m[2] * v.x + a.m[6] * v.y + a.m[10] * v.z + a.m[14] * v.w, a.m[3] * v.x + a.m[7] * v.y +
			a.m[11] * v.z + a.m[15] * v.w)

fn quatTimesQuat(a Quat, b Quat) Quat:
	Quat(
		a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
		a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
		a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
		a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z
	)

# ---------- matrices made as a shader makes them (the checker calls these) ----------

fn mat2Columns(c0 Vec2, c1 Vec2) Mat2:
	Mat2([c0.x, c0.y, c1.x, c1.y])

fn mat3Columns(c0 Vec3, c1 Vec3, c2 Vec3) Mat3:
	Mat3([c0.x, c0.y, c0.z, c1.x, c1.y, c1.z, c2.x, c2.y, c2.z])

fn mat4Columns(c0 Vec4, c1 Vec4, c2 Vec4, c3 Vec4) Mat4:
	Mat4(
		[
			c0.x,
			c0.y,
			c0.z,
			c0.w,
			c1.x,
			c1.y,
			c1.z,
			c1.w,
			c2.x,
			c2.y,
			c2.z,
			c2.w,
			c3.x,
			c3.y,
			c3.z,
			c3.w
		]
	)

fn mat2Diagonal(k f32) Mat2:
	Mat2([k, 0.0, 0.0, k])

fn mat3Diagonal(k f32) Mat3:
	Mat3([k, 0.0, 0.0, 0.0, k, 0.0, 0.0, 0.0, k])

fn mat4Diagonal(k f32) Mat4:
	Mat4([k, 0.0, 0.0, 0.0, 0.0, k, 0.0, 0.0, 0.0, 0.0, k, 0.0, 0.0, 0.0, 0.0, k])

# a matrix of another size: its upper left corner, the rest of the identity
fn mat2OfMat3(o Mat3) Mat2:
	Mat2([o.m[0], o.m[1], o.m[3], o.m[4]])

fn mat2OfMat4(o Mat4) Mat2:
	Mat2([o.m[0], o.m[1], o.m[4], o.m[5]])

fn mat3OfMat2(o Mat2) Mat3:
	Mat3([o.m[0], o.m[1], 0.0, o.m[2], o.m[3], 0.0, 0.0, 0.0, 1.0])

fn mat3OfMat4(o Mat4) Mat3:
	Mat3([o.m[0], o.m[1], o.m[2], o.m[4], o.m[5], o.m[6], o.m[8], o.m[9], o.m[10]])

fn mat4OfMat2(o Mat2) Mat4:
	Mat4(
		[o.m[0], o.m[1], 0.0, 0.0, o.m[2], o.m[3], 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0]
	)

fn mat4OfMat3(o Mat3) Mat4:
	Mat4(
		[
			o.m[0],
			o.m[1],
			o.m[2],
			0.0,
			o.m[3],
			o.m[4],
			o.m[5],
			0.0,
			o.m[6],
			o.m[7],
			o.m[8],
			0.0,
			0.0,
			0.0,
			0.0,
			1.0
		]
	)
