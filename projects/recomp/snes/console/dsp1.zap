# The DSP-1 (DSP-1B) rewritten in Zap from the reading of its firmware (tools/necDis.zap): its
# commands' arithmetic to the bit and their timing to the cycle, so a cartridge carrying it runs
# from its ROM alone. The data ROM's tables are computed (dsp1Rom). The values live in the chip's
# RAM (necRam) at the firmware's addresses, where commands leave them for later ones (Raster reads
# what Parameter wrote). Every command is written: those Super Mario Kart sends here, the rest in
# dsp1Commands.zap.

type Dsp1Part:
	Reset
	Command
	ParameterIn(index i64)
	ParameterLast
	ParameterAzs
	ParameterAzsAgain
	ParameterOut(index i64)
	MultiplyK
	MultiplyL
	TriangleIn
	TriangleRadius
	RotateIn(index i64)
	RotateOut
	DistanceIn(index i64)
	DistanceLast
	ProjectIn(index i64)
	ProjectLast
	RasterIn
	RasterOut(index i64)
	RasterNext
	FastOut
	InverseIn
	InverseExponent
	SquaresIn(index i64)
	GyrateIn(index i64)
	GyrateLast
	PolarIn(index i64)
	PolarLast
	TargetIn
	TargetLast
	AttitudeIn(index i64)
	AttitudeLast
	MatrixIn(index i64)
	ScalarIn(index i64)
	MemoryCheck
	Results(index i64)

mut dPart = Dsp1Part.Reset
mut dA = 0
mut dB = 0
mut dK = 0
mut dL = 0
mut dTR = 0
mut dRom u16[] = []

fn dsp1PowerOn():
	dPart = .Reset
	if dRom.isEmpty: dRom = dsp1Rom()

fn dataRom(at i64):
	i64(dRom[at & 0x3FF])

fn ram(at i64):
	i64(necRam[at & 0xFF])

fn setRam(at i64, v i64):
	necRam[at & 0xFF] = u16.wrap(v)

fn setRams(ats i64[], values i64[]):
	for i, at in ats:
		setRam(at, values[i])

fn asSigned(v i64):
	i64(i16.wrap(v))

# the multiplier's high word (M) and low word (N) of K times L
fn hi(k i64, l i64):
	((asSigned(k) * asSigned(l)) >> 15) & 0xFFFF

fn lo(k i64, l i64):
	((asSigned(k) * asSigned(l)) << 1) & 0xFFFF

fn negate(v i64):
	(-v) & 0xFFFF

fn isNegative(v i64):
	v & 0x8000 != 0

# whether a + b, or a - b, leaves the signed 16-bit range (OV0)
fn overflows(a i64, b i64, subtract bool):
	s = asSigned(a) - asSigned(b) if subtract else asSigned(a) + asSigned(b)
	s < -0x8000 or s > 0x7FFF

fn clamp15(v i64):
	v if v < 0x7FFF else 0x7FFF

