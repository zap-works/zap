# A set of targets (engine/render/target.zap) on the backend the environment picks: one draw
# writes a color into an RGBA8 target and a pair into an RG16F one, scissored to the left half,
# the second target blended additively over what it was cleared to; both are read back, then the
# first is read by a later draw into the left half of an R8 target (its viewport: the right half
# of what it reads lands left of the middle), read back too. Every pixel checked must hold
# what the formats make of the values.
#   zap run projects/examples/targets/main.zap                (from the repository's root; ZAP_RUN=gpu=d3d12 for Direct3D 12)

import engine
import rhi.core
import split

width = 64
height = 32

mut failures = 0

fn expectBytes(what str, got u8[], want u8[]):
	if got != want:
		print("{what}: {got} in place of {want}")
		failures += 1

# the bytes of pixel x, y of a target of `size` bytes a pixel
fn pixelBytes(bytes u8[], x i64, y i64, size i64) u8[]:
	at = (y * width + x) * size
	bytes[at..at + size].copy()

mut frames = engine.newFrames()
mut win = engine.openWindow("Targets", width, height)
mut r = engine.newRenderer()
set = engine.newTargetSet(width, height, [.Rgba8, .Rg16Float], .D32Float)
picked = engine.newTargetSet(width, height, [.R8], .D24S8)
writer = engine.newScreenPass(shader(split.pixel))
reader = engine.newScreenPass(shader(split.green))

if not win.nextFrame(frames):
	fail("the window closed")
r.useTargetSet(set)
r.setDepth(false, false, false)
r.clearColorTarget(0, Vec4(0.0, 0.0, 0.0, 0.0))
r.clearColorTarget(1, Vec4(0.25, 1.0, 0.0, 0.0))
r.clearDepthTarget(1.0)
added = core.TargetBlend(on = true, srcColor = 1, dstColor = 1, srcAlpha = 1, dstAlpha = 1)
r.setTargetBlends([core.TargetBlend(), added])
r.setScissor(core.Scissor(x = 0, y = 0, width = width / 2, height = height))
r.drawScreenPass(
	writer,
	split.Values(color = Vec4(1.0, 0.2, 0.6, 1.0), pair = Vec4(0.5, -2.0, 0.0, 0.0))
)
r.setTargetBlends([])
colors = engine.readColor(set, 0)
if not win.nextFrame(frames):
	fail("the window closed")
pairs = engine.readColor(set, 1)
if not win.nextFrame(frames):
	fail("the window closed")
r.useTargetSet(picked)
r.clearTarget(Vec4(1.0, 1.0, 1.0, 1.0))
r.setViewport(core.Viewport(x = 0.0, y = 0.0, width = f32(width / 2), height = f32(height)))
r.drawScreenPass(reader, split.Source(picture = set.colorTexture(0)))
greens = engine.readColor(picked, 0)

# RGBA8: 0.2 and 0.6 as 51 and 153; RG16F: 0.25 + 0.5 = 0.75 (0x3A00), 1 - 2 = -1
# (0xBC00), and as cleared 0.25 (0x3400), 1 (0x3C00)
expectBytes("RGBA8 drawn", colors.pixelBytes(5, 7, 4), [u8(255), 51, 153, 255])
expectBytes("RGBA8 cleared", colors.pixelBytes(50, 20, 4), [u8(0), 0, 0, 0])
expectBytes("RG16F blended", pairs.pixelBytes(5, 7, 4), [u8(0x00), 0x3A, 0x00, 0xBC])
expectBytes("RG16F cleared", pairs.pixelBytes(50, 20, 4), [u8(0x00), 0x34, 0x00, 0x3C])
expectBytes("R8 sampled", greens.pixelBytes(5, 7, 1), [u8(51)])
expectBytes("R8 sampled", greens.pixelBytes(20, 7, 1), [u8(0)])
expectBytes("R8 cleared", greens.pixelBytes(50, 20, 1), [u8(255)])
print("{engine.backendName()}: {"right" if failures == 0 else "WRONG"}")
if failures > 0:
	exit(1)
