# Division and remainder by a constant: a shift for a power of two, else a multiplication by
# the divisor's magic number.

# rax = rax / v or rax % v for a signed rax of `bits` bits and a constant v (not 0 nor -1): a
# shift for a power of two, else a multiplication by its magic number (clobbers rcx, rdx, r8)
fn genSignedDivBy(mut g Gen, op i64, v i64, bits i64):
	if v > 0 and (v & (v - 1)) == 0:
		k = 0
		pw = 1
		while pw < v:
			pw *= 2
			k += 1
		if op == binDiv:
			if k > 0:
				g.a.em3(0x48, 0x89, 0xC1)   # mov rcx, rax
				g.a.em4(0x48, 0xC1, 0xF9, 0x3F)   # sar rcx, 63
				g.a.em3(0x48, 0x81, 0xE1)   # and rcx, v-1
				g.a.emit32(v - 1)
				g.a.em3(0x48, 0x01, 0xC8)   # add rax, rcx
				g.a.em4(0x48, 0xC1, 0xF8, k)   # sar rax, k
			return
		g.a.em3(0x48, 0x89, 0xC2)   # mov rdx, rax
		if k == 0:
			g.a.em2(0x31, 0xC0)
			return
		g.a.em3(0x48, 0x89, 0xC1)   # mov rcx, rax
		g.a.em4(0x48, 0xC1, 0xF9, 0x3F)   # sar rcx, 63
		g.a.em3(0x48, 0x81, 0xE1)   # and rcx, v-1
		g.a.emit32(v - 1)
		g.a.em3(0x48, 0x01, 0xC8)   # add rax, rcx
		g.a.em4(0x48, 0xC1, 0xF8, k)   # sar rax, k   (the quotient)
		g.a.em4(0x48, 0xC1, 0xE0, k)   # shl rax, k
		g.a.em3(0x48, 0x29, 0xC2)   # sub rdx, rax
		g.a.em3(0x48, 0x89, 0xD0)   # mov rax, rdx
		return
	if bits == 32:
		g.genMagicDiv32(op, v, true)
		return
	g.genMagicDiv64(op, v)

# rax = rax / v or rax % v for a 32-bit operand (sign-extended in rax) and a constant v that is
# not a power of two: |rax| * M >> k with M = ceil(2^k / |v|), k = 32 + ceil(log2 |v|), which
# is exact for every 32-bit magnitude (Granlund-Montgomery)
fn genMagicDiv32(mut g Gen, op i64, v i64, signed bool):
	d = v
	if d < 0:
		d = 0 - d
	l = 0
	pw = 1
	while pw < d:
		pw *= 2
		l += 1
	k = 32 + l
	half = 1   # 2^(k-1): 2^k itself may not fit in i64
	i = 1
	while i < k:
		half *= 2
		i += 1
	# ceil(2^k / d) from the quotient and remainder of 2^(k-1)
	q = half / d
	r = half - q * d
	q *= 2
	r *= 2
	if r >= d:
		q += 1
		r -= d
	if r != 0:
		q += 1
	g.a.em3(0x49, 0x89, 0xC0)   # mov r8, rax   (the dividend)
	fast = signed and v > 0 and (v & (v - 1)) != 0
	if fast:
		# x * M signed in rdx:rax, shifted by k (a floor), plus one when x < 0: the quotient
		# rounded toward zero (M rounds up, so a negative product never lands on a whole)
		g.a.em2(0x48, 0xB9)   # movabs rcx, M
		g.a.emit64(q)
		g.a.em3(0x48, 0xF7, 0xE9)   # imul rcx
		g.a.em5(0x48, 0x0F, 0xAC, 0xD0, k)   # shrd rax, rdx, k
		g.a.em3(0x4C, 0x89, 0xC1)   # mov rcx, r8
		g.a.em4(0x48, 0xC1, 0xF9, 0x3F)   # sar rcx, 63
		g.a.em3(0x48, 0x29, 0xC8)   # sub rax, rcx
	elif signed:
		g.a.em3(0x48, 0x89, 0xC1)   # mov rcx, rax
		g.a.em3(0x48, 0xF7, 0xD9)   # neg rcx
		g.a.em3(0x48, 0x85, 0xC0)   # test rax, rax
		g.a.em4(0x48, 0x0F, 0x49, 0xC8)   # cmovns rcx, rax   (rcx = |rax|)
	else:
		g.a.em3(0x48, 0x89, 0xC1)   # mov rcx, rax
	if not fast:
		g.a.em2(0x48, 0xB8)   # movabs rax, M
		g.a.emit64(q)
		g.a.em3(0x48, 0xF7, 0xE1)   # mul rcx   (rdx:rax, the product may pass 2^64 unsigned)
		g.a.em5(0x48, 0x0F, 0xAC, 0xD0, k)   # shrd rax, rdx, k
	if signed and not fast:
		g.a.em3(0x4D, 0x85, 0xC0)   # test r8, r8
		if v < 0:
			g.a.em2(0x78, 0x03)   # js +3: the quotient flips when the signs differ
		else:
			g.a.em2(0x79, 0x03)   # jns +3
		g.a.em3(0x48, 0xF7, 0xD8)   # neg rax
	if op == binMod:
		g.a.em3(0x48, 0x69, 0xC0)   # imul rax, rax, v
		g.a.emit32(v)
		g.a.em3(0x49, 0x29, 0xC0)   # sub r8, rax
		g.a.em3(0x4C, 0x89, 0xC0)   # mov rax, r8

