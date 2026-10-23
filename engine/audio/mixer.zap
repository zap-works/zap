# The mixer: sounds (decoded samples, mono or stereo, at their own rates) played by voices, each
# with its volume, pan, pitch, looping, fades and, when positional, the gain and pan its place
# gives it from the listener; and music, streamed from its decoder a piece at a time, with
# crossfades between songs. It renders interleaved stereo floats at the output's rate. It does
# nothing but compute: the audio thread feeds it commands and hands its blocks to the device, and
# a test renders it into a buffer and checks the samples.
#
# Resampling is linear interpolation at (the sound's rate / the output's rate) * pitch frames per
# output frame. Gains change smoothly: each block of at most `mixBlock` frames ramps the gains
# from where the last block ended to the new ones, so volume, pan and fade changes do not click; a
# sound starts at its full gain (no ramp) unless it fades in, and a stop without a fade ramps to
# silence over one block.

mixBlock = 256   # frames rendered between gain updates

# What a voice plays with, given when it starts.
pub type PlayParams:
	volume f32 = 1.0
	pan f32 = 0.0   # -1 left .. 1 right (a stereo sound: the balance)
	pitch f32 = 1.0   # playback speed: 2.0 an octave up
	looping bool = false
	fadeIn f32 = 0.0   # seconds from silence to its volume
	positional bool = false   # placed in the world: gain and pan from the listener
	position Vec3 = Vec3(0.0, 0.0, 0.0)
	minDistance f32 = 1.0   # full gain up to this distance
	maxDistance f32 = 60.0   # no quieter past this one
	rolloff f32 = 1.0   # how fast the gain falls between them (1: inverse distance)
	# with `curved`, the gain falls along `curve` instead: its points spread evenly from
	# minDistance to maxDistance, linear between them, the last held past it (curveGain)
	curved bool = false
	curve f32[5] = [1.0, 1.0, 1.0, 1.0, 1.0]

# Where the sounds are heard from: a position, the direction looked at, and up.
pub type Listener:
	position Vec3 = Vec3(0.0, 0.0, 0.0)
	forward Vec3 = Vec3(0.0, 0.0, -1.0)
	up Vec3 = Vec3(0.0, 1.0, 0.0)

# a value that moves linearly to a target, `step` per frame
type Ramp:
	value f32
	target f32
	step f32

fn rampTo(mut r Ramp, target f32, seconds f32, rate i64):
	r.target = target
	frames = seconds * f32(rate)
	if frames < 1.0:
		r.value = target
		r.step = 0.0
	else:
		r.step = (target - r.value).abs() / frames

# the value after n frames
fn advanceRamp(mut r Ramp, n i64):
	if r.value < r.target:
		r.value = (r.value + r.step * f32(n)).min(r.target)
	elif r.value > r.target:
		r.value = (r.value - r.step * f32(n)).max(r.target)

fn steady(v f32):
	Ramp(value = v, target = v, step = 0.0)

# a sound's samples, as the mixer holds them
type MixSound:
	samples f32[]   # interleaved
	channels i64   # 1 or 2
	rate i64
	frames i64

type MixVoice:
	id i64
	sound i64
	params PlayParams
	pos f64 = 0.0   # in the sound's frames
	volume Ramp
	fade Ramp   # 0..1: fades in and out
	stopping bool = false   # ends when the fade reaches 0
	gainL f32 = 0.0   # the gains at the end of the last block
	gainR f32 = 0.0
	fresh bool = true   # not rendered yet: starts at its gains, no ramp
	finished bool = false

# a song playing: its stream, what is decoded of it and not yet played, and its fade
type MusicTrack:
	stream Stream
	buffer f32[] = []   # decoded frames from `base` on, interleaved
	base i64 = 0   # the stream frame buffer[0] holds
	pos f64 = 0.0   # the stream frame playing (fractional)
	ended bool = false   # the stream gave all it has (no loop)
	endFrame i64 = -1   # where it ended
	looping bool
	volume f32
	fade Ramp
	stopping bool = false
	gainL f32 = 0.0
	gainR f32 = 0.0
	fresh bool = true
	finished bool = false

