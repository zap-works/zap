# ZAP_RUN=disasm: after a build, a function of the executable disassembled on stderr, in Intel
# syntax, to its end: main (the target of the first call after the entry point), or the function
# `disasm=` names: a name of the map ZAP_RUN=map writes, `callN` the target of main's N-th direct
# call, or an RVA in hex (0x optional when no function has that name). The decoder knows the
# instructions the compiler emits: the integer ones, SSE and AVX (VEX), branches and calls. One it
# does not name still has its length decoded, and shows its opcode.

fn disasmWord():
	TraceWord(
		"disasm",
		"after a build, main disassembled (disasm=name a function of the map, callN, or an RVA)"
	)

import compare
import fs
import perf

# ---------- the PE file ----------

type Image:
	data u8[]
	sections compare.Section[]
	entry i64
	base i64

fn readImage(path str):
	data = fs.readBytes(path) ?? []
	if data.len < 64:
		fail("cannot read {path}")
	opt = i64(data.u32le(60)) + 24
	sections = compare.sections(data)
	Image(
		entry = data.u32le(opt + 16),
		base = data.i64le(opt + 24),
		sections,
		data = move data
	)

# the file offset of an rva
fn offsetOf(img Image, rva i64):
	if img.sections.find(rva >= .va and rva < .va + .rawSize) is s: return s.raw + rva - s.va
	fail("rva {hex(rva)} is outside the sections")
	0

# ---------- the decoder ----------

type Decoder:
	img Image
	at i64 = 0   # the file offset being read
	rva i64 = 0   # the rva of the instruction being decoded
	rex i64 = 0
	opsize bool = false   # 0x66
	rep i64 = 0   # 0xF3 or 0xF2 (0: none)
	vex bool = false
	vexL bool = false
	vexW bool = false
	vexReg i64 = 0   # vvvv, already inverted
	vexMap i64 = 0
	target i64 = -1   # a branch's target rva (-1: none)

type ModRm:
	md i64
	reg i64
	rm i64
	text str   # the memory or register operand, already written

fn byte(mut d Decoder):
	b = i64(d.img.data[d.at])
	d.at += 1
	b

fn imm8(mut d Decoder):
	v = d.byte()
	if v >= 128: v - 256
	else: v

fn imm32(mut d Decoder) i64:
	v = d.img.data.i32le(d.at)
	d.at += 4
	v

fn hex(v i64):
	"{u64(v):x}"   # a negative value as its 64 bits

fn signedHex(v i64):
	if v < 0: "-0x{hex(-v)}"
	else: "0x{hex(v)}"

regs64 = [
	"rax",
	"rcx",
	"rdx",
	"rbx",
	"rsp",
	"rbp",
	"rsi",
	"rdi",
	"r8",
	"r9",
	"r10",
	"r11",
	"r12",
	"r13",
	"r14",
	"r15"
]
regs32 = [
	"eax",
	"ecx",
	"edx",
	"ebx",
	"esp",
	"ebp",
	"esi",
	"edi",
	"r8d",
	"r9d",
	"r10d",
	"r11d",
	"r12d",
	"r13d",
	"r14d",
	"r15d"
]
regs16 = [
	"ax",
	"cx",
	"dx",
	"bx",
	"sp",
	"bp",
	"si",
	"di",
	"r8w",
	"r9w",
	"r10w",
	"r11w",
	"r12w",
	"r13w",
	"r14w",
	"r15w"
]
regs8 = [
	"al",
	"cl",
	"dl",
	"bl",
	"spl",
	"bpl",
	"sil",
	"dil",
	"r8b",
	"r9b",
	"r10b",
	"r11b",
	"r12b",
	"r13b",
	"r14b",
	"r15b"
]
conditions = [
	"o",
	"no",
	"b",
	"ae",
	"e",
	"ne",
	"be",
	"a",
	"s",
	"ns",
	"p",
	"np",
	"l",
	"ge",
	"le",
	"g"
]
aluNames = ["add", "or", "adc", "sbb", "and", "sub", "xor", "cmp"]
shiftNames = ["rol", "ror", "rcl", "rcr", "shl", "shr", "sal", "sar"]

