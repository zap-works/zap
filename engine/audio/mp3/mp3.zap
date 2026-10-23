# An MP3 decoder (MPEG-1, MPEG-2 and MPEG-2.5 Layer III, every bit rate, free format, mono,
# stereo, joint stereo with mid/side and intensity), a port of minimp3's float path (public
# domain, github.com/lieff/minimp3): frames found by their headers (an ID3v2 tag skipped), side
# information, the bit reservoir, scale factors, Huffman decoding through lookup trees,
# requantization, stereo, reordering of short blocks, alias reduction, IMDCT with overlap, and the
# polyphase synthesis filter bank. It decodes frame by frame, so music streams from it with only
# the compressed file in memory. A LAME/Xing "Info" frame gives the encoder's delay and padding,
# which are dropped as ffmpeg drops them (gapless: a loop of a song has no gap).

maxReservoir = 511
maxFramePayload = 2304

# the four bytes of a frame header (b0 is 0xFF when there is one)
type Header:
	b0 i64
	b1 i64
	b2 i64
	b3 i64

	fn isMono():
		(b3 & 0xC0) == 0xC0

	fn isMsStereo():
		(b3 & 0xE0) == 0x60

	fn isFreeFormat():
		(b2 & 0xF0) == 0

	fn hasCrc():
		(b1 & 1) == 0

	fn hasPadding():
		(b2 & 2) != 0

	fn isMpeg1():
		(b1 & 8) != 0

	fn isNotMpeg25():
		(b1 & 0x10) != 0

	fn testIStereo():
		(b3 & 0x10) != 0

	fn testMsStereo():
		(b3 & 0x20) != 0

	fn layer():
		b1.bits(1, 2)

	fn bitrateIndex():
		b2 >> 4

	fn sampleRateIndex():
		b2.bits(2, 2)

	fn mySampleRate():
		sampleRateIndex() + (b1.bits(3, 1) + b1.bits(4, 1)) * 3

	fn isFrame576():
		(b1 & 14) == 2

	fn isLayer1():
		(b1 & 6) == 6

	fn valid():
		b0 == 0xFF and ((b1 & 0xF0) == 0xF0 or (b1 & 0xFE) == 0xE2) and layer() != 0 and
			bitrateIndex() != 15 and sampleRateIndex() != 3

	# whether `o` is a valid header of the same stream
	fn matches(o Header):
		o.valid() and ((b1 ^ o.b1) & 0xFE) == 0 and ((b2 ^ o.b2) & 0x0C) == 0 and
			isFreeFormat() == o.isFreeFormat()

	fn bitrateKbps():
		row = (3 if isMpeg1() else 0) + layer() - 1
		2 * i64(mp3HalfRates[row * 15 + bitrateIndex()])

	fn sampleRateHz():
		hz = [44_100, 48_000, 32_000][sampleRateIndex()]
		hz >> (0 if isMpeg1() else 1) >> (0 if isNotMpeg25() else 1)

	fn frameSamples():
		384 if isLayer1() else 1152 >> (1 if isFrame576() else 0)

	fn frameBytes(freeFormatSize i64):
		n = frameSamples() * bitrateKbps() * 125 / sampleRateHz()
		if isLayer1():
			n &= ~3
		n if n != 0 else freeFormatSize

	fn padding():
		(4 if isLayer1() else 1) if hasPadding() else 0

# a granule of a channel: its side information
type Granule:
	sfbBase i64   # where its band widths start in mp3Bands
	part23Length i64
	bigValues i64
	scalefacCompress i64
	globalGain i64
	blockType i64
	mixedBlockFlag i64
	nLongSfb i64
	nShortSfb i64
	tableSelect i64[3]
	regionCount i64[3]
	subblockGain i64[3]
	preflag i64
	scalefacScale i64
	count1Table i64
	scfsi i64

# a position in bits inside a byte buffer, and the end it must not pass
type Bits:
	pos i64
	limit i64

