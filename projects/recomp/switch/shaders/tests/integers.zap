# Integer instructions from a hand-written compute program (fields as Ryujinx's InstDecoders reads
# them): the condition codes of IADD.CC and IADD.X, ISETP.X, P2R and R2P of the codes or by a
# register, the saturations, IADD3.RS, IMNMX's extended modes, XMAD.CSFU, IMAD, IMUL, LEA, PRMT;
# their module builds, and maxwell's integer helpers give the CPU's results on both backends.

import recomp.switch.shaders.checks

fn words():
	[
		checks.regs(0x5C10, 0, 2, 4, [(47, 1)]),   # IADD.CC R0, R2, R4
		checks.regs(0x5C10, 1, 3, 5, [(43, 1)]),   # IADD.X R1, R3, R5
		checks.regs(0x5C10, 6, 2, 4, [(48, 1), (50, 1)]),   # IADD.SAT R6, R2, -R4
		checks.regs(0x5CC0, 7, 2, 4, [(37, 1), (39, 6)]),   # IADD3.RS R7, R2, R4, R6
		checks.regs(0x5CE0, 8, 0, 2, [(10, 2), (12, 1), (13, 1), (50, 1)]),   # I2I.S8.S32.SAT R8, R2
		checks.regs(0x5C20, 9, 2, 4, [(39, 7), (43, 1)]),   # IMNMX.U32.XLO R9, R2, R4, PT
		checks.regs(0x5B00, 10, 2, 4, [(39, 6), (48, 1), (49, 1), (50, 3)]),   # XMAD.S16.S16.CSFU R10, R2, R4, R6
		checks.regs(0x5A00, 11, 2, 4, [(39, 6), (48, 1), (53, 1), (54, 1)]),   # IMAD.HI R11, R2, R4, R6
		checks.regs(0x5C38, 12, 2, 4, [(39, 1)]),   # IMUL.U32.U32.HI R12, R2, R4
		checks.regs(0x1F00, 13, 2, 0x1_2345),   # IMUL32I R13, R2, 0x12345
		checks.regs(0x5BD0, 14, 2, 4, [(39, 3), (48, 7)]),   # LEA R14, R2, R4, 3
		checks.regs(0x5BD8, 15, 2, 4, [(28, 5), (37, 1), (39, 3), (48, 7)]),   # LEA.HI R15, -R2, R4, R3, 5
		checks.regs(0x36C0, 16, 2, 0x3210, [(39, 4)]),   # PRMT R16, R2, 0x3210, R4
		checks.alu(0x5B60, [(0, 7), (3, 0), (8, 3), (20, 5), (39, 7), (43, 1), (49, 1)]),   # ISETP.LT.U32.X P0, PT, R3, R5, PT
		checks.regs(0x5CE8, 17, 2, 4),   # P2R R17, PR, R2, R4
		checks.regs(0x38E8, 18, 2, 0xF, [(40, 1)]),   # P2R R18, CC, R2, 0xF
		checks.regs(0x38F0, 0, 2, 0xF, [(40, 1)]),   # R2P CC, R2, 0xF
		checks.regs(0x5CF0, 0, 2, 4),   # R2P PR, R2, R4
		checks.regs(0x5C40, 255, 2, 4, [(47, 1), (48, 7)]),   # LOP.AND.CC RZ, R2, R4
	]

fn source():
	checks.sourceOf("Integers", words())

test "each integer instruction translates, nothing left out":
	parts = [
		"cf = maxwell.carriesOut(ca, cb, 0)",
		"of = ((ca ^ cr) & (cb ^ cr)) >> 31 != 0",
		"r3 + r5 + maxwell.bit(cf)",
		"cr = 0x7FFF_FFFF + (ca >> 31) if ((ca ^ cr) & (cb ^ cr)) >> 31 != 0 else cr",
		"((r2 + r4) >> 16) + r6",
		"maxwell.saturateInt(maxwell.extractBits(r2, 0, 32, true), 8, true, true)",
		"r2.min(r4)",
		"r6 - (((maxwell.half(r2, false, true) >> 31) + (maxwell.half(r4, false, true) >> 31)) << 16)",
		"maxwell.mulHigh(r2, r4, true, true) + r6",
		"maxwell.mulHigh(r2, r4, false, false)",
		"r2 * 74565",
		"(r2 << 3) + r4",
		"~maxwell.funnelShift(r2, r3, 5, false, false) + r4 + maxwell.bit((r2 << 5) == 0)",
		"maxwell.permuteBytes(r2, r4, 12816, 0)",
		"test = (r3 < r5 or (r3 == r5 and not cf))",
		"mask = (r4 & 127) << 0",
		"(r2 & 4294967280) | (1 if zf else 0) | (2 if sf else 0) | (4 if cf else 0) | (8 if of else 0)",
		"of = (r2 >> 3) & 1 != 0",
		"p6 = (r2 >> 6) & 1 != 0 if (mask >> 6) & 1 != 0 else p6",
		"cr = r2 & r4"
	]
	expect source().lacks(parts).isEmpty