# a general register of `size` bytes
fn reg(n i64, size i64):
	if size == 8:
		regs64[n].copy()
	elif size == 4:
		regs32[n].copy()
	elif size == 2:
		regs16[n].copy()
	else:
		regs8[n].copy()

fn xmm(d Decoder, n i64):
	if d.vex and d.vexL: "ymm{n}"
	else: "xmm{n}"

# the operand size of the usual instructions: 8 with REX.W, 2 with 0x66, else 4
fn opSize(d Decoder):
	if d.rex & 8 != 0: 8
	elif d.opsize: 2
	else: 4

fn sizeWord(size i64):
	if size == 8: "qword"
	elif size == 4: "dword"
	elif size == 2: "word"
	elif size == 1: "byte"
	elif size == 32: "ymmword"
	else: "xmmword"

# The ModRM byte (and SIB, displacement): the r/m operand as a register of `size` bytes, an
# xmm register when `vector`, or memory written with its width.
fn modrm(mut d Decoder, size i64, vector bool):
	b = d.byte()
	md = b >> 6
	r = ((b >> 3) & 7) | (8 if d.rex & 4 != 0 else 0)
	rm = b & 7
	if md == 3:
		n = rm | (8 if d.rex & 1 != 0 else 0)
		text = d.xmm(n) if vector else reg(n, size)
		return ModRm(md, reg = r, rm = n, text)
	parts = ""
	if rm == 4:
		sib = d.byte()
		scale = 1 << (sib >> 6)
		index = ((sib >> 3) & 7) | (8 if d.rex & 2 != 0 else 0)
		baseReg = (sib & 7) | (8 if d.rex & 1 != 0 else 0)
		if (sib & 7) == 5 and md == 0:
			parts = signedHex(d.imm32())
		else:
			parts = regs64[baseReg].copy()
		if index != 4:
			parts += " + {regs64[index]}{("*{scale}" if scale > 1 else "")}"
	elif rm == 5 and md == 0:
		disp = d.imm32()
		return ModRm(
			md,
			reg = r,
			rm = -1,
			text = "{sizeWord(size)} ptr [rip + {signedHex(disp)}]"
		)
	else:
		parts = regs64[rm | (8 if d.rex & 1 != 0 else 0)].copy()
	if md == 1:
		disp = d.imm8()
		parts += " - 0x{hex(-disp)}" if disp < 0 else " + 0x{hex(disp)}"
	elif md == 2:
		disp = d.imm32()
		parts += " - 0x{hex(-disp)}" if disp < 0 else " + 0x{hex(disp)}"
	ModRm(md, reg = r, rm, text = "{sizeWord(size)} ptr [{parts}]")

# the operands "reg, r/m" (or "r/m, reg" when reversed)
fn regRm(mut d Decoder, size i64, reversed bool):
	m = d.modrm(size, false)
	g = reg(m.reg, size)
	if reversed: "{m.text}, {g}"
	else: "{g}, {m.text}"

# one instruction at the decoder's offset: its mnemonic and operands
fn decodeOne(mut d Decoder) (str, str):
	d.rex = 0
	d.opsize = false
	d.rep = 0
	d.vex = false
	d.vexL = false
	d.target = -1
	b = d.byte()
	while b in [0x66, 0xF2, 0xF3, 0xF0, 0x2E, 0x3E, 0x64, 0x65]:
		if b == 0x66:
			d.opsize = true
		elif b == 0xF2 or b == 0xF3:
			d.rep = b
		b = d.byte()
	if b >= 0x40 and b <= 0x4F:
		d.rex = b & 15
		b = d.byte()
	if b == 0xC4 or b == 0xC5: return d.decodeVex(b)
	if b == 0x0F: return d.decodeTwoByte()
	size = d.opSize()
	d.decodeOneAlu(b, size)