# The decoder of one MP3 file, frame by frame: decodeFrame() leaves a frame's samples in `pcm`.
pub type Decoder:
	data u8[]   # the whole file, compressed
	at i64 = 0   # where the next frame is looked for
	audioStart i64 = 0   # the first audio frame (after the tags and the Info frame)
	header Header = Header(b0 = 0, b1 = 0, b2 = 0, b3 = 0)
	freeFormatBytes i64 = 0
	reservoir u8[] = zeros(maxReservoir)
	reservBytes i64 = 0
	overlap f32[] = zeros(2 * 9 * 32)
	qmfState f32[] = zeros(15 * 2 * 32)
	mainData u8[] = zeros(maxReservoir + maxFramePayload + 16)
	bs Bits = Bits(pos = 0, limit = 0)
	granules Granule[] = []
	grbuf f32[] = zeros(2 * 576)
	scf f32[] = zeros(40)
	syn f32[] = zeros(33 * 64)
	istPos i64[] = zeros(2 * 40)
	iscf i64[] = zeros(40)
	pcm f32[] = zeros(1152 * 2)   # the last frame: interleaved, `channels` per sample
	channels i64 = 0
	sampleRate i64 = 0
	bitrateKbps i64 = 0
	encoderDelay i64 = -1   # samples the encoder put before the music (-1: no Info frame)
	encoderPadding i64 = 0   # and after it
	totalFrames i64 = 0   # audio frames the Info frame counts (0: unknown)

# ---------- the band tables ----------

mp3LongBase = 0
mp3ShortBase = 184
mp3MixedBase = 504

fn bandWidth(at i64) i64:
	mp3Bands[at]

# ---------- the header ----------

fn headerAt(b ref u8[], at i64):
	Header(b0 = b[at], b1 = b[at + 1], b2 = b[at + 2], b3 = b[at + 3])

# half the bit rates in kbps: MPEG-2 layers 1..3, then MPEG-1 layers 1..3, 15 indices each
mp3HalfRates i32[] = [
	0, 4, 8, 12, 16, 20, 24, 28, 32, 40, 48, 56, 64, 72, 80,
	0, 4, 8, 12, 16, 20, 24, 28, 32, 40, 48, 56, 64, 72, 80,
	0, 16, 24, 28, 32, 40, 48, 56, 64, 72, 80, 88, 96, 112, 128,
	0, 16, 20, 24, 28, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160,
	0, 16, 24, 28, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192,
	0, 16, 32, 48, 64, 80, 96, 112, 128, 144, 160, 176, 192, 208, 224
]

# ---------- bits ----------

fn getBits(buf ref u8[], mut bs Bits, n i64):
	s = bs.pos & 7
	shl = n + s
	p = bs.pos >> 3
	bs.pos += n
	if bs.pos > bs.limit: return 0
	next = i64(buf[p]) & (255 >> s)
	p += 1
	cache = 0
	shl -= 8
	while shl > 0:
		cache |= next << shl
		next = buf[p]
		p += 1
		shl -= 8
	cache | next >> -shl

# ---------- opening ----------

# A decoder over an MP3 file's bytes (moved in); none when no frame is found.
pub fn openMp3(move bytes u8[]) Decoder?:
	d = Decoder(data = bytes)
	loop 4:
		d.granules.push(Granule(
			sfbBase = 0,
			part23Length = 0,
			bigValues = 0,
			scalefacCompress = 0,
			globalGain = 0,
			blockType = 0,
			mixedBlockFlag = 0,
			nLongSfb = 0,
			nShortSfb = 0,
			tableSelect = [0, 0, 0],
			regionCount = [0, 0, 0],
			subblockGain = [0, 0, 0],
			preflag = 0,
			scalefacScale = 0,
			count1Table = 0, scfsi = 0))
	d.at = id3v2Size(d.data)
	first, size = d.findFrame(d.at)
	if size == 0: return none
	h = headerAt(d.data, first)
	d.channels = 1 if h.isMono() else 2
	d.sampleRate = h.sampleRateHz()
	d.bitrateKbps = h.bitrateKbps()
	d.at = first
	if d.readInfoFrame(first, size):
		d.at = first + size   # the Info frame holds no music
	d.audioStart = d.at
	d

# the bytes of an ID3v2 tag at the start (0 when there is none)
fn id3v2Size(b ref u8[]):
	if b.len < 10 or not b.startsWith("ID3"): return 0
	size = (i64(b[6]) & 127) << 21 | (i64(b[7]) & 127) << 14 | (
		i64(b[8]) & 127
	) << 7 | i64(b[9]) & 127
	footer = 10 if (b[5] & 0x10) != 0 else 0
	(10 + size + footer).min(b.len)

