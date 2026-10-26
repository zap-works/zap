# AVX2 for the vector types of vecs.zap (f32x8, i32x8, i64x4, u8x32). A vector is 32 bytes in
# the frame like any aggregate; an expression is computed in ymm0, its right operand parked in a
# frame slot and used as the instruction's memory operand. The instructions come from one table
# keyed by the element (vecOp), which Simd<4, f64> and Simd<16, u8> read too (their generators in
# irVec.zap keeps locals in registers), encoded by irVecX64.zap.

alias nodes = g.c.nodes
alias tys = g.c.types

vecRowU8 = 3   # u8x32's row, and Simd<16, u8>'s at 128 bits
vecRowF64 = 4   # Simd<4, f64>'s

# an element's row: 0 f32, 1 i32, 2 i64, 3 u8
fn vecRow(mut g Gen, v TypeId):
	elem = innerOf(tys, v)
	if g.tyK(elem) == tFloat: return 0
	bits = tys[elem].bits
	if bits == 32: return 1
	if bits == 64: return 2
	3

# language's operations: load and store (unaligned), move (register to register), shuffle,
# and f64's hadd and cmp (its predicate follows).
fn vecOp(row i64, op str):
	if row == vecRowF64:
		if op == "add": return [1, 1, 0x58]   # vaddpd
		if op == "sub": return [1, 1, 0x5C]
		if op == "mul": return [1, 1, 0x59]
		if op == "div": return [1, 1, 0x5E]
		if op == "min": return [1, 1, 0x5D]
		if op == "max": return [1, 1, 0x5F]
		if op == "xor": return [1, 1, 0x57]   # vxorpd
		if op == "hadd": return [1, 1, 0x7C]   # vhaddpd
		if op == "cmp": return [1, 1, 0xC2]   # vcmppd
		if op == "load": return [1, 1, 0x10]   # vmovupd
		if op == "store": return [1, 1, 0x11]
		if op == "move": return [1, 1, 0x28]   # vmovapd
		return []
	if op == "load": return [1, 2, 0x6F]   # vmovdqu
	if row == 0:
		if op == "add": return [1, 0, 0x58]
		if op == "sub": return [1, 0, 0x5C]
		if op == "mul": return [1, 0, 0x59]
		if op == "div": return [1, 0, 0x5E]
		if op == "min": return [1, 0, 0x5D]
		if op == "max": return [1, 0, 0x5F]
		return []
	if op == "and": return [1, 1, 0xDB]
	if op == "or": return [1, 1, 0xEB]
	if op == "xor": return [1, 1, 0xEF]
	if row == 1:
		if op == "add": return [1, 1, 0xFE]
		if op == "sub": return [1, 1, 0xFA]
		if op == "mul": return [2, 1, 0x40]   # vpmulld
		if op == "min": return [2, 1, 0x39]   # vpminsd
		if op == "max": return [2, 1, 0x3D]   # vpmaxsd
		if op == "eq": return [1, 1, 0x76]
		if op == "gt": return [1, 1, 0x66]
		return []
	if row == 2:
		if op == "add": return [1, 1, 0xD4]
		if op == "sub": return [1, 1, 0xFB]
		if op == "eq": return [2, 1, 0x29]   # vpcmpeqq
		if op == "gt": return [2, 1, 0x37]   # vpcmpgtq
		return []
	if op == "move": return [1, 1, 0x6F]   # vmovdqa
	if op == "shuffle": return [2, 1, 0x00]   # vpshufb
	if op == "add": return [1, 1, 0xFC]
	if op == "sub": return [1, 1, 0xF8]
	if op == "min": return [1, 1, 0xDA]   # vpminub
	if op == "max": return [1, 1, 0xDE]   # vpmaxub
	if op == "eq": return [1, 1, 0x74]
	if op == "gt": return [1, 1, 0x64]   # signed, as u8x16's gtMask
	[]

# the three-byte VEX prefix of a 256-bit instruction on ymm registers below 8

# the same with [base] as the last operand, base a general register other than rsp, rbp, r12
# and r13 (their encodings need more bytes)

# the table's name of a binary operator over vectors
fn vecOpName(op i64):
	if op == binAdd: return "add"
	if op == binSub: return "sub"
	if op == binMul: return "mul"
	if op == binDiv: return "div"
	if op == binBand: return "and"
	if op == binBor: return "or"
	"xor"