fn decodeOneAlu(mut d Decoder, b i64, size i64) (str, str):
	if b < 0x40 and (b & 7) < 6:
		op = aluNames[b >> 3].copy()
		k = b & 7
		if k == 0: return (op, d.regRm(1, true))
		if k == 1: return (op, d.regRm(size, true))
		if k == 2: return (op, d.regRm(1, false))
		if k == 3: return (op, d.regRm(size, false))
		if k == 4: return (op, "al, {signedHex(d.imm8())}")
		return (op, "{reg(0, size)}, {signedHex(d.imm32())}")
	if b >= 0x50 and b <= 0x57:
		return ("push", regs64[(b & 7) | (8 if d.rex & 1 != 0 else 0)].copy())
	if b >= 0x58 and b <= 0x5F:
		return ("pop", regs64[(b & 7) | (8 if d.rex & 1 != 0 else 0)].copy())
	if b == 0x63:
		m = d.modrm(4, false)
		return ("movsxd", "{reg(m.reg, 8)}, {m.text}")
	if b == 0x68: return ("push", signedHex(d.imm32()))
	if b == 0x6A: return ("push", signedHex(d.imm8()))
	if b == 0x69 or b == 0x6B:
		ops = d.regRm(size, false)
		v = d.imm32() if b == 0x69 else d.imm8()
		return ("imul", "{ops}, {signedHex(v)}")
	if b >= 0x70 and b <= 0x7F:
		rel = d.imm8()
		d.target = d.rva + (d.at - d.img.offsetOf(d.rva)) + rel
		return ("j{conditions[b & 15]}", "0x{hex(d.target)}")
	if b in [0x80, 0x81, 0x83]:
		s = 1 if b == 0x80 else size
		m = d.modrm(s, false)
		v = d.imm32() if b == 0x81 else d.imm8()
		return (aluNames[m.reg & 7].copy(), "{m.text}, {signedHex(v)}")
	if b == 0x84: return ("test", d.regRm(1, true))
	if b == 0x85: return ("test", d.regRm(size, true))
	if b == 0x86 or b == 0x87: return ("xchg", d.regRm(1 if b == 0x86 else size, true))
	if b == 0x88: return ("mov", d.regRm(1, true))
	if b == 0x89: return ("mov", d.regRm(size, true))
	if b == 0x8A: return ("mov", d.regRm(1, false))
	if b == 0x8B: return ("mov", d.regRm(size, false))
	if b == 0x8D: return ("lea", d.regRm(size, false))
	if b == 0x90: return ("nop", "")
	if b == 0x98: return ("cdqe" if size == 8 else "cwde", "")
	if b == 0x99: return ("cqo" if size == 8 else "cdq", "")
	if b == 0xA8: return ("test", "al, {signedHex(d.imm8())}")
	if b == 0xA9: return ("test", "{reg(0, size)}, {signedHex(d.imm32())}")
	d.decodeOneMov(b, size)

fn decodeOneMov(mut d Decoder, b i64, size i64):
	if b >= 0xB0 and b <= 0xB7:
		return ("mov", "{reg((b & 7) | (8 if d.rex & 1 != 0 else 0), 1)}, {signedHex(d.imm8())}")
	if b >= 0xB8 and b <= 0xBF:
		r = (b & 7) | (8 if d.rex & 1 != 0 else 0)
		if size == 8:
			v = d.img.data.i64le(d.at)
			d.at += 8
			return ("movabs", "{reg(r, 8)}, 0x{hex(v)}")
		return ("mov", "{reg(r, size)}, {signedHex(d.imm32())}")
	if b in [0xC0, 0xC1, 0xD0, 0xD1, 0xD2, 0xD3]:
		s = 1 if b in [0xC0, 0xD0, 0xD2] else size
		m = d.modrm(s, false)
		count = signedHex(d.imm8()) if b <= 0xC1 else "1" if b <= 0xD1 else "cl"
		return (shiftNames[m.reg & 7].copy(), "{m.text}, {count}")
	if b == 0xC3: return ("ret", "")
	if b == 0xC6 or b == 0xC7:
		s = 1 if b == 0xC6 else size
		m = d.modrm(s, false)
		v = d.imm8() if b == 0xC6 else d.imm32()
		return ("mov", "{m.text}, {signedHex(v)}")
	if b == 0xCC: return ("int3", "")
	if b == 0xE8 or b == 0xE9:
		rel = d.imm32()
		d.target = d.rva + (d.at - d.img.offsetOf(d.rva)) + rel
		return ("call" if b == 0xE8 else "jmp", "0x{hex(d.target)}")
	if b == 0xEB:
		rel = d.imm8()
		d.target = d.rva + (d.at - d.img.offsetOf(d.rva)) + rel
		return ("jmp", "0x{hex(d.target)}")
	if b == 0xF6 or b == 0xF7:
		s = 1 if b == 0xF6 else size
		m = d.modrm(s, false)
		names = ["test", "test", "not", "neg", "mul", "imul", "div", "idiv"]
		if m.reg & 7 <= 1:
			v = d.imm8() if b == 0xF6 else d.imm32()
			return ("test", "{m.text}, {signedHex(v)}")
		return (names[m.reg & 7].copy(), m.text)
	if b == 0xFE or b == 0xFF:
		k = (i64(d.img.data[d.at]) >> 3) & 7
		s = 1 if b == 0xFE else 8 if k in [2, 4, 6] else size
		m = d.modrm(s, false)
		names = ["inc", "dec", "call", "call far", "jmp", "jmp far", "push", "?"]
		return (names[k].copy(), m.text)
	("db", "0x{hex(b)}")

