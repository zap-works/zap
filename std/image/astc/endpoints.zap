# The color endpoint modes: each turns 2 to 8 unquantized values (0..255) into two RGBA endpoints.
# Modes 0 and 1 are luminance, 4 and 5 luminance with alpha, 6 and 10 a color and its scale,
# 8, 9, 12 and 13 two colors (direct, or a base and an offset), the odd ones of 8..13 with blue
# contraction when the second sum is lower. The HDR modes (2, 3, 7, 11, 14, 15) are left out: they
# have no 8-bit result, and an LDR decoder gives the error color for a block that uses one.

# whether the mode is one of the HDR ones
fn isHdr(mode i64):
	mode in [2, 3, 7, 11, 14, 15]

# The endpoints of `mode` from the values at `at`, as out[0..4] and out[4..8]; false for a mode
# that is not decoded.
fn readEndpoints(mode i64, v i64[96], at i64, mut out i64[8]):
	if isHdr(mode): return false
	match mode:
		0: gray(out, v[at], v[at + 1], 255, 255)
		1:
			low = (v[at] >> 2) | (v[at + 1] & 0xC0)
			gray(out, low, (low + (v[at + 1] & 0x3F)).min(255), 255, 255)
		4: gray(out, v[at], v[at + 1], v[at + 2], v[at + 3])
		5:
			base, offset = transfer(v[at + 1], v[at])
			alpha, alphaOffset = transfer(v[at + 3], v[at + 2])
			gray(
				out,
				base,
				(base + offset).clamp(0, 255),
				alpha,
				(alpha + alphaOffset).clamp(0, 255)
			)
		6: scaled(out, v, at, 255, 255)
		10: scaled(out, v, at, v[at + 4], v[at + 5])
		8: direct(out, v, at, false)
		12: direct(out, v, at, true)
		9: offset(out, v, at, false)
		_: offset(out, v, at, true)
	true

fn setEndpoints(mut out i64[8], r0 i64, g0 i64, b0 i64, a0 i64, r1 i64, g1 i64, b1 i64, a1 i64):
	out[0] = r0
	out[1] = g0
	out[2] = b0
	out[3] = a0
	out[4] = r1
	out[5] = g1
	out[6] = b1
	out[7] = a1

fn gray(mut out i64[8], l0 i64, l1 i64, a0 i64, a1 i64):
	setEndpoints(out, l0, l0, l0, a0, l1, l1, l1, a1)

# the offset of a base and offset pair: the offset's top bit goes to the base, the rest of the
# offset is a signed 6-bit number; returns (base, offset)
fn transfer(offset i64, base i64):
	b = (base >> 1) | (offset & 0x80)
	a = (offset >> 1) & 0x3F
	b, a - 64 if a & 0x20 != 0 else a

# red, green and blue moved towards blue, as the second endpoint of a lower sum is stored
fn contract(mut out i64[8], from i64, r i64, g i64, b i64, a i64):
	out[from] = (r + b) >> 1
	out[from + 1] = (g + b) >> 1
	out[from + 2] = b
	out[from + 3] = a

# the color v[at..at+3] and a scale v[at+3] in 1/256: the first endpoint is the color scaled down
fn scaled(mut out i64[8], v i64[96], at i64, a0 i64, a1 i64):
	s = v[at + 3]
	setEndpoints(
		out,
		v[at] * s >> 8,
		v[at + 1] * s >> 8,
		v[at + 2] * s >> 8,
		a0,
		v[at],
		v[at + 1],
		v[at + 2],
		a1
	)

# two colors, in the order of their sums (blue contracted when the second is lower), `alpha` with
# a pair of alpha values after the colors
fn direct(mut out i64[8], v i64[96], at i64, alpha bool):
	a0 = v[at + 6] if alpha else 255
	a1 = v[at + 7] if alpha else 255
	if v[at + 1] + v[at + 3] + v[at + 5] >= v[at] + v[at + 2] + v[at + 4]:
		setEndpoints(out, v[at], v[at + 2], v[at + 4], a0, v[at + 1], v[at + 3], v[at + 5], a1)
	else:
		contract(out, 0, v[at + 1], v[at + 3], v[at + 5], a1)
		contract(out, 4, v[at], v[at + 2], v[at + 4], a0)

# a color and signed offsets from it; a negative sum of them swaps the two and contracts blue,
# and both are clamped last
fn offset(mut out i64[8], v i64[96], at i64, alpha bool):
	r0, r1 = transfer(v[at + 1], v[at])
	g0, g1 = transfer(v[at + 3], v[at + 2])
	b0, b1 = transfer(v[at + 5], v[at + 4])
	a0 = 255
	a1 = 0
	if alpha: a0, a1 = transfer(v[at + 7], v[at + 6])
	if r1 + g1 + b1 >= 0:
		setEndpoints(out, r0, g0, b0, a0, r0 + r1, g0 + g1, b0 + b1, a0 + a1)
	else:
		contract(out, 0, r0 + r1, g0 + g1, b0 + b1, a0 + a1)
		contract(out, 4, r0, g0, b0, a0)
	for i in 0..8:
		out[i] = out[i].clamp(0, 255)
