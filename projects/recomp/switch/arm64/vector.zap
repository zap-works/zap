# A64's Advanced SIMD (scalar and vector forms) and cryptographic groups (Arm ARM C4.1.6), after
# the Armv8.0 Cortex-A57: no dot product, no half-precision arithmetic, no rounding-multiply
# accumulate. Each encoding group is a VectorOp; the opcode, the U bit and the size are the
# instruction's fields (cpu/vector*.zap say what each opcode does).

pub type VectorOp:
	None
	ThreeSame   # opc: the opcode; pair for the pairwise ones, folded onto their lane opcode
	ThreeDifferent   # opc: the opcode; q the "2" form working on the high half
	Indexed   # a three-same or three-different opc, rm the register of the lane, index its number
	TwoMisc   # opc: the opcode
	AcrossLanes   # opc: the opcode
	Copy   # opc: the imm4 (dup, ins, smov, umov); size the lane's, index its number, imm the source's
	ModifiedImmediate   # opc: movi, mvni, orr, bic; imm the 64 bits of the immediate
	ShiftImmediate   # opc: the opcode; size the lane's; amount the shift
	Permute   # opc: uzp1, trn1, zip1, uzp2, trn2, zip2 (1-3, 5-7)
	Extract
	Table   # imm the registers of the table, opc 1 for tbx
	FloatSame   # fop the operation; pair for the pairwise ones, size 0 single or 1 double
	FloatIndexed   # fop a three-same one, rm the register of the lane, index its number
	FloatUnary   # fop: the operation on each lane; amount the fraction bits of the fixed-point conversions
	FloatAcross   # fop: the operation reduced over the lanes (scalar: the two lanes of a pairwise one)
	Aes   # opc: aese, aesd, aesmc, aesimc
	ShaThree   # opc: sha1c, sha1p, sha1m, sha1su0, sha256h, sha256h2, sha256su1
	ShaTwo   # opc: sha1h, sha1su1, sha256su0
	FloatSame   # opc: the opcode (24 and up); size bit 22 double, bit 23 its pair's second
	FloatTwo   # opc: the opcode
	FloatIndexed   # opc: the opcode (1 fmla, 5 fmls, 9 fmul or fmulx); index the lane of rm
	FloatAcross   # opc: 12 fmaxnm(v/p) or fminnm, 13 faddp, 15 fmax or fmin
# The Advanced SIMD or crypto instruction w, Op.Unknown when it is none the decoder knows.
fn advancedSimd(w i64):
	if bit(w, 31): return Instr()
	if bit(w, 28): return scalarGroup(w) if bit(w, 30) else Instr()
	vectorGroup(w)

fn vectorGroup(w i64):
	if bit(w, 24):
		if not bit(w, 10): return sameIndexed(w, false)
		if bit(w, 23): return Instr()
		return modifiedImmediate(w) if bits(w, 19, 4) == 0 else shiftImmediate(w, false)
	if bit(w, 21):
		if bit(w, 10): return threeSame(w, false)
		if not bit(w, 11): return threeDifferent(w, false)
		return twoRegister(w, false)
	if bit(w, 15): return Instr()
	if bits(w, 21, 3) == 0 and bit(w, 10): return elementCopy(w, false)
	if bit(w, 29): return extract(w) if bits(w, 22, 2) == 0 and not bit(w, 10) else Instr()
	if bit(w, 10): return Instr()
	if bit(w, 11): return permute(w)
	table(w) if bits(w, 22, 2) == 0 else Instr()

fn scalarGroup(w i64):
	if bit(w, 24):
		if not bit(w, 10): return sameIndexed(w, true)
		return shiftImmediate(w, true) if not bit(w, 23) and bits(w, 19, 4) != 0 else Instr()
	if bit(w, 21):
		if bit(w, 10): return threeSame(w, true)
		if not bit(w, 11): return threeDifferent(w, true)
		return twoRegister(w, true)
	if bit(w, 15) or bit(w, 29): return Instr()
	if bits(w, 21, 3) == 0 and bit(w, 10): return elementCopy(w, true)
	shaThree(w) if not bit(w, 10) and not bit(w, 11) and bits(w, 22, 2) == 0 else Instr()
