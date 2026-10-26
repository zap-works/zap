# What a loop holds in a register from before it (irOptPaths.zap's irHeldConstants): a constant
# wider than 32 bits, and a shuffle's indices cleared once (irVecMasks.zap), with a shuffle by
# indices known clear and a blend by a comparison's mask taking AArch64's shorter forms.

fn masked(n i64):
	h = 0
	for i in 0..n:
		h = ((h << 1) ^ i) & 0x7FF0_1234_5678_9ABC
		if h == 0x7FF0_0000_0000_0000: h = 1
	h

test "a wide constant read in a loop":
	expect masked(1000) == 668
	expect masked(0) == 0

test "shuffles and blends in a loop, by indices with bits 4..6 set and by known ones":
	xs u8[] = (0..32).map(u8(it * 7 % 256))
	odd = (0..16).map(u8((it * 0x35 + 0x13) % 256))   # bits 4..6 set, some top bits
	idx = odd.load16(0)
	acc = Simd<16>(0)
	for k in 0..2:
		v = xs.load16(k * 16)
		lo = v & Simd<16>(15)
		sel = (v & Simd<16>(16)).eqBytes(Simd<16>(16))
		acc = acc + v.shuffle(idx) + v.shuffle(lo).blend(v, sel)
	want = (0..16).map(i:
		(0..2).map(k:
			b = xs[16 * k + i]
			picked = 0 if odd[i] >= 128 else xs[16 * k + odd[i] % 16]
			picked + (b if b & 16 != 0 else xs[16 * k + b % 16])
		).sum() % 256
	)
	expect (0..16).map(acc.lane(it)) == want