# a stream of samples the program makes as it runs (an emulator's sound), played as they come at
# their own rate; those not played yet wait, the oldest dropped past feedSeconds, so the delay
# stays short when the program makes more than is played
type MixFeed:
	id i64
	sound MixSound
	pos f64 = 0.0   # in the waiting frames

	# the first n frames taken away, those after moved down where they are
	fn dropFrames(n i64):
		dropFirst(sound.samples, n * sound.channels)
		sound.frames -= n
		pos = (pos - n).max(0.0)

feedSeconds = 0.25

# The mixer: everything that sounds, and the output's rate.
pub type Mixer:
	rate i64
	sounds {i64: MixSound} = {}
	voices MixVoice[] = []
	music MusicTrack[] = []
	feeds MixFeed[] = []
	listener Listener = Listener()
	master Ramp = steady(1.0)
	musicVolume Ramp = steady(1.0)
	ended i64[] = []   # voices that ended since the owner last took them
	framesMixed i64 = 0

	# The output's rate changed (another device): the voices keep their place in their sounds.
	fn setRate(r i64):
		rate = r.max(1)

	# Holds a sound's samples (interleaved, 1 or 2 channels) under an id.
	fn addSound(id i64, move samples f32[], channels i64, soundRate i64):
		ch = channels.clamp(1, 2)
		frames = samples.len / ch
		sounds[id] = MixSound(samples, channels = ch, rate = soundRate.max(1), frames)

	# Forgets a sound; the voices playing it end.
	fn removeSound(id i64):
		for mut voice in voices:
			if voice.sound == id:
				voice.finished = true
		sounds.remove(id)

	# Starts voice `id` playing a sound (one not held ends at once).
	fn play(id i64, sound i64, params PlayParams):
		if sound not in sounds:
			ended.push(id)
			return
		v = MixVoice(id, sound, params, volume = steady(params.volume), fade = steady(1.0))
		if params.fadeIn > 0.0:
			v.fade = steady(0.0)
			v.fade.rampTo(1.0, params.fadeIn, rate)
		voices.push(v)

	# A voice's volume, reached over `seconds`.
	fn setVolume(id i64, volume f32, seconds f32):
		i = self.voiceIndex(id)
		if i >= 0:
			voices[i].volume.rampTo(volume, seconds, rate)

	# -1 left .. 1 right.
	fn setPan(id i64, pan f32):
		i = self.voiceIndex(id)
		if i >= 0:
			voices[i].params.pan = pan.clamp(-1.0, 1.0)

	# Playback speed, 0.01 .. 16.
	fn setPitch(id i64, pitch f32):
		i = self.voiceIndex(id)
		if i >= 0:
			voices[i].params.pitch = pitch.clamp(0.01, 16.0)

	fn setPosition(id i64, position Vec3):
		i = self.voiceIndex(id)
		if i >= 0:
			voices[i].params.position = position

	# Stops a voice: at once (over one block), or fading out over `seconds`.
	fn stop(id i64, seconds f32):
		i = self.voiceIndex(id)
		if i >= 0:
			voices[i].stopping = true
			voices[i].fade.rampTo(0.0, seconds, rate)

	fn setListener(l Listener):
		listener = l

	# Reached over 50 ms.
	fn setMasterVolume(volume f32):
		master.rampTo(volume, 0.05, rate)

	# Reached over 50 ms.
	fn setMusicVolume(volume f32):
		musicVolume.rampTo(volume, 0.05, rate)

	# Starts a song: it fades in over `fade` seconds while the songs playing fade out over the
	# same time (a crossfade), or replaces them at once when `fade` is 0.
	fn playMusic(move stream Stream, looping bool, fade f32, volume f32):
		self.stopMusic(fade)
		t = MusicTrack(stream, looping, volume, fade = steady(1.0))
		if fade > 0.0:
			t.fade = steady(0.0)
			t.fade.rampTo(1.0, fade, rate)
		music.push(t)

	# Fades the songs out over `seconds` (0: at once, over one block).
	fn stopMusic(seconds f32):
		for i in 0..music.len:
			music[i].stopping = true
			music[i].fade.rampTo(0.0, seconds, rate)

	# More samples of feed `id` (interleaved, 1 or 2 channels at soundRate), after those waiting.
	fn feed(id i64, samples f32[], channels i64, soundRate i64):
		if feeds.findIndex(.id == id) == none:
			sound = MixSound(
				samples = [],
				channels = channels.clamp(1, 2),
				rate = soundRate.max(1),
				frames = 0
			)
			feeds.push(MixFeed(id, sound))
		f = mut ref feeds[feeds.findIndex(.id == id) ?? 0]
		f.sound.samples.extend(samples)
		f.sound.frames = f.sound.samples.len / f.sound.channels
		played = i64(f.pos.floor()).min(f.sound.frames)
		over = f.sound.frames - played - i64(feedSeconds * f.sound.rate)
		if over > 0: f.dropFrames(played + over)

	# the voices that ended since the last call
	fn takeEnded() i64[]:
		move ended

	fn voiceCount():
		voices.len

	# one fading out counts
	fn musicCount():
		music.len

	# Mixes the next n frames into out[0 .. 2n] (stereo, overwritten).
	fn render(mut out f32[], n i64):
		while out.len < 2 * n:
			out.push(0.0)
		for k in 0..2 * n:
			out[k] = 0.0
		done = 0
		while done < n:
			count = (n - done).min(mixBlock)
			self.renderBlock(out, done, count)
			done += count
		framesMixed += n

