# The GPU as the driver's channel interface shows it (switchbrew: NV services; deko3d's and
# nouveau's headers for the classes): channels whose pushbuffers are read through an address
# space, subchannels bound to engine classes with each engine's registers kept as an array, and
# the counters of what ran. Work completes the moment it is submitted, so a semaphore or a
# syncpoint that is waited for is already there; clears are done (clear.zap), draws kept as
# DrawCalls (draw.zap) for the frame and counted.

# the object classes of a Tegra X1 (what nvhost-ctrl-gpu reports)
pub classChannel = 0xB06F
pub classThreeD = 0xB197
pub classCompute = 0xB1C0
pub classCopy = 0xB0B5
pub classTwoD = 0x902D
pub classInline = 0xA140

subchannelCount = 8
registerCount = 0x1000
syncpointCount = 192
maxNotes = 64

# the methods below this number belong to the channel, whichever class a subchannel holds
channelMethods = 0x40

# Macro programs a 3D engine was given (the MME, macro.zap): instruction words and the start of
# each macro, each written through its pointer; the call under way and its parameters.
pub type MacroMemory:
	code i64[] = zeros(macroCodeWords)
	starts i64[] = zeros(macroStarts)
	codeAt i64 = 0
	startAt i64 = 0
	pending i64 = -1
	params i64[] = []

pub type Engine:
	class i64 = 0
	regs i64[] = zeros(registerCount)
	uploaded i64 = 0   # bytes the inline-to-memory engine took since its last exec
	macros MacroMemory = MacroMemory()
	bound i64[] = zeros(constantStages * constantSlots * 3)   # constant buffers: enable, address, size
	inlineIndices i64[] = []   # indices sent as method data since the last draw
	drawIndexed bool = false   # the index count was written since the last draw

pub type Channel:
	space i64 = -1   # the address space it reads through
	syncpoint i64 = -1   # the syncpoint its jobs signal
	userData i64 = 0   # the 64 bits the client keeps on the channel
	engines Engine[] = []   # one a subchannel
	regs i64[] = zeros(channelMethods)
	mode i64 = 0   # the method burst being read: 0 none, 1 incrementing, 3 not, 5 once
	method i64 = 0
	subchannel i64 = 0
	remaining i64 = 0
	burstStart i64 = 0

# What ran: counted for a test or a renderer to read.
pub type Stats:
	methods i64 = 0
	draws i64 = 0
	drawsThisFrame i64 = 0
	clears i64 = 0
	frameDraws i64[] = []   # the draws of each finished frame
	macroCalls i64 = 0
	dispatches i64 = 0
	copies i64 = 0
	inlineUploads i64 = 0
	semaphores i64 = 0
	syncpointIncrements i64 = 0
	blockLinearCopies i64 = 0   # copied as bytes in order, not swizzled

pub type Gpu:
	spaces AddressSpace[] = []
	channels Channel[] = []
	syncpoints i64[] = zeros(syncpointCount)
	nextSyncpoint i64 = 10
	timestamp i64 = 0   # nanoseconds, set by whoever submits
	stats Stats = Stats()
	notes str[] = []   # what the front end met and did not do
	draws DrawCall[] = []   # the frame's draws so far
	recordDir str = ""   # where the programs draws use are written, none when empty
	recorded str[] = []   # the names of the programs written

# something the front end did not do, kept once
pub fn note(mut g Gpu, text str):
	if g.notes.len < maxNotes and not (text in g.notes): g.notes.push(text.copy())

# A new address space: its index.
pub fn newSpace(mut g Gpu) i64:
	g.spaces.push(AddressSpace())
	g.spaces.len - 1

# A new channel with its own syncpoint: its index.
pub fn newChannel(mut g Gpu) i64:
	c = Channel(syncpoint = g.nextSyncpoint)
	g.nextSyncpoint += 1
	loop subchannelCount:
		c.engines.push(Engine())
	g.channels.push(c)
	g.channels.len - 1

# a syncpoint raised by one
pub fn incrementSyncpoint(mut g Gpu, id i64):
	if id < 0 or id >= syncpointCount: return g.note("syncpoint {id} does not exist")
	g.syncpoints[id] += 1
	g.stats.syncpointIncrements += 1

# whether a syncpoint's value reached a threshold (the counters wrap at 32 bits)
pub fn hasReachedSyncpoint(g Gpu, id i64, threshold i64) bool:
	if id < 0 or id >= syncpointCount: return false
	((g.syncpoints[id] - threshold) & 0xFFFF_FFFF) < 0x8000_0000

# The frame ended: the draws since the last one are its, and their DrawCalls go.
pub fn endFrame(mut g Gpu):
	g.draws.clear()
	g.stats.frameDraws.push(g.stats.drawsThisFrame)
	g.stats.drawsThisFrame = 0
