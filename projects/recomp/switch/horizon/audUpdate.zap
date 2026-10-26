# RequestUpdate: the game's update data (switchbrew: Audio services; yuzu's InfoUpdater) parsed as
# the revision it declared lays it out, and the answer written in the layout the game reads back.
# The input is a 0x40-byte header of section sizes, then the behavior, the memory pools, the
# voice channel resources, the voices, the effects, the splitters, the mixes, the sinks and the
# performance request; the output a header, then the pools', voices', effects' and sinks'
# states, the performance history, the behavior's errors and the render info.

# the Result of audio module 153: an update the renderer cannot make sense of
pub resultInvalidUpdateInfo = 0x5399

poolRequestDetach = 2
poolRequestAttach = 4
poolDetached = 3
poolAttached = 5

effectUsed = 3
effectRemoved = 4

splitterMagic = 0x4844_4E53
splitterInfoMagic = 0x4944_4E53
splitterDataMagic = 0x4444_4E53

# The section sizes of the update header.
type UpdateSizes:
	behavior i64
	pools i64
	voices i64
	resources i64
	effects i64
	mixes i64
	sinks i64
	performance i64
	splitter i64

fn readSizes(input u8[]):
	UpdateSizes(
		behavior = input.u32le(4),
		pools = input.u32le(8),
		voices = input.u32le(0xC),
		resources = input.u32le(0x10),
		effects = input.u32le(0x14),
		mixes = input.u32le(0x18),
		sinks = input.u32le(0x1C),
		performance = input.u32le(0x20),
		splitter = input.u32le(0x24)
	)

fn f32s(input u8[], at i64, n i64):
	(0..n).map(input.f32le(at + it * 4))

# the memory pools: each asked to attach or detach, the answer its new state
fn updatePools(mut r Renderer, input u8[], at i64, size i64, mut out u8[]):
	count = size / 0x20
	while r.pools.len < count:
		r.pools.push(Pool())
	for i in 0..count:
		p = at + i * 0x20
		request = i64(input.u32le(p + 0x10))
		state = 0
		if request == poolRequestAttach:
			r.pools[i] = Pool(address = i64(input.u64le(p)), size = i64(input.u64le(p + 8)))
			state = poolAttached
		elif request == poolRequestDetach:
			r.pools[i] = Pool()
			state = poolDetached
		out.pushU32le(state)
		out.pushU32le(0)
		out.pushU64le(0)

fn updateResources(mut r Renderer, input u8[], at i64, size i64):
	for i in 0..(size / 0x70).min(r.resources.len):
		p = at + i * 0x70
		r.resources[i].inUse = input[p + 0x64] != 0
		if r.resources[i].inUse: r.resources[i].volumes = f32s(input, p + 4, 24)

# the play state a voice's request moves it to
fn playStateOf(current i64, requested i64):
	if requested == 0: return playStarted
	if requested == 1: return playRequestStop if current != playStopped else current
	playPaused

# where a voice entry keeps its fields: revision 15's has float filters and is longer
type VoiceLayout:
	waveBufferCount i64
	dataAddress i64
	mixId i64
	splitterId i64
	waveBuffers i64
	resources i64
	clearDrop i64
	flags i64

fn voiceLayout(stride i64):
	if stride >= 0x188: return VoiceLayout(0x54, 0x60, 0x70, 0x74, 0x78, 0x158, 0x170, 0x174)
	VoiceLayout(0x3C, 0x48, 0x58, 0x5C, 0x60, 0x140, 0x158, 0x15C)

# a wave buffer's queued entry (0x38 bytes), taken in when the game has not marked it sent
fn updateWaveBuffer(mut r Renderer, voice i64, i i64, input u8[], p i64):
	first = r.voices[voice].resources[0]
	if not r.states[first].valid[i] and r.voices[voice].buffers[i].sentToDsp:
		r.voices[voice].buffers[i].address = 0
	if input[p + 0x1A] != 0: return
	start = i64(input.i32le(p + 0x10))
	end = i64(input.i32le(p + 0x14))
	if start < 0 or end < 0: return
	looping = input[p + 0x18] != 0
	v2 = r.params.revision >= 8
	r.voices[voice].buffers[i] = WaveBuffer(
		address = i64(input.u64le(p)),
		size = i64(input.u64le(p + 8)),
		startOffset = start,
		endOffset = end,
		looping,
		streamEnded = input[p + 0x19] != 0,
		sentToDsp = false,
		loopCount = input.i32le(p + 0x1C) if v2 else (-1 if looping else 0),
		loopStart = input.u32le(p + 0x30) if v2 else start,
		loopEnd = input.u32le(p + 0x34) if v2 else end,
		contextAddress = i64(input.u64le(p + 0x20))
	)

