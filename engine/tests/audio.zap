# The engine's audio without a device: the decoders against ffmpeg's output (WAV of every
# sample kind built here, ADPCM, MP3 and Ogg Vorbis files in engine/tests/audio/ with what
# ffmpeg 9 decoded them to, as raw floats), and the mixer rendered into a buffer: gains and pans, resampling,
# looping, the end of a sound, fades, volume ramps, music from a stream with a crossfade, and
# the 3D helper. The fixtures were made with ffmpeg from lavfi sources (sine, anoisesrc,
# aevalsrc): `-c:a adpcm_ima_wav` / `adpcm_ms` / `libmp3lame` / `libvorbis`, and each decoded back with
# `ffmpeg -i x -f f32le x.f32`.

import engine.audio
import fs
import engine.audio.wav

fn fixture(name str):
	text = fs.readFile("engine/tests/audio/{name}") ?? ""
	b = []
	b.extend(text.bytes())
	b

# the floats of a raw little-endian f32 file (ffmpeg's -f f32le)
fn floatsOf(name str):
	b = fixture(name)
	out = []
	i = 0
	while i + 4 <= b.len:
		out.push(b.f32le(i))
		i += 4
	out

# the signal-to-noise ratio of `ours` against `reference`, in dB (999 when equal; lengths must match)
fn snr(ours f32[], reference f32[]):
	if ours.len != reference.len: return -1.0
	signal = 0.0
	noise = 0.0
	for i in 0..ours.len:
		r = f64(reference[i])
		e = f64(ours[i]) - r
		signal += r * r
		noise += e * e
	999.0 if noise == 0.0 else 10.0 * (signal / noise).ln() / 10.0.ln()

fn decoded(name str):
	audio.decodeAudio(fixture(name)) ?? wav.Pcm(samples = [], channels = 0, sampleRate = 0)

# ---------- WAV ----------

# a WAV file's bytes around a data chunk: the format tag, channels, rate, bits and the data
fn wavBytes(tag i64, channels i64, rate i64, bits i64, data u8[]):
	b = "RIFF".bytes().copy()
	b.pushU32le(36 + data.len)
	b.extend("WAVEfmt ".bytes())
	b.pushU32le(16)
	b.pushU16le(tag)
	b.pushU16le(channels)
	b.pushU32le(rate)
	b.pushU32le(rate * channels * bits / 8)
	b.pushU16le(channels * bits / 8)
	b.pushU16le(bits)
	b.extend("data".bytes())
	b.pushU32le(data.len)
	b.extend(data)
	b

test "16-bit PCM written and read back is exact":
	samples = (0..1000).map(f32((it * 37 % 2000) - 1000) / 32768.0)
	bytes = wav.encodeWav(samples, 2, 22_050, 16)
	pcm = wav.decodeWav(bytes) ?? fail("not decoded")
	expect pcm.channels == 2 and pcm.sampleRate == 22_050 and pcm.frames() == 500
	expect snr(pcm.samples, samples) == 999.0

test "float WAV written and read back is exact":
	samples f32[] = [0.0, 0.5, -0.25, 1.0, -1.0, 0.123456789, 3.0, -0.000001]
	pcm = wav.decodeWav(wav.encodeWav(samples, 1, 8000, 32)) ?? fail("not decoded")
	expect pcm.samples == samples

test "every PCM sample kind reads as ffmpeg reads it":
	# 8-bit unsigned: (x - 128) / 128
	u8wav = wav.decodeWav(wavBytes(1, 1, 8000, 8, [0, 64, 128, 192, 255])) ?? fail("8-bit")
	expect u8wav.samples == [-1.0, -0.5, 0.0, 0.5, 0.9921875]
	# 24-bit: x / 2^23
	s24 = wav.decodeWav(
		wavBytes(1, 1, 8000, 24, [0, 0, 0x80, 0xFF, 0xFF, 0x7F, 0x01, 0, 0, 0xFF, 0xFF, 0xFF])
	) ??
		fail("24-bit")
	expect s24.samples == [-1.0, 8388607.0 / 8388608.0, 1.0 / 8388608.0, -1.0 / 8388608.0]
	# 32-bit: x / 2^31, rounded to f32 as ffmpeg's conversion rounds it
	s32 = wav.decodeWav(
		wavBytes(1, 1, 8000, 32, [0, 0, 0, 0x80, 0, 0, 0, 0x40, 0xFF, 0xFF, 0xFF, 0x7F])
	) ??
		fail("32-bit")
	expect s32.samples == [-1.0, 0.5, 1.0]
	# 64-bit float
	f64wav = wav.decodeWav(
		wavBytes(3, 1, 8000, 64, [0, 0, 0, 0, 0, 0, 0xE0, 0x3F, 0, 0, 0, 0, 0, 0, 0xF0, 0xBF])
	) ??
		fail("64-bit float")
	expect f64wav.samples == [0.5, -1.0]
	expect wav.decodeWav(wavBytes(7, 1, 8000, 8, [1, 2, 3])) == none   # mu-law: not read
	expect wav.decodeWav(fixture("missing.wav")) == none

