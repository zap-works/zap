# An Android app's picture (engine/pixels.zap's, in an app): copied into the app's window by the
# runtime (runtime/system/linux/app/window.zap), which scales it to the screen keeping its shape.

import image

pub type PixelWindow:
	width i64   # the picture's
	height i64

# the app's window, for a picture of width x height (the title and the zoom are the system's)
pub fn openPixelWindow(title str, width i64, height i64, zoom i64, first image.Image) PixelWindow:
	PixelWindow(width, height)

# Shows the picture (of any size, scaled to the screen keeping its shape) and reads the keys; true
# while the app runs (its end ends the process).
pub fn show(mut w PixelWindow, picture image.Image) bool:
	appShowPixels(picture.cells.bytes(), picture.width, picture.height)
	true

pub fn setFrameRate(mut w PixelWindow, perSecond f64):
	appSetFrameRate(perSecond)

pub fn screenSize(w PixelWindow) IVec2:
	width, height = appScreenSize()
	IVec2(i32(width), i32(height))