# a voice's parameters taken in
fn updateVoiceParameters(mut r Renderer, id i64, input u8[], p i64, lay VoiceLayout):
	flags = i64(input[p + lay.flags])
	state = playStateOf(r.voices[id].playState, input[p + 0xA])
	flush = i64(input[p + lay.clearDrop + 1]) if r.params.revision >= 5 else 0
	r.voices[id].lastPlayState = r.voices[id].playState
	r.voices[id].playState = state
	r.voices[id].inUse = true
	r.voices[id].format = input[p + 0xB]
	r.voices[id].sampleRate = input.u32le(p + 0xC)
	r.voices[id].channels = i64(input.u32le(p + 0x18)).min(maxChannels)
	r.voices[id].pitch = input.f32le(p + 0x1C)
	r.voices[id].volume = input.f32le(p + 0x20)
	r.voices[id].waveBufferCount = input.u32le(p + lay.waveBufferCount)
	r.voices[id].flushCount += flush
	r.voices[id].mixId = input.u32le(p + lay.mixId)
	r.voices[id].splitterId = input.i32le(p + lay.splitterId) if r.params.revision >= 2 else -1
	r.voices[id].dataAddress = i64(input.u64le(p + lay.dataAddress))
	r.voices[id].resetCounts = flags & 1 != 0 and r.params.revision >= 5
	r.voices[id].skipsResampling = flags & 2 != 0 and r.params.revision >= 5
	if input[p + lay.clearDrop] != 0: r.voices[id].dropped = false
	for c in 0..maxChannels:
		slot = i64(input.u32le(p + lay.resources + c * 4))
		r.voices[id].resources[c] = slot.min(r.states.len - 1)

# one voice entry taken in; its answer (played samples, consumed buffers, dropped) appended
fn updateVoice(mut r Renderer, input u8[], p i64, lay VoiceLayout, mut out u8[]):
	id = i64(input.u32le(p)).min(r.voices.len - 1)
	isNew = input[p + 8] != 0
	if input[p + 9] == 0:
		out.pushU64le(0)
		out.pushU64le(0)
		return
	if isNew:
		r.voices[id] = Voice()
		for c in 0..i64(input.u32le(p + 0x18)).min(maxChannels):
			slot = i64(input.u32le(p + lay.resources + c * 4)).min(r.states.len - 1)
			r.states[slot] = VoiceState()
	r.updateVoiceParameters(id, input, p, lay)
	for i in 0..maxWaveBuffers:
		r.updateWaveBuffer(id, i, input, p + lay.waveBuffers + i * 0x38)
	if isNew: r.voices[id].isNew = true
	first = r.voices[id].resources[0]
	fresh = r.voices[id].isNew
	out.pushU64le(0 if fresh else r.states[first].played)
	out.pushU32le(0 if fresh else r.states[first].consumed)
	out.pushU32le(1 if r.voices[id].dropped and not fresh else 0)

fn updateVoices(mut r Renderer, input u8[], at i64, size i64, mut out u8[]):
	count = r.params.voices
	for i in 0..count:
		r.voices[i].inUse = false
	if count == 0: return
	stride = size / count
	lay = voiceLayout(stride)
	for i in 0..count:
		r.updateVoice(input, at + i * stride, lay, out)

# the effects' states: used while the renderer runs and the effect is not disabled
fn updateEffects(mut r Renderer, input u8[], at i64, size i64, mut out u8[]):
	count = size / 0xC0
	while r.effects.len < count:
		r.effects.push(Effect())
	for i in 0..count:
		p = at + i * 0xC0
		kind = i64(input[p])
		r.effects[i] = Effect(kind, enabled = input[p + 2] != 0, isNew = input[p + 1] != 0)
		active = kind != 0 and (r.effects[i].enabled or r.started)
		out.push(effectUsed if active else effectRemoved)
		loop (0x90 if r.params.revision >= 9 else 0x10) - 1:
			out.push(0)