# A Xing or Info frame at `at` (LAME's and ffmpeg's encoders write one first): its frame count and,
# in the LAME extension, the encoder's delay and padding. Whether the frame is one.
fn readInfoFrame(mut d Decoder, at i64, size i64):
	h = headerAt(d.data, at)
	if h.layer() != 1: return false
	side = (17 if h.isMono() else 32) if h.isMpeg1() else (9 if h.isMono() else 17)
	p = at + 4 + side + (2 if h.hasCrc() else 0)
	b = d.data
	if p + 8 > at + size: return false
	if not b.matchesAt(p, "Xing") and not b.matchesAt(p, "Info"): return false
	flags = b.u32be(p + 4)
	p += 8
	if (flags & 1) != 0:
		d.totalFrames = b.u32be(p)
		p += 4
	if (flags & 2) != 0:
		p += 4
	if (flags & 4) != 0:
		p += 100
	if (flags & 8) != 0:
		p += 4
	# the LAME extension: a 9-byte encoder name, then at 21 the delay and padding, 12 bits each
	if p + 24 <= at + size and b[p] == 'L':
		v = i64(b[p + 21]) << 16 | i64(b[p + 22]) << 8 | b[p + 23]
		d.encoderDelay = v >> 12
		d.encoderPadding = v & 4095
	true

# whether the frames after the one at `at` follow on with the same kind of header
fn matchFrame(d Decoder, at i64, frameBytes i64):
	n = d.data.len
	h = headerAt(d.data, at)
	i = 0
	for nmatch in 0..10:
		hi = headerAt(d.data, at + i)
		i += hi.frameBytes(frameBytes) + hi.padding()
		if at + i + 4 > n: return nmatch > 0
		if not h.matches(headerAt(d.data, at + i)): return false
	true

# The next frame at or after `from`: its offset and size with padding (size 0: none). A free
# format stream's frame size is found from the distance to the next header and kept.
fn findFrame(mut d Decoder, from i64):
	n = d.data.len
	i = from
	while i < n - 4:
		h = headerAt(d.data, i)
		if h.valid():
			frameBytes = h.frameBytes(d.freeFormatBytes)
			frameAndPadding = frameBytes + h.padding()
			k = 4
			while frameBytes == 0 and k < maxFramePayload and i + 2 * k < n - 4:
				if h.matches(headerAt(d.data, i + k)):
					fb = k - h.padding()
					nextFb = fb + headerAt(d.data, i + k).padding()
					if i + k + nextFb + 4 <= n and h.matches(headerAt(d.data, i + k + nextFb)):
						frameAndPadding = k
						frameBytes = fb
						d.freeFormatBytes = fb
				k += 1
			if frameBytes != 0 and i + frameAndPadding <= n and d.matchFrame(i, frameBytes) or
				i == from and frameAndPadding == n - from:
				return (i, frameAndPadding)
			d.freeFormatBytes = 0
		i += 1
	(n, 0)

# ---------- decoding ----------

# Back to the first audio frame, the state of the filters cleared.
pub fn rewindMp3(mut d Decoder):
	d.at = d.audioStart
	d.header = Header(b0 = 0, b1 = 0, b2 = 0, b3 = 0)
	d.reservBytes = 0
	for i in 0..d.overlap.len:
		d.overlap[i] = 0.0
	for i in 0..d.qmfState.len:
		d.qmfState[i] = 0.0

# Decodes the next frame into d.pcm: its samples per channel, 0 at the end of the file. Frames of
# layers 1 and 2 and damaged frames are skipped.
pub fn decodeMp3Frame(mut d Decoder) i64:
	n = d.data.len
	while d.at + 4 < n:
		consumed, samples = d.decodeFrameAt(d.at)
		if consumed == 0:
			d.at = n
			return 0
		d.at += consumed
		if samples > 0: return samples
	0

