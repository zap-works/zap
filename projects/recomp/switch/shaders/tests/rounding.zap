# The rounding modes of the conversions to an f32 (fields as yuzu's
# integer_floating_point_conversion.cpp and floating_point_conversion_floating_point.cpp read
# them): I2F and F2F of an f64 down, up and toward zero translate, and maxwell's roundings on the
# GPU give the floats each mode picks.

import recomp.switch.shaders.checks

fn words():
	[
		0x5CB8 << 48 | 7 << 16 | 1 << 39 | 1 << 13 | 2 << 10 | 2 << 8 | 2 << 20,   # I2F.F32.S32.RM R0, R2
		0x5CA8 << 48 | 7 << 16 | 3 << 39 | 3 << 10 | 2 << 8 | 2 << 20 | 1   # F2F.F32.F64.RZ R1, R2
	]

test "I2F and F2F to an f32 by each rounding mode translate, nothing left out":
	parts = ["maxwell.intToFloat(r2, true, 1)", "maxwell.narrow(f64.fromWords(r2, r3), 3)"]
	expect checks.lacks(checks.sourceOf("Rounding", words()), parts).isEmpty

# a kernel giving, for each of 16 integers (read signed when `signed[i]` is 1) and doubles, the
# conversions by modes 1 to 3 (down, up, toward zero), as f32 bits; the doubles' only where the
# device has them
roundingKernel = """
	import recomp.switch.shaders.maxwell

	pub type Checks:
		integers u32[]
		signed u32[]
		doubles u32[]
		withDoubles u32
		out u32[]

	pub fn roundings(mut p Checks):
		i = globalId.x
		for mode in 1..4:
			f = maxwell.intToFloat(p.integers[i], p.signed[i] == 1, u32(mode))
			p.out[i * 6 + mode - 1] = f.toBits()
			if p.withDoubles == 1:
				x = f64.fromWords(p.doubles[2 * i], p.doubles[2 * i + 1])
				p.out[i * 6 + mode + 2] = maxwell.narrow(x, u32(mode)).toBits()
	"""

# the kernel run on the backend, each conversion against the float its mode picks
roundingProgram = r"""
	big = 3.4028234663852886e38

	# (integer, signed, down, up, toward zero)
	integerCases = [
		(5, true, 5.0, 5.0, 5.0),
		(16_777_217, true, 16_777_216.0, 16_777_218.0, 16_777_216.0),
		(-16_777_217, true, -16_777_218.0, -16_777_216.0, -16_777_216.0),
		(2_147_483_647, true, 2_147_483_520.0, 2_147_483_648.0, 2_147_483_520.0),
		(-2_147_483_648, true, -2_147_483_648.0, -2_147_483_648.0, -2_147_483_648.0),
		(4_294_967_295, false, 4_294_967_040.0, 4_294_967_296.0, 4_294_967_040.0),
		(33_554_435, false, 33_554_432.0, 33_554_436.0, 33_554_432.0),
		(0, false, 0.0, 0.0, 0.0)
	]

	# (double, down, up, toward zero)
	doubleCases = [
		(1.0 + 1.0 / 1_073_741_824.0, 1.0, 1.0000001192092896, 1.0),
		(-1.0 - 1.0 / 1_073_741_824.0, -1.0000001192092896, -1.0, -1.0),
		(1e40, big, 1.0 / 0.0, big),
		(0.5, 0.5, 0.5, 0.5),
		(1e-50, 0.0, 1.401298464324817e-45, 0.0),
		(-3.0e9 - 1.0, -3.000000256e9, -3.0e9, -3.0e9),
		(0.1, 0.09999999403953552, 0.10000000149011612, 0.09999999403953552),
		(-0.1, -0.10000000149011612, -0.09999999403953552, -0.09999999403953552)
	]

	fn wrongs() i64:
		integers u32[] = []
		signed u32[] = []
		for (v, isSigned, _, _, _) in integerCases:
			integers.push(u32.wrap(v))
			signed.push(1 if isSigned else 0)
		doubles u32[] = []
		for (x, _, _, _) in doubleCases:
			doubles.extend([x.lowWord(), x.highWord()])
		withDoubles u32 = 1 if engine.gpuDoubles() else 0
		kernel = engine.newKernel(compute(kernels.roundings, 8))
		out = fill(48, u32(0))
		engine.setParams(kernel, kernels.Checks(integers, signed, doubles, withDoubles, out))
		kernel.dispatch(1)
		bytes = kernel.readStorage(3, 48 * 4)
		wrong = 0
		for k, (v, _, down, up, zero) in integerCases:
			for mode, want in [down, up, zero]:
				got = f32.fromBits(bytes.u32le((k * 6 + mode) * 4))
				if got != f32(want):
					print("I2F of {v} mode {mode + 1}: {got} in place of {want}")
					wrong += 1
		if withDoubles == 0: return wrong
		for k, (x, down, up, zero) in doubleCases:
			for mode, want in [down, up, zero]:
				got = f32.fromBits(bytes.u32le((k * 6 + mode + 3) * 4))
				if got != f32(want):
					print("F2F of {x} mode {mode + 1}: {got} in place of {want}")
					wrong += 1
		wrong
	"""

test "maxwell's roundings on the GPU pick each mode's float" for gpu in ["vulkan", "d3d12"]:
	expect checks.gpuVerdict("rounding", gpu, roundingKernel, roundingProgram) == "right"
