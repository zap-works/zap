# The interface's sounds as SkyrimSE.exe 1.7.104 asks for them: the game plays one by the editor id of
# its sound (UI::PlaySound 0x1409920a0, "UIFavorite"), here queued in the world for the sound
# system to play (game.sound's playAsk) as a frame ends. A notice with a sound is ShowHUDMessage
# (0x140991a30): the same text is not shown again, nor its sound, for 5 s.

# how long a notice is not shown again (0x1388 ms in the table of the last eight)
pub noticeRepeatSeconds = 5.0
noticeTableSize = 8

# one sound asked for: an interface sound by the editor id of its SNDR or SOUN, else a sound
# descriptor (SNDR) by its form id, played as its own record says
pub type SoundAsk:
	name str = ""
	descriptor i64 = 0

# The interface sound named `name` asked for.
pub fn playUi(mut w GameWorld, name str):
	w.soundAsks.push(SoundAsk(name = name.copy()))

# The sound descriptor `descriptor` asked for, played where the player is.
pub fn playDescriptorForPlayer(mut w GameWorld, descriptor i64):
	if descriptor != 0: w.soundAsks.push(SoundAsk(descriptor))

# The sounds asked for since the last call, in order.
pub fn takeSoundAsks(mut w GameWorld) SoundAsk[]:
	out = w.soundAsks.copy()
	w.soundAsks.clear()
	out

# Whether the notice `text` may show now: not when it showed within noticeRepeatSeconds, and
# remembered (the table holds eight) when it may.
fn noticeMayShow(mut w GameWorld, text str):
	now = w.playSeconds
	for t in w.noticeTimes.keys():
		if now - w.noticeTimes[t] >= noticeRepeatSeconds: w.noticeTimes.remove(t)
	if text in w.noticeTimes: return false
	if w.noticeTimes.len < noticeTableSize: w.noticeTimes[text.copy()] = now
	true

# The HUD message `text` with its sound (ShowHUDMessage): shown and sounded unless the same text
# showed in the last five seconds.
pub fn showNotice(mut w GameWorld, text str, sound str):
	if not w.noticeMayShow(text): return
	if not text.isEmpty: w.notifications.push(text.copy())
	if not sound.isEmpty: w.playUi(sound)