test "IMA ADPCM decodes as ffmpeg decodes it":
	pcm = decoded("ima.wav")
	expect pcm.channels == 2 and pcm.sampleRate == 22_050
	expect snr(pcm.samples, floatsOf("ima.f32")) == 999.0

test "Microsoft ADPCM decodes as ffmpeg decodes it":
	pcm = decoded("ms.wav")
	expect pcm.channels == 1
	expect snr(pcm.samples, floatsOf("ms.f32")) == 999.0

# ---------- MP3 ----------

test "MPEG-1 joint stereo MP3 matches ffmpeg (gapless, the encoder's delay cut)":
	pcm = decoded("stereo44.mp3")
	expect pcm.channels == 2 and pcm.sampleRate == 44_100
	expect pcm.frames() == 6615
	expect snr(pcm.samples, floatsOf("stereo44.f32")) > 100.0

test "MPEG-2 mono MP3 with short blocks matches ffmpeg":
	pcm = decoded("mono22.mp3")
	expect pcm.channels == 1 and pcm.sampleRate == 22_050
	expect snr(pcm.samples, floatsOf("mono22.f32")) > 100.0

# ---------- Ogg Vorbis ----------

test "Ogg Vorbis matches ffmpeg":
	pcm = decoded("stereo22.ogg")
	expect pcm.channels == 2 and pcm.sampleRate == 22_050
	# 0.3 s: 6615 frames, as the last page's granule position says. ffmpeg decodes 41 more: on a
	# file of one audio page its Ogg reader gets the last packet's length wrong (a negative
	# duration) and keeps samples the granule position cuts; the ones before agree
	expect pcm.frames() == 6615
	reference = floatsOf("stereo22.f32")
	expect reference.len == 6656 * 2
	expect snr(pcm.samples, reference[..pcm.samples.len]) > 100.0

test "a rewound stream gives the same samples again" for name in [
	"stereo22.ogg",
	"stereo44.mp3",
	"ima.wav"
]:
	s = audio.openStream(fixture(name)) ?? fail(name)
	first = []
	while s.readStream(first) > 0:
		pass
	s.rewindStream()
	second = []
	while s.readStream(second) > 0:
		pass
	expect not first.isEmpty and first == second

test "bytes that are no sound give none":
	expect audio.decodeAudio([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]) == none
	junk = (0..5000).map(u8(it * 7919 % 251))
	result = audio.decodeAudio(move junk)
	expect result == none

test "a damaged MP3 decodes without stopping":
	b = fixture("stereo44.mp3")
	for i in 600..b.len step 97:
		b[i] = i64(b[i]) ^ 0x5A
	pcm = decoded("stereo44.mp3")
	damaged = audio.decodeAudio(b) ?? wav.Pcm(samples = [], channels = 0, sampleRate = 0)
	expect damaged.frames() > 0 and damaged.frames() <= pcm.frames() + 1152

# ---------- the mixer ----------

rate = 48_000

fn ramp(n i64):
	s = (0..n).map(f32(it % 100) / 100.0 - 0.5)
	s

fn near(a f32, b f32):
	(a - b).abs() < 0.00001

test "a mono sound in the middle plays at -3 dB on both sides":
	m = audio.newMixer(rate)
	m.addSound(1, ramp(1000), 1, rate)
	m.play(7, 1, audio.PlayParams())
	out = []
	m.render(out, 300)
	g = f32(0.70710678)
	expect near(out[2 * 10], (0.1 - 0.5) * g) and near(out[2 * 10 + 1], (0.1 - 0.5) * g)
	expect near(out[2 * 250], (0.5 - 0.5) * g)

