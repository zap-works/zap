# A DSP voice: its BRR sample decoded four samples at a time into a ring of twelve, read at its
# pitch through the Gaussian table (or the noise in its place), shaped by its ADSR or gain
# envelope; keyed on (after 5 silent samples) and off as KON and KOFF say every other sample.
# Its registers are those at its number << 4: VOLL VOLR PITCHL PITCHH SRCN ADSR1 ADSR2 GAIN ENVX OUTX.

type EnvelopeMode:
	Release
	Attack
	Decay
	Sustain

type DspVoice:
	bit i64
	brrAddress i64 = 0   # the block decoded
	brrOffset i64 = 1    # its next pair of bytes
	ring i64[12] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]   # decoded samples, doubled to 16 bits
	ringAt i64 = 0       # where the next four go
	position i64 = 0     # the pitch counter: bits 12-13 the sample, 4-11 between it and the next
	konDelay i64 = 0
	envelope i64 = 0
	hiddenEnvelope i64 = 0
	mode EnvelopeMode = .Release

	# the voice's sample for this tick after its envelope (`previous`: the voice before's, for PMON)
	fn runVoice(v i64, previous i64):
		base = v << 4
		pitch = (dspRegs[base + 2] | (dspRegs[base + 3] << 8)) & 0x3FFF
		if v > 0 and dspRegs[0x2D] & bit != 0: pitch += ((previous >> 5) * pitch) >> 10
		entry = (dspRegs[dirReg] << 8) + (dspRegs[base + 4] << 2)
		if konDelay > 0:
			if konDelay == 5:
				brrAddress = ramWord(entry)
				brrOffset = 1
				ringAt = 0
				endx &= ~bit
			envelope = 0
			hiddenEnvelope = 0
			konDelay -= 1
			position = 0x4000 if konDelay & 3 != 0 else 0
			pitch = 0
		header = i64(spcRam[brrAddress])
		sample = wrap16(noise * 2) if dspRegs[0x3D] & bit != 0 else interpolated()
		out = ((sample * envelope) >> 11) & ~1
		dspRegs[base + 8] = envelope >> 4
		dspRegs[base + 9] = (out >> 8) & 0xFF
		if dspRegs[flgReg] & 0x80 != 0 or header & 3 == 1:
			mode = .Release
			envelope = 0
		if everyOther:
			if koffNow & bit != 0: mode = .Release
			if konNow & bit != 0:
				konDelay = 5
				mode = .Attack
		if konDelay == 0: runEnvelope(base)
		if position >= 0x4000: decodeBrr(header, ramWord(entry + 2))
		position = ((position & 0x3FFF) + pitch).min(0x7FFF)
		out

	# the four latest samples weighed by the counter's fraction
	fn interpolated():
		at = (position >> 12) + ringAt
		i = (position >> 4) & 0xFF
		out = (gaussTable[255 - i] * ring[at % 12]) >> 11
		out += (gaussTable[511 - i] * ring[(at + 1) % 12]) >> 11
		out += (gaussTable[256 + i] * ring[(at + 2) % 12]) >> 11
		out = wrap16(out) + ((gaussTable[i] * ring[(at + 3) % 12]) >> 11)
		clamp16(out) & ~1

	# four samples from the block's next two bytes; past its last, the next block or the loop's
	fn decodeBrr(header i64, loopAddress i64):
		shift = header >> 4
		filter = (header >> 2) & 3
		for k in 0..4:
			byte = i64(spcRam[(brrAddress + brrOffset + (k >> 1)) & 0xFFFF])
			nibble = ((byte >> 4) if k & 1 == 0 else byte & 0x0F) ^ 8
			s = (((nibble - 8) << shift) >> 1) if shift <= 12 else (-2048 if nibble < 8 else 0)
			old = ring[(ringAt + k + 11) % 12] >> 1
			older = ring[(ringAt + k + 10) % 12] >> 1
			match filter:
				1: s += old + ((-old) >> 4)
				2: s += old * 2 + ((-old * 3) >> 5) - older + (older >> 4)
				3: s += old * 2 + ((-old * 13) >> 6) - older + ((older * 3) >> 4)
				_: pass
			ring[(ringAt + k) % 12] = wrap16(clamp16(s) * 2)
		ringAt = (ringAt + 4) % 12
		brrOffset += 2
		if brrOffset < 9: return
		brrAddress = (brrAddress + 9) & 0xFFFF
		if header & 1 != 0:
			brrAddress = loopAddress
			endx |= bit
		brrOffset = 1

	# One step of the envelope when its rate falls on this sample: release down by 8, attack up,
	# decay and sustain down exponentially, or the gain's direct level or its four slopes.
	fn runEnvelope(base i64):
		env = envelope
		if mode == .Release:
			envelope = (env - 8).max(0)
			return
		adsr1 = dspRegs[base + 5]
		boundary = dspRegs[base + 6]
		rate = 0
		if adsr1 & 0x80 != 0:
			if mode == .Attack:
				rate = (adsr1 & 0x0F) * 2 + 1
				env += 0x400 if rate == 31 else 0x20
			else:
				env -= 1
				env -= env >> 8
				rate = ((adsr1 >> 3) & 0x0E) + 0x10 if mode == .Decay else dspRegs[base + 6] & 0x1F
		else:
			gain = dspRegs[base + 7]
			boundary = gain
			rate = gain & 0x1F
			if gain < 0x80:
				env = gain << 4
				rate = 31
			else:
				match gain >> 5:
					4: env -= 0x20
					5:
						env -= 1
						env -= env >> 8
					6: env += 0x20
					_: env += 0x20 if hiddenEnvelope < 0x600 else 8
		if mode == .Decay and env >> 8 == boundary >> 5: mode = .Sustain
		hiddenEnvelope = env
		if env < 0 or env > 0x7FF:
			env = 0 if env < 0 else 0x7FF
			if mode == .Attack: mode = .Decay
		if isRateDue(rate): envelope = env

fn ramWord(at i64):
	spcRam[at & 0xFFFF] | (i64(spcRam[(at + 1) & 0xFFFF]) << 8)