# The data ROM: powers of two, reciprocals of 1 + i/128, square roots, sines and cosines of i/128
# of a half turn, arc cosines, the constants the commands load; the rest reads as FFFF.
pub fn dsp1Rom() u16[]:
	out u16[] = zeros(0x400)
	for i in 0..15:
		out[0x22 + i] = 1 << i
	out[0x31] = 0x7FFF
	for i in 0..10:
		out[0x32 + i] = 0x4000 >> i
	for i, v in [0x0001, 0x0008, 0x0004, 0x0002, 0x0001]:
		out[0x3C + i] = u16(v)
	for i, v in [0x8000, 0xFFE5, 0x0100]:
		out[0x62 + i] = u16(v)
	for i in 0..128:
		out[0x65 + i] = u16(clamp15((32_768 * 128 * 2 / (128 + i) + 1) / 2))
	for i in 0..49:
		out[0xE5 + i] = u16(clamp15(i64(32767.0 * (1.0 + i / 16.0).sqrt() / 2.0)))
	out[0x114] = 0x7EFE   # the one entry a unit above the formula's
	for i in 0..128:
		angle = i * pi / 128.0
		out[0x116 + i] = u16.wrap(clamp15(i64(angle.sin() * 32768.0)))
		out[0x196 + i] = u16.wrap(clamp15(i64(angle.cos() * 32768.0)))
	for i, v in [0x6488, 0x0080, 0x03FF, 0x0116, 0x0002, 0x0080]:
		out[0x216 + i] = u16(v)
	for i in 0..257:
		out[0x21C + i] = u16(i64((i / 256.0).acos() * 32768.0 / pi + 0.5))
	constants = [
		0x7FFF, 0x0100, 0x0080, 0x021D, 0x00C8, 0x00CE, 0x0048, 0x0A26, 0x277A, 0x00CE, 0x6488,
		0x14AC, 0x0001, 0x00F9, 0x00FC, 0x00FF, 0x00FC, 0x00F9
	]
	for i, v in constants:
		out[0x31D + i] = u16(v)
	for i in 0x32F..0x400:
		out[i] = 0xFFFF
	out

# The subroutines, each spending the cycles its path through the firmware takes (the CALL that
# reaches it is its caller's).

# x shifted left until its two top bits differ, e lowered by the shifts; zero gives (0, 0)
fn normalize(x i64, e i64):
	if x == 0:
		spend(4)
		return (0, 0)
	v = x
	shifts = 0
	while (v ^ (v << 1)) & 0x8000 == 0:
		v = (v << 1) & 0xFFFF
		shifts += 1
	spend(7 + 2 * shifts)
	(v, (e - shifts) & 0xFFFF)

# normalize with the exponent 15, the routine that loads it first
fn normalize15(x i64):
	spend(1)
	normalize(x, 15)

# The reciprocal of the normalized mantissa x by two steps of Newton's from the table, and the
# exponent 1 - e; zero gives (7FFF, 2F).
fn reciprocal(x i64, e i64):
	if x == 0:
		spend(5)
		return (0x7FFF, 0x2F)
	spend(3)
	negative = isNegative(x)
	m = x
	if negative:
		spend(3)
		m = negate(x)
		if m == 0x8000:
			spend(1)
			m = 0x7FFF
	spend(12)
	r = dataRom(dataRom(0x63) + hi(m, dataRom(0x64)))
	loop 2:
		half = hi((negate(hi(m, r)) - 0x8000) & 0xFFFF, r)
		r = (half * 2) & 0xFFFF
		if overflows(half, half, false):
			spend(1)
			r = 0x7FFF
	spend(7)
	if negative:
		spend(3)
		r = negate(r)
	else:
		spend(2)
	(r, (1 - e) & 0xFFFF)

# The mantissa x times 2 to the e - 15 (both normalized first), saturating.
fn scale(x i64, e i64):
	spend(1)
	v, e2 = normalize(x, e)
	spend(3)
	d = (e2 - 15) & 0xFFFF
	if isNegative(d):
		spend(5)
		return hi(v, dataRom(d + 0x31))
	if d == 0:
		spend(2)
		return v
	spend(5)
	0x8001 if isNegative(v) else 0x7FFF

# The cosine and sine of the angle (a half turn is 8000), from the tables' entry and the slope to
# the next one; -8000 gives (8000, 0).
fn cosSin(angle i64):
	spend(2)
	x = angle
	negative = isNegative(angle)
	if negative:
		spend(3)
		x = negate(angle)
		if x == 0x8000:
			spend(1)
			return (0x8000, 0)
	spend(15)
	index = hi(x, dataRom(0x21B))
	delta = hi(dataRom(0x218) & lo(x, dataRom(0x21A)), dataRom(0x216))
	s = dataRom(dataRom(0x219) + index)
	c = dataRom(dataRom(0x219) + index + dataRom(0x217))
	toS = hi(delta, s)
	a = (c - toS) & 0xFFFF
	if overflows(c, toS, true):
		spend(1)
		a = 0x8001
	spend(3)
	toC = hi(delta, c)
	b = (s + toC) & 0xFFFF
	if overflows(s, toC, false):
		spend(1)
		b = 0x7FFF
	spend(1)
	if negative:
		spend(2)
		b = negate(b)
	else:
		spend(1)
	(a, b)

