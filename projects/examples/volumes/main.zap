# 3D textures, cubes and cube arrays read by a compute stage (probes/) on the backend the
# environment picks: a 3D texture at its texels' centres, by an offset and fetched, a cube and
# two cubes toward each face, and a shadow map compared at a level and with a bias; what it read
# is checked against the textures' bytes.
#   zap run projects/examples/volumes/main.zap             (from the repository's root; ZAP_RUN=gpu=d3d12 for Direct3D 12)

import engine
import probes

mut frames = engine.newFrames()
mut win = engine.openWindow("Volumes", 64, 64)
mut r = engine.newRenderer()

fn words(values u32[]):
	out = []
	for v in values:
		out.pushU32le(v)
	out

fogOf = (
	x i64,
	y i64,
	z i64
): u32(x * 60 + 7) | u32(y * 50 + 9) << 8 | u32(z * 40 + 11) << 16 | u32(255) << 24
faceOf = (
	cube i64,
	face i64
): u32(face * 40 + 5) | u32(cube * 100 + 20) << 8 | u32(77) << 16 | u32(255) << 24

fog = engine.newVolume(4, 4, 4, words((0..64).map(fogOf(it % 4, it / 4 % 4, it / 16))))
sky = engine.newCube(2, (0..6).map(words(fill(4, faceOf(0, it)))))
rooms = engine.newCube(2, (0..12).map(words(fill(4, faceOf(it / 6, it % 6)))))
shadow = engine.newShadowTarget(8)
kernel = engine.newKernel(compute(probes.probe, 64))
if not win.nextFrame(frames):
	fail("the window closed")
r.useTarget(shadow)
r.clearDepthTarget(0.5)
engine.setParams(
	kernel,
	probes.Probes(
		fog = fog.volume(),
		sky = sky.cube(),
		rooms = rooms.cubes(),
		shadow = shadow.shadowMap(),
		out = fill(64 * 8, u32(0))
	)
)
kernel.dispatch(1)
bytes = kernel.readStorage(0, 64 * 8 * 4)
mut wrong = 0
for i in 0..64:
	x = i % 4
	y = i / 4 % 4
	z = i / 16
	shifted = fogOf((x + 1).min(3), y, (z - 1).max(0))
	expected = [
		fogOf(x, y, z),
		shifted,
		fogOf(x, y, z),
		faceOf(0, i % 6),
		faceOf(i / 6 % 2, i % 6),
		u32(100),
		u32(4 * 100 + 2 * 10 + 2),
		u32(7)
	]
	for k, want in expected:
		got = bytes.u32le((i * 8 + k) * 4)
		if got != want:
			if wrong < 8:
				print("probe {i} read {k}: {got} in place of {want}")
			wrong += 1
print("{engine.backendName()}: {64 * 8} reads, {"right" if wrong == 0 else "{wrong} WRONG"}")
if wrong != 0:
	exit(1)
