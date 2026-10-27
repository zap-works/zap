# The warp's instructions and the special registers from hand-written programs (fields as yuzu's
# warp_shuffle.cpp, vote.cpp and move_special_register.cpp read them): S2R of the lane, its masks,
# the y direction and a register read as 0, SHFL by immediates and registers, VOTE with a ballot,
# in a compute and a pixel stage; their module builds, and SHFL's lanes on the GPU are yuzu's.

import fs
import recomp.switch.shaders

# an S2R of special register sr into rd
fn s2r(d i64, sr i64):
	0xF0C8 << 48 | 7 << 16 | sr << 20 | d

# SHFL rd, ra by `mode`, the index and the mask immediates
fn shfl(d i64, a i64, mode i64, index i64, mask i64):
	0xEF10 << 48 | 7 << 16 | 1 << 28 | 1 << 29 | mode << 30 | 7 << 48 | index << 20 | mask << 34 |
		a << 8 | d

exit u64 = 0xE300_0000_0007_000F

fn words():
	[
		s2r(0, 0),   # S2R R0, SR_LANEID
		s2r(1, 57),   # S2R R1, SR_LTMASK
		s2r(2, 18),   # S2R R2, SR_Y_DIRECTION
		s2r(3, 80),   # S2R R3, SR_CLOCKLO
		shfl(4, 0, 3, 1, 0x1F),   # SHFL.BFLY PT, R4, R0, 0x1, 0x1f
		0xEF10 << 48 | 7 << 16 | 1 << 30 | 1 << 48 | 5 << 20 | 6 << 39 | 1 << 8 | 7,   # SHFL.UP P1, R7, R1, R5, R6
		0x50D8 << 48 | 7 << 16 | 1 << 48 | 2 << 45 | 7 << 39 | 8,   # VOTE.ANY R8, P2, PT
		i64.wrap(exit)
	]

fn program(stage shaders.Stage):
	shaders.Program(stage, header = none, words = words(), start = 0)

test "each warp instruction and special register translates, nothing left out":
	s = shaders.newTable().translateProgram(program(.Compute), "T", [], [32, 1, 1], {}) ?? fail
	expect s.missing.isEmpty
	parts = [
		"r0 = (u32(lane) & 31)",
		"r1 = (u32(1) << (u32(lane) & 31)) - 1",
		"_ = 0x3F80_0000",
		"_ = 0",
		"source = maxwell.shuffleSource(1, 31, 3, (u32(lane) & 31))",
		"shuffled = r0.laneAt(source.max(0))",
		"source = maxwell.shuffleSource(r5, r6, 1, (u32(lane) & 31))",
		"_ = source >= 0",
		"_ = true.laneAny()",
		"(maxwell.bit(true) << (u32(lane) & 31)).laneSum()"
	]
	absent = parts.filter(it not in s.text)
	if not absent.isEmpty: print(s.text)
	expect absent.isEmpty

test "the warp's module builds, its compute stage and a pixel one":
	sources = [
		shaders.Source(name = "Warp", program = program(.Compute), group = [32, 1, 1]),
		shaders.Source(name = "WarpPixel", program = program(.Pixel), group = [])
	]
	done, said = shaders.writeBuilt(sources, "projects/recomp/switch/out/tests/warp") ?? fail
	if said != "": print(said)
	expect said == ""
	expect done.shaders.all(.missing.isEmpty)

# a kernel giving, for each of 32 lanes, the value (10 times its lane) SHFL takes by each mode
# by 1 (IDX, UP, DOWN, BFLY), 0xFFFFFFFF when the source lies outside; and laneCount
shuffleKernel = """
	import recomp.switch.shaders.maxwell

	pub type Checks:
		out u32[]

	pub fn shuffles(mut p Checks):
		at = u32(lane) & 31
		v = at * 10
		masks u32[4] = [0x1F, 0, 0x1F, 0x1F]
		for mode in 0..4:
			source = maxwell.shuffleSource(1, masks[mode], u32(mode), at)
			s = v.laneAt(source.max(0))
			p.out[i32(at) * 4 + mode] = s if source >= 0 else 0xFFFF_FFFF
		if at == 0: p.out[128] = u32(laneCount)
	"""

# the kernel run on the backend, each lane's against yuzu's reading (a GPU running fewer than 32
# lanes together said so and not checked)
shuffleProgram = r"""
	import engine
	import checks

	fn wrongs() i64:
		kernel = engine.newKernel(compute(checks.shuffles, 32))
		engine.setParams(kernel, checks.Checks(out = fill(129, u32(0))))
		kernel.dispatch(1)
		bytes = kernel.readStorage(0, 129 * 4)
		if bytes.u32le(128 * 4) < 32: return -1
		wrong = 0
		for at in 0..32:
			outside = 0xFFFF_FFFF
			wants = [10, (at - 1) * 10 if at > 0 else outside, (at + 1) * 10 if at < 31 else outside, (at ^ 1) * 10]
			for mode in 0..4:
				got = bytes.u32le((at * 4 + mode) * 4)
				if got != u32(wants[mode]):
					print("lane {at} mode {mode}: {got} in place of {wants[mode]}")
					wrong += 1
		wrong

	mut frames = engine.newFrames()
	mut win = engine.openWindow("Shuffles", 16, 16)
	if not win.nextFrame(frames): fail("the window closed")
	n = wrongs()
	said = "right" if n == 0 else "fewer than 32 lanes" if n < 0 else "{n} WRONG"
	print("{engine.backendName()}: {said}")
	"""

test "SHFL's lanes on the GPU are yuzu's" for gpu in ["vulkan", "d3d12"]:
	# (in the project's out/, where its modules are found)
	dir = "projects/recomp/switch/out/tests/warp{gpu}"
	_ = fs.createDir("{dir}/checks")
	fs.writeFile("{dir}/checks/checks.gpu.zap", shuffleKernel) ?? fail("{error}")
	fs.writeFile("{dir}/shuffles.zap", shuffleProgram) ?? fail("{error}")
	run = Process.output("{zapPath()} run {dir}/shuffles.zap", vars = [runAssignment("gpu={gpu}")])
	said = run.out.trimmed().split(": ").last ?? ""
	if said != "right": print(run.out)
	expect said in ["right", "fewer than 32 lanes"]