# the frame at or after `at`: the bytes it took (skipped bytes too) and the samples it gave
fn decodeFrameAt(mut d Decoder, from i64):
	n = d.data.len
	i = from
	frameSize = 0
	if n - from > 4 and d.header.b0 == 0xFF and d.header.matches(headerAt(d.data, from)):
		h = headerAt(d.data, from)
		frameSize = h.frameBytes(d.freeFormatBytes) + h.padding()
		if from + frameSize > n:
			frameSize = 0   # in step with the stream: the next header is not asked for (a tag may follow the last frame)
	if frameSize == 0:
		d.header = Header(b0 = 0, b1 = 0, b2 = 0, b3 = 0)
		d.reservBytes = 0
		found, size = d.findFrame(from)
		frameSize = size
		i = found
		if frameSize == 0 or i + frameSize > n: return (0, 0)
	h = headerAt(d.data, i)
	d.header = h
	consumed = i - from + frameSize
	if h.layer() != 1: return (consumed, 0)
	nch = 1 if h.isMono() else 2
	if nch != d.channels:
		return (consumed, 0)   # a stream that changes its channels is not followed
	bs = Bits(pos = (i + 4) * 8, limit = (i + frameSize) * 8)
	if h.hasCrc():
		bs.pos += 16
	mainDataBegin = d.readSideInfo(bs, h)
	if mainDataBegin < 0 or bs.pos > bs.limit:
		d.header = Header(b0 = 0, b1 = 0, b2 = 0, b3 = 0)
		return (consumed, 0)
	success = d.restoreReservoir(bs, mainDataBegin)
	samples = 0
	if success:
		grCount = 2 if h.isMpeg1() else 1
		for igr in 0..grCount:
			for k in 0..1152:
				d.grbuf[k] = 0.0
			d.decodeGranule(igr * nch, nch)
			d.synthGranule(nch, igr * 576 * nch)
		samples = h.frameSamples()
	d.saveReservoir()
	(consumed, samples)

# the side information of the frame's granules into d.granules; main_data_begin, -1 when damaged
fn readSideInfo(mut d Decoder, mut bs Bits, h Header):
	b = d.data
	srIdx = h.mySampleRate()
	srIdx -= 1 if srIdx != 0 else 0
	grCount = 1 if h.isMono() else 2
	scfsi = 0
	mainDataBegin = 0
	if h.isMpeg1():
		grCount *= 2
		mainDataBegin = getBits(b, bs, 9)
		scfsi = getBits(b, bs, 7 + grCount)
	else:
		mainDataBegin = getBits(b, bs, 8 + grCount) >> grCount
	part23Sum = 0
	for g in 0..grCount:
		if h.isMono():
			scfsi <<= 4
		gr = mut ref d.granules[g]
		gr.part23Length = getBits(b, bs, 12)
		part23Sum += gr.part23Length
		gr.bigValues = getBits(b, bs, 9)
		if gr.bigValues > 288: return -1
		gr.globalGain = getBits(b, bs, 8)
		gr.scalefacCompress = getBits(b, bs, 4 if h.isMpeg1() else 9)
		gr.sfbBase = mp3LongBase + srIdx * 23
		gr.nLongSfb = 22
		gr.nShortSfb = 0
		tables = 0
		if getBits(b, bs, 1) != 0:
			gr.blockType = getBits(b, bs, 2)
			if gr.blockType == 0: return -1
			gr.mixedBlockFlag = getBits(b, bs, 1)
			gr.regionCount[0] = 7
			gr.regionCount[1] = 255
			if gr.blockType == 2:
				scfsi &= 0x0F0F
				if gr.mixedBlockFlag == 0:
					gr.regionCount[0] = 8
					gr.sfbBase = mp3ShortBase + srIdx * 40
					gr.nLongSfb = 0
					gr.nShortSfb = 39
				else:
					gr.sfbBase = mp3MixedBase + srIdx * 40
					gr.nLongSfb = 8 if h.isMpeg1() else 6
					gr.nShortSfb = 30
			tables = getBits(b, bs, 10) << 5
			gr.subblockGain[0] = getBits(b, bs, 3)
			gr.subblockGain[1] = getBits(b, bs, 3)
			gr.subblockGain[2] = getBits(b, bs, 3)
		else:
			gr.blockType = 0
			gr.mixedBlockFlag = 0
			tables = getBits(b, bs, 15)
			gr.regionCount[0] = getBits(b, bs, 4)
			gr.regionCount[1] = getBits(b, bs, 3)
			gr.regionCount[2] = 255
		gr.tableSelect[0] = tables >> 10
		gr.tableSelect[1] = tables.bits(5, 5)
		gr.tableSelect[2] = tables & 31
		gr.preflag = getBits(b, bs, 1) if h.isMpeg1() else (1 if gr.scalefacCompress >= 500 else 0)
		gr.scalefacScale = getBits(b, bs, 1)
		gr.count1Table = getBits(b, bs, 1)
		gr.scfsi = scfsi.bits(12, 4)
		scfsi <<= 4
	if part23Sum + bs.pos > bs.limit + mainDataBegin * 8: return -1
	mainDataBegin