# the splitters: their destinations' lists, and each destination's mix and volumes
fn updateSplitters(mut r Renderer, input u8[], at i64, size i64):
	if size < 0x20 or i64(input.u32le(at)) != splitterMagic: return
	while r.splitters.len < input.u32le(at + 4):
		r.splitters.push(SplitterInfo())
	while r.destinations.len < input.u32le(at + 8):
		r.destinations.push(SplitterDestination())
	p = at + 0x20
	loop i64(input.u32le(at + 4)):
		id = i64(input.i32le(p + 4))
		count = i64(input.u32le(p + 0xC))
		if i64(input.u32le(p)) == splitterInfoMagic and id >= 0 and id < r.splitters.len:
			r.splitters[id].destinations = (0..count).map(i64(input.u32le(p + 0x10 + it * 4)))
		p += 0x10 + count * 4
	entry = 0x70
	inUse = 0x6C
	if r.params.revision >= 15:
		entry = 0xA8
		inUse = 0x9C
	elif r.params.revision >= 12:
		entry = 0x90
		inUse = 0x84
	loop i64(input.u32le(at + 8)):
		id = i64(input.i32le(p + 4))
		if i64(input.u32le(p)) == splitterDataMagic and id >= 0 and id < r.destinations.len:
			r.destinations[id] = SplitterDestination(
				mixId = input.u32le(p + 0x68),
				inUse = input[p + inUse] != 0,
				volumes = f32s(input, p + 8, 24)
			)
		p += entry

# the mixes: revision 7 sends a count first and names each entry's mix
fn updateMixes(mut r Renderer, input u8[], at i64, size i64):
	count = r.mixes.len
	p = at
	named = r.params.revision >= 7
	if named:
		count = i64(input.u32le(at + 4)).clamp(0, r.mixes.len)
		p += 0x20
	for i in 0..count:
		e = p + i * 0x930
		id = i64(input.i32le(e + 0x10)) if named else i
		if id < 0 or id >= r.mixes.len: continue
		r.mixes[id] = Mix(
			inUse = input[e + 0xC] != 0,
			volume = input.f32le(e),
			bufferCount = i64(input.u32le(e + 8)).min(maxMixBuffers),
			destMix = input.u32le(e + 0x924),
			volumes = f32s(input, e + 0x24, 576)
		)

# the sinks: a device's input buffers and downmix
fn updateSinks(mut r Renderer, input u8[], at i64, mut out u8[]):
	for i in 0..r.params.sinks:
		p = at + i * 0x140
		kind = i64(input[p])
		sink = Sink(kind, inUse = input[p + 1] != 0)
		if kind == 1:
			sink.inputCount = i64(input.u32le(p + 0x120)).min(maxChannels)
			sink.inputs = (0..maxChannels).map(i64(i8(input[p + 0x124 + it])))
			sink.downmix = input[p + 0x12B] != 0
			sink.coefficients = f32s(input, p + 0x12C, 4)
		r.sinks[i] = sink
		loop 0x20:
			out.push(0)

# the answer: its header of the sections' sizes, then the sections
fn updateAnswer(r Renderer, input u8[], pools u8[], voices u8[], effects u8[], sinks u8[]):
	behavior = 0xB0
	perf = 0x10
	info = 0x10 if r.params.revision >= 5 else 0
	total = 0x40 + behavior + pools.len + voices.len + effects.len + sinks.len + perf + info
	out = []
	out.pushU32le(input.u32le(0))
	for size in [behavior, pools.len, voices.len, 0, effects.len, 0, sinks.len, perf, 0, info]:
		out.pushU32le(size)
	while out.len < 0x3C:
		out.push(0)
	out.pushU32le(total)
	out.extend(pools)
	out.extend(voices)
	out.extend(effects)
	out.extend(sinks)
	loop perf + behavior:
		out.push(0)
	if info > 0:
		out.pushU64le(r.frames)
		out.pushU64le(0)
	out

# The renderer's state updated by the game's data; the answer, or the Result of an update it
# cannot read.
pub fn requestUpdate(mut r Renderer, input u8[]) u8[] ? i64:
	if input.len < 0x40: return resultInvalidUpdateInfo
	sizes = readSizes(input)
	p = 0x40
	if revisionNumber(input.u32le(p)) != r.params.revision: return resultInvalidUpdateInfo
	p += sizes.behavior
	pools = []
	r.updatePools(input, p, sizes.pools, pools)
	p += sizes.pools
	r.updateResources(input, p, sizes.resources)
	p += sizes.resources
	voices = []
	r.updateVoices(input, p, sizes.voices, voices)
	p += sizes.voices
	effects = []
	r.updateEffects(input, p, sizes.effects, effects)
	p += sizes.effects
	r.updateSplitters(input, p, sizes.splitter)
	p += sizes.splitter
	r.updateMixes(input, p, sizes.mixes)
	p += sizes.mixes
	sinks = []
	r.updateSinks(input, p, sinks)
	r.updateAnswer(input, pools, voices, effects, sinks)