# the scalar and packed SSE operations of 0F 5x, by their low nibble (with the 66/F3/F2 forms)
fn sseName(op i64, d Decoder):
	base = [
		"",
		"sqrt",
		"rsqrt",
		"rcp",
		"and",
		"andn",
		"or",
		"xor",
		"add",
		"mul",
		"",
		"",
		"sub",
		"min",
		"div",
		"max"
	]
	name = base[op & 15]
	suffix = "ss" if d.rep == 0xF3 else "sd" if d.rep == 0xF2 else "pd" if d.opsize else "ps"
	name + suffix

fn decodeTwoByte(mut d Decoder) (str, str):
	b = d.byte()
	size = d.opSize()
	if b == 0x05: return ("syscall", "")
	if b == 0x0B: return ("ud2", "")
	if b == 0xA2: return ("cpuid", "")
	if b == 0x31: return ("rdtsc", "")
	if b >= 0x80 and b <= 0x8F:
		rel = d.imm32()
		d.target = d.rva + (d.at - d.img.offsetOf(d.rva)) + rel
		return ("j{conditions[b & 15]}", "0x{hex(d.target)}")
	if b >= 0x90 and b <= 0x9F:
		m = d.modrm(1, false)
		return ("set{conditions[b & 15]}", m.text)
	if b >= 0x40 and b <= 0x4F: return ("cmov{conditions[b & 15]}", d.regRm(size, false))
	if b == 0x1F:
		m = d.modrm(size, false)
		return ("nop", m.text)
	if b == 0xAF: return ("imul", d.regRm(size, false))
	if b == 0xBA:
		m = d.modrm(size, false)
		names = ["?", "?", "?", "?", "bt", "bts", "btr", "btc"]
		return (names[m.reg & 7].copy(), "{m.text}, {signedHex(d.imm8())}")
	if b in [0xA3, 0xAB, 0xB3, 0xBB]:
		name = "bt" if b == 0xA3 else "bts" if b == 0xAB else "btr" if b == 0xB3 else "btc"
		return (name, d.regRm(size, true))
	if b in [0xB6, 0xB7, 0xBE, 0xBF]:
		m = d.modrm(1 if b == 0xB6 or b == 0xBE else 2, false)
		return ("movzx" if b <= 0xB7 else "movsx", "{reg(m.reg, size)}, {m.text}")
	if b == 0xB8 and d.rep == 0xF3: return ("popcnt", d.regRm(size, false))
	if b == 0xBC or b == 0xBD:
		name = ("tzcnt" if b == 0xBC else "lzcnt") if d.rep == 0xF3
			else ("bsf" if b == 0xBC else "bsr")
		return (name, d.regRm(size, false))
	d.decodeTwoByteSse(b)

