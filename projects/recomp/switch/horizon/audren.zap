# audren:u, the audio renderer manager (switchbrew: Audio services), and the renderers and audio
# device it gives out. A game opens a renderer with its parameters and a work buffer, then at
# every audio frame (the renderer's sample count at its rate, 5 ms at 48 kHz and 240 samples) it
# is woken by the renderer's event and sends RequestUpdate with the state of its voices and mixes;
# audupdate.zap reads that, audrender.zap plays it. The frame is on the guest's clock, so a run
# repeats.

import recomp.switch.cpu
import engine.audio

resultInsufficientBuffer = 0x899
resultOutOfSessions = 0xA99
resultInvalidRevision = 0xC_0299
maxRenderers = 2

# the name the audio device goes by, in the 0x100 bytes a DeviceName takes
deviceName = "AudioStereoJackOutput"
deviceNameSize = 0x100

# the counter's ticks in one frame of the renderer
fn framePeriod(r Renderer):
	r.params.sampleCount * cpu.counterHz / r.params.sampleRate

fn newRenderer(mut k Kernel, params RendererParams):
	e, _ = k.newEvent(false)
	slots = params.voices
	Renderer(
		params,
		event = e,
		voices = fill(slots, Voice()),
		states = fill(slots, VoiceState()),
		resources = fill(slots, ChannelResource()),
		mixes = fill(params.subMixes + 1, Mix()),
		sinks = fill(params.sinks, Sink()),
		effects = fill(params.effects, Effect())
	)

# audren:u
fn audioRendererManager(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		0: k.openAudioRenderer(req, res)
		1: res.u64(readRendererParams(req.data, 0).workBufferSize())
		2, 4: k.offer(res, "IAudioDevice")
		_: k.unwritten(i, req)

fn openAudioRenderer(mut k Kernel, req Request, mut res Response):
	params = readRendererParams(req.data, 0)
	if params.revision > currentRevision: return res.fail(resultInvalidRevision)
	if k.audio.renderers.count(not .closed) >= maxRenderers: return res.fail(resultOutOfSessions)
	if req.arg(0x38, 8) < params.workBufferSize(): return res.fail(resultInsufficientBuffer)
	k.audio.renderers.push(k.newRenderer(params))
	k.audio.sound.rate = params.sampleRate
	s = k.subService(res, "IAudioRenderer")
	k.services[s].value = k.audio.renderers.len - 1

# IAudioRenderer
fn audioRenderer(mut k Kernel, i i64, req Request, mut res Response):
	r = k.services[i].value
	match req.command:
		0: res.u32(k.audio.renderers[r].params.sampleRate)
		1: res.u32(k.audio.renderers[r].params.sampleCount)
		2: res.u32(k.audio.renderers[r].params.mixes)
		3: res.u32(0 if k.audio.renderers[r].started else 1)
		4, 10: k.requestUpdateCommand(r, req, res)
		5:
			k.audio.renderers[r].started = true
			k.audio.renderers[r].nextFrame = k.now() + k.audio.renderers[r].framePeriod()
		6: k.audio.renderers[r].started = false
		7: res.copied.push(k.add(.Event(k.audio.renderers[r].event)))
		8: k.audio.renderers[r].renderingTimeLimit = req.arg(0, 4)
		9: res.u32(k.audio.renderers[r].renderingTimeLimit)
		12: k.audio.renderers[r].voiceDrop = req.data.f32le(0)
		13: res.data.pushF32le(k.audio.renderers[r].voiceDrop)
		14: pass
		_: k.unwritten(i, req)

# RequestUpdate (and its Auto form): the game's data in, the renderer's answer out
fn requestUpdateCommand(mut k Kernel, r i64, req Request, mut res Response):
	answer = k.audio.renderers[r].requestUpdate(req.sent(0)) ?? return res.fail(error)
	req.receive(0).putBuffer(answer)
	k.setEvent(k.audio.renderers[r].event, false)

# IAudioDevice
fn audioDevice(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		0, 6, 14:
			req.receive(0).putBuffer(deviceNameBytes())
			res.u32(1)
		1, 7: pass
		2, 8: res.u32(0x3F80_0000)
		3, 10, 13: req.receive(0).putBuffer(deviceNameBytes())
		4, 11, 12:
			_, h = k.newEvent(false)
			res.copied.push(h)
		5: res.u32(2)
		21: res.u8(0)
		_: k.unwritten(i, req)

fn deviceNameBytes():
	name u8[] = deviceName.bytes().copy()
	while name.len < deviceNameSize:
		name.push(0)
	name

# The renderers that are due a frame, their voices advanced and the sound heard; their events
# signaled. A game that falls behind loses the frames it missed.
pub fn audioTick(mut k Kernel):
	now = k.now()
	for r in 0..k.audio.renderers.len:
		if not k.audio.renderers[r].started or now < k.audio.renderers[r].nextFrame: continue
		hear = k.audio.sound.isWanted()
		period = k.audio.renderers[r].framePeriod()
		if now - k.audio.renderers[r].nextFrame > 8 * period:
			k.audio.renderers[r].nextFrame = now
		frame = k.audio.renderers[r].renderFrame(hear)
		if hear and not frame.isEmpty: k.audio.sound.pushFrame(frame)
		k.audio.renderers[r].nextFrame += period
		k.setEvent(k.audio.renderers[r].event, true)
