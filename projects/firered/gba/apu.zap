# The sound: the two tone channels (the first with its sweep), the wave channel, the noise
# channel, and the two sample FIFOs (sound.zap), mixed as SOUNDCNT_L and SOUNDCNT_H say at
# 32768 samples a second, a sample each 512 cycles, and pushed to the engine's audio each frame.
# The frame sequencer steps 512 times a second: the lengths at 256 Hz, the sweep at 128 Hz, the
# envelopes at 64 Hz.

import engine.audio

pub outputRate = 32_768
cyclesPerSample = 512
cyclesPerStep = 32_768

dutyPatterns = [0x01, 0x81, 0x87, 0x7E]   # 12.5%, 25%, 50%, 75%: the high steps of eight

# a channel of the PSG: what plays and how loud
type Channel:
	on bool = false
	volume i64 = 0
	envelopeTime i64 = 0
	envelopeUp bool = false
	envelopeCount i64 = 0
	length i64 = 0
	lengthOn bool = false
	period i64 = 1   # cycles a step of its wave lasts
	left i64 = 0   # cycles left of the step
	step i64 = 0
	output i64 = 0   # -volume or volume (the wave: its sample)

	fn levelOf(k i64):
		match k:
			0, 1:
				duty = i64(ioHalf(0x62 if k == 0 else 0x68) >> 6) & 3
				volume if (dutyPatterns[duty] >> (step & 7)) & 1 == 1 else -volume
			2: waveLevel(step)
			_: -volume if lfsr & 1 == 1 else volume

mut channels Channel[] = [Channel(), Channel(), Channel(), Channel()]
mut sweepCount = 0
mut frequency1 = 0   # the first channel's, which its sweep changes
mut lfsr = 0x7FFF
mut waveBanks u8[] = zeros(32)
mut nextSample i64 = 0
mut nextStep i64 = 0
mut sequencer = 0
mut pending f32[] = []
mut sound = audio.FrameSound(rate = outputRate, wavPath = args.option("--wav") ?? "")

# the sound opened (a window's run): the samples made from now on are heard
pub fn openSound():
	sound.hear()

fn isOn():
	sound.isWanted()

# the samples of the time up to cycle t made
pub fn soundTo(t i64):
	if not isOn(): return
	while nextSample <= t:
		while nextStep <= nextSample:
			stepSequencer()
			nextStep += cyclesPerStep
		advanceChannels()
		left, right = mixed()
		pending.push(left)
		pending.push(right)
		nextSample += cyclesPerSample

# the samples made since the last frame handed to the engine
pub fn pushSound():
	if not isOn(): return
	soundTo(cycles)
	sound.pushFrame(pending)
	pending.clear()

# the sound of the run written to the --wav file
pub fn saveSound():
	sound.saveWav()

fn stepSequencer():
	for k in 0..4:
		if sequencer % 2 == 0: channels[k].tickLength()
		if sequencer == 7: channels[k].tickEnvelope()
	if sequencer % 4 == 2: sweep()
	sequencer = (sequencer + 1) % 8

fn tickLength(mut c Channel):
	if c.lengthOn and c.length > 0:
		c.length -= 1
		if c.length == 0: c.on = false

fn tickEnvelope(mut c Channel):
	if c.envelopeTime == 0: return
	c.envelopeCount -= 1
	if c.envelopeCount <= 0:
		c.envelopeCount = c.envelopeTime
		c.volume = (c.volume + (1 if c.envelopeUp else -1)).clamp(0, 15)

fn sweep():
	control = ioHalf(0x60)
	time = i64((control >> 4) & 7)
	if time == 0 or not channels[0].on: return
	sweepCount -= 1
	if sweepCount > 0: return
	sweepCount = time
	change = frequency1 >> (control & 7)
	next = frequency1 - change if control & 8 != 0 else frequency1 + change
	if next > 2047:
		channels[0].on = false
	elif control & 7 != 0:
		frequency1 = next
		channels[0].period = 16 * (2048 - next)

# each channel moved on by a sample's cycles
fn advanceChannels():
	for k in 0..4:
		channels[k].advance(k)

fn advance(mut c Channel, k i64):
	if not c.on: return
	c.left -= cyclesPerSample
	while c.left <= 0:
		c.left += c.period
		c.step += 1
		if k == 3:
			bit = (lfsr ^ (lfsr >> 1)) & 1
			lfsr = (lfsr >> 1) | (bit << 14)
			if ioHalf(0x7C) & 8 != 0: lfsr = (lfsr & ~0x40) | (bit << 6)
	c.output = c.levelOf(k)