fn decodeTwoByteSse(mut d Decoder, b i64) (str, str):
	vsize = 8 if d.rep == 0xF2 else 4 if d.rep == 0xF3 else 16
	if b == 0x10 or b == 0x11:
		name = "movss" if d.rep == 0xF3
			else "movsd" if d.rep == 0xF2
			else "movupd" if d.opsize
			else "movups"
		m = d.modrm(vsize, true)
		x = d.xmm(m.reg)
		return (name, "{x}, {m.text}" if b == 0x10 else "{m.text}, {x}")
	if b == 0x28 or b == 0x29:
		m = d.modrm(16, true)
		x = d.xmm(m.reg)
		return (
			"movapd" if d.opsize else "movaps",
			"{x}, {m.text}" if b == 0x28 else "{m.text}, {x}"
		)
	if b == 0x2A:
		m = d.modrm(8 if d.rex & 8 != 0 else 4, false)
		return ("cvtsi2sd" if d.rep == 0xF2 else "cvtsi2ss", "{d.xmm(m.reg)}, {m.text}")
	if b == 0x2C or b == 0x2D:
		m = d.modrm(vsize, true)
		name = ("cvtt" if b == 0x2C else "cvt") + ("sd2si" if d.rep == 0xF2 else "ss2si")
		return (name, "{reg(m.reg, 8 if d.rex & 8 != 0 else 4)}, {m.text}")
	if b == 0x2E or b == 0x2F:
		m = d.modrm(8 if d.opsize else 4, true)
		name = ("ucomis" if b == 0x2E else "comis") + ("d" if d.opsize else "s")
		return (name, "{d.xmm(m.reg)}, {m.text}")
	if b == 0x5A:
		m = d.modrm(vsize, true)
		name = "cvtss2sd" if d.rep == 0xF3
			else "cvtsd2ss" if d.rep == 0xF2
			else "cvtpd2ps" if d.opsize
			else "cvtps2pd"
		return (name, "{d.xmm(m.reg)}, {m.text}")
	if b >= 0x51 and b <= 0x5F:
		m = d.modrm(vsize, true)
		return (sseName(b, d), "{d.xmm(m.reg)}, {m.text}")
	d.decodeTwoBytePacked(b)

fn decodeTwoBytePacked(mut d Decoder, b i64):
	if b == 0x6E or b == 0x7E:
		if b == 0x7E and d.rep == 0xF3:
			m = d.modrm(8, true)
			return ("movq", "{d.xmm(m.reg)}, {m.text}")
		m = d.modrm(8 if d.rex & 8 != 0 else 4, false)
		name = "movq" if d.rex & 8 != 0 else "movd"
		return (
			name,
			"{d.xmm(m.reg)}, {m.text}" if b == 0x6E else "{m.text}, {d.xmm(m.reg)}"
		)
	if b == 0xD6:
		m = d.modrm(8, true)
		return ("movq", "{m.text}, {d.xmm(m.reg)}")
	if b == 0x6F or b == 0x7F:
		m = d.modrm(16, true)
		name = "movdqu" if d.rep == 0xF3 else "movdqa"
		return (
			name,
			"{d.xmm(m.reg)}, {m.text}" if b == 0x6F else "{m.text}, {d.xmm(m.reg)}"
		)
	if b == 0x38:
		op = d.byte()
		m = d.modrm(16, true)
		return ("op 0f38 {hex(op)}", "{d.xmm(m.reg)}, {m.text}")
	if b == 0x3A:
		op = d.byte()
		m = d.modrm(16, true)
		return ("op 0f3a {hex(op)}", "{d.xmm(m.reg)}, {m.text}, {signedHex(d.imm8())}")
	known = [
		"pxor 0xef",
		"paddd 0xfe",
		"paddq 0xd4",
		"psubq 0xfb",
		"pand 0xdb",
		"por 0xeb",
		"pcmpeqb 0x74",
		"pcmpeqd 0x76",
		"punpcklqdq 0x6c",
		"pshufd 0x70",
		"shufps 0xc6"
	]
	m = d.modrm(16, true)
	name = "op 0f {hex(b)}"
	for k in known:
		parts = k.split(" ")
		if parts[1] == "0x{hex(b)}":
			name = parts[0].copy()
	if b == 0xC2:
		return (
			"cmp{("ss" if d.rep == 0xF3 else "sd" if d.rep == 0xF2 else "pd" if d.opsize else "ps")}",
			"{d.xmm(m.reg)}, {m.text}, {signedHex(d.imm8())}"
		)
	if b in [0x70, 0xC6, 0x71, 0x72, 0x73, 0xC4, 0xC5]:
		return (name, "{d.xmm(m.reg)}, {m.text}, {signedHex(d.imm8())}")
	(name, "{d.xmm(m.reg)}, {m.text}")