# -s, saturating where s is -8000
fn minus(s i64):
	if s == 0x8000:
		spend(1)
		return 0x7FFF
	negate(s)

# The rotation by the angle about the first axis, its rows at RAM 7F-7D, 6F-6D, 5F-5D.
fn rotateX(angle i64):
	setRam(0, 0x7F)
	spend(3)
	c, s = cosSin(angle)
	spend(4)
	ms = minus(s)
	spend(9)
	setRams(
		[0x7F, 0x7E, 0x7D, 0x6F, 0x6E, 0x6D, 0x5F, 0x5E, 0x5D],
		[c, ms, 0, s, c, 0, 0, 0, 0x7FFF]
	)
	dB = s

# The rotation by the angle about the third axis, its columns at RAM 76-74, 66-64, 56-54.
fn rotateZ(angle i64):
	for at in [0x75, 0x74, 0x66, 0x56]:
		setRam(at, 0)
	setRam(0x76, 0x7FFF)
	setRam(0, 0x65)
	spend(11)
	c, s = cosSin(angle)
	spend(4)
	ms = minus(s)
	spend(3)
	setRams([0x65, 0x64, 0x55, 0x54], [c, s, ms, c])
	dB = s

# The parts.

fn dsp1Part():
	match dPart.copy():   # a copy: a part sets the next while its own is matched
		Reset: resetPart()
		Command: commandPart()
		ParameterIn(index): parameterIn(index)
		ParameterLast: parameterLast()
		ParameterAzs: parameterAzs()
		ParameterAzsAgain: parameterAzsAgain()
		ParameterOut(index): parameterOut(index)
		MultiplyK: multiplyK()
		MultiplyL: multiplyL()
		TriangleIn: triangleIn()
		TriangleRadius: triangleRadius()
		RotateIn(index): rotateIn(index)
		RotateOut: rotateOut()
		DistanceIn(index): distanceIn(index)
		DistanceLast: distanceLast()
		ProjectIn(index): projectIn(index)
		ProjectLast: projectLast()
		RasterIn: rasterIn()
		RasterOut(index): rasterOut(index)
		RasterNext: rasterNext()
		FastOut: fastOut()
		InverseIn: inverseIn()
		InverseExponent: inverseExponent()
		SquaresIn(index): squaresIn(index)
		GyrateIn(index): gyrateIn(index)
		GyrateLast: gyrateLast()
		PolarIn(index): polarIn(index)
		PolarLast: polarLast()
		TargetIn: targetIn()
		TargetLast: targetLast()
		AttitudeIn(index): attitudeIn(index)
		AttitudeLast: attitudeLast()
		MatrixIn(index): matrixIn(index)
		ScalarIn(index): scalarIn(index)
		MemoryCheck: memoryCheck()
		Results(index): resultOut(index)

fn waitFor(next Dsp1Part):
	dPart = next
	waitRqm()

# the firmware's start: DR holds 80 for the 65816 and a command byte (8-bit transfers) is awaited
fn resetPart():
	srOut(0x0400)
	drOut(0x0080)
	spend(1)
	dB = 0xC0
	waitFor(.Command)