# the main data: what the reservoir kept of earlier frames, then this frame's; whether the
# reservoir held all the frame asks for
fn restoreReservoir(mut d Decoder, bs Bits, mainDataBegin i64):
	frameBytes = (bs.limit - bs.pos) / 8
	bytesHave = d.reservBytes.min(mainDataBegin)
	start = (d.reservBytes - mainDataBegin).max(0)
	for k in 0..bytesHave:
		d.mainData[k] = d.reservoir[start + k]
	src = bs.pos / 8
	for k in 0..frameBytes:
		d.mainData[bytesHave + k] = d.data[src + k]
	for k in bytesHave + frameBytes..(bytesHave + frameBytes + 8).min(d.mainData.len):
		d.mainData[k] = 0
	d.bs = Bits(pos = 0, limit = (bytesHave + frameBytes) * 8)
	d.reservBytes >= mainDataBegin

# what the next frames may take from this one's main data
fn saveReservoir(mut d Decoder):
	pos = (d.bs.pos + 7) / 8
	remains = d.bs.limit / 8 - pos
	if remains > maxReservoir:
		pos += remains - maxReservoir
		remains = maxReservoir
	if remains > 0:
		for k in 0..remains:
			d.reservoir[k] = d.mainData[pos + k]
	d.reservBytes = remains.max(0)

# ---------- a granule ----------

fn decodeGranule(mut d Decoder, firstGranule i64, nch i64):
	h = d.header
	for ch in 0..nch:
		gr = d.granules[firstGranule + ch]
		limit = d.bs.pos + gr.part23Length
		d.decodeScalefactors(gr, ch)
		d.huffman(ch * 576, gr, limit)
	if h.testIStereo():
		d.intensityStereo(firstGranule)
	elif h.isMsStereo():
		d.midSideStereo(0, 576)
	for ch in 0..nch:
		gr = d.granules[firstGranule + ch]
		aaBands = 31
		nLongBands = (2 if gr.mixedBlockFlag != 0 else 0) << (1 if h.mySampleRate() == 2 else 0)
		if gr.nShortSfb != 0:
			aaBands = nLongBands - 1
			d.reorder(ch * 576 + nLongBands * 18, gr.sfbBase + gr.nLongSfb)
		d.antialias(ch * 576, aaBands)
		d.imdctGranule(ch, gr.blockType, nLongBands)
		d.changeSign(ch * 576)

fn ldexpQ2(y f32, expQ2 i64):
	v = y
	rest = expQ2
	loop:
		e = rest.min(30 * 4)
		v *= mp3ExpFrac[e & 3] * f32(1 << 30 >> (e >> 2))
		rest -= e
		if rest <= 0: break
	v