test "pan -1 is the left side only; a stereo sound keeps its sides":
	m = audio.newMixer(rate)
	m.addSound(1, ramp(1000), 1, rate)
	m.addSound(2, [0.25, -0.5, 0.25, -0.5, 0.25, -0.5], 2, rate)
	m.play(7, 1, audio.PlayParams(pan = -1.0))
	out = []
	m.render(out, 3)
	expect near(out[0], -0.5) and out[1] == 0.0 and near(out[2], -0.49)
	s = audio.newMixer(rate)
	s.addSound(2, [0.25, -0.5, 0.25, -0.5, 0.25, -0.5], 2, rate)
	s.play(8, 2, audio.PlayParams())
	s.render(out, 3)
	expect out[0] == 0.25 and out[1] == -0.5 and out[4] == 0.25 and out[5] == -0.5

test "a sound at half the output's rate is interpolated between its samples":
	m = audio.newMixer(rate)
	m.addSound(1, [0.0, 0.4, 0.8, 0.4], 1, rate / 2)
	m.play(7, 1, audio.PlayParams(pan = -1.0))
	out = []
	m.render(out, 6)
	expect (
		out[0] == 0.0 and near(out[2], 0.2) and near(out[4], 0.4) and near(out[6], 0.6) and
			near(out[8], 0.8) and near(out[10], 0.6)
	)

test "pitch 2 skips every other sample":
	m = audio.newMixer(rate)
	m.addSound(1, ramp(1000), 1, rate)
	m.play(7, 1, audio.PlayParams(pan = -1.0, pitch = 2.0))
	out = []
	m.render(out, 4)
	expect (
		near(out[0], -0.5) and near(out[2], -0.48) and near(out[4], -0.46) and near(out[6], -0.44)
	)

test "a feed waits silent until a twentieth of a second is pushed, then plays it as it came":
	m = audio.newMixer(rate)
	m.feed(3, [0.5, -0.5], 2, rate)
	out = []
	m.render(out, 1)
	expect out == [0.0, 0.0]
	m.feed(3, fill(2 * (rate / 20), f32(0.25)), 2, rate)
	m.render(out, 2)
	expect near(out[0], 0.5) and near(out[1], -0.5) and near(out[2], 0.25) and near(out[3], 0.25)

test "a feed keeps a quarter of a second waiting, the oldest dropped":
	m = audio.newMixer(rate)
	m.feed(3, fill(rate, 1.0), 1, rate)
	m.feed(3, fill(rate / 4, 0.5), 1, rate)
	out = []
	m.render(out, 1)
	expect out[0] == 0.5 and out[1] == 0.5

test "a sound that ends frees its voice and is reported":
	m = audio.newMixer(rate)
	m.addSound(1, ramp(100), 1, rate)
	m.play(7, 1, audio.PlayParams(pan = -1.0))
	out = []
	m.render(out, 200)
	expect near(out[2 * 99], 0.49) and out[2 * 100] == 0.0 and out[2 * 150] == 0.0
	expect m.voiceCount() == 0
	expect m.takeEnded() == [7]
	expect m.takeEnded().isEmpty

test "a looping sound starts over":
	m = audio.newMixer(rate)
	m.addSound(1, ramp(100), 1, rate)
	m.play(7, 1, audio.PlayParams(pan = -1.0, looping = true))
	out = []
	m.render(out, 1000)
	expect near(out[2 * 100], -0.5) and near(out[2 * 250], 0.0) and near(out[2 * 999], 0.49)
	expect m.voiceCount() == 1

test "a stop with a fade falls to silence over its time, then the voice ends":
	m = audio.newMixer(rate)
	dc f32[] = []
	loop rate:
		dc.push(0.5)
	m.addSound(1, dc, 1, rate)
	m.play(7, 1, audio.PlayParams(pan = -1.0, looping = true))
	out = []
	m.render(out, 256)
	m.stop(7, 0.0256)   # 1228.8 frames
	m.render(out, 2048)
	expect out[0] < 0.5 and out[0] > 0.499
	# the gain at the end of each block of 256 frames is the fade's value there
	expect near(out[2 * 255], 0.5 * (1.0 - 256.0 / 1228.8))
	expect near(out[2 * 511], 0.5 * (1.0 - 512.0 / 1228.8))
	expect out[2 * 1500] == 0.0
	expect m.voiceCount() == 0 and m.takeEnded() == [7]

