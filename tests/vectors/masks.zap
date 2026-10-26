# A byte mask's uses (a test against 0, trailingZeros, bitCount, the lowest lane cleared, or-ed
# masks) against the scalar code's, at every place of a match: AArch64 keeps such masks four bits
# a byte (a64Masks.zap), run with --target linux-arm64 too

test "16-byte masks give the scalar's places, counts and first lanes":
	xs = fill(48, u8(1))
	bad = 0
	for p in 0..16:
		for q in p..16:
			xs[16 + p] = 7
			xs[16 + q] = 9
			v = xs.load16(16)
			hits = v.eqMask(Simd<16>(u8(7))) | v.eqMask(Simd<16>(u8(9)))
			got = []
			while hits != 0:
				got.push(hits.trailingZeros())
				hits &= hits - 1
			want = (0..16).filter(xs[16 + it] == 7 or xs[16 + it] == 9)
			if got != want: bad += 1
			m = v.eqMask(Simd<16>(u8(9)))
			if m == 0 or m.trailingZeros() != q or m.bitCount() != 1: bad += 1
			if v.eqMask(Simd<16>(u8(5))).trailingZeros() != 64: bad += 1
			if v.eqMask(Simd<16>(u8(1))).bitCount() != 16 - want.len: bad += 1
			xs[16 + p] = 1
			xs[16 + q] = 1
	print(bad)
	prints "0"

test "32-byte masks give the scalar's first lane and count":
	xs = fill(32, u8(3))
	bad = 0
	for p in 0..32:
		xs[p] = 8
		m = xs.load32(0).eqMask(Simd<32, u8>(u8(8)))
		if m.trailingZeros() != p or m.bitCount() != 1 or m != 1 << p: bad += 1
		xs[p] = 3
	print(bad)
	prints "0"