# the magic number of a signed division of an i64 by v, |v| >= 2 and v not a positive power of
# two: (M, s), the quotient the high word of x * M, plus x when M's sign differs from v's (minus
# x when v < 0 < M), shifted arithmetically by s, plus its sign bit (Hacker's Delight 10-1)
fn magicS64(v i64):
	two63 u64 = 9_223_372_036_854_775_808
	ad = u64(v)
	if v < 0:
		ad = 0 - v
	t = two63 + (u64(v) >> 63)
	anc = t - 1 - t % ad   # |nc|: the largest dividend with nc % ad == ad - 1
	p = 63
	q1 = two63 / anc
	r1 = two63 - q1 * anc
	q2 = two63 / ad
	r2 = two63 - q2 * ad
	loop:
		p += 1
		q1 *= 2
		r1 *= 2
		if r1 >= anc:
			q1 += 1
			r1 -= anc
		q2 *= 2
		r2 *= 2
		if r2 >= ad:
			q2 += 1
			r2 -= ad
		delta = ad - r2
		if not (q1 < delta or (q1 == delta and r1 == 0)): break
	m = i64(q2 + 1)
	if v < 0:
		m = 0 - m
	sh = p - 64
	(m, sh)

# rax = rax / v or rax % v for an i64 rax and a constant v, |v| >= 2 and v not a positive power
# of two: the high word of rax * M (one-operand imul), corrected by the dividend when M's sign
# differs from v's, shifted arithmetically by s and rounded toward zero by adding its sign bit
# (Hacker's Delight 10-1, with M and s found when compiling)
fn genMagicDiv64(mut g Gen, op i64, v i64):
	m, sh = magicS64(v)
	g.a.em3(0x48, 0x89, 0xC1)   # mov rcx, rax   (the dividend)
	g.a.em2(0x48, 0xB8)   # movabs rax, M
	g.a.emit64(m)
	g.a.em3(0x48, 0xF7, 0xE9)   # imul rcx   (rdx = the high word)
	if v > 0 and m < 0:
		g.a.em3(0x48, 0x01, 0xCA)   # add rdx, rcx
	elif v < 0 and m > 0:
		g.a.em3(0x48, 0x29, 0xCA)   # sub rdx, rcx
	if sh > 0:
		g.a.em4(0x48, 0xC1, 0xFA, sh)   # sar rdx, s
	g.a.em3(0x48, 0x89, 0xD0)   # mov rax, rdx
	g.a.em4(0x48, 0xC1, 0xE8, 0x3F)   # shr rax, 63
	g.a.em3(0x48, 0x01, 0xD0)   # add rax, rdx   (the quotient)
	if op == binMod:
		g.a.em3(0x48, 0x69, 0xC0)   # imul rax, rax, v
		g.a.emit32(v)
		g.a.em3(0x48, 0x29, 0xC1)   # sub rcx, rax
		g.a.em3(0x48, 0x89, 0xC8)   # mov rax, rcx