# the wave channel's level at a step: its 4-bit sample, centred, at its volume
fn waveLevel(step i64):
	control = ioHalf(0x70)
	if control & 0x80 == 0: return 0
	both = control & 0x20 != 0
	bank = (control >> 6) & 1
	at = step % (64 if both else 32)
	b = waveBanks[(bank * 16 + at / 2) % 32] if not both else waveBanks[at / 2]
	sample = i64((b >> 4) if at % 2 == 0 else b & 15) - 8
	level = ioHalf(0x72)
	if level & 0x8000 != 0: return sample * 3 / 4 * 2
	match i64((level >> 13) & 3):
		0: 0
		1: sample * 2
		2: sample
		_: sample / 2

# the left and right samples: the PSG's channels at their side's volume and the PSG's share,
# the FIFOs at theirs
fn mixed() (f32, f32):
	cntL = ioHalf(0x80)
	cntH = ioHalf(0x82)
	if ioHalf(0x84) & 0x80 == 0: return (0.0, 0.0)
	share = [1, 2, 4, 0][cntH & 3]
	left = 0
	right = 0
	for k in 0..4:
		c = channels[k]
		if not c.on: continue
		if cntL & (u32(0x100) << u32(k)) != 0: right += c.output
		if cntL & (u32(0x1000) << u32(k)) != 0: left += c.output
	left = left * (i64((cntL >> 4) & 7) + 1) * share / 4
	right = right * (i64(cntL & 7) + 1) * share / 4
	for which in 0..2:
		sample = i64(samples[which]) * (4 if cntH & (u32(4) << u32(which)) != 0 else 2)
		if cntH & (u32(0x100) << u32(4 * which)) != 0: right += sample
		if cntH & (u32(0x200) << u32(4 * which)) != 0: left += sample
	(f32(left) / 1024.0, f32(right) / 1024.0)

# a write to a sound register (0x60 to 0x9F), after io holds it
pub fn soundWritten(off i64, v u16):
	soundTo(cycles)
	match off:
		0x64: if v & 0x8000 != 0: restartTone(0, 0x62, v & 0x7FF, v)
		0x6C: if v & 0x8000 != 0: restartTone(1, 0x68, v & 0x7FF, v)
		0x74:
			if v & 0x8000 != 0: channels[2].startWave(v)
		0x7C:
			if v & 0x8000 != 0:
				lfsr = 0x7F if v & 8 != 0 else 0x7FFF
				ratio = i64(v & 7)
				startChannel(
					3,
					ioHalf(0x78),
					(16 if ratio == 0 else 32 * ratio) << (i64((v >> 4) & 15) + 1),
					v
				)
		0x82:
			if v & 0x800 != 0: fifoReset(0)
			if v & 0x8000 != 0: fifoReset(1)
		_:
			if off >= 0x90 and off < 0xA0:
				bank = 16 * i64(((ioHalf(0x70) >> 6) & 1) ^ 1)   # the one not playing
				waveBanks[bank + off - 0x90] = v & 0xFF
				waveBanks[bank + off - 0x90 + 1] = v >> 8

fn restartTone(k i64, envelope i64, frequency i64, v u16):
	if k == 0:
		frequency1 = frequency
		sweepCount = (ioHalf(0x60) >> 4) & 7
	startChannel(k, ioHalf(envelope), 16 * (2048 - frequency), v)

# a channel started: its length and envelope from `settings` (length 0-5, the envelope 8-15)
fn startWave(mut c Channel, v u16):
	c.on = ioHalf(0x70) & 0x80 != 0
	c.length = 256 - i64(ioHalf(0x72) & 0xFF)
	c.lengthOn = v & 0x4000 != 0
	c.period = 8 * (2048 - i64(v & 0x7FF))
	c.left = c.period
	c.step = 0

fn startChannel(k i64, settings u32, period i64, v u16):
	channels[k].startTone(settings, period, v)

fn startTone(mut c Channel, settings u32, period i64, v u16):
	c.on = true
	c.length = 64 - i64(settings & 63)
	c.lengthOn = v & 0x4000 != 0
	c.volume = settings >> 12
	c.envelopeUp = settings & 0x800 != 0
	c.envelopeTime = (settings >> 8) & 7
	c.envelopeCount = c.envelopeTime
	c.period = period.max(1)
	c.left = c.period
	c.step = 0
	if settings & 0xF800 == 0: c.on = false   # no volume and falling: the channel is off