# An AVX instruction: the VEX prefix gives the map, the 66/F3/F2 form, the width and a second
# source register.
fn decodeVex(mut d Decoder, first i64):
	b1 = d.byte()
	d.vex = true
	if first == 0xC5:
		d.rex = 4 if b1 & 0x80 == 0 else 0
		d.vexReg = (~(b1 >> 3)) & 15
		d.vexL = b1 & 4 != 0
		d.vexMap = 1
		pp = b1 & 3
		d.opsize = pp == 1
		d.rep = 0xF3 if pp == 2 else 0xF2 if pp == 3 else 0
	else:
		b2 = d.byte()
		d.rex = (4 if b1 & 0x80 == 0 else 0) | (2 if b1 & 0x40 == 0 else 0) | (1 if b1 & 0x20 == 0 else 0) | (
			8 if b2 & 0x80 != 0 else 0
		)
		d.vexMap = b1 & 31
		d.vexReg = (~(b2 >> 3)) & 15
		d.vexL = b2 & 4 != 0
		pp = b2 & 3
		d.opsize = pp == 1
		d.rep = 0xF3 if pp == 2 else 0xF2 if pp == 3 else 0
	op = d.byte()
	if d.vexMap == 1 and op == 0x77: return ("vzeroall" if d.vexL else "vzeroupper", "")
	width = 32 if d.vexL else 16
	vsize = 8 if d.rep == 0xF2 or (d.vexMap == 1 and op == 0xD6) else 4 if d.rep == 0xF3 else width
	m = d.modrm(vsize, true)
	dst = d.xmm(m.reg)
	src2 = d.xmm(d.vexReg)
	if d.vexMap == 1:
		if op == 0x10 or op == 0x11:
			kind = "movupd" if d.opsize else "movups"
			if d.rep == 0xF3:
				kind = "movss"
			elif d.rep == 0xF2:
				kind = "movsd"
			name = "v{kind}"
			return (name, "{dst}, {m.text}" if op == 0x10 else "{m.text}, {dst}")
		if op == 0xD6 and d.opsize: return ("vmovq", "{m.text}, {dst}")
		if op == 0x28 or op == 0x29:
			name = "vmovapd" if d.opsize else "vmovaps"
			return (name, "{dst}, {m.text}" if op == 0x28 else "{m.text}, {dst}")
		if op == 0x6F or op == 0x7F:
			name = "vmovdqu" if d.rep == 0xF3 else "vmovdqa"
			return (name, "{dst}, {m.text}" if op == 0x6F else "{m.text}, {dst}")
		if op >= 0x51 and op <= 0x5F and op != 0x5A and op != 0x5B:
			if op == 0x51: return ("v{sseName(op, d)}", "{dst}, {m.text}")
			return ("v{sseName(op, d)}", "{dst}, {src2}, {m.text}")
		if op == 0xC6:
			return (
				"vshufpd" if d.opsize else "vshufps",
				"{dst}, {src2}, {m.text}, {signedHex(d.imm8())}"
			)
		if op == 0xC2:
			kind = "ss" if d.rep == 0xF3 else "sd" if d.rep == 0xF2 else "pd" if d.opsize else "ps"
			p = d.imm8()
			predicates = ["eq", "lt", "le", "unord", "neq", "nlt", "nle", "ord"]
			if p >= 0 and p < 8: return ("vcmp{predicates[p]}{kind}", "{dst}, {src2}, {m.text}")
			return ("vcmp{kind}", "{dst}, {src2}, {m.text}, {signedHex(p)}")
		if op == 0x50:
			return ("vmovmskpd" if d.opsize else "vmovmskps", "{reg(m.reg, 4)}, {m.text}")
		if op in [0x70, 0x71, 0x72, 0x73, 0xC4, 0xC5]:
			return (
				"vex.0f {hex(op)}",
				"{dst}, {src2}, {m.text}, {signedHex(d.imm8())}"
			)
		return ("vex.0f {hex(op)}", "{dst}, {src2}, {m.text}")
	if d.vexMap == 2:
		fma = ["vfmadd", "vfmsub", "vfnmadd", "vfnmsub"]
		if op >= 0x98 and op <= 0xBF:
			order = "132" if op < 0xA8 else "213" if op < 0xB8 else "231"
			kind = (op & 15) - 8
			if kind >= 0 and kind < 8:
				name = fma[kind / 2] + order +
					(
						("sd" if d.vexW or d.rex & 8 != 0 else "ss") if kind % 2 == 1
						else ("pd" if d.rex & 8 != 0 else "ps")
					)
				return (name, "{dst}, {src2}, {m.text}")
		if op == 0x00: return ("vpshufb", "{dst}, {src2}, {m.text}")
		if op in [0x18, 0x19, 0x58, 0x59, 0x78]:
			names = ["vbroadcastss", "vbroadcastsd", "vpbroadcastd", "vpbroadcastq", "vpbroadcastb"]
			k = 0 if op == 0x18
				else 1 if op == 0x19
				else 2 if op == 0x58
				else 3 if op == 0x59
				else 4
			return (names[k].copy(), "{dst}, {m.text}")
		return ("vex.0f38 {hex(op)}", "{dst}, {src2}, {m.text}")
	imm = signedHex(d.imm8())
	if op == 0x18: return ("vinsertf128", "{dst}, {src2}, {m.text}, {imm}")
	if op == 0x19: return ("vextractf128", "{m.text}, {dst}, {imm}")
	if op == 0x06: return ("vperm2f128", "{dst}, {src2}, {m.text}, {imm}")
	("vex.0f3a {hex(op)}", "{dst}, {src2}, {m.text}, {imm}")