# rax = rax / v or rax % v for a u64 rax and a constant v >= 2: a shift or a mask for a power of
# two, else a multiplication by its magic number
fn genUnsignedDivBy(mut g Gen, op i64, v i64):
	if (v & (v - 1)) == 0:
		k = 0
		while (1 << k) < v:
			k += 1
		if op == binDiv:
			g.a.em4(0x48, 0xC1, 0xE8, k)   # shr rax, k
		else:
			g.a.em2(0x48, 0x25)   # and rax, v - 1
			g.a.emit32(v - 1)
		return
	g.genMagicDivU64(op, v)

# x / v for every x below 2^32 as x * M >> p in one 64-bit word: M = ceil(2^p / v) for the least
# p whose error M * v - 2^p is at most 2^(p - 32); (M, p), M 0 when it is 2^31 or more (not an
# imul's immediate)
fn magicU32(v i64):
	d = u64(v)
	p = 32
	pw u64 = 1   # 2^(p - 32)
	loop:
		m = ((pw << 32) + d - 1) / d   # ceil(2^p / v)
		if m * d - (pw << 32) <= pw: return (i64(m) if m < 2_147_483_648 else 0, p)
		p += 1
		pw *= 2

# the magic number of an unsigned division of a u64 by v, not a power of two: (M, s, add), the
# quotient the high word of x * M shifted by s, or when M has a 65th bit (add) the high word h
# plus (x - h) / 2, shifted by s - 1 (Hacker's Delight 10-10)
fn magicU64(v i64):
	d = u64(v)
	two63 u64 = 9_223_372_036_854_775_808
	all = two63 - 1 + two63   # 2^64 - 1
	zero u64 = 0
	nc = all - (zero - d) % d
	p = 63
	q1 = two63 / nc
	r1 = two63 - q1 * nc
	q2 = (two63 - 1) / d
	r2 = two63 - 1 - q2 * d
	add = false
	loop:
		p += 1
		if r1 >= nc - r1:
			q1 = 2 * q1 + 1
			r1 = 2 * r1 - nc
		else:
			q1 = 2 * q1
			r1 = 2 * r1
		if r2 + 1 >= d - r2:
			add = add or q2 >= two63 - 1
			q2 = 2 * q2 + 1
			r2 = 2 * r2 + 1 - d
		else:
			add = add or q2 >= two63
			q2 = 2 * q2
			r2 = 2 * r2 + 1
		delta = d - 1 - r2
		if not (p < 128 and (q1 < delta or (q1 == delta and r1 == 0))): break
	(i64(q2 + 1), p - 64, add)

# rax = rax / v or rax % v for a u64 rax and a constant v, not a power of two: the high word of
# rax * M shifted by s, with the 65th bit of M added back when it has one (Hacker's Delight
# 10-10, M and s found when compiling)
fn genMagicDivU64(mut g Gen, op i64, v i64):
	m, sh, add = magicU64(v)
	g.a.em3(0x48, 0x89, 0xC1)   # mov rcx, rax   (the dividend)
	g.a.em2(0x48, 0xB8)   # movabs rax, M
	g.a.emit64(m)
	g.a.em3(0x48, 0xF7, 0xE1)   # mul rcx   (rdx = the high word)
	if add:
		g.a.em3(0x48, 0x89, 0xC8)   # mov rax, rcx
		g.a.em3(0x48, 0x29, 0xD0)   # sub rax, rdx
		g.a.em3(0x48, 0xD1, 0xE8)   # shr rax, 1
		g.a.em3(0x48, 0x01, 0xD0)   # add rax, rdx
		if sh > 1:
			g.a.em4(0x48, 0xC1, 0xE8, sh - 1)   # shr rax, s - 1
	else:
		g.a.em3(0x48, 0x89, 0xD0)   # mov rax, rdx
		if sh > 0:
			g.a.em4(0x48, 0xC1, 0xE8, sh)   # shr rax, s
	if op == binMod:
		g.a.em3(0x48, 0x69, 0xC0)   # imul rax, rax, v
		g.a.emit32(v)
		g.a.em3(0x48, 0x29, 0xC1)   # sub rcx, rax
		g.a.em3(0x48, 0x89, 0xC8)   # mov rax, rcx
