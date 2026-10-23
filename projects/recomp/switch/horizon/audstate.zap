# What an audio renderer keeps between its updates and its frames: the memory pools, voices and
# the state of what they play, the mixes and the sinks, as the game's update data sets them
# (audupdate.zap) and each frame plays them (audrender.zap).

import engine.audio

# the server's play states of a voice
pub playStarted = 0
pub playStopped = 1
pub playRequestStop = 2
pub playPaused = 3

# the sample formats of a voice
pub formatPcm8 = 1
pub formatPcm16 = 2
pub formatFloat = 5
pub formatAdpcm = 6

pub unusedMixId = 0x7FFF_FFFF

# a block of memory the game gave the renderer: attached to it, or not
pub type Pool:
	address i64 = 0
	size i64 = 0

# a buffer of samples a voice plays, as the game queued it
pub type WaveBuffer:
	address i64 = 0
	size i64 = 0
	startOffset i64 = 0
	endOffset i64 = 0
	looping bool = false
	streamEnded bool = false
	sentToDsp bool = true
	loopCount i64 = 0
	loopStart i64 = 0
	loopEnd i64 = 0
	contextAddress i64 = 0

# a voice: what the game set for it
pub type Voice:
	inUse bool = false
	isNew bool = false
	wasPlaying bool = false
	format i64 = 0
	sampleRate i64 = 0
	channels i64 = 0
	mixId i64 = unusedMixId
	splitterId i64 = -1
	playState i64 = playStopped
	lastPlayState i64 = playStarted
	pitch f32 = 1.0
	volume f32 = 0.0
	waveBufferCount i64 = 0
	flushCount i64 = 0
	dataAddress i64 = 0   # an ADPCM voice's coefficients
	dropped bool = false
	buffers WaveBuffer[] = [WaveBuffer(), WaveBuffer(), WaveBuffer(), WaveBuffer()]
	resources i64[] = [0, 0, 0, 0, 0, 0]   # the channel resource of each channel
	resetCounts bool = false   # the played count starts again at a loop's end (revision 5)
	skipsResampling bool = false

# what one channel of a voice has played
pub type VoiceState:
	played i64 = 0
	offset i64 = 0
	bufferIndex i64 = 0
	valid bool[] = [false, false, false, false]
	consumed i64 = 0
	fraction f64 = 0.0
	loopCount i64 = 0
	last f32 = 0.0   # the newest sample taken from the stream
	yn0 i64 = 0
	yn1 i64 = 0

# a voice channel's volumes into the buffers of its mix
pub type ChannelResource:
	inUse bool = false
	volumes f32[] = fill(24, 0.0)

pub type Mix:
	inUse bool = false
	volume f32 = 0.0
	bufferCount i64 = 0
	destMix i64 = unusedMixId
	volumes f32[] = fill(576, 0.0)   # [source buffer][destination buffer]
	offset i64 = 0   # its first buffer among the mix buffers

pub type Sink:
	kind i64 = 0   # 1 a device, 2 a circular buffer
	inUse bool = false
	inputCount i64 = 0
	inputs i64[] = [0, 0, 0, 0, 0, 0]
	downmix bool = false
	coefficients f32[] = [0.0, 0.0, 0.0, 0.0]

pub type Effect:
	kind i64 = 0
	enabled bool = false
	isNew bool = false

# a splitter's destination: a mix and the volumes into it
pub type SplitterDestination:
	mixId i64 = unusedMixId
	inUse bool = false
	volumes f32[] = fill(24, 0.0)

# a splitter: its destinations, in order
pub type SplitterInfo:
	destinations i64[] = []

pub type Renderer:
	params RendererParams
	pools Pool[] = []
	voices Voice[] = []
	states VoiceState[] = []
	resources ChannelResource[] = []
	mixes Mix[] = []
	sinks Sink[] = []
	effects Effect[] = []
	splitters SplitterInfo[] = []
	destinations SplitterDestination[] = []
	started bool = false
	event i64 = -1   # Kernel.events' index of the event signaled at each frame
	nextFrame i64 = 0   # the counter tick of the next frame
	frames i64 = 0
	renderingTimeLimit i64 = 80
	voiceDrop f32 = 1.0
	closed bool = false

# The renderers a process opened and the sound they make heard.
pub type Audio:
	renderers Renderer[] = []
	sound audio.FrameSound = audio.FrameSound(rate = 48_000)