fn commandPart():
	command = drIn()
	spend(1)
	if command & 0xC0 != 0:
		spend(1)
		dB = 0xC0
		waitFor(.Command)
		return
	srOut(0)
	entry, tests, shifts = commandEntry(command)
	dA = (asSigned(command) >> shifts) & 0xFFFF
	spend(tests)
	match entry:
		0x1AC: waitFor(.MultiplyK)
		0x1B3: waitFor(.InverseIn)
		0x1BD: waitFor(.DistanceIn(0))
		0x1D0: squaresStart(3)
		0x1E1: squaresStart(4)
		0x1F4: waitFor(.TriangleIn)
		0x200:
			spend(1)
			waitFor(.GyrateIn(0))
		0x23F: waitFor(.RotateIn(0))
		0x250: waitFor(.PolarIn(0))
		0x27B:
			spend(1)
			waitFor(.ParameterIn(0))
		0x360:
			spend(1)
			waitFor(.RasterIn)
		0x3A3:
			spend(2)
			waitFor(.ProjectIn(0))
		0x41A: waitFor(.TargetIn)
		0x448: attitudeStart()
		0x489: matrixStart(false)
		0x4A3: matrixStart(true)
		0x4BD: scalarStart()
		0x4CF: memoryFill()
		0x4EA: romDump()
		_: awaitAnswer([0x0101], [1])   # the version

# The firmware's walk over the command's bits, two instructions a bit: the address of the
# command's code, the instructions from the first test to it, and the bits shifted out.
fn commandEntry(command i64):
	b = [0, 1, 2, 3, 4, 5].map((command >> it) & 1)
	if b[0] == 1:
		if b[1] == 0: return (0x448 if b[3] == 0 else 0x489, 7 + b[3], 4)
		if b[2] == 0: return (0x4A3 if b[3] == 0 else 0x4BD, 8 + b[3], 4)
		if b[4] == 1: return (0x4EA, 9, 5)
		return (0x4CF if b[5] == 0 else 0x4F0, 11 + b[5], 6)
	if b[1] == 1:
		if b[2] == 0: return (0x27B if b[3] == 0 else 0x360, 8 + b[3], 4)
		return (0x3A3 if b[3] == 0 else 0x41A, 8 + b[3], 4)
	if b[2] == 1:
		if b[3] == 0: return (0x1F4 if b[4] == 0 else 0x200, 10 + b[4], 5)
		return (0x23F if b[4] == 0 else 0x250, 10 + b[4], 5)
	if b[3] == 0: return (0x1AC if b[4] == 0 else 0x1B3, 10 + b[4], 5)
	if b[4] == 1: return (0x1E1, 10, 5)
	(0x1D0 if b[5] == 0 else 0x1BD, 12 + b[5], 6)

# Parameter: the view's position (Fx, Fy, Fz), the distances to the screen and the eye (Lfe, Les),
# the angles about the first and third axes (Aas, Azs); out the vanishing line's offset (Vof), the
# screen's first line (Vva) and the centre's coordinates (Cx, Cy).
fn parameterIn(index i64):
	match index:
		0:
			setRam(0x3A, drIn())
			waitFor(.ParameterIn(1))
		1:
			setRam(0x2A, drIn())
			waitFor(.ParameterIn(2))
		2:
			setRam(0x1A, drIn())
			spend(1)
			waitFor(.ParameterIn(3))
		3:
			setRam(0xCF, drIn())
			setRam(0x4F, dA)
			spend(1)
			waitFor(.ParameterIn(4))
		4:
			setRam(0xCE, drIn())
			setRam(0x4E, dA)
			spend(2)
			waitFor(.ParameterIn(5))
		_:
			dA = drIn()
			spend(1)
			rotateX(dA)
			spend(1)
			waitFor(.ParameterLast)

fn parameterLast():
	dA = drPeek()
	spend(1)
	rotateZ(dA)
	setRam(0x49, dB)
	spend(103)
	multiplyRotations()
	place()
	spend(1)
	x, e = normalize15(ram(0x9A))
	setRam(0x4C, x)
	setRam(0xCC, e)
	spend(7)
	n, e2 = normalize((0x1200 + e) & 0xFFFF, 0xFFF5)
	spend(1)
	r, er = reciprocal(n, e2)
	spend(1)
	dTR = scale(r, er)
	spend(1)
	dPart = .ParameterAzs
	wakeHere()