# the scale factors of a channel's granule, read and turned into gains per band (d.scf); the
# intensity positions into d.istPos
fn decodeScalefactors(mut d Decoder, gr Granule, ch i64):
	h = d.header
	partition = (1 if gr.nShortSfb != 0 else 0) + (1 if gr.nLongSfb == 0 else 0)
	partitionAt = partition * 28
	scfSize i64[4]
	scfsi = gr.scfsi
	if h.isMpeg1():
		part = i64(mp3ScfcDecode[gr.scalefacCompress])
		scfSize[0] = part >> 2
		scfSize[1] = part >> 2
		scfSize[2] = part & 3
		scfSize[3] = part & 3
	else:
		ist = 1 if h.testIStereo() and ch != 0 else 0
		sfc = gr.scalefacCompress >> ist
		k = ist * 3 * 4
		while sfc >= 0:
			modprod = 1
			i = 3
			while i >= 0:
				m = i64(mp3Mod[k + i])
				scfSize[i] = sfc / modprod % m
				modprod *= m
				i -= 1
			sfc -= modprod
			k += 4
		partitionAt += k
		scfsi = -16
	# the scale factors (iscf) and intensity positions, partition by partition
	istBase = ch * 40
	at = 0
	for i in 0..4:
		cnt = i64(mp3ScfPartitions[partitionAt + i])
		if cnt == 0: break
		if (scfsi & 8) != 0:
			for k in 0..cnt:
				d.iscf[at + k] = d.istPos[istBase + at + k]
		else:
			bits = scfSize[i]
			if bits == 0:
				for k in 0..cnt:
					d.iscf[at + k] = 0
					d.istPos[istBase + at + k] = 0
			else:
				for k in 0..cnt:
					s = getBits(d.mainData, d.bs, bits)
					d.istPos[istBase + at + k] = s
					d.iscf[at + k] = s
		at += cnt
		scfsi *= 2
	d.iscf[at] = 0
	d.iscf[at + 1] = 0
	d.iscf[at + 2] = 0
	scfShift = gr.scalefacScale + 1
	if gr.nShortSfb != 0:
		sh = 3 - scfShift
		i = 0
		while i < gr.nShortSfb:
			for w in 0..3:
				d.iscf[gr.nLongSfb + i + w] = (
					d.iscf[gr.nLongSfb + i + w] + (gr.subblockGain[w] << sh)
				) & 255
			i += 3
	elif gr.preflag != 0:
		for i in 0..10:
			d.iscf[11 + i] = (d.iscf[11 + i] + mp3Preamp[i]) & 255
	maxScfi = 44
	gainExp = gr.globalGain - 4 - 210 - (2 if h.isMsStereo() else 0)
	gain = ldexpQ2(f32(1 << (maxScfi / 4)), maxScfi - gainExp)
	for i in 0..gr.nLongSfb + gr.nShortSfb:
		d.scf[i] = ldexpQ2(gain, d.iscf[i] << scfShift)

fn pow43(x i64):
	if x < 129: return mp3Pow43[16 + x]
	if x >= 8128:
		return f32(f64(x).pow(4.0 / 3.0))   # past the table's reach
	v = x
	mult = 256.0
	if v < 1024:
		mult = 16.0
		v <<= 3
	sign = 2 * v & 64
	frac = f32((v & 63) - sign) / f32((v & ~63) + sign)
	mp3Pow43[16 + ((v + sign) >> 6)] * (1.0 + frac * (4.0 / 3.0 + frac * (2.0 / 9.0))) *
		f32(mult)

# The Huffman-coded values of a channel's granule, requantized with its band gains, into
# d.grbuf at `dst`; the reading stops at `limit` (bits).
fn huffman(mut d Decoder, dstStart i64, gr Granule, limit i64):
	mask = 0xFFFF_FFFF
	bufLen = d.mainData.len
	one = f32(0.0)
	bigValCnt = gr.bigValues
	sfb = gr.sfbBase
	scfAt = 0
	dst = dstStart
	pos = d.bs.pos
	next = pos / 8
	cache = (
		i64(d.mainData[next]) << 24 | i64(d.mainData[next + 1]) << 16 | i64(d.mainData[next + 2]) << 8 | d.mainData[
			next + 3
		]
	) << (pos & 7) & mask
	sh = (pos & 7) - 8
	next += 4
	one, bigValCnt, sfb, scfAt, dst, cache, sh, next = huffmanBigValues(
		d, gr, mask, bufLen, one, bigValCnt, sfb, scfAt, dst, cache, sh, next
	)
	d.huffmanCount1(gr, limit, mask, bufLen, one, bigValCnt, sfb, scfAt, dst, cache, sh, next)
	d.bs.pos = limit

