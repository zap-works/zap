# The DSP-1's commands past those Super Mario Kart sends (dsp1.zap has the parts' dispatch and the
# firmware's subroutines): Inverse, Radius, Range, Gyrate, Polar, Target, the attitude matrices
# and what reads them, the memory test, the data ROM's dump and the version.

mut dResults i64[] = []
mut dGaps i64[] = []
mut dWide = 0          # a 32-bit sum, the high word in B and the low in A
mut dSquares = 0
mut dDp = 0            # the RAM address an attitude matrix is laid out from
mut dTransposed = false

# The values out one at a time, each followed by the instructions to the next wait.
fn answer(move values i64[], move gaps i64[]):
	dResults = values
	dGaps = gaps
	resultOut(0)

fn awaitAnswer(move values i64[], move gaps i64[]):
	dResults = values
	dGaps = gaps
	waitFor(.Results(0))

fn resultOut(index i64):
	drOut(dResults[index])
	spend(dGaps[index])
	waitFor(.Results(index + 1) if index + 1 < dResults.len else .Reset)

# K times L as the multiplier's 32-bit M:N
fn wide(k i64, l i64):
	((asSigned(k) * asSigned(l)) << 1) & 0xFFFF_FFFF

# the RAM address `offset` words along and `flip` rows across from d, as DPL and DPH step it
fn cell(d i64, offset i64, flip i64):
	((d & 0xF0) ^ (flip << 4)) | ((d + offset) & 0x0F)

# Inverse: a mantissa and an exponent; out the reciprocal's.
fn inverseIn():
	dA = drIn()
	waitFor(.InverseExponent)

fn inverseExponent():
	r, er = reciprocalAfterCall(dA, drPeek())
	drOut(r)
	awaitAnswer([er], [1])

# Radius (three words) and Range (four, the last's square taken away): the sum of their squares,
# Radius out its low and high words, Range its high word.
fn squaresStart(count i64):
	dSquares = count
	dWide = (dA << 16) | dA
	waitFor(.SquaresIn(0))

fn squaresIn(index i64):
	last = index == dSquares - 1
	v = drPeek() if last else drIn()
	square = wide(v, v)
	dWide = (dWide - square if last and dSquares == 4 else dWide + square) & 0xFFFF_FFFF
	if not last:
		spend(2)
		waitFor(.SquaresIn(index + 1))
		return
	spend(3)
	if dSquares == 4:
		answer([dWide >> 16], [1])
	else:
		answer([dWide & 0xFFFF, dWide >> 16], [0, 1])

# Gyrate: the angles about the third, first and second axes, the turn rates U, F and L; out the
# angles turned.
fn gyrateIn(index i64):
	match index:
		0: setRam(0xF0, drIn())
		1:
			v = drIn()
			dA |= v
			setRam(0xE0, v)
		2: setRam(0xD0, drIn())
		3: setRam(0x41, drIn())
		_:
			setRam(0x42, drIn())
			gyrateTurn()
			return
	waitFor(.GyrateIn(index + 1))

fn gyrateTurn():
	spend(1)
	c, s = cosSin(dA)
	setRam(0x00, s)
	spend(2)
	r, er = reciprocalAfterCall(c, 0x10)
	setRam(0x40, r)
	setRam(0x00, er)
	spend(4)
	n, e = normalize(s, er)
	setRam(0x10, e)
	setRam(0x50, hi(r, n))
	spend(5)
	c2, s2 = cosSin(ram(0xD0))
	u = ram(0x41)
	f = ram(0x42)
	setRam(0xE0, (hi(u, s2) + hi(f, c2) + ram(0xE0)) & 0xFFFF)
	sum = (wide(u, c2) + wide(f, s2)) & 0xFFFF_FFFF
	difference = (wide(u, c2) - wide(f, s2)) & 0xFFFF_FFFF
	setRam(0x02, lo(u, c2))
	setRam(0x01, sum & 0xFFFF)
	spend(15)
	m, em = normalize32(difference >> 16, difference & 0xFFFF)
	spend(4)
	setRam(0xF0, (ram(0xF0) + scale(hi(r, m), (em + er) & 0xFFFF)) & 0xFFFF)
	spend(5)
	m2, em2 = normalize32(sum >> 16, sum & 0xFFFF)
	spend(4)
	dA = scale(negate(hi(ram(0x50), m2)), (em2 + ram(0x10)) & 0xFFFF)
	waitFor(.GyrateLast)