# the product of the two rotations, its rows at 7C-7A, 6C-6A, 5C-5A
fn multiplyRotations():
	for row in [0x7F, 0x6F, 0x5F]:
		for column in [0x76, 0x75, 0x74]:
			sum = (hi(ram(column), ram(row)) + hi(ram(column - 0x10), ram(row - 1))) & 0xFFFF
			sum = (sum + hi(ram(column - 0x20), ram(row - 2))) & 0xFFFF
			setRam(row - 3 - (0x76 - column), sum)

# Each coordinate F moved by the rotation's third column times Lfe (the low word at F | 80, its
# sign at F) and that less the column times Les (at F + 81 and F + 1).
fn place():
	lfe = ram(0xCF)
	les = ram(0xCE)
	for at in [0x3A, 0x2A, 0x1A]:
		column = ram(at + 0x40)
		near = (ram(at) + hi(column, lfe)) & 0xFFFF
		far = (near - hi(column, les)) & 0xFFFF
		setRam(at + 0x80, near)
		setRam(at, hi(near, 1))
		setRam(at + 0x81, far)
		setRam(at + 1, hi(far, 1))

fn parameterAzs():
	azs = drPeek()
	sign = 0x7FFF if isNegative(azs) else 0x8000
	room = (negate(hi(azs, sign)) - dTR) & 0xFFFF
	dA = negate(hi(dTR, sign))
	spend(5)
	if isNegative(room):
		dPart = .ParameterAzsAgain
		wakeHere()
		return
	dB = ((hi(room, sign) << 2) | 3) & 0xFFFF
	spend(3)
	parameterRest()

fn parameterAzsAgain():
	dA = drPeek()
	dB = 0
	spend(2)
	parameterRest()

fn parameterRest():
	w = dB
	setRam(0x40, w)
	spend(3)
	c, s = cosSin(dA)
	setRam(0x48, c)
	setRam(0xC9, s)
	spend(3)
	reciprocalTo(c, 0, 0x4A)
	q = hi(w, dataRom(0x328))
	t = hi(w, (dataRom(0x327) + hi(w, q)) & 0xFFFF)
	setRam(0x0C, negate(hi(ram(0xCE), t)))
	ww = hi(w, w)
	g = hi(ww, (dataRom(0x325) + hi(ww, dataRom(0x324))) & 0xFFFF)
	h = (c + hi(c, g)) & 0xFFFF
	setRam(0xC8, hi(ram(0xCE), h))
	spend(23)
	reciprocalTo(h, 0, 0x4B)
	spend(3)
	rs, es = reciprocalAfterCall(s, 0xFFF1)
	spend(4)
	n8, e8 = normalize(ram(0xC8), es)
	spend(3)
	dTR = scale(negate(hi(rs, n8)), e8)
	spend(4)
	nz, ez = normalize15(ram(0x9A))
	spend(5)
	dA = scale(hi(ram(0x4A), nz), (ez + ram(0xCA)) & 0xFFFF)
	spend(1)
	drOut(ram(0x0C))
	waitFor(.ParameterOut(1))

# normalize and reciprocal called in turn, the result kept at `at` and its exponent at at | 80
fn reciprocalTo(x i64, e i64, at i64):
	r, er = reciprocalAfterCall(x, e)
	setRam(at, r)
	setRam(at | 0x80, er)
	spend(3)

fn reciprocalAfterCall(x i64, e i64):
	spend(1)
	n, e2 = normalize(x, e)
	spend(1)
	reciprocal(n, e2)

fn parameterOut(index i64):
	match index:
		1:
			drOut(dTR)
			dL = hi(ram(0xC9), dA)
			dA = (hi(ram(0x6F), dL) + ram(0xBA)) & 0xFFFF
			dK = ram(0x7F)
			spend(8)
			waitFor(.ParameterOut(2))
		2:
			drOut(dA)
			setRam(0xB9, dA)
			dA = (negate(hi(dK, dL)) + ram(0xAA)) & 0xFFFF
			spend(3)
			waitFor(.ParameterOut(3))
		_:
			drOut(dA)
			setRam(0xA9, dA)
			spend(2)
			waitFor(.Reset)

