# An Android app's picture (engine/pixels.zap's, in an app): scaled to fill the screen keeping its
# shape, at the rate the screen is asked to match.

# the picture's zoom in a window of ww x wh: the largest that fits, a fraction too (a phone's
# screen is seldom a whole number of a console's)
fn pictureZoom(ww i64, wh i64, width i64, height i64) f64:
	(f64(ww) / width).min(f64(wh) / height)

pub fn setFrameRate(mut w PixelWindow, perSecond f64):
	_ = w
	appSetFrameRate(perSecond)