# the big-values region of `huffman`: pairs of values by Huffman table, returns the scan state
fn huffmanBigValues(
	mut d Decoder,
	gr Granule,
	mask i64,
	bufLen i64,
	oneIn f32,
	bigValCntIn i64,
	sfbIn i64,
	scfAtIn i64,
	dstIn i64,
	cacheIn i64,
	shIn i64,
	nextIn i64
):
	one = oneIn
	ireg = 0
	bigValCnt = bigValCntIn
	sfb = sfbIn
	scfAt = scfAtIn
	dst = dstIn
	cache = cacheIn
	sh = shIn
	next = nextIn
	while bigValCnt > 0:
		tabNum = gr.tableSelect[ireg]
		sfbCnt = gr.regionCount[ireg]
		ireg += 1
		codebook = i64(mp3TabIndex[tabNum])
		linbits = i64(mp3Linbits[tabNum])
		loop:
			np = bandWidth(sfb) / 2
			sfb += 1
			pairs = bigValCnt.min(np)
			one = d.scf[scfAt]
			scfAt += 1
			while pairs > 0:
				w = 5
				leaf = i64(mp3Tabs[codebook + (cache >> (32 - w))])
				while leaf < 0:
					cache = cache << w & mask
					sh += w
					w = leaf & 7
					leaf = mp3Tabs[codebook + (cache >> (32 - w)) - (leaf >> 3)]
				cache = cache << (leaf >> 8) & mask
				sh += leaf >> 8
				loop 2:
					lsb = leaf & 15
					if linbits > 0 and lsb == 15:
						lsb += cache >> (32 - linbits)
						cache = cache << linbits & mask
						sh += linbits
						while sh >= 0:
							cache |= (d.mainData[next] if next < bufLen else 0) << sh
							next += 1
							sh -= 8
						v = one * pow43(lsb)
						d.grbuf[dst] = -v if (cache >> 31) != 0 else v
					else:
						d.grbuf[dst] = mp3Pow43[16 + lsb - 16 * (cache >> 31)] * one
					dst += 1
					if lsb != 0:
						cache = cache << 1 & mask
						sh += 1
					leaf >>= 4
				while sh >= 0:
					cache |= (d.mainData[next] if next < bufLen else 0) << sh
					next += 1
					sh -= 8
				pairs -= 1
			bigValCnt -= np
			if bigValCnt <= 0: break
			sfbCnt -= 1
			if sfbCnt < 0: break
	(one, bigValCnt, sfb, scfAt, dst, cache, sh, next)

# the count1 region of `huffman`: quadruples of -1, 0, 1
fn huffmanCount1(
	mut d Decoder,
	gr Granule,
	limit i64,
	mask i64,
	bufLen i64,
	oneIn f32,
	bigValCnt i64,
	sfbIn i64,
	scfAtIn i64,
	dstIn i64,
	cacheIn i64,
	shIn i64,
	nextIn i64
):
	one = oneIn
	sfb = sfbIn
	scfAt = scfAtIn
	dst = dstIn
	cache = cacheIn
	sh = shIn
	next = nextIn
	np = 1 - bigValCnt
	count1 = mp3Tab33 if gr.count1Table != 0 else mp3Tab32
	loop:
		leaf = i64(count1[cache >> 28])
		if (leaf & 8) == 0:
			leaf = count1[(leaf >> 3) + ((cache << 4 & mask) >> (32 - (leaf & 3)))]
		cache = cache << (leaf & 7) & mask
		sh += leaf & 7
		if next * 8 - 24 + sh > limit: break
		np -= 1
		if np == 0:
			np = bandWidth(sfb) / 2
			sfb += 1
			if np == 0: break
			one = d.scf[scfAt]
			scfAt += 1
		for s in 0..2:
			if (leaf & (128 >> s)) != 0:
				d.grbuf[dst + s] = -one if (cache >> 31) != 0 else one
				cache = cache << 1 & mask
				sh += 1
		np -= 1
		if np == 0:
			np = bandWidth(sfb) / 2
			sfb += 1
			if np == 0: break
			one = d.scf[scfAt]
			scfAt += 1
		for s in 2..4:
			if (leaf & (128 >> s)) != 0:
				d.grbuf[dst + s] = -one if (cache >> 31) != 0 else one
				cache = cache << 1 & mask
				sh += 1
		while sh >= 0:
			cache |= (d.mainData[next] if next < bufLen else 0) << sh
			next += 1
			sh -= 8
		dst += 4