# `rate`: the output's frames a second.
pub fn newMixer(rate i64) Mixer:
	Mixer(rate = rate.max(1))

fn voiceIndex(m Mixer, id i64):
	m.voices.findIndex(.id == id) ?? -1

# ---------- 3D ----------

# The gain and pan a sound at `position` has for the listener: the inverse distance gain,
# clamped (1 up to minDistance, held from maxDistance on), and the pan from where it is to the
# listener's right (-1 left, 1 right; 0 straight ahead, behind, above or at the listener).
pub fn spatialize(
	l Listener,
	position Vec3,
	minDistance f32,
	maxDistance f32,
	rolloff f32
) (f32, f32):
	d = position - l.position
	dist = d.length()
	near = minDistance.max(0.0001)
	clamped = dist.clamp(near, maxDistance.max(near))
	gain = near / (near + rolloff * (clamped - near))
	right = l.forward.cross(l.up).normalized()
	pan = (d @ right / dist).clamp(-1.0, 1.0) if dist > 0.000001 else 0.0
	(gain, pan)

# The gain at `distance` along a curve of five points spread evenly from `near` to `far`: the
# first up to `near`, linear between two points, the last from `far` on.
pub fn curveGain(curve f32[5], near f32, far f32, distance f32) f32:
	if distance <= near: return curve[0]
	if distance >= far: return curve[4]
	at = (distance - near) / (far - near) * 4.0
	k = i64(at.floor())
	curve[k].lerp(curve[k + 1], at - f32(k))

# the left and right gains of a pan: equal power for mono (-3 dB each in the middle), the
# balance for stereo (each side at full gain in the middle)
fn panGains(pan f32, channels i64):
	p = pan.clamp(-1.0, 1.0)
	if channels == 1:
		a = (p + 1.0) * 0.785398163
		return (a.cos(), a.sin())
	((1.0 - p).min(1.0), (1.0 + p).min(1.0))

# ---------- rendering ----------

fn renderBlock(mut m Mixer, mut out f32[], at i64, n i64):
	for i in 0..m.voices.len:
		if not m.voices[i].finished:
			m.mixVoice(i, out, at, n)
	k = 0
	while k < m.voices.len:
		if m.voices[k].finished:
			v = m.voices.remove(k)
			m.ended.push(v.id)
		else:
			k += 1
	for i in 0..m.feeds.len:
		f = mut ref m.feeds[i]
		pos, _ = f.sound.resample(
			f.pos,
			f64(f.sound.rate) / f64(m.rate),
			false,
			out,
			at,
			n,
			1.0,
			1.0,
			1.0,
			1.0
		)
		f.pos = pos
		# what is played dropped once it is half the frames held: each frame moved once or twice
		played = i64(pos.floor()).min(f.sound.frames)
		if played * 2 >= f.sound.frames:
			f.dropFrames(played)
	m.musicVolume.advanceRamp(n)
	for i in 0..m.music.len:
		m.mixMusic(i, out, at, n)
	j = 0
	while j < m.music.len:
		if m.music[j].finished:
			m.music.remove(j)
		else:
			j += 1
	# the master volume, ramped over the block, and a hard limit at full scale
	g0 = m.master.value
	m.master.advanceRamp(n)
	g1 = m.master.value
	dg = (g1 - g0) / f32(n)
	g = g0 + dg   # each frame a step on: the last at the new value
	for f in at..at + n:
		out[2 * f] = (out[2 * f] * g).clamp(-1.0, 1.0)
		out[2 * f + 1] = (out[2 * f + 1] * g).clamp(-1.0, 1.0)
		g += dg