# Raster: a screen line in; out the matrix of mode 7 for it (A, B, C, D), then for each line after
# while the 65816 reads them and writes nothing.
fn rasterIn():
	setRam(0x09, drPeek())
	setRam(0x46, dA)
	spend(2)
	rasterLine()

fn rasterLine():
	screenLine = ram(0x09)
	setRam(0x09, (screenLine + 1) & 0xFFFF)
	spend(7)
	n, e = normalize((hi(ram(0x49), screenLine) + ram(0xC8)) & 0xFFFF, 7)
	spend(1)
	r, er = reciprocal(n, e)
	spend(6)
	along = hi(ram(0x4C), r)
	exponent = (er + ram(0xCC)) & 0xFFFF
	p = scale(along, exponent)
	setRam(0x3F, p)
	setRam(0x2F, p)
	spend(9)
	q = scale(hi(ram(0x4B), along), (exponent + ram(0xCB)) & 0xFFFF)
	setRam(0x3E, q)
	setRam(0x2E, q)
	spend(9)
	dB = hi(ram(0x7E), q)
	dA = hi(ram(0x6F), p)
	drOut(hi(ram(0x7F), p))
	spend(1)
	if ram(0x46) & 0x0F != 0:
		srOut(0x0001)
		waitFor(.FastOut)
	else:
		waitFor(.RasterOut(2))

fn rasterOut(index i64):
	match index:
		2:
			drOut(dB)
			spend(1)
			waitFor(.RasterOut(3))
		3:
			drOut(dA)
			dB = hi(ram(0x6E), ram(0x2E))
			spend(1)
			waitFor(.RasterOut(4))
		_:
			drOut(dB)
			waitFor(.RasterNext)

# the 65816 wrote nothing into DR since the last value went out: the next line; else the start
fn rasterNext():
	changed = dB ^ drPeek()
	spend(1)
	if changed == 0:
		rasterLine()
		return
	spend(1)
	resetPart()

# Raster 1A: the line's last three values out a cycle apart, without waiting for the 65816
fn fastOut():
	drOut(dB)
	spend(1)
	drOut(dA)
	spend(1)
	dB = hi(ram(0x6E), ram(0x2E))
	drOut(dB)
	srOut(0)
	dPart = .RasterNext
	wakeHere()

# Multiply: K times L, the high word of their product
fn multiplyK():
	dK = drIn()
	waitFor(.MultiplyL)

fn multiplyL():
	dL = drPeek()
	dA |= hi(dK, dL)
	spend(1)
	drOut(dA)
	dA = 0
	spend(1)
	waitFor(.Reset)

# Triangle: an angle and a radius; out the radius times its sine and times its cosine.
fn triangleIn():
	angle = drIn()
	spend(1)
	c, s = cosSin(angle)
	dA = c
	dK = s
	spend(1)
	waitFor(.TriangleRadius)

fn triangleRadius():
	radius = drPeek()
	spend(1)
	drOut(hi(dK, radius))
	spend(1)
	awaitAnswer([hi(dA, radius)], [1])

# Rotate: an angle and a point (X, Y); out the point turned by the angle.
fn rotateIn(index i64):
	if index == 0:
		dA = drIn()
		spend(1)
		waitFor(.RotateIn(1))
		return
	x = drIn()
	setRam(0x40, x)
	spend(1)
	c, s = cosSin(dA)
	spend(4)
	dTR = c
	dA = hi(x, c)
	dK = x
	dL = s
	waitFor(.RotateOut)

fn rotateOut():
	y = drPeek()
	dA = (dA + hi(y, dL)) & 0xFFFF
	dB = (negate(hi(dK, dL)) + hi(y, dTR)) & 0xFFFF
	spend(1)
	drOut(dA)
	awaitAnswer([dB], [1])

