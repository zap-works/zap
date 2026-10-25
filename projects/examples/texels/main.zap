# Texels fetched by a compute stage (reads/) on the backend the environment picks: a color
# texture's at two levels and by an offset, an unsigned and a signed integer texture's numbers as
# they are, a two-component one's, and texels outside a level or past the levels, which are 0;
# what it read is checked against the textures' bytes.
#   zap run projects/examples/texels/main.zap             (from the repository's root; ZAP_RUN=gpu=d3d12 for Direct3D 12)

import engine
import reads

mut frames = engine.newFrames()
mut win = engine.openWindow("Texels", 64, 64)

fn words(values u32[]):
	out = []
	for v in values:
		out.pushU32le(v)
	out

colorOf = (
	x i64,
	y i64
): u32(x * 40 + 10) | u32(y * 50 + 5) << 8 | u32(200 - x - y) << 16 | u32(255) << 24
small = (x i64, y i64): u32(x * 90 + 3) | u32(y * 70 + 7) << 8 | u32(33) << 16 | u32(128) << 24
countOf = (x i64, y i64): u32(x * 1_000_003 + y * 77 + 0x8000_0000)
signOf = (x i64, y i64): x * 7 - y * 13 - 20
colors = engine.newTextureOfFormat(
	4,
	4,
	words((0..16).map(colorOf(it % 4, it / 4))),
	mips = [words((0..4).map(small(it % 2, it / 2)))]
)
counts = engine.newTextureOfFormat(
	4,
	4,
	words((0..16).map(countOf(it % 4, it / 4))),
	format = .R32Uint
)
signs = engine.newTextureOfFormat(
	4,
	4,
	words((0..16).map(u32.wrap(signOf(it % 4, it / 4)))),
	format = .R32Int
)
pairs = engine.newTextureOfFormat(
	2,
	2,
	words((0..8).map(u32(it * 3 + 1))),
	format = .Rg32Uint
)
kernel = engine.newKernel(compute(reads.read, 16))
if not win.nextFrame(frames):
	fail("the window closed")
engine.setParams(
	kernel,
	reads.Reads(
		colors = colors.texture(),
		counts = counts.uintTexture(),
		signs = signs.intTexture(),
		pairs = pairs.uintTexture(),
		out = fill(16 * 8, 0)
	)
)
kernel.dispatch(1)
bytes = kernel.readStorage(0, 16 * 8 * 4)
mut wrong = 0
for i in 0..16:
	x = i % 4
	y = i / 4
	pair = (x % 2 + y % 2 * 2) * 2
	shifted = colorOf(x + 1, y - 1) if x < 3 and y > 0 else 0
	expected = [
		colorOf(x, y),
		small(x / 2, y / 2),
		countOf(x, y),
		u32(signOf(y, x) + 1000),
		u32(pair * 3 + 1) + u32(pair * 3 + 4) * 65_536,
		u32(0),
		shifted,
		u32(4 * 10 + 2)
	]
	for k, want in expected:
		got = bytes.u32le((i * 8 + k) * 4)
		if got != want:
			if wrong < 8:
				print("texel {x},{y} read {k}: {got} in place of {want}")
			wrong += 1
print("{engine.backendName()}: {16 * 8} reads, {"right" if wrong == 0 else "{wrong} WRONG"}")
if wrong != 0:
	exit(1)
