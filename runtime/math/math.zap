# The functions of floats, in Zap: x.sin(), x.cos(), x.tan(), x.atan(), y.atan2(x), the inverse
# and hyperbolic ones and the shader's helpers (fract, sign, step, radians...), built on them and
# on x.exp() and x.ln() (the core's, num.zap: `**` needs them). The polynomials and reductions are fdlibm's (Sun, freely
# usable), accurate to about one unit in the last place for the arguments a program meets
# (sin and cos lose precision past |x| ~ 1e9). Each function has one implementation, in f64: an
# f32's is computed in f64 and rounded once (checkexpr.zap).

# x reduced to r in [-pi/4, pi/4] and its quadrant: x = r + k * pi / 2
fn reduceHalfPi(x f64) (f64, i64):
	k = (x * 0.6366197723675814 + 0.5).floor()   # the nearest whole (floor is one instruction)
	r = ((x - k * 1.57079632673412561417) - k * 6.07710050650619224932e-11) -
		k * 2.02226624879595063154e-21
	(r, i64(k) & 3)

fn kernelSin(r f64) f64:
	z = r * r
	r +
		r * z *
		(
			-1.66666666666666324348e-01 +
				z *
				(
					8.33333333332248946124e-03 +
						z *
						(
							-1.98412698298579493134e-04 +
								z *
								(
									2.75573137070700676789e-06 +
										z *
										(
											-2.50507602534068634195e-08 +
												z * 1.58969099521155010221e-10
										)
								)
						)
				)
		)

fn kernelCos(r f64) f64:
	z = r * r
	1.0 - 0.5 * z +
		z * z *
		(
			4.16666666666666019037e-02 +
				z *
				(
					-1.38888888888741095749e-03 +
						z *
						(
							2.48015872894767294178e-05 +
								z *
								(
									-2.75573143513906633035e-07 +
										z *
										(
											2.08757232129817482790e-09 +
												z * -1.13596475577881948265e-11
										)
								)
						)
				)
		)

# x.sin(): the sine of x radians
pub fn f64Sin(x f64) f64:
	r, q = reduceHalfPi(x)
	if q == 0: kernelSin(r)
	elif q == 1: kernelCos(r)
	elif q == 2: -kernelSin(r)
	else: -kernelCos(r)

# x.cos(): the cosine of x radians
pub fn f64Cos(x f64) f64:
	r, q = reduceHalfPi(x)
	if q == 0: kernelCos(r)
	elif q == 1: -kernelSin(r)
	elif q == 2: -kernelCos(r)
	else: kernelSin(r)

# x.tan(): the tangent of x radians
pub fn f64Tan(x f64) f64:
	r, q = reduceHalfPi(x)
	s = kernelSin(r)
	c = kernelCos(r)
	if q % 2 == 0: s / c
	else: -c / s

# x.atan(): the angle in -pi/2..pi/2 whose tangent is x
pub fn f64Atan(x f64) f64:
	negative = x < 0.0
	a = x.abs()
	id = -1
	if a >= 1e19: return -pi / 2.0 if negative else pi / 2.0
	if a >= 0.4375:
		if a < 1.1875:
			if a < 0.6875:
				id = 0
				a = (2.0 * a - 1.0) / (2.0 + a)
			else:
				id = 1
				a = (a - 1.0) / (a + 1.0)
		elif a < 2.4375:
			id = 2
			a = (a - 1.5) / (1.0 + 1.5 * a)
		else:
			id = 3
			a = -1.0 / a
	z = a * a
	w = z * z
	s1 = z *
		(
			3.33333333333329318027e-01 +
				w *
				(
					1.42857142725034663711e-01 +
						w *
						(
							9.09088713343650656196e-02 +
								w *
								(
									6.66107313738753120669e-02 +
										w *
										(
											4.97687799461593236017e-02 +
												w * 1.62858201153657823623e-02
										)
								)
						)
				)
		)
	s2 = w *
		(
			-1.99999999998764832476e-01 +
				w *
				(
					-1.11111104054623557880e-01 +
						w *
						(
							-7.69187620504482999495e-02 +
								w * (-5.83357013379057348645e-02 + w * -3.65315727442169155270e-02)
						)
				)
		)
	if id < 0:
		v = a - a * (s1 + s2)
		return -v if negative else v
	hi = [
		4.63647609000806093515e-01,
		7.85398163397448278999e-01,
		9.82793723247329054082e-01,
		1.57079632679489655800e+00
	]
	lo = [
		2.26987774529616870924e-17,
		3.06161699786838301793e-17,
		1.39033110312309984516e-17,
		6.12323399573676603587e-17
	]
	v = hi[id] - ((a * (s1 + s2) - lo[id]) - a)
	if negative: -v
	else: v

