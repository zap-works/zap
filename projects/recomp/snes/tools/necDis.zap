# The firmware of a NEC uPD77C25 (DSP-1 to DSP-4) read as pseudo-code: each instruction of its
# program a line, as console/necDsp.zap runs it, its jumps and calls named by label, the routine
# each call reaches marked, and the data ROM's words listed after. To read what a command does
# when it is written anew without the firmware. Run from the repository root, the player's dump:
#
#   zap run projects/recomp/snes/tools/necDis.zap <dsp1b.rom> [out.txt] [--lift]

import fs

srcNames = [
	"TRB",
	"A",
	"B",
	"TR",
	"DP",
	"RP",
	"ROM[RP]",
	"SGN",
	"DR!",
	"DR",
	"SR",
	"SI",
	"SI",
	"K",
	"L",
	"RAM[DP]"
]
dstNames = [
	"-",
	"A",
	"B",
	"TR",
	"DP",
	"RP",
	"DR!",
	"SR",
	"SOL",
	"SOM",
	"K",
	"K,L=ROM[RP]",
	"L,K=RAM[DP|40]",
	"L",
	"TRB",
	"RAM[DP]"
]
aluNames = [
	"",
	"OR",
	"AND",
	"XOR",
	"SUB",
	"ADD",
	"SBB",
	"ADC",
	"DEC",
	"INC",
	"NOT",
	"SAR1",
	"RCL1",
	"SLL2",
	"SLL4",
	"XCHG"
]
pNames = ["RAM[DP]", "IDB", "M", "N"]

fn conditionName(kind i64):
	if kind >= 0x80 and kind < 0xB0:
		acc = "B" if kind & 4 != 0 else "A"
		flag = ["C", "Z", "OV0", "OV1", "S0", "S1"][(kind - 0x80) >> 3]
		return "{"" if kind & 2 != 0 else "!"}{acc}.{flag}"
	match kind:
		0xB0: "DPL==0"
		0xB1: "DPL!=0"
		0xB2: "DPL==F"
		0xB3: "DPL!=F"
		0xBC: "!RQM"
		0xBE: "RQM"
		_: "cond{kind:03X}"

# one instruction as text, and the address it jumps or calls to (-1 none)
fn instructionText(op i64, at i64):
	match op & 0xC0_0000:
		0x80_0000:
			target = (at & 0x2000) | ((op & 3) << 11) | ((op >> 2) & 0x7FF)
			kind = (op >> 13) & 0x1FF
			match kind:
				0x00: ("JMP SO", -1)
				0x100, 0x101: ("JMP L{target:04X}", target)
				0x140, 0x141: ("CALL L{target:04X}", target)
				_: ("IF {conditionName(kind)} JMP L{target:04X}", target)
		0xC0_0000: ("{dstNames[op & 0x0F]} = #{(op >> 6) & 0xFFFF:04X}", -1)
		_:
			parts = []
			alu = (op >> 16) & 0x0F
			if alu != 0:
				acc = "B" if (op >> 15) & 1 != 0 else "A"
				parts.push("{acc} = {aluNames[alu]}({acc}, {pNames[(op >> 20) & 3]})")
			src = srcNames[(op >> 4) & 0x0F]
			dst = dstNames[op & 0x0F]
			if dst != "-" or src != "TRB": parts.push("{dst} = {src}")
			match (op >> 13) & 3:
				1: parts.push("DPL++")
				2: parts.push("DPL--")
				3: parts.push("DPL=0")
				_: pass
			if (op >> 9) & 0x0F != 0: parts.push("DPH^={(op >> 9) & 0x0F:X}")
			if (op >> 8) & 1 != 0: parts.push("RP--")
			if op & 0xC0_0000 == 0x40_0000: parts.push("RET")
			("NOP" if parts.isEmpty else parts.join("; "), -1)

