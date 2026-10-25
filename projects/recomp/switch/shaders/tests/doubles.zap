# f64 instructions from a hand-written compute program (fields as yuzu's double_*.cpp,
# floating_point_conversion_*.cpp and multi_function.cpp read them): DADD of a register, a
# constant buffer's pair and an immediate, DMUL, DFMA, DMNMX, DSETP, DSET, F2F, F2I and I2F of f64,
# MUFU.RCP64H and RSQ64H; their module builds, and maxwell's f64 helpers run on both backends.

import fs
import recomp.switch.shaders

exit u64 = 0xE300_0000_0007_000F

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

fn words():
	[
		regs(0x5C70, 0, 2, 4),   # DADD R0, R2, R4
		alu(0x4C70, [(0, 6), (8, 2), (20, 4), (34, 1)]),   # DADD R6, R2, c[1][0x10]
		regs(0x3870, 8, 2, 0x3_FF80),   # DADD R8, R2, 1.5
		regs(0x5C80, 10, 2, 4, [(48, 1)]),   # DMUL R10, R2, -R4
		regs(0x5B70, 12, 2, 4, [(39, 6)]),   # DFMA R12, R2, R4, R6
		regs(0x5C50, 14, 2, 4, [(39, 7)]),   # DMNMX R14, R2, R4, PT (the less)
		alu(0x5B80, [(0, 7), (3, 1), (8, 2), (20, 4), (39, 7), (48, 1)]),   # DSETP.LT P1, PT, R2, R4, PT
		regs(0x5900, 16, 2, 4, [(39, 7), (48, 4), (52, 1)]),   # DSET.GT.BF R16, R2, R4, PT
		alu(0x5CA8, [(0, 18), (8, 0xE), (20, 2)]),   # F2F.F32.F64 R18, R2
		alu(0x5CA8, [(0, 20), (8, 0xB), (20, 3)]),   # F2F.F64.F32 R20, R3
		alu(0x5CA8, [(0, 22), (8, 0xF), (20, 2), (39, 9)]),   # F2F.F64.F64.FLOOR R22, R2
		alu(0x5CB0, [(0, 24), (8, 0xE), (12, 1), (20, 2), (39, 3)]),   # F2I.S32.F64.TRUNC R24, R2
		alu(0x5CB8, [(0, 26), (8, 0xB), (13, 1), (20, 5)]),   # I2F.F64.S32 R26, R5
		alu(0x5080, [(0, 28), (8, 3), (20, 6)]),   # MUFU.RCP64H R28, R3
		alu(0x5080, [(0, 29), (8, 3), (20, 7)]),   # MUFU.RSQ64H R29, R3
		i64.wrap(exit)
	]

fn program():
	shaders.Program(stage = .Compute, header = none, words = words(), start = 0)

test "each f64 instruction translates, nothing left out":
	s = shaders.newTable().translateProgram(program(), "T", [], [1, 1, 1], {}) ?? fail
	expect s.missing.isEmpty
	a = "f64.fromWords(r2, r3)"
	b = "f64.fromWords(r4, r5)"
	parts = [
		"wide = {a} + {b}",
		"16384 + 5]",
		"{a} + f64.fromWords(0, 1073217536)",
		"{a} * -{b}",
		"maxwell.fusedDouble({a}, {b}, f64.fromWords(r6, r7))",
		"({a}).min({b})",
		"test = {a} < {b}",
		"0x3F80_0000 if {a} > {b} else 0",
		"(f32({a})).toBits()",
		"wide = f64(f32.fromBits(r3))",
		"maxwell.roundDouble({a}, 1)",
		"maxwell.doubleToInt(maxwell.roundDouble({a}, 3), true)",
		"wide = f64(i32(r5))",
		"(1.0 / f64.fromWords(0, r3)).highWord()",
		"maxwell.rsqrtHigh(r3)",
		"wide.highWord()"
	]
	absent = parts.filter(it not in s.text)
	if not absent.isEmpty: print(s.text)
	expect absent.isEmpty

test "the f64 instructions' module builds":
	source = shaders.Source(name = "Doubles", program = program(), group = [1, 1, 1])
	out = "projects/recomp/switch/out/tests/doubles"
	done, said = shaders.writeBuilt([source], out) ?? fail
	expect done.shaders.all(.missing.isEmpty)
	if said != "": print(said)
	expect said == ""

