# A voice's samples, taken from the wave buffers its game queued (yuzu's DecodeFromWaveBuffers):
# PCM16, PCM8 and DSP ADPCM read from guest memory, the loops and the buffers ended and counted,
# then resampled to the renderer's rate by the voice's pitch. Memory is read only while the
# sound is wanted; otherwise the voices advance and report as if it were (nobody hears them,
# but the game waits for its buffers to be consumed).

import recomp.switch.cpu

adpcmSamplesPerFrame = 14
adpcmFrameBytes = 8

fn s16At(a i64):
	v = i64(cpu.memory.load(a, 1))
	v - 0x1_0000 if v >= 0x8000 else v

fn s8At(a i64):
	v = i64(cpu.memory.load(a, 0))
	(v - 0x100 if v >= 0x80 else v) * 256

# `n` samples of a PCM wave buffer from its sample `first`, for channel `ch` of `channels`
fn decodePcm(format i64, base i64, first i64, n i64, ch i64, channels i64):
	if format == formatPcm8: return (0..n).map(s8At(base + (first + it) * channels + ch))
	(0..n).map(s16At(base + ((first + it) * channels + ch) * 2))

# `n` samples of a DSP ADPCM wave buffer from its sample `first`; the filter state in the voice's
# state (its last two samples)
fn decodeAdpcm(mut s VoiceState, coefficients i64, base i64, first i64, n i64):
	out = []
	for i in 0..n:
		index = first + i
		frame = base + index / adpcmSamplesPerFrame * adpcmFrameBytes
		within = index % adpcmSamplesPerFrame
		header = i64(cpu.memory.load(frame, 0))
		pair = (header >> 4 & 7) * 2
		byte = i64(cpu.memory.load(frame + 1 + within / 2, 0))
		nibble = byte >> 4 if within % 2 == 0 else byte & 15
		code = nibble - 16 if nibble >= 8 else nibble
		prediction = s16At(coefficients + pair * 2) * s.yn0 +
			s16At(coefficients + pair * 2 + 2) * s.yn1
		sample = (((code << (header & 15)) << 11) + 0x400 + prediction) >> 11
		s.yn1 = s.yn0
		s.yn0 = sample.clamp(-0x8000, 0x7FFF)
		out.push(s.yn0)
	out

# the wave buffer `i` of the voice ended: its slot free, the next one current
fn endWaveBuffer(mut s VoiceState, streamEnded bool):
	s.valid[s.bufferIndex] = false
	s.loopCount = 0
	if streamEnded: s.played = 0
	s.bufferIndex = (s.bufferIndex + 1) % maxWaveBuffers
	s.consumed += 1

# Up to `want` source samples of channel `ch` of voice `v`, in 16-bit steps; fewer when its
# buffers run out. `hear` says whether the samples are read at all (else zeros).
fn takeSamples(mut r Renderer, v i64, ch i64, want i64, hear bool):
	out = []
	slot = r.voices[v].resources[ch]
	format = r.voices[v].format
	while out.len < want:
		if r.states[slot].bufferIndex >= maxWaveBuffers:
			r.states[slot].bufferIndex = 0
		index = r.states[slot].bufferIndex
		if not r.states[slot].valid[index]: break
		wb = r.voices[v].buffers[index].copy()
		offset = r.states[slot].offset
		if offset == 0 and format == formatAdpcm and wb.contextAddress != 0 and hear:
			r.states[slot].yn0 = s16At(wb.contextAddress + 2)
			r.states[slot].yn1 = s16At(wb.contextAddress + 4)
		start = wb.startOffset
		end = wb.endOffset
		if wb.looping and r.states[slot].loopCount > 0 and wb.loopStart <= wb.loopEnd:
			start = wb.loopStart
			end = wb.loopEnd
		n = (end - start - offset).clamp(0, want - out.len)
		if hear and n > 0:
			if format == formatAdpcm:
				out.extend(
					decodeAdpcm(
						mut ref r.states[slot],
						r.voices[v].dataAddress,
						wb.address,
						start + offset,
						n
					)
				)
			else:
				out.extend(
					decodePcm(format, wb.address, start + offset, n, ch, r.voices[v].channels)
				)
		elif n > 0:
			out.extend(fill(n, 0))
		r.states[slot].played += n
		r.states[slot].offset += n
		if n > 0 and r.states[slot].offset < end - start: continue
		r.states[slot].offset = 0
		if wb.looping:
			r.states[slot].loopCount += 1
			if wb.loopCount >= 0 and (r.states[slot].loopCount > wb.loopCount or n == 0):
				endWaveBuffer(mut ref r.states[slot], wb.streamEnded)
			if n == 0: break
			if r.voices[v].resetCounts: r.states[slot].played = 0
		else:
			endWaveBuffer(mut ref r.states[slot], wb.streamEnded)
	out

# One frame (`count` samples at the renderer's rate) of channel `ch` of voice `v`, as floats in
# -1..1; empty when nobody hears (the voice still advances).
pub fn voiceFrame(mut r Renderer, v i64, ch i64, count i64, hear bool) f32[]:
	slot = r.voices[v].resources[ch]
	ratio = f64(r.voices[v].sampleRate) / f64(r.params.sampleRate) * f64(r.voices[v].pitch)
	if r.voices[v].skipsResampling: ratio = 1.0
	fraction = r.states[slot].fraction
	total = fraction + count * ratio
	need = i64(total)
	raw = r.takeSamples(v, ch, need, hear)
	r.states[slot].fraction = total - need
	if not hear: return []
	while raw.len < need:
		raw.push(0)
	out = []
	if ratio == 1.0:
		for i in 0..count:
			out.push(f32(raw[i]) / 32768.0)
		return out
	last = r.states[slot].last
	source f32[] = [last]
	for s in raw:
		source.push(f32(s) / 32768.0)
	for i in 0..count:
		p = fraction + i * ratio
		at = i64(p).min(source.len - 1)
		t = f32(p - at)
		out.push(source[at] * (1.0 - t) + source[(at + 1).min(len - 1)] * t)
	r.states[slot].last = source[len - 1]
	out