# y.atan2(x): the angle of the point (x, y) from the x axis, in -pi..pi
pub fn f64Atan2(y f64, x f64) f64:
	if x == 0.0:
		if y > 0.0: return pi / 2.0
		if y < 0.0: return -pi / 2.0
		return 0.0
	a = f64Atan((y / x).abs())
	if x > 0.0: return -a if y < 0.0 else a
	if y < 0.0: a - pi
	else: pi - a

# x.pow(y): x to the power y (as x ** y)
pub fn f64Pow(x f64, y f64) f64:
	x ** y

# x.rem(d): the remainder of x / d, with the sign of x (x % d)
pub fn f64Rem(x f64, d f64) f64:
	x % d

# a.isClose(b, tolerance): whether a and b differ by tolerance at most (an expect of floats, whose
# failure shows both, their difference and the tolerance)
pub fn f64IsClose(a f64, b f64, tolerance f64) bool:
	(a - b).abs() <= tolerance

# a.lerp(b, t): the point t of the way from a to b (a at 0, b at 1)
pub fn f64Lerp(a f64, b f64, t f64) f64:
	a + (b - a) * t

# x.smoothstep(lo, hi): 0 up to lo, 1 from hi, and between them a curve with no jump in slope at
# either end (3t^2 - 2t^3 of the way t from lo to hi)
pub fn f64Smoothstep(x f64, lo f64, hi f64) f64:
	t = (x - lo) / (hi - lo)
	if t < 0.0:
		t = 0.0
	elif t > 1.0:
		t = 1.0
	t * t * (3.0 - 2.0 * t)

# x.fract(): the part above the floor, 0 <= f < 1 (as a shader's fract)
pub fn f64Fract(x f64) f64:
	x - x.floor()

# x.sign(): -1, 0 or 1
pub fn f64Sign(x f64) f64:
	1.0 if x > 0.0 else -1.0 if x < 0.0 else 0.0

# x.step(edge): 0 below the edge, 1 from it on
pub fn f64Step(x f64, edge f64) f64:
	0.0 if x < edge else 1.0

pub fn f64InverseSqrt(x f64) f64:
	1.0 / x.sqrt()

pub fn f64Exp2(x f64) f64:
	2.0 ** x

pub fn f64Log2(x f64) f64:
	f64Ln(x) / 0.6931471805599453

pub fn f64Asin(x f64) f64:
	f64Atan2(x, (1.0 - x * x).sqrt())

pub fn f64Acos(x f64) f64:
	f64Atan2((1.0 - x * x).sqrt(), x)

pub fn f64Sinh(x f64) f64:
	(f64Exp(x) - f64Exp(-x)) * 0.5

pub fn f64Cosh(x f64) f64:
	(f64Exp(x) + f64Exp(-x)) * 0.5

pub fn f64Tanh(x f64) f64:
	if x > 20.0: return 1.0
	if x < -20.0: return -1.0
	e = f64Exp(2.0 * x)
	(e - 1.0) / (e + 1.0)

# x.radians(): degrees to radians; x.degrees() back
pub fn f64Radians(x f64) f64:
	x / 180.0 * pi

pub fn f64Degrees(x f64) f64:
	x / pi * 180.0
