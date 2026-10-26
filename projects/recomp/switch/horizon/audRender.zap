# One audio frame of a renderer (yuzu's command generator and the DSP's commands, in one pass):
# each started voice's wave buffers are put to use, its samples mixed into the buffers of its
# mix by its volumes, the mixes summed into the final mix in the order of their distance from
# it, and the device sink's channels downmixed to stereo. Left out: the voices' biquad filters,
# volume ramps, and the effects (reverb, delay, aux and the rest).

# the voice's wave buffers made current by its play state; whether it plays this frame
fn prepareVoice(mut r Renderer, v i64) bool:
	first = r.voices[v].resources[0]
	channels = r.voices[v].channels
	if r.voices[v].flushCount > 0:
		wave = r.voices[v].buffers.len
		for i in 0..r.voices[v].flushCount.min(wave):
			for c in 0..channels:
				slot = r.voices[v].resources[c]
				if r.states[slot].bufferIndex == i:
					r.states[slot].bufferIndex = (i + 1) % maxWaveBuffers
					r.states[slot].consumed += 1
				r.states[slot].valid[i] = false
			r.voices[v].buffers[i].sentToDsp = true
		r.voices[v].flushCount = 0
	state = r.voices[v].playState
	if state == playStarted:
		for i in 0..maxWaveBuffers:
			if not r.voices[v].buffers[i].sentToDsp:
				for c in 0..channels:
					r.states[r.voices[v].resources[c]].valid[i] = true
				r.voices[v].buffers[i].sentToDsp = true
		r.voices[v].wasPlaying = false
		return r.states[first].valid.any(it)
	if state == playRequestStop:
		for i in 0..maxWaveBuffers:
			r.voices[v].buffers[i].sentToDsp = true
			for c in 0..channels:
				slot = r.voices[v].resources[c]
				if r.states[slot].valid[i]:
					r.states[slot].bufferIndex = (r.states[slot].bufferIndex + 1) % maxWaveBuffers
					r.states[slot].consumed += 1
				r.states[slot].valid[i] = false
		for c in 0..channels:
			slot = r.voices[v].resources[c]
			played = r.states[slot].consumed
			r.states[slot] = VoiceState(consumed = played, bufferIndex = r.states[slot].bufferIndex)
		r.voices[v].playState = playStopped
	r.voices[v].wasPlaying = r.voices[v].lastPlayState == playStarted
	false

# the mixes in the order they are processed (the farthest from the final mix first), their first
# buffers among the mix buffers set
fn orderMixes(mut r Renderer) i64[]:
	order i64[] = []
	far = -1_000_000
	dist i64[] = []
	for m in 0..r.mixes.len:
		d = 0
		at = m
		while at != 0 and d < r.mixes.len + 1:
			at = r.mixes[at].destMix
			d += 1
			if at < 0 or at >= r.mixes.len:
				d = far
				break
		dist.push(d)
	for m in 0..r.mixes.len:
		if not r.mixes[m].inUse: continue
		place = order.len
		while place > 0 and dist[order[place - 1]] < dist[m]:
			place -= 1
		order.insert(place, m)
	offset = 0
	for m in order:
		r.mixes[m].offset = offset
		offset += r.mixes[m].bufferCount
	order

# `samples` added to the buffers of mix `m` by `volumes`, scaled by `gain`
fn addToMix(r Renderer, mut buffers f32[], m i64, samples f32[], volumes f32[], gain f32):
	count = r.params.sampleCount
	if m < 0 or m >= r.mixes.len or not r.mixes[m].inUse: return
	for b in 0..r.mixes[m].bufferCount:
		scale = gain * volumes[b]
		if scale == 0.0: continue
		base = (r.mixes[m].offset + b) * count
		if base + count > buffers.len: return
		for i in 0..count:
			buffers[base + i] += samples[i] * scale

# the voice's channel `ch` frame sent where the voice points: its mix, or its splitter's
# destinations
fn routeVoice(r Renderer, mut buffers f32[], v i64, ch i64, samples f32[]):
	gain = r.voices[v].volume
	if r.voices[v].mixId != unusedMixId:
		r.addToMix(
			buffers,
			r.voices[v].mixId,
			samples,
			r.resources[r.voices[v].resources[ch]].volumes,
			gain
		)
		return
	splitter = r.voices[v].splitterId
	if splitter < 0 or splitter >= r.splitters.len: return
	targets = r.splitters[splitter].destinations.copy()
	for j, d in targets:
		if j % r.voices[v].channels != ch or d >= r.destinations.len: continue
		if r.destinations[d].inUse:
			r.addToMix(buffers, r.destinations[d].mixId, samples, r.destinations[d].volumes, gain)

fn mixVoices(mut r Renderer, mut buffers f32[], hear bool):
	for v in 0..r.voices.len:
		voice = r.voices[v].copy()
		if voice.isNew: r.voices[v].isNew = false
		if not voice.inUse or voice.waveBufferCount == 0 or voice.dropped: continue
		if not r.prepareVoice(v): continue
		for ch in 0..voice.channels:
			samples = r.voiceFrame(v, ch, r.params.sampleCount, hear)
			if hear: r.routeVoice(buffers, v, ch, samples)

# the mixes summed toward the final mix, which is then scaled by its volume
fn mixDown(mut r Renderer, mut buffers f32[], order i64[]):
	count = r.params.sampleCount
	for m in order:
		if m == 0: continue
		dest = r.mixes[m].destMix
		if dest < 0 or dest >= r.mixes.len or not r.mixes[dest].inUse: continue
		for i in 0..r.mixes[m].bufferCount:
			volumes = (0..maxMixBuffers).map(r.mixes[m].volumes[i * maxMixBuffers + it])
			src = buffers[
				(r.mixes[m].offset + i) * count..(r.mixes[m].offset + i + 1) * count
			].copy()
			r.addToMix(buffers, dest, src, volumes, r.mixes[m].volume)
	final = r.mixes[0].copy()
	for i in 0..final.bufferCount * count:
		buffers[final.offset * count + i] *= final.volume

# the first device sink's channels as interleaved stereo
fn deviceFrame(r Renderer, buffers f32[]) f32[]:
	count = r.params.sampleCount
	out f32[] = []
	for sink in r.sinks:
		if sink.kind != 1 or not sink.inUse: continue
		input f32[] = []   # the sink's channels one after another
		for index in sink.inputs:
			first = (r.mixes[0].offset + index) * count
			input.extend(buffers[first..first + count])
		for i in 0..count:
			left = input[i]
			right = input[count + i] if sink.inputCount > 1 else left
			if sink.inputCount >= 6 and sink.downmix:
				c = sink.coefficients
				center = input[2 * count + i] * c[1]
				lfe = input[3 * count + i] * c[2]
				left = left * c[0] + center + lfe + input[4 * count + i] * c[3]
				right = right * c[0] + center + lfe + input[5 * count + i] * c[3]
			out.push(left.clamp(-1.0, 1.0))
			out.push(right.clamp(-1.0, 1.0))
		return out
	out

# One frame of the renderer: the voices advanced, and when `hear` its sound as interleaved stereo.
pub fn renderFrame(mut r Renderer, hear bool) f32[]:
	r.frames += 1
	buffers f32[] = []
	if hear: buffers = fill(r.params.mixes * r.params.sampleCount, 0.0)
	order = r.orderMixes()
	r.mixVoices(buffers, hear)
	if not hear or r.mixes.isEmpty or not r.mixes[0].inUse: return []
	r.mixDown(buffers, order)
	r.deviceFrame(buffers)