fn gyrateLast():
	second = (dA + drPeek() + ram(0xD0)) & 0xFFFF
	drOut(ram(0xF0))
	setRam(0xD0, second)
	awaitAnswer([ram(0xE0), second], [2, 1])

# Polar: the angles about the third, second and first axes and a point (X, Y, Z); out the point
# turned by each in turn.
fn polarIn(index i64):
	match index:
		0:
			dA = drIn()
			spend(1)
		1: setRam(0x42, drIn())
		2: setRam(0x43, drIn())
		3: setRam(0x40, drIn())
		_:
			setRam(0x41, drIn())
			spend(1)
			c, s = cosSin(dA)
			x = ram(0x40)
			y = ram(0x41)
			setRam(0x40, hi(x, c) + hi(y, s))
			setRam(0x41, hi(y, c) - hi(x, s))
			spend(9)
			dK, dL = cosSin(ram(0x42))
			spend(2)
			waitFor(.PolarLast)
			return
	waitFor(.PolarIn(index + 1))

fn polarLast():
	z = drPeek()
	x = ram(0x40)
	setRam(0x40, hi(x, dK) - hi(z, dL))
	setRam(0x42, hi(z, dK) + hi(x, dL))
	spend(7)
	c, s = cosSin(ram(0x43))
	spend(1)
	drOut(ram(0x40))
	y = ram(0x41)
	z2 = ram(0x42)
	spend(4)
	awaitAnswer([(hi(y, c) + hi(z2, s)) & 0xFFFF, (hi(z2, c) - hi(y, s)) & 0xFFFF], [0, 1])

# Target: a point of the screen (H, V); out the point of the field it shows, as the last Parameter
# set the view.
fn targetIn():
	dL = drIn()
	spend(2)
	waitFor(.TargetLast)

fn targetLast():
	v = drPeek()
	setRam(0x08, (dA + lo(0x80, dL)) & 0xFFFF)
	setRam(0x09, lo(0x80, v))
	spend(6)
	r, er = reciprocalAfterCall((hi(ram(0x49), v) + ram(0xC8)) & 0xFFFF, 8)
	spend(6)
	along = hi(ram(0x4C), r)
	exponent = (er + ram(0xCC)) & 0xFFFF
	s1 = scale(along, exponent)
	spend(6)
	s2 = scale(hi(ram(0x4A), along), (exponent + ram(0xCA)) & 0xFFFF)
	spend(14)
	t1 = hi(ram(0x08), s1)
	t2 = hi(ram(0x09), s2)
	drOut((ram(0xB9) + hi(ram(0x7F), t1) + hi(ram(0x7E), t2)) & 0xFFFF)
	spend(2)
	awaitAnswer([(ram(0xA9) - hi(ram(0x6F), t1) + hi(ram(0x6E), t2)) & 0xFFFF], [1])

# Attitude (01, 05): a scale and the angles about the third, second and first axes; the matrix of
# the three turns times the scale laid out from the RAM address the command's high bits pick.
fn attitudeStart():
	dDp = dataRom(0x32C - dA)
	spend(4)
	waitFor(.AttitudeIn(0))

fn attitudeIn(index i64):
	d = dDp
	match index:
		0:
			dB = (asSigned(drIn()) >> 1) & 0xFFFF
			setRam(cell(d, 0, 0), dB)
			spend(2)
			waitFor(.AttitudeIn(1))
		1:
			dA = drIn()
			setRam(cell(d, -2, 0), dB)
			setRam(cell(d, -1, 1), dB)
			spend(2)
			waitFor(.AttitudeIn(2))
		_:
			setRam(cell(d, 0, 2), drIn())
			setRam((d & 0xF0) ^ 0xF0, d)
			spend(2)
			c, s = cosSin(dA)
			dK = ram(cell(d, 0, 0) | 0x40)
			dL = c
			setRam(cell(d, -1, 0), hi(dK, s))
			spend(4)
			waitFor(.AttitudeLast)

