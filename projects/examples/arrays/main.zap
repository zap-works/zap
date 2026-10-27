# Two textures read through a texture array (Texture[]) at literal indices on the backend the
# environment picks: the compiler gives such an array a length, so a device without descriptor
# indexing binds it too (Vulkan 1.1, or 1.2 without it: vulkan=1.2, Android's emulator). A pass
# draws the left half of its target from the first texture and the right half from the second;
# a pixel of each half is checked.
#   zap run projects/examples/arrays/main.zap                 (from the repository's root; ZAP_RUN=gpu=d3d12 for Direct3D 12)

import engine
import halves

width = 32
height = 16

mut frames = engine.newFrames()
mut win = engine.openWindow("Arrays", width, height)
mut r = engine.newRenderer()
set = engine.newTargetSet(width, height, [.Rgba8], none)
pass = engine.newScreenPass(shader(halves.pixel))
red = engine.newTextureOfFormat(1, 1, [200, 30, 10, 255])
blue = engine.newTextureOfFormat(1, 1, [20, 40, 220, 255])

if not win.nextFrame(frames):
	fail("the window closed")
r.useTargetSet(set)
r.drawScreenPass(pass, halves.Pictures(pictures = [red.texture(), blue.texture()]))
pixels = set.readColor(0)

# the bytes of pixel x, y
fn pixelAt(x i64, y i64):
	at = (y * width + x) * 4
	pixels[at..at + 4].copy()

left = pixelAt(3, 8)
right = pixelAt(28, 8)
drawn = left == [200, 30, 10, 255] and right == [20, 40, 220, 255]
print("{engine.backendName()}: left {left}, right {right}: {"right" if drawn else "WRONG"}")
if not drawn:
	exit(1)
