# An A64 instruction decoded (Arm ARM, part C4): what it does and its fields, the same for the
# translation, which writes them as constants, and the interpreter, which reads them. A register
# number is 0-30, `zr` (31 read as zero, a write dropped) or `sp`; the decoder has already chosen
# which one a field's 31 means.

pub zr = 31
pub sp = 32

pub type Op:
	Unknown
	Adr   # imm the address
	AddImm   # rd = rn + imm (sub: imm negated is not enough for the flags; see sub)
	LogicImm   # opc: and, orr, eor, ands
	MoveWide   # opc: movn, movz, movk; imm the 16 bits, shift its place
	Bitfield   # opc: sbfm, bfm, ubfm; immr, imms
	Extract   # rd = (rn:rm) >> imm
	AddShifted   # rd = rn +- (rm shifted)
	AddExtended   # rd = rn +- (rm extended, shifted)
	AddCarry   # adc, sbc
	LogicShifted   # opc and invert (n): and, bic, orr, orn, eor, eon, ands, bics
	CondCompare   # ccmn, ccmp; rm or imm, nzcv the flags when the condition fails
	CondSelect   # csel, csinc, csinv, csneg
	OneSource   # opc: rbit, rev16, rev32, rev, clz, cls
	TwoSource   # opc: udiv, sdiv, lslv, lsrv, asrv, rorv, crc32 (b h w x), crc32c
	ThreeSource   # opc: madd, msub, smaddl, smsubl, umaddl, umsubl, smulh, umulh
	Branch   # b; imm the target
	BranchLink   # bl
	BranchCond   # b.cond
	CompareBranch   # cbz, cbnz (opc 1)
	TestBranch   # tbz, tbnz (opc 1); imm2 the bit
	BranchReg   # br
	BranchLinkReg   # blr
	Return   # ret
	Svc   # imm the call's number
	Brk
	Hint   # nop, yield, wfe...: nothing here
	Barrier   # dmb, dsb, isb: nothing for one thread's view
	ClearExclusive
	ReadSystem   # mrs; imm the register's encoding
	WriteSystem   # msr (register)
	WriteState   # msr (immediate) to pstate fields
	System   # sys: dc zva and the cache operations; imm the operation
	LoadLiteral   # ldr (literal); imm the address, size and signed as a load's
	Load   # ldr*, size the bytes' log2, signed, extend to 32 or 64 (sf)
	Store
	LoadPair
	StorePair
	LoadExclusive   # ldxr, ldaxr; pair for ldxp
	StoreExclusive   # stxr, stlxr; rs the status
	LoadAcquire   # ldar
	StoreRelease   # stlr
	Prefetch
	Float   # the scalar FP group (float.zap): what it does in `float`
	Vector   # Advanced SIMD and crypto (vector.zap): what it does in `vector`
	VectorStructure   # ld1-ld4, st1-st4, ld1r-ld4r (structure.zap)

# how a memory access finds its address
pub type Mode:
	Offset   # rn + imm
	PreIndex   # rn += imm, then at rn
	PostIndex   # at rn, then rn += imm
	RegisterOffset   # rn + (rm extended, shifted)

pub type Instr:
	op Op = .Unknown
	rd i64 = 0
	rn i64 = 0
	rm i64 = 0
	ra i64 = 0   # a third source, or a pair's second register, or a store's status
	imm i64 = 0
	imm2 i64 = 0
	opc i64 = 0
	sf bool = true   # 64 bits, else 32
	setFlags bool = false
	subtract bool = false
	shift i64 = 0   # lsl, lsr, asr, ror; or an extend's kind (uxtb... sxtx)
	amount i64 = 0
	cond i64 = 0
	size i64 = 0   # a memory access's bytes as their log2 (4 for a q register)
	signed bool = false
	vector bool = false   # a memory access of the FP/SIMD registers
	mode Mode = .Offset
	acquire bool = false
	pair bool = false
	q bool = false   # a vector's 128 bits, else its low 64
	index i64 = 0   # a lane's number
	fop FloatOp = .None
	vop VectorOp = .None

# The instruction as Zap source for the translation: its printed fields that differ from a
# default Instr's, an enum's variant written with its dot (fields hold plain variants only).
pub fn literal(i Instr) str:
	defaults = "{Instr()}"
	given = "{i}"
	base = defaults["Instr(".len..defaults.len - 1].split(", ")
	parts str[] = []
	for k, part in given["Instr(".len..given.len - 1].split(", "):
		if part == base[k]: continue
		at = part.indexOf(" = ") ?? continue
		value = part[at + 3..]
		parts.push("{part[..at]} = .{value}" if value[0].isUpper() else part.copy())
	"arm64.Instr({parts.join(", ")})"
