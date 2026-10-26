# The S-DSP: 128 registers the SPC700 reaches through F2/F3, eight voices (dspVoice.zap) mixed at
# 32 kHz into a stereo sample with the main and echo volumes, the echo's ring buffer in the
# SPC700's RAM through its 8-tap FIR filter and feedback, and the noise generator, as fullsnes
# describes them. A sample a time, not the hardware's 32 steps of one: what the SPC700 reads back
# (ENDX, ENVX, OUTX) is a sample's, which is all the sound driver looks at.

dirReg = 0x5D
konReg = 0x4C
koffReg = 0x5C
flgReg = 0x6C
endxReg = 0x7C

# a rate's period in samples (index 0 never), and its phase against the shared counter
ratePeriods = [
	30_721,
	2048,
	1536,
	1280,
	1024,
	768,
	640,
	512,
	384,
	320,
	256,
	192,
	160,
	128,
	96,
	80,
	64,
	48,
	40,
	32,
	24, 20, 16, 12, 10, 8, 6, 5, 4, 3, 2, 1
]
rateOffsets = [
	1, 0, 1040, 536, 0, 1040, 536, 0, 1040, 536, 0, 1040, 536, 0, 1040, 536, 0, 1040, 536, 0, 1040,
	536, 0, 1040, 536, 0, 1040, 536, 0, 1040, 0, 0
]
counterRange = 30_720

pub mut dspRegs i64[] = zeros(128)
mut voices DspVoice[] = []
mut endx = 0
mut newKon = 0     # KON as last written
mut konNow = 0     # the voices it keys on this pair of samples
mut koffNow = 0
mut everyOther = false
mut rateCounter = 0
mut noise = 0x4000
mut echoOffset = 0
mut echoLength = 0
mut firLeft i64[8] = [0, 0, 0, 0, 0, 0, 0, 0]
mut firRight i64[8] = [0, 0, 0, 0, 0, 0, 0, 0]
mut firAt = 0
pub mut soundSamples f32[] = []   # the samples made since the frame's sound was taken
pub mut makesSound = false

fn dspFields(mut f StateFile):
	f.intList(dspRegs)
	f.voices(voices)
	endx = f.int(endx)
	newKon = f.int(newKon)
	konNow = f.int(konNow)
	koffNow = f.int(koffNow)
	everyOther = f.isSet(everyOther)
	rateCounter = f.int(rateCounter)
	noise = f.int(noise)
	echoOffset = f.int(echoOffset)
	echoLength = f.int(echoLength)
	for k in 0..8:
		firLeft[k] = f.int(firLeft[k])
		firRight[k] = f.int(firRight[k])
	firAt = f.int(firAt)

fn dspPowerOn():
	dspRegs = zeros(128)
	dspRegs[flgReg] = 0xE0
	voices = (0..8).map(DspVoice(bit = 1 << it))
	endx = 0
	newKon = 0
	konNow = 0
	koffNow = 0
	everyOther = false
	rateCounter = 0
	noise = 0x4000
	echoOffset = 0
	echoLength = 0
	firLeft = [0, 0, 0, 0, 0, 0, 0, 0]
	firRight = [0, 0, 0, 0, 0, 0, 0, 0]
	firAt = 0
	soundSamples.clear()

fn dspRead(reg i64):
	if reg == endxReg: return endx
	dspRegs[reg]

fn dspWrite(reg i64, v i64):
	dspRegs[reg] = v
	if reg == konReg: newKon = v
	if reg == endxReg: endx = 0

fn signedReg(reg i64):
	signed(dspRegs[reg])

fn clamp16(v i64):
	v.clamp(-0x8000, 0x7FFF)

fn wrap16(v i64):
	((v & 0xFFFF) ^ 0x8000) - 0x8000

# whether a step of the rate falls on this sample
fn isRateDue(rate i64):
	rate > 0 and (rateCounter + rateOffsets[rate]) % ratePeriods[rate] == 0

fn dspSample():
	rateCounter = rateCounter - 1 if rateCounter > 0 else counterRange - 1
	everyOther = not everyOther
	if everyOther:
		konNow = newKon
		koffNow = dspRegs[koffReg]
	else:
		newKon &= ~konNow
	if isRateDue(dspRegs[flgReg] & 0x1F):
		noise = (((noise << 13) ^ (noise << 14)) & 0x4000) ^ (noise >> 1)
	mainLeft = 0
	mainRight = 0
	echoLeft = 0
	echoRight = 0
	previous = 0
	for v in 0..8:
		out = voices[v].runVoice(v, previous)
		previous = out
		left = (out * signedReg(v << 4)) >> 7
		right = (out * signedReg((v << 4) | 1)) >> 7
		mainLeft = clamp16(mainLeft + left)
		mainRight = clamp16(mainRight + right)
		if dspRegs[0x4D] & (1 << v) != 0:
			echoLeft = clamp16(echoLeft + left)
			echoRight = clamp16(echoRight + right)
	firOutLeft, firOutRight = runEcho(echoLeft, echoRight)
	outLeft = clamp16(((mainLeft * signedReg(0x0C)) >> 7) + ((firOutLeft * signedReg(0x2C)) >> 7))
	outRight = clamp16(
		((mainRight * signedReg(0x1C)) >> 7) + ((firOutRight * signedReg(0x3C)) >> 7)
	)
	if dspRegs[flgReg] & 0x40 != 0:
		outLeft = 0
		outRight = 0
	if makesSound:
		soundSamples.push(f32(outLeft) / 32_768.0)
		soundSamples.push(f32(outRight) / 32_768.0)

# The echo: the oldest entry of the ring buffer through the FIR filter, the voices that echo plus
# the feedback written in its place; the filter's output, left and right.
fn runEcho(inLeft i64, inRight i64):
	at = ((dspRegs[0x6D] << 8) + echoOffset) & 0xFFFF
	firLeft[firAt] = echoWord(at) >> 1
	firRight[firAt] = echoWord(at + 2) >> 1
	left = firSum(firLeft)
	right = firSum(firRight)
	firAt = (firAt + 1) & 7
	if dspRegs[flgReg] & 0x20 == 0:
		writeEchoWord(at, clamp16(inLeft + ((left * signedReg(0x0D)) >> 7)) & ~1)
		writeEchoWord(at + 2, clamp16(inRight + ((right * signedReg(0x0D)) >> 7)) & ~1)
	if echoOffset == 0: echoLength = (dspRegs[0x7D] & 0x0F) << 11
	echoOffset += 4
	if echoOffset >= echoLength: echoOffset = 0
	(left, right)

# the filter over the last eight entries, the oldest by FIR0: the first seven summed in 16 bits
fn firSum(history i64[8]):
	sum = 0
	for k in 0..7:
		sum += (history[(firAt + 1 + k) & 7] * signedReg((k << 4) | 0x0F)) >> 6
	clamp16(wrap16(sum) + ((history[firAt] * signedReg(0x7F)) >> 6)) & ~1

fn echoWord(at i64):
	lo = spcRam[at & 0xFFFF]
	wrap16(lo | (i64(spcRam[(at + 1) & 0xFFFF]) << 8))

fn writeEchoWord(at i64, v i64):
	spcRam[at & 0xFFFF] = v & 0xFF
	spcRam[(at + 1) & 0xFFFF] = (v >> 8) & 0xFF
