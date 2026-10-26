# The audio renderer's parameters as a game opens it with (nn::audio::AudioRendererParameter,
# 0x34 bytes), the revision it was built against, and the size of the work buffer the system
# computes for them (yuzu's System::GetWorkBufferSize): games allocate exactly that much.

pub type RendererParams:
	sampleRate i64
	sampleCount i64
	mixes i64
	subMixes i64
	voices i64
	sinks i64
	effects i64
	perfFrames i64
	renderingDevice i64
	splitterInfos i64
	splitterDestinations i64
	revision i64   # the number of the revision (REV9 is 9)

# the sizes of the system's own structures, in the work buffer
sizeVoiceInfo = 560
sizeVoiceChannelResource = 200
sizeVoiceState = 296
sizeMixInfo = 2368
sizeMemoryPoolInfo = 32
sizeEffectResultState = 128
sizeUpsamplerInfo = 616
sizeEffectInfoBase = 1592
sizeSinkInfoBase = 352
sizeSplitterDestination = 264
sizeSplitterInfo = 32
sizeBitArray = 48
maxEffectsPerMix = 256
maxMixBuffers = 24
maxChannels = 6
maxWaveBuffers = 4
targetSampleCount = 240
maxDetailEntries = 100

pub currentRevision = 15

# the sizes of the commands the renderer would generate (their maximum, by revision)
sizeDataSourceV1 = 288
sizeDataSourceV2 = 296
sizeBiquadCommand = 80
sizeVolumeRampCommand = 40
sizeMixRampGroupedCommand = 328
sizeDepopPrepareCommand = 96
sizeDepopForMixBuffersCommand = 48
sizeMixCommand = 40
sizeVolumeCommand = 40
sizeMixRampCommand = 48
sizeDeviceSinkCommand = 320
sizePerformanceCommand = 64

# the revision number of a game's revision word ('REV9' or a plain number)
pub fn revisionNumber(raw i64) i64:
	if raw < 0x100: return raw
	((raw - 0x3056_4552) & 0xFFFF_FFFF) >> 24

# the parameters in the 0x34 bytes at `at` of `bytes`
pub fn readRendererParams(bytes u8[], at i64) RendererParams:
	RendererParams(
		sampleRate = bytes.u32le(at),
		sampleCount = bytes.u32le(at + 4),
		mixes = bytes.u32le(at + 8),
		subMixes = bytes.u32le(at + 0xC),
		voices = bytes.u32le(at + 0x10),
		sinks = bytes.u32le(at + 0x14),
		effects = bytes.u32le(at + 0x18),
		perfFrames = bytes.u32le(at + 0x1C),
		renderingDevice = bytes[at + 0x22],
		splitterInfos = bytes.u32le(at + 0x24),
		splitterDestinations = bytes.u32le(at + 0x28),
		revision = revisionNumber(bytes.u32le(at + 0x30))
	)

fn alignUp(v i64, n i64):
	(v + n - 1) / n * n

# the bytes the performance metrics of one frame take
fn performanceFrameSize(p RendererParams):
	entries = p.voices + p.effects + p.subMixes + p.sinks + 1
	if p.revision >= 5: 0x30 + maxDetailEntries * 0x18 + entries * 0x18
	else: 0x18 + maxDetailEntries * 0x10 + entries * 0x10

# the bytes of commands a frame may generate
fn commandBufferSize(p RendererParams):
	voiceCommand = sizeDataSourceV2 if p.revision >= 8 else sizeDataSourceV1
	voiceCommand += 2 * sizeBiquadCommand + sizeVolumeRampCommand + sizeMixRampGroupedCommand
	size = p.effects * sizeEffectInfoBase
	size += p.voices * (p.splitterInfos * sizeDepopPrepareCommand + voiceCommand)
	size += sizeDepopForMixBuffersCommand + sizeMixCommand * maxMixBuffers * maxMixBuffers
	size += sizeDepopForMixBuffersCommand + sizeVolumeCommand * maxMixBuffers
	size += p.splitterDestinations * sizeMixRampCommand * maxMixBuffers
	size += p.sinks * sizeDeviceSinkCommand
	size +
		(p.effects + p.voices + p.sinks + p.subMixes + 1 + maxDetailEntries) *
		sizePerformanceCommand

# The bytes of work buffer the system needs for these parameters.
pub fn workBufferSize(p RendererParams) i64:
	size = alignUp(p.mixes * 4, 0x40)
	size += p.subMixes * maxEffectsPerMix * 4
	size += (p.subMixes + 1) * sizeMixInfo
	size += p.voices * (sizeVoiceInfo + sizeVoiceChannelResource + sizeVoiceState)
	size += alignUp((p.subMixes + 1) * 8, 0x10)
	size += alignUp(p.voices * 8, 0x10)
	size += alignUp(
		((p.sinks + p.subMixes) * targetSampleCount * 4 + p.sampleCount * 4) * (p.mixes + maxChannels),
		0x40
	)
	nodes = p.subMixes + 1
	if p.revision >= 2:
		nodeStates = alignUp(nodes, 0x40) / 8 * 2 + nodes * sizeBitArray + nodes * nodes * 4
		size += alignUp(nodeStates + alignUp(nodes * nodes, 0x40) / 8, 0x10)
		size += p.splitterDestinations * sizeSplitterDestination +
			p.splitterInfos * sizeSplitterInfo
		if p.revision >= 5: size += alignUp(p.splitterDestinations * 4, 0x10)
	size += (p.effects + p.voices * maxWaveBuffers) * sizeMemoryPoolInfo
	if p.revision >= 9: size += p.effects * sizeEffectResultState
	size += 0x50
	size = alignUp(size, 0x40)
	size += (p.sinks + p.subMixes) * sizeUpsamplerInfo
	size += p.effects * sizeEffectInfoBase
	size += alignUp(p.voices * sizeVoiceState, 0x40)
	size += p.sinks * sizeSinkInfoBase
	if p.revision >= 9: size += p.effects * sizeEffectResultState
	if p.perfFrames > 0:
		size += alignUp(p.performanceFrameSize() * (p.perfFrames + 1) + 0xC0, 0x100)
	size += p.commandBufferSize() + 0x7E if p.revision >= 5 else 0x1_8000 + 0x7E
	alignUp(size, 0x1000)