test "a volume change ramps to its value":
	m = audio.newMixer(rate)
	m.addSound(1, fill(rate, 1.0), 1, rate)
	m.play(7, 1, audio.PlayParams(pan = 1.0, volume = 1.0, looping = true))
	out = []
	m.render(out, 256)
	expect near(out[1], 1.0)
	m.setVolume(7, 0.25, 0.01)   # 480 frames
	m.render(out, 1024)
	expect out[1] < 1.0 and out[1] > 0.99
	expect near(out[2 * 255 + 1], 1.0 - 0.75 * 256.0 / 480.0)
	expect near(out[2 * 1000 + 1], 0.25)

test "an unknown sound ends its voice at once; removing a sound ends its voices":
	m = audio.newMixer(rate)
	m.play(3, 99, audio.PlayParams())
	expect m.takeEnded() == [3]
	m.addSound(1, ramp(1000), 1, rate)
	m.play(4, 1, audio.PlayParams(looping = true))
	m.removeSound(1)
	out = []
	m.render(out, 10)
	expect m.voiceCount() == 0 and m.takeEnded() == [4] and out[0] == 0.0

fn dcWav(value f32, frames i64, sampleRate i64):
	s = []
	loop frames:
		s.push(value)
	wav.encodeWav(s, 1, sampleRate, 32)

test "music streams from its decoder; a crossfade hands one song to the next":
	m = audio.newMixer(rate)
	a = audio.openStream(dcWav(0.5, rate * 3, rate)) ?? fail("a")
	m.playMusic(a, true, 0.0, 1.0)
	out = []
	m.render(out, 1000)
	expect out[0] == 0.5 and out[1] == 0.5 and out[2 * 999] == 0.5   # a mono song: full gain on both sides
	b = audio.openStream(dcWav(-0.25, rate * 3, rate)) ?? fail("b")
	m.playMusic(b, true, 0.5, 1.0)   # 24000 frames of crossfade
	m.render(out, 12_032)
	expect m.musicCount() == 2
	# at 12032 frames in: a at 1 - 12032/24000, b at 12032/24000
	t = f32(12032.0 / 24000.0)
	expect near(out[2 * 12_031], 0.5 * (1.0 - t) - 0.25 * t)
	m.render(out, 24_000)
	expect m.musicCount() == 1 and near(out[2 * 23_999], -0.25)

test "a song that does not loop ends; one that loops goes on without a gap":
	m = audio.newMixer(rate)
	s = audio.openStream(dcWav(0.5, 3000, rate)) ?? fail("s")
	m.playMusic(s, false, 0.0, 1.0)
	out = []
	m.render(out, 4000)
	expect out[2 * 2998] == 0.5 and out[2 * 3500] == 0.0 and m.musicCount() == 0
	l = audio.openStream(dcWav(0.5, 3000, rate)) ?? fail("l")
	m.playMusic(l, true, 0.0, 1.0)
	m.render(out, 10_000)
	gaps = 0
	for f in 0..10000:
		if out[2 * f] != 0.5:
			gaps += 1
	expect gaps == 0 and m.musicCount() == 1

test "an MP3 song streams at the output's rate":
	m = audio.newMixer(rate)
	s = audio.openStream(fixture("stereo44.mp3")) ?? fail("mp3")
	m.playMusic(s, false, 0.0, 1.0)
	out = []
	peak = f32(0.0)
	loop 10:
		m.render(out, 960)
		for x in out:
			peak = peak.max(x.abs())
	# 0.15 s of two tones of 0.375 each, resampled from 44100 to 48000 Hz: done after 7200 frames
	expect peak > 0.3 and peak < 0.45 and m.musicCount() == 0