fn mixVoice(mut m Mixer, i i64, mut out f32[], at i64, n i64):
	v = mut ref m.voices[i]
	snd = m.sounds.get(v.sound) ?? return
	v.volume.advanceRamp(n)
	v.fade.advanceRamp(n)
	gain = v.volume.value * v.fade.value
	pan = v.params.pan
	if v.params.positional:
		g, p = spatialize(
			m.listener,
			v.params.position,
			v.params.minDistance,
			v.params.maxDistance,
			v.params.rolloff
		)
		if v.params.curved:
			g = curveGain(
				v.params.curve,
				v.params.minDistance,
				v.params.maxDistance,
				(v.params.position - m.listener.position).length()
			)
		gain *= g
		pan = (pan + p).clamp(-1.0, 1.0)
	pl, pr = panGains(pan, snd.channels)
	tl = gain * pl
	tr = gain * pr
	if v.fresh:
		v.fresh = false
		if v.params.fadeIn <= 0.0:
			v.gainL = tl
			v.gainR = tr
	step = f64(snd.rate) / f64(m.rate) * f64(v.params.pitch)
	pos = v.pos
	played = 0
	if tl == 0.0 and tr == 0.0 and v.gainL == 0.0 and v.gainR == 0.0:
		pos, played = skipped(snd, v.pos, step, v.params.looping, n)
	else:
		pos, played = resample(
			snd,
			v.pos,
			step,
			v.params.looping,
			out,
			at,
			n,
			v.gainL,
			v.gainR,
			tl,
			tr
		)
	v.pos = pos
	v.gainL = tl
	v.gainR = tr
	if played < n or v.stopping and v.fade.value <= 0.0:
		v.finished = true

# Adds the sound from frame `pos`, `step` frames per output frame, to out[at ..] for n frames,
# the gains ramping from (l0, r0) to (l1, r1). The new position, and the frames played (fewer
# than n when the sound ended).
fn resample(
	s MixSound,
	pos0 f64,
	step f64,
	looping bool,
	mut out f32[],
	at i64,
	n i64,
	l0 f32,
	r0 f32,
	l1 f32,
	r1 f32
):
	frames = s.frames
	if frames == 0: return (pos0, 0)
	framesF = f64(frames)
	dl = (l1 - l0) / f32(n)
	dr = (r1 - r0) / f32(n)
	gl = l0 + dl
	gr = r0 + dr
	pos = pos0
	i = 0
	src = s.samples
	while i < n:
		if pos >= framesF:
			if not looping: return (pos, i)
			pos -= (pos / framesF).floor() * framesF
		# frames that surely have a next one to interpolate toward
		safe = i64(((framesF - 1.0 - pos) / step).floor())
		if safe <= 0:
			idx = i64(pos)
			frac = f32(pos - idx)
			last = idx + 1 >= frames
			if s.channels == 1:
				a = src[idx]
				b = (src[0] if looping else 0.0) if last else src[idx + 1]
				x = a + (b - a) * frac
				out[2 * (at + i)] += x * gl
				out[2 * (at + i) + 1] += x * gr
			else:
				al = src[2 * idx]
				ar = src[2 * idx + 1]
				bl = (src[0] if looping else 0.0) if last else src[2 * idx + 2]
				br = (src[1] if looping else 0.0) if last else src[2 * idx + 3]
				out[2 * (at + i)] += (al + (bl - al) * frac) * gl
				out[2 * (at + i) + 1] += (ar + (br - ar) * frac) * gr
			gl += dl
			gr += dr
			pos += step
			i += 1
			continue
		run = safe.min(n - i)
		o = 2 * (at + i)
		if s.channels == 1:
			loop run:
				idx = i64(pos)
				frac = f32(pos - idx)
				a = src[idx]
				x = a + (src[idx + 1] - a) * frac
				out[o] += x * gl
				out[o + 1] += x * gr
				gl += dl
				gr += dr
				pos += step
				o += 2
		else:
			loop run:
				idx = i64(pos)
				frac = f32(pos - idx)
				j = 2 * idx
				al = src[j]
				ar = src[j + 1]
				out[o] += (al + (src[j + 2] - al) * frac) * gl
				out[o + 1] += (ar + (src[j + 3] - ar) * frac) * gr
				gl += dl
				gr += dr
				pos += step
				o += 2
		i += run
	(pos, n)

