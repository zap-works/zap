# Textures staged through the frame's ring on the backend the environment picks: 48 BC7 ones of
# 1 MB each made in one frame (a level's load), far more than the ring holds, then drawn for a few
# frames. The ring is emptied and used again as it fills, so the host-visible memory stays near
# its own size: the frame does not make it the size of everything it staged.
#   zap run projects/examples/staged/main.zap          (from the repository's root; ZAP_RUN=gpu=d3d12 for Direct3D 12)

import engine

size = 1024
count = 48
hostBudget = 16 * 1_048_576

mut frames = engine.newFrames()
mut win = engine.openWindow("Staged textures", 64, 64)
mut r = engine.newRenderer()
pixels u8[] = fill(size * size, 0)   # BC7: a byte a pixel
textures = []
for k in 0..4:
	if not win.nextFrame(frames):
		fail("the window closed")
	if k == 0:
		loop count:
			textures.push(engine.newTextureOfFormat(size, size, pixels, format = .Bc7))
	r.beginFrame(win.width, win.height, Vec4(0.0, 0.0, 0.0, 1.0), engine.Camera())
	for t in textures:
		r.draw(t.texture(), 0.0, 0.0)
	r.showFrame(win, frames)
peak = engine.hostMemoryPeak()
print(
	"{engine.backendName()}: {count} MB of textures staged, host-visible peak {peak / 1_048_576} MB"
)
if peak > hostBudget:
	exit(1)