test "the integer instructions' module builds":
	expect checks.built([source()], "integers") == ""

# a kernel giving, for each pair of `pairs`, maxwell's high products (unsigned, A signed, B
# signed, both), the carry of a + b + 1 and three saturations of a; and PRMT's of two fixed words
# by each pair of `selectors` (a selector and a mode)
helpersKernel = """
	import recomp.switch.shaders.maxwell

	pub type Checks:
		pairs u32[]
		selectors u32[]
		out u32[]

	pub fn helpers(mut p Checks):
		i = globalId.x
		a = p.pairs[2 * i]
		b = p.pairs[2 * i + 1]
		at = 9 * i
		p.out[at] = maxwell.mulHigh(a, b, false, false)
		p.out[at + 1] = maxwell.mulHigh(a, b, true, false)
		p.out[at + 2] = maxwell.mulHigh(a, b, false, true)
		p.out[at + 3] = maxwell.mulHigh(a, b, true, true)
		p.out[at + 4] = maxwell.bit(maxwell.carriesOut(a, b, 1))
		p.out[at + 5] = maxwell.saturateInt(a, 8, true, true)
		p.out[at + 6] = maxwell.saturateInt(a, 16, false, false)
		p.out[at + 7] = maxwell.saturateInt(a, 8, true, false)
		selector = p.selectors[2 * i]
		p.out[at + 8] = maxwell.permuteBytes(0x4433_2211, 0x8877_6655, selector, p.selectors[2 * i + 1])
	"""

# the kernel run on the backend, each result against the CPU's (PRMT's against PTX's table)
helpersProgram = r"""
	# the bits of a signed or unsigned 32-bit word as an i64
	fn wide(v u32, signed bool) i64:
		i64(i32.wrap(v)) if signed else i64(v)

	# the results that differ from the CPU's, printed
	fn wrongs() i64:
		values u32[] = [0, 1, 0xFFFF_FFFF, 0x8000_0000, 0x7FFF_FFFF, 0x1234_5678, 0xDEAD_BEEF, 300, 0xFFFF_FF80, 0x0001_0000, 70000, 0xFFFF_0001, 5, 0x8000_0001, 0xC000_0000, 127]
		pairs u32[] = []
		for k, v in values:
			pairs.extend([v, values[(k * 7 + 3) % values.len]])
		# (selector, mode, the word PTX's prmt gives of 0x88776655:44332211)
		prmts = [(0x3210, 0, 0x4433_2211), (0x7654, 0, 0x8877_6655), (0x0123, 0, 0x1122_3344), (0x8888, 0, 0), (0xFFFF, 0, 0xFFFF_FFFF), (1, 1, 0x5544_3322), (1, 2, 0x7788_1122), (2, 3, 0x3333_3333), (1, 4, 0x4433_2222), (2, 5, 0x3333_2211), (1, 6, 0x4433_4433)]
		selectors u32[] = []
		for k in 0..values.len:
			s, mode, _ = prmts[k % prmts.len]
			selectors.extend([u32(s), u32(mode)])
		kernel = engine.newKernel(compute(kernels.helpers, 16))
		engine.setParams(kernel, kernels.Checks(pairs = pairs.copy(), selectors, out = fill(values.len * 9, u32(0))))
		kernel.dispatch(1)
		bytes = kernel.readStorage(2, values.len * 36)
		wrong = 0
		for k in 0..values.len:
			a = pairs[2 * k]
			b = pairs[2 * k + 1]
			got = (0..9).map(bytes.u32le((k * 9 + it) * 4))
			wants u32[] = []
			for (sa, sb) in [(false, false), (true, false), (false, true), (true, true)]:
				wants.push(u32.wrap(u64.wrap(wide(a, sa)) * u64.wrap(wide(b, sb)) >> 32))
			wants.push(1 if i64(a) + i64(b) + 1 > 0xFFFF_FFFF else 0)
			wants.push(u32.wrap(wide(a, true).clamp(-128, 127)))
			wants.push(a.min(0xFFFF))
			wants.push(0 if wide(a, true) < 0 else a.min(0xFF))
			_, _, permuted = prmts[k % prmts.len]
			wants.push(u32(permuted))
			for n in 0..9:
				if got[n] != wants[n]:
					print("{a:x} {b:x} result {n}: {got[n]:x} in place of {wants[n]:x}")
					wrong += 1
		wrong
	"""

test "maxwell's integer helpers on the GPU give the CPU's products, carries, saturations and PRMT" for gpu in [
	"vulkan",
	"d3d12"
]:
	expect checks.gpuVerdict("integers", gpu, helpersKernel, helpersProgram) == "right"