# The 32-bit hi:lo normalized: its mantissa and exponent (31 less the shifts).
fn normalize32(high i64, low i64):
	spend(2)
	if high == 0xFFFF or high == 0:
		spend(4 if high == 0 else 2)
		if isNegative(low) == (high == 0):
			spend(4)
			return (((asSigned(low) >> 1) & 0xFFFF) ^ 0x8000, 0x10)
		spend(2)
		return normalize(low, 15)
	spend(8)
	v, e = normalize(high, 0x40)
	spend(5)
	((v + hi(low >> 1, dataRom(e))) & 0xFFFF, (e - 0x21) & 0xFFFF)

# The square root of the mantissa m with the exponent e (made even first), from the table's entry
# and the slope to the next one.
fn squareRoot(m i64, e i64):
	spend(2)
	x = m
	half = (asSigned(e) >> 1) & 0xFFFF
	if e & 1 != 0:
		spend(2)
		x = (asSigned(m) >> 1) & 0xFFFF
		half = (half + 1) & 0xFFFF
	spend(12)
	fraction = 0x7FC0 & lo(x, 0x20)
	at = (0xD6 + hi(x, 0x40)) & 0xFFFF
	low = dataRom(at - 1)
	((low + hi(fraction, (dataRom(at) - low) & 0xFFFF)) & 0xFFFF, half)

# x with the exponent e as a 32-bit integer (high word, low word), saturating.
fn toInteger(x i64, e i64):
	spend(1)
	v, e2 = normalize(x, e)
	spend(3)
	d = (e2 - 15) & 0xFFFF
	if d == 0:
		spend(2)
		if isNegative(v):
			spend(2)
			return (0xFFFF, v)
		spend(1)
		return (0, v)
	spend(1)
	if isNegative(d):
		spend(6)
		b = hi(v, dataRom(d + 0x31))
		spend(1)
		return (0xFFFF if isNegative(b) else 0, b)
	spend(4)
	high = 0
	if isNegative(v):
		spend(1)
		high = 0xFFFF
	spend(1)
	shiftLeft(high, v, d)

# high:low shifted left by `shift` through the multiplier, saturating.
fn shiftLeft(high i64, low i64, shift i64):
	spend(3)
	if not isNegative(negate(shift)):
		spend(1)
		return (high, low)
	spend(6)
	r = dataRom(0x41 - shift)
	a = hi(high, r)
	if isNegative(a):
		spend(2)
		if a != 0xFFFF:
			spend(2)
			return (0x8001, 0)
		a = lo(high, r)
		spend(2)
		if not isNegative(a):
			spend(2)
			return (0x8001, 0)
	else:
		spend(1)
		if a != 0:
			spend(2)
			return (0x7FFF, 0xFFFF)
		a = lo(high, r)
		spend(2)
		if isNegative(a):
			spend(2)
			return (0x7FFF, 0xFFFF)
	spend(2)
	if isNegative(low):
		spend(2)
		a = (a + 2 * r) & 0xFFFF
	spend(3)
	((a + hi(low, r)) & 0xFFFF, lo(low, r))

# Distance: a vector (X, Y, Z); out its length.
fn distanceIn(index i64):
	v = drIn()
	if index == 0:
		dB = dA
		dA = (dA + hi(v, v)) & 0xFFFF
		dK = v
		spend(2)
		waitFor(.DistanceIn(1))
		return
	dB = (dB + lo(dK, dK)) & 0xFFFF
	dK = v
	spend(2)
	waitFor(.DistanceLast)

fn distanceLast():
	z = drPeek()
	a, b = addWithCarry(dA, dB, hi(dK, dK), lo(dK, dK))
	a, b = addWithCarry(a, b, hi(z, z), lo(z, z))
	spend(4)
	m, e = normalize32(a, b)
	spend(2)
	r, er = squareRoot(m, (e - 1) & 0xFFFF)
	spend(1)
	drOut(scale(r, er))
	spend(1)
	waitFor(.Reset)

