# Storage images written and read by compute stages (canvas/) on the backend the environment
# picks: a color image's texels read and written, atomics counting into an image of unsigned
# integers, the least of a value kept in one of signed integers, a compare-exchange that takes
# and one that does not; a second kernel reads them into a buffer, checked here.
#   zap run projects/examples/images/main.zap             (from the repository's root; ZAP_RUN=gpu=d3d12 for Direct3D 12)

import engine
import canvas

mut frames = engine.newFrames()
mut win = engine.openWindow("Images", 64, 64)

fn words(values u32[]):
	out = []
	for v in values:
		out.pushU32le(v)
	out

colorOf = (x i64, y i64): u32(2 * (x + y)) | u32(4 * x) << 8 | u32(2 * y) << 16 | u32(100) << 24
colors = engine.newImage(16, 16, words((0..256).map(colorOf(it % 16, it / 16))))
startCounts = (0..16).map(u32(3) if it == 14 else u32(0))
counts = engine.newImage(8, 2, words(startCounts), format = .R32Uint)
lows = engine.newImage(1, 1, words([u32(1000)]), format = .R32Int)
paint = engine.newKernel(compute(canvas.paint, 16, 16))
read = engine.newKernel(compute(canvas.read, 16, 16))
if not win.nextFrame(frames):
	fail("the window closed")
engine.setParams(
	paint,
	canvas.Canvas(colors = colors.image(), counts = counts.uintImage(), lows = lows.intImage())
)
paint.dispatch(1)
engine.setParams(
	read,
	canvas.Reading(
		colors = colors.image(),
		counts = counts.uintImage(),
		lows = lows.intImage(),
		out = fill(273, u32(0))
	)
)
read.dispatch(1)
bytes = read.readStorage(0, 273 * 4)
mut wrong = 0
fn check(what str, got i64, want i64):
	if got != want:
		if wrong < 8:
			print("{what}: {got} in place of {want}")
		wrong += 1
for i in 0..256:
	x = i % 16
	y = i / 16
	want = (x + y + 64) | (2 * x) << 8 | y << 16 | 255 << 24
	check("texel {x},{y}", i64(bytes.u32le(i * 4)), want)
for i in 0..16:
	want = 64 if i < 4 else 9 if i == 13 else 3 if i == 14 else 16 if i == 15 else 0
	check("count {i}", i64(bytes.u32le((256 + i) * 4)), want)
check("least", i64(bytes.u32le(272 * 4)), 1000 - 15)
print("{engine.backendName()}: 273 values, {"right" if wrong == 0 else "{wrong} WRONG"}")
if wrong != 0:
	exit(1)