# the firmware's reads and writes of the matrix in its order, the cells shared by the turns
fn attitudeLast():
	d = dDp
	c, s = cosSin(attitudeSecond(d))
	k1 = ram(cell(d, 0, 0) | 0x40)
	k2 = ram(cell(d, -1, 0))
	setRam(cell(d, 0, 0), hi(k1, c))
	setRam(cell(d, -1, 0), negate(hi(k2, c)))
	k3 = ram(cell(d, -2, 1))
	k4 = ram(cell(d, -2, 2))
	setRam(cell(d, -2, 1), negate(hi(k3, c)))
	k5 = ram(cell(d, -2, 0) | 0x40)
	setRam(cell(d, -2, 2), hi(k4, c))
	setRam(cell(d, -2, 0), hi(k5, s))
	k6 = ram(cell(d, -1, 2))
	k7 = ram(cell(d, 0, 1))
	setRam(cell(d, -1, 2), hi(k6, s) + k7)
	setRam(cell(d, 0, 1), k6 + hi(k7, s))
	k8 = ram(cell(d, -1, 1))
	k9 = ram(cell(d, 0, 2))
	setRam(cell(d, -1, 1), k9 - hi(k8, s))
	setRam(cell(d, 0, 2), k8 - hi(k9, s))
	spend(25)
	resetPart()

# the turn about the second axis; the third angle, kept in RAM, back
fn attitudeSecond(d i64):
	ax = drPeek()
	setRam(cell(d, 0, 0), hi(dK, dL))
	spend(2)
	c, s = cosSin(ax)
	k1 = ram(cell(d, 0, 0) | 0x40)
	k2 = ram(cell(d, -1, 0))
	setRam(cell(d, 0, 1), hi(k1, s))
	k3 = ram(cell(d, -1, 1))
	setRam(cell(d, -1, 1), hi(k2, s))
	setRam(cell(d, -2, 1), hi(k3, s))
	k4 = ram(cell(d, -1, 0))
	setRam(cell(d, -2, 2), hi(k3, c))
	k5 = ram(cell(d, 0, 0))
	setRam(cell(d, -1, 2), hi(k4, c))
	third = ram(cell(d, 0, 2))
	setRam(cell(d, 0, 2), hi(k5, c))
	spend(16)
	third

# Objective (09, 0D) and Subjective (03): a vector times the attitude matrix, or its transpose.
fn matrixStart(transposed bool):
	dTransposed = transposed
	dDp = dataRom(0x32C - dA)
	spend(3)
	waitFor(.MatrixIn(0))

fn matrixIn(index i64):
	match index:
		0:
			dA = drIn()
			spend(2)
		1:
			dTR = drIn()
			spend(1)
		_:
			matrixLast()
			return
	waitFor(.MatrixIn(index + 1))

fn matrixLast():
	v = [dA, dTR, drPeek()]
	out = [0, 0, 0]
	for row in 0..3:
		for j in 0..3:
			at = cell(dDp, -row, j) if dTransposed else cell(dDp, -j, row)
			loaded = (row == 1 and j == 2) or (row == 2 and j == 0)   # read without DP | 40
			out[row] = (out[row] + hi(ram(at if loaded else at | 0x40), v[j])) & 0xFFFF
	spend(2)
	drOut(out[0])
	spend(3)
	awaitAnswer([out[1], out[2]], [3, 1])

# Scalar (0B): a vector times the attitude matrix's first row, the 32-bit sum's high word out.
fn scalarStart():
	dDp = dataRom(0x32C + dA)
	dWide = 0
	spend(4)
	waitFor(.ScalarIn(0))

fn scalarIn(index i64):
	v = drPeek() if index == 2 else drIn()
	dWide = (dWide + wide(ram(cell(dDp, -index, 0) | 0x40), v)) & 0xFFFF_FFFF
	spend(2)
	if index < 2:
		waitFor(.ScalarIn(index + 1))
		return
	answer([dWide >> 16], [1])

# The memory test (07, 0F): the RAM filled with 5555 and AAAA alternating, read back, then the
# same with the two swapped; 0 out, the RAM left with the second fill.
fn memoryFill():
	fillRam(0x5555)
	spend(771)
	waitFor(.MemoryCheck)

fn memoryCheck():
	fillRam(0xAAAA)
	spend(3335)
	answer([0], [1])

# the even addresses `first`, the odd ones its complement
fn fillRam(first i64):
	for at in 0..0x100:
		setRam(at, first if at & 1 == 0 else first ^ 0xFFFF)

# The data ROM's dump (17, 1F): its 1,024 words from the one the command's high bits pick.
fn romDump():
	words = []
	gaps = []
	loop 0x400:
		words.push(dataRom(dA + words.len))
		gaps.push(2)
	spend(2)
	awaitAnswer(words, gaps)
