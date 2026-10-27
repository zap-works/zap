# Half float instructions from a hand-written compute program (fields as yuzu's
# half_floating_point_*.cpp read them): HADD2 of registers, an immediate and into an f32, HMUL2 of
# a constant by FMZ merged into a half, HFMA2 saturated and of a 32-bit immediate, HSET2.BF and
# HSETP2.H_AND; their module builds.

import recomp.switch.shaders

# an ALU word: the opcode's top 16 bits, PT as the guard, then the fields
fn alu(top i64, fields (i64, i64)[]):
	w = top << 48 | (7 << 16)
	for (at, value) in fields:
		w |= value << at
	w

# an ALU word of rd, ra and B at 20, then the other fields
fn regs(top i64, d i64, a i64, b i64, more (i64, i64)[] = []):
	fields = [(0, d), (8, a), (20, b)]
	fields.extend(more)
	alu(top, fields)

exit u64 = 0xE300_0000_0007_000F

fn words():
	[
		regs(0x5D10, 0, 2, 4),   # HADD2 R0, R2, R4
		regs(0x5D10, 1, 2, 4, [(47, 3), (49, 1)]),   # HADD2.F32 R1, R2.H1_H1, R4
		regs(0x7A00, 3, 2, 0xF0, [(30, 0xF0)]),   # HADD2 R3, R2, 1.0, 1.0
		regs(0x7880, 5, 2, 4, [(34, 1), (39, 2), (49, 2)]),   # HMUL2.FMZ.MRG_H0 R5, R2, c[1][0x10]
		regs(0x5D00, 6, 2, 4, [(32, 1), (39, 8)]),   # HFMA2.SAT R6, R2, R4, R8
		regs(0x2800, 7, 2, 0x3C00_3C00),   # HFMA2.32I R7, R2, 1.0, 1.0, R7
		regs(0x5D18, 9, 2, 4, [(35, 1), (39, 7), (49, 1)]),   # HSET2.BF.LT R9, R2, R4, PT
		alu(0x5D20, [(0, 2), (3, 1), (8, 2), (20, 4), (35, 1), (39, 7), (49, 1)]),   # HSETP2.LT.H_AND P1, P2, R2, R4, PT
		i64.wrap(exit)
	]

fn program():
	shaders.Program(stage = .Compute, header = none, words = words(), start = 0)

test "each half float instruction translates, nothing left out":
	s = shaders.newTable().translateProgram(program(), "T", [], [1, 1, 1], {}) ?? fail
	expect s.missing.isEmpty
	parts = [
		"lo = halfValue(r2) + halfValue(r4)",
		"hi = halfValue(r2 >> 16) + halfValue(r4 >> 16)",
		"_ = halfBits(lo) | halfBits(hi) << 16",
		"lo = halfValue(r2 >> 16) + halfValue(r4)",
		"_ = (halfValue(halfBits(lo))).toBits()",
		"lo = halfValue(r2) + halfValue(1006648320)",
		"maxwell.mulZero(halfValue(r2), f32.fromBits(p.computeConstants[16384 + 4]))",
		"r5 = (r5 & 0xFFFF_0000) | halfBits(lo)",
		"(halfValue(r2) * halfValue(r4) + halfValue(r8)).clamp(0.0, 1.0)",
		"hi = halfValue(r2 >> 16) * halfValue(1006648320 >> 16) + halfValue(r7 >> 16)",
		"(15360 if halfValue(r2) < halfValue(r4) else 0) | (1006632960 if halfValue(r2 >> 16) < halfValue(r4 >> 16) else 0)",
		"test = (halfValue(r2) < halfValue(r4)) and (halfValue(r2 >> 16) < halfValue(r4 >> 16))"
	]
	absent = parts.filter(it not in s.text)
	if not absent.isEmpty: print(s.text)
	expect absent.isEmpty

test "the half float instructions' module builds":
	source = shaders.Source(name = "Halves", program = program(), group = [1, 1, 1])
	done, said = shaders.writeBuilt([source], "projects/recomp/switch/out/tests/halves") ?? fail
	if said != "": print(said)
	expect said == ""
	expect done.shaders.all(.missing.isEmpty)