# high:low plus addHigh:addLow, the low words' carry into the high ones
fn addWithCarry(high i64, low i64, addHigh i64, addLow i64):
	sum = low + addLow
	((high + addHigh + (sum >> 16)) & 0xFFFF, sum & 0xFFFF)

# Project: a point (X, Y, Z) of the field; out where it shows on the screen (H, V) and its
# scale (M), as the last Parameter set the view.
fn projectIn(index i64):
	v = drIn()
	at = 0xBC if index == 0 else 0xAC
	setRam(at, v)
	setRam(at & 0x7F, dA | hi(v, 1))
	dA = 0
	spend(2)
	waitFor(.ProjectIn(1) if index == 0 else .ProjectLast)

fn projectLast():
	z = drPeek()
	setRam(0x9C, z)
	setRam(0x1C, hi(z, 1))
	spend(2)
	for i, at in [0x3C, 0x2C, 0x1C]:
		spend(4 if i == 0 else 5)
		low = ram(at | 0x80) - ram((at - 1) | 0x80)
		borrow = 1 if low < 0 else 0
		spend(1)
		m, e = normalize32((ram(at) - ram(at - 1) - borrow) & 0xFFFF, low & 0xFFFF)
		spend(4)
		setRam(0x76 - i, (asSigned(m) >> 1) & 0xFFFF)
		setRam(0xF6 - i, (e + 1) & 0xFFFF)
	spend(3)
	alignExponents()
	spend(12)
	for at in [0xF3, 0xF2, 0xF1]:
		setRam(at, ram(0xF6))
	for row in [0x7C, 0x7B, 0x7A]:
		sum = (hi(ram(row), ram(0x76)) + hi(ram(row - 0x10), ram(0x75))) & 0xFFFF
		setRam(row - 9, (sum + hi(ram(row - 0x20), ram(0x74))) & 0xFFFF)
	spend(21)
	high, low = toInteger(negate(ram(0x71)), ram(0xF1))
	spend(4)
	sum = low + ram(0xCE)
	carried = sum >> 16
	high2 = (high + ram(0x4E) + carried) & 0xFFFF
	wide = asSigned(high) + asSigned(ram(0x4E)) + carried
	if wide < -0x8000 or wide > 0x7FFF:
		spend(1)
		high2 = 0x7FFF if isNegative(high2) else 0x8000
	spend(1)
	m, e = normalize32(high2, sum & 0xFFFF)
	spend(1)
	r, er = reciprocal(m, e)
	setRam(0x71, r)
	setRam(0xF1, er)
	spend(6)
	n, e2 = normalize15(ram(0xCE))
	t = hi(r, n)
	exponent = (e2 + er) & 0xFFFF
	spend(8)
	setRam(0x71, scale(t, (8 + exponent) & 0xFFFF))
	spend(6)
	setRam(0x72, scale(hi(ram(0x72), t), (exponent + ram(0xF2)) & 0xFFFF))
	spend(6)
	drOut(scale(hi(ram(0x73), t), (exponent + ram(0xF3)) & 0xFFFF))
	spend(1)
	awaitAnswer([ram(0x72), ram(0x71)], [0, 1])

# The three exponents at F6-F4 made the largest of them, each value at 76-74 shifted right to match.
fn alignExponents():
	e6 = ram(0xF6)
	e5 = ram(0xF5)
	e4 = ram(0xF4)
	spend(4)
	top = e6
	if isNegative((e6 - e5) & 0xFFFF):
		top = e4 if isNegative((e5 - e4) & 0xFFFF) else e5
		spend(5)
	elif isNegative((e6 - e4) & 0xFFFF):
		top = e4
		spend(6)
	else:
		spend(5)
	spend(18)
	for at in [0x76, 0x75, 0x74]:
		setRam(at, hi(ram(at), dataRom(0x31 + top - ram(at | 0x80))))
		setRam(at | 0x80, top)