# A silent voice's sound passed over as resample plays it, nothing added: the new position, and
# the frames played.
fn skipped(s MixSound, pos0 f64, step f64, looping bool, n i64):
	frames = f64(s.frames)
	if s.frames == 0: return (pos0, 0)
	pos = pos0
	for i in 0..n:
		if pos >= frames:
			if not looping: return (pos, i)
			pos -= (pos / frames).floor() * frames
		pos += step
	(pos, n)

# the first n samples taken away, those after moved down where they are (no list made)
fn dropFirst(mut samples f32[], n i64):
	rest = samples.len - n
	for k in 0..rest:
		samples[k] = samples[k + n]
	samples.truncate(rest)

# ---------- music ----------

# Decodes until the track's buffer holds stream frame `last` (or the stream ends: then the
# frames past its end are silence and the end is noted). A looping track goes on from its start.
fn fillTrack(mut t MusicTrack, last i64):
	ch = t.stream.channels
	# drop what is played: the frames before the one playing
	keepFrom = i64(t.pos) - t.base
	if keepFrom > 4096:
		dropFirst(t.buffer, keepFrom * ch)
		t.base += keepFrom
	rewound = false
	while t.base + t.buffer.len / ch <= last:
		if t.ended:
			loop ch:
				t.buffer.push(0.0)
			continue
		got = t.stream.readStream(t.buffer)
		if got == 0:
			if t.looping and not rewound:
				t.stream.rewindStream()
				rewound = true   # a stream that gives nothing even from its start ends
			else:
				t.ended = true
				t.endFrame = t.base + t.buffer.len / ch
		else:
			rewound = false

fn mixMusic(mut m Mixer, i i64, mut out f32[], at i64, n i64):
	rate = m.rate
	busGain = m.musicVolume.value
	t = mut ref m.music[i]
	ch = t.stream.channels
	step = f64(t.stream.sampleRate) / f64(rate)
	t.fade.advanceRamp(n)
	gain = t.volume * t.fade.value * busGain   # a mono song plays at full gain on both sides
	tl = gain
	tr = gain
	if t.fresh:
		t.fresh = false
		if t.fade.value >= 1.0:
			t.gainL = tl
			t.gainR = tr
	lastNeeded = i64(t.pos + step * n) + 1
	fillTrack(t, lastNeeded)
	dl = (tl - t.gainL) / f32(n)
	dr = (tr - t.gainR) / f32(n)
	gl = t.gainL + dl
	gr = t.gainR + dr
	pos = t.pos
	base = t.base
	for f in 0..n:
		idx = i64(pos)
		frac = f32(pos - idx)
		j = (idx - base) * ch
		if ch == 1:
			a = t.buffer[j]
			x = a + (t.buffer[j + 1] - a) * frac
			out[2 * (at + f)] += x * gl
			out[2 * (at + f) + 1] += x * gr
		else:
			al = t.buffer[j]
			ar = t.buffer[j + 1]
			out[2 * (at + f)] += (al + (t.buffer[j + 2] - al) * frac) * gl
			out[2 * (at + f) + 1] += (ar + (t.buffer[j + 3] - ar) * frac) * gr
		gl += dl
		gr += dr
		pos += step
	t.pos = pos
	t.gainL = tl
	t.gainR = tr
	if t.stopping and t.fade.value <= 0.0 or t.ended and i64(t.pos) >= t.endFrame:
		t.finished = true