# a kernel giving, for each double of `inputs`, maxwell's roundings of it (by each mode), its F2I
# and its high word's RSQ64H
helpersKernel = """
	import recomp.switch.shaders.maxwell

	pub type Checks:
		inputs u32[]
		out u32[]

	pub fn helpers(mut p Checks):
		i = globalId.x
		x = f64.fromWords(p.inputs[2 * i], p.inputs[2 * i + 1])
		at = 10 * i
		for mode in 0..4:
			r = maxwell.roundDouble(x, mode)
			p.out[at + 2 * mode] = r.lowWord()
			p.out[at + 2 * mode + 1] = r.highWord()
		p.out[at + 8] = maxwell.doubleToInt(x, true)
		p.out[at + 9] = maxwell.rsqrtHigh(p.inputs[2 * i + 1])
	"""

# the kernel run on the backend, each result against the CPU's (RSQ64H within a part in 10^6)
helpersProgram = r"""
	import engine
	import checks

	# the results that differ from the CPU's, printed
	fn wrongs() i64:
		xs = [2.5, 3.5, -2.5, -0.7, 0.3, 7.0, 1e300, 123456.75, -2_147_483_648.5, 5e9, 0.001, 4.0, 1.0 / 3.0, -1e-5, 1e15 + 0.5, 0.5]
		words u32[] = []
		for x in xs:
			words.extend([x.lowWord(), x.highWord()])
		kernel = engine.newKernel(compute(checks.helpers, 16))
		engine.setParams(kernel, checks.Checks(inputs = words, out = fill(xs.len * 10, u32(0))))
		kernel.dispatch(1)
		bytes = kernel.readStorage(1, xs.len * 40)
		wrong = 0
		for i, x in xs:
			t = x.trunc()
			near = x.round()
			if (x - t).abs() == 0.5 and (t * 0.5).trunc() == t * 0.5: near = t
			for mode, want in [near, x.floor(), x.ceil(), t]:
				at = (i * 10 + 2 * mode) * 4
				got = f64.fromWords(bytes.u32le(at), bytes.u32le(at + 4))
				if got != want:
					print("{x} mode {mode}: {got} in place of {want}")
					wrong += 1
			int = i64(x.clamp(-2_147_483_648.0, 2_147_483_647.0))
			if bytes.u32le((i * 10 + 8) * 4) != u32.wrap(int):
				print("{x}: F2I {bytes.u32le((i * 10 + 8) * 4)} in place of {int}")
				wrong += 1
			high = f64.fromWords(0, x.highWord())
			root = f64.fromWords(0, bytes.u32le((i * 10 + 9) * 4))
			if high > 0.0 and ((root - 1.0 / high.sqrt()) * high.sqrt()).abs() > 1e-6:
				print("{x}: RSQ64H {root} in place of {1.0 / high.sqrt()}")
				wrong += 1
		wrong

	mut frames = engine.newFrames()
	mut win = engine.openWindow("Helpers", 16, 16)
	if not win.nextFrame(frames): fail("the window closed")
	n = wrongs() if engine.gpuDoubles() else 0
	said = "right" if n == 0 else "{n} WRONG"
	print("{engine.backendName()}: {said if engine.gpuDoubles() else "no f64 on this device"}")
	"""

test "maxwell's f64 helpers on the GPU give the CPU's roundings, F2I and RSQ64H" for gpu in [
	"vulkan",
	"d3d12"
]:
	# (in the project's out/, where its modules are found)
	dir = "projects/recomp/switch/out/tests/helpers{gpu}"
	_ = fs.createDir("{dir}/checks")
	fs.writeFile("{dir}/checks/checks.gpu.zap", helpersKernel) ?? fail("{error}")
	fs.writeFile("{dir}/helpers.zap", helpersProgram) ?? fail("{error}")
	run = Process.output("{zapPath()} run {dir}/helpers.zap", vars = [runAssignment("gpu={gpu}")])
	said = run.out.trimmed().split(": ").last ?? ""
	if said != "right": print(run.out)
	expect said in ["right", "no f64 on this device"]