# The lifted reading (--lift): within a run of instructions, DP and RP followed as constants, so a
# RAM or ROM operand reads as its address, and the multiplier's M and N as the product of the K
# and L the instruction before loaded. A label or a call forgets them (other paths arrive there).
type Lift:
	dp i64 = -1
	rp i64 = -1
	k str = "K"
	l str = "L"
	product str = "K*L"

	fn ram(at i64):
		"RAM[{at:02X}]" if at >= 0 else "RAM[DP]"

	fn rom():
		"ROM[{rp:03X}]" if rp >= 0 else "ROM[RP]"

	fn source(s i64):
		match s:
			6: self.rom()
			13: k.copy()
			14: l.copy()
			15: self.ram(dp)
			_: srcNames[s].copy()

	fn forget():
		dp = -1
		rp = -1
		k = "K"
		l = "L"
		product = "K*L"

	fn load(dest i64, value str):
		match dest:
			4: dp = -1
			5: rp = -1
			10: k = value.copy()
			11:
				k = value.copy()
				l = self.rom()
			12:
				l = value.copy()
				k = self.ram(dp | 0x40 if dp >= 0 else -1)
			13: l = value.copy()
			_: pass

	fn line(op i64, at i64):
		text, _ = instructionText(op, at)
		if op & 0xC0_0000 == 0x80_0000:
			if text.startsWith("CALL"): self.forget()
			return text
		if op & 0xC0_0000 == 0xC0_0000:
			imm = (op >> 6) & 0xFFFF
			dest = op & 0x0F
			self.load(dest, "#{imm:04X}")
			if dest == 4: dp = imm & 0xFF
			if dest == 5: rp = imm & 0x3FF
			product = "{k}*{l}"
			return "{dstNames[dest]} = #{imm:04X}"
		parts = []
		alu = (op >> 16) & 0x0F
		src = self.source((op >> 4) & 0x0F)
		if alu != 0:
			acc = "B" if (op >> 15) & 1 != 0 else "A"
			operand = match (op >> 20) & 3:
				0: self.ram(dp)
				1: src.copy()
				2: "hi({product})"
				_: "lo({product})"
			parts.push("{acc} = {aluNames[alu]}({acc}, {operand})")
		dest = op & 0x0F
		if dest == 15:
			parts.push("{self.ram(dp)} = {src}")
		elif dest != 0:
			parts.push("{dstNames[dest]} = {src}")
		self.load(dest, src)
		if dest != 4 and dp >= 0:
			match (op >> 13) & 3:
				1: dp = (dp & 0xF0) | ((dp + 1) & 0x0F)
				2: dp = (dp & 0xF0) | ((dp - 1) & 0x0F)
				3: dp &= 0xF0
				_: pass
			dp ^= ((op >> 9) & 0x0F) << 4
		if (op >> 8) & 1 != 0 and dest != 5 and rp >= 0: rp -= 1
		product = "{k}*{l}"
		if op & 0xC0_0000 == 0x40_0000: parts.push("RET")
		"NOP" if parts.isEmpty else parts.join("; ")

paths = args.positional()
if paths.isEmpty: fail("usage: zap run projects/recomp/snes/tools/necDis.zap <dsp.rom> [out.txt]")
bytes = fs.readBytes(paths[0]) ?? fail("cannot read {paths[0]}: {error}")
programWords = 0x800
code = []
for i in 0..programWords:
	code.push(bytes[3 * i] | (i64(bytes[3 * i + 1]) << 8) | (i64(bytes[3 * i + 2]) << 16))
labels {i64: bool} = {}
called {i64: bool} = {}
for at, op in code:
	text, target = instructionText(op, at)
	if target >= 0:
		labels[target] = true
		if text.startsWith("CALL"): called[target] = true
lines = []
lifting = args.hasFlag("--lift")
lift = Lift()
for at, op in code:
	if at in called: lines.push("\n; ---- routine L{at:04X}")
	if at in labels: lift.forget()
	plain, _ = instructionText(op, at)
	lifted = lift.line(op, at)
	text = lifted if lifting else plain
	mark = "L{at:04X}:" if at in labels else ""
	lines.push("{mark:<7}{at:04X}  {op:06X}  {text}")
lines.push("\n; ---- data ROM")
dataAt = 3 * programWords
for row in 0..64:
	words = []
	for k in 0..16:
		i = dataAt + 2 * (row * 16 + k)
		words.push("{bytes[i] | (i64(bytes[i + 1]) << 8):04X}")
	lines.push("{row * 16:03X}: {words.join(" ")}")
text = "{lines.join("\n")}\n"
if paths.len > 1:
	fs.writeFile(paths[1], text) ?? fail("cannot write {paths[1]}: {error}")
	print("{code.len} instructions, {labels.len} labels, {called.len} routines: {paths[1]}")
else:
	print(text)
