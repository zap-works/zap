# An Android app's keys (engine/window.zap's, in an app): a keyboard's or a game pad's, by
# Android's key codes, as the runtime reads them from the app's input queue.

# whether the key is held now
pub fn isKeyDown(k Key) bool:
	if k.androidCode() is code: return isAppKeyDown(code)
	false

# the key's Android key code (KeyEvent's KEYCODE_), none for one Android has not
fn androidCode(k Key) i64?:
	match k:
		Char(c):
			if c >= 'a' and c <= 'z': return 29 + c - 'a'
			if c >= 'A' and c <= 'Z': return 29 + c - 'A'
			if c >= '0' and c <= '9': return 7 + c - '0'
			none
		F(n): 130 + n
		Left: 21
		Up: 19
		Right: 22
		Down: 20
		Space: 62
		Escape: 111
		Enter: 66
		Shift: 59
		Ctrl: 113
		Raw(c): c
		Backspace: 67
		Tab: 61

# whether a game pad's button is held
pub fn isPadDown(b PadButton) bool:
	isAppPadDown(b.index())

# where a game pad's axis stands now
pub fn padAxis(a PadAxis) f32:
	f32(appPadAxis(a.index()))

pub fn touches() Vec2[]:
	at = appTouches()
	(0..at.len / 2).map(Vec2(f32(at[2 * it]), f32(at[2 * it + 1])))

pub fn hasTouchScreen() bool:
	true