test "the 3D helper: distance gain and pan from the listener's right":
	l = audio.Listener(
		position = Vec3(0.0, 0.0, 0.0),
		forward = Vec3(0.0, 0.0, -1.0),
		up = Vec3(0.0, 1.0, 0.0)
	)
	g1, p1 = l.spatialize(Vec3(4.0, 0.0, 0.0), 1.0, 60.0, 1.0)
	expect near(g1, 0.25) and near(p1, 1.0)
	g2, p2 = l.spatialize(Vec3(0.0, 0.0, -0.5), 1.0, 60.0, 1.0)
	expect g2 == 1.0 and near(p2, 0.0)
	g3, p3 = l.spatialize(Vec3(-100.0, 0.0, 0.0), 1.0, 10.0, 1.0)
	expect near(g3, 0.1) and near(p3, -1.0)
	# turned around (looking toward +z), the right is -x
	back = audio.Listener(forward = Vec3(0.0, 0.0, 1.0))
	_, p4 = back.spatialize(Vec3(4.0, 0.0, 0.0), 1.0, 60.0, 1.0)
	expect near(p4, -1.0)

test "a positional voice takes its gain and pan from where it is":
	m = audio.newMixer(rate)
	m.addSound(1, fill(1000, 1.0), 1, rate)
	m.play(7, 1, audio.PlayParams(positional = true, position = Vec3(2.0, 0.0, 0.0)))
	out = []
	m.render(out, 10)
	expect near(out[0], 0.0) and near(out[1], 0.5)   # all right, at half gain (2 m)

test "the mix is limited to full scale":
	m = audio.newMixer(rate)
	m.addSound(1, fill(100, 0.9), 1, rate)
	for v in 0..4:
		m.play(v, 1, audio.PlayParams(pan = -1.0))
	out = []
	m.render(out, 10)
	expect out[0] == 1.0

test "a block in each device format: stereo spread, mono mixed, integers scaled":
	out f32[] = [0.5, -0.25, 1.5, -2.0]
	b = []
	audio.deviceBytes(out, 2, 1, false, 16, b)
	expect b == [0x00, 0x10, 0x00, 0xE0]   # (0.5 - 0.25) / 2 * 32767 rounds to 4096, (1.5 - 2) / 2 to -8192
	audio.deviceBytes(out, 1, 6, false, 24, b)
	expect (
		b.len == 18 and b[..6] == [0x00, 0x00, 0x40, 0x00, 0x00, 0xE0] and
			b[6..18].all(it == 0)
	)
	audio.deviceBytes(out, 1, 2, true, 32, b)
	expect b == [0, 0, 0, 0x3F, 0, 0, 0x80, 0xBE]
	audio.deviceBytes(out, 1, 1, false, 32, b)
	expect b == [0x00, 0x00, 0x00, 0x10]

test "a curve's gain: full to the near end, linear between its points, the last past the far end":
	curve f32[5] = [1.0, 0.5, 0.2, 0.05, 0.0]
	expect audio.curveGain(curve, 150.0, 1800.0, 100.0) == 1.0
	expect near(audio.curveGain(curve, 150.0, 1800.0, 562.5), 0.5)
	expect near(audio.curveGain(curve, 150.0, 1800.0, 768.75), 0.35)
	expect audio.curveGain(curve, 150.0, 1800.0, 5000.0) == 0.0

test "a curved positional voice takes its gain from the curve":
	m = audio.newMixer(rate)
	m.addSound(1, fill(1000, 1.0), 1, rate)
	m.play(7, 1, audio.PlayParams(positional = true, position = Vec3(2.0, 0.0, 0.0),
		minDistance = 1.0, maxDistance = 5.0, curved = true, curve = [1.0, 0.5, 0.0, 0.0, 0.0]))
	out = []
	m.render(out, 10)
	expect near(out[0], 0.0) and near(out[1], 0.5)

test "a WAV's and an xWMA's declared length; none for a format that does not declare it":
	samples = fill(2 * 4800, f32(0.5))
	b = wav.encodeWav(samples, 2, 48_000)
	expect audio.declaredSeconds(b) == 0.1
	mp3 = fixture("stereo44.mp3")
	expect audio.declaredSeconds(mp3) == none

test "the offline mix renders what was played, with no device":
	audio.startOffline(rate)
	s = audio.newSound(fill(rate, 0.5), 1, rate)
	v = s.play(audio.PlayParams(pan = -1.0))
	first = audio.renderOffline(100)
	expect first.len == 200 and near(first[0], 0.5) and near(first[1], 0.0)
	audio.renderOffline(rate)
	expect not v.isPlaying()
