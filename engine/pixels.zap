# A picture of pixels shown in a window at an integer zoom, centred on black: what a console's
# frame needs of the engine (the SNES of projects/recomp/snes, the GBA of projects/firered), and
# its pixels converted from the 15-bit BGR such hardware keeps.

import image

pub type PixelWindow:
	window Window
	frames Frames
	renderer Renderer
	texture GpuTexture
	width i64   # the picture's
	height i64

# a window for a picture of width x height, opened `zoom` times that size, `first` its first picture
pub fn openPixelWindow(title str, width i64, height i64, zoom i64, first image.Image) PixelWindow:
	PixelWindow(
		window = openWindow(title, width * zoom, height * zoom),
		frames = newFrames(),
		renderer = newRenderer(),
		texture = first.newTexture(),
		width,
		height
	)

# Shows the picture at the largest whole zoom the window holds; false once the window was closed.
pub fn show(mut w PixelWindow, picture image.Image) bool:
	if not w.window.nextFrame(w.frames, escEnds = false): return false
	w.texture.updateTexture(picture)
	ww = w.window.width
	wh = w.window.height
	zoom = (ww / w.width).min(wh / w.height).max(1)
	w.renderer.beginFrame(ww, wh, Vec4(0.0, 0.0, 0.0, 1.0), Camera())
	w.renderer.drawQuad(
		w.texture.texture(),
		f32((ww - w.width * zoom) / 2),
		f32((wh - w.height * zoom) / 2),
		f32(w.width * zoom),
		f32(w.height * zoom)
	)
	w.renderer.showFrame(w.window, w.frames)
	true

# the rate the pictures come at, for a screen that can match it (an app's; a window of Windows
# shows at its own)
pub fn setFrameRate(mut w PixelWindow, perSecond f64):
	_ = perSecond

# the size of what the window shows, in the screen's pixels
pub fn screenSize(w PixelWindow) IVec2:
	IVec2(i32(w.window.width), i32(w.window.height))

# the colours (15-bit BGR, 5 bits a channel, rows from the top) as an RGBA image
pub fn bgr555Image(colors u16[], width i64, height i64) image.Image:
	out = fill(width * height * 4, u8(0))
	for i in 0..colors.len:
		c = i64(colors[i])
		out[4 * i] = channel8(c & 0x1F)
		out[4 * i + 1] = channel8((c >> 5) & 0x1F)
		out[4 * i + 2] = channel8((c >> 10) & 0x1F)
		out[4 * i + 3] = 255
	image.fromBytes(width, height, out)

# a 5-bit channel as 8 bits, its top bits repeated below (as the hardware's screen shows it)
fn channel8(v i64) u8:
	u8((v << 3) | (v >> 2))