# ---------- where to start ----------

# the decoder moved to the instruction at rva
fn seek(mut d Decoder, rva i64):
	d.at = d.img.offsetOf(rva)
	d.rva = rva

# the target of the first call after the entry point: the program's main
fn findMain(mut d Decoder):
	d.seek(d.img.entry)
	loop 32:
		start = d.at
		name, _ = d.decodeOne()
		if name == "call" and d.target >= 0: return d.target
		d.rva += d.at - start
	fail("no call after the entry point")
	0

# the target of main's n-th direct call
fn nthCall(mut d Decoder, n i64):
	d.seek(d.findMain())
	seen = 0
	loop 4000:
		start = d.at
		name, _ = d.decodeOne()
		if name == "call" and d.target >= 0:
			seen += 1
			if seen == n: return d.target
		if name == "ret": break
		d.rva += d.at - start
	fail("main has no call {n}")
	0

# s in hexadecimal (0x optional), or -1
fn parseHex(s str):
	i64.parse("0x{s[(2 if s.startsWith("0x") else 0)..]}") ?? -1

# where `which` starts (see above), in the executable whose map is fns
fn disasmStart(mut d Decoder, fns perf.MapFunction[], which str):
	if which == "": return d.findMain()
	if which.startsWith("call") and i64.parse(which[4..]) is n: return d.nthCall(n)
	if rvaOf(fns, which) is named: return named
	at = parseHex(which)
	if at < 0: fail("{which} is neither a function of the map, callN nor an RVA")
	at

# the function `which` names, disassembled to its end (the next function of the map)
fn traceDisasm(exe str, which str):
	fns = functionsOf(exe)
	d = Decoder(img = readImage(exe))
	start = d.disasmStart(fns, which)
	f = perf.functionAtRva(fns, start)
	end = fns[f + 1].start if f >= 0 and f + 1 < fns.len else start + 400
	d.seek(start)
	while d.rva < end and d.at < d.img.data.len:
		at = d.at
		name, operands = d.decodeOne()
		eprint("{hex(d.rva):0>8}  {name:<8} {operands}")
		d.rva += d.at - at
