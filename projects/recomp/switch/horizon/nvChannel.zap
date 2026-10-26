# /dev/nvhost-gpu, a GPU channel (switchbrew: NV services#nvhost-gpu): the client allocates a
# GPFIFO, makes objects of the classes it will use, and submits GPFIFO entries, which name the
# pushbuffers the GPU reads (maxwell/pushBuffer.zap). `object` is the channel's index in the GPU.
# The work runs when it is submitted, so the fence a submission returns is already reached.

import recomp.switch.maxwell

# SUBMIT_GPFIFO's flags (yuzu's IoctlSubmitGpfifo): wait for the fence given, add two increments
# of the channel's syncpoint after the entries, and count the fence's value as increments the
# entries make themselves
flagFenceWait = 1
flagFenceIncrement = 2
flagIncrementValue = 1 << 8

submitHeaderSize = 24

fn channelIoctl(mut k Kernel, c i64, cmd i64, mut io u8[], extra u8[]) i64:
	if c < 0: return nvInvalidState
	match cmd:
		0x4801, 0x4803, 0x4805, 0x480D, 0x480E, 0x480F, 0x4810, 0x4811, 0x4812, 0x481D, 0x0007:
			nvOk   # SET_NVMAP_FD, SET_TIMEOUT, ALLOC_GPFIFO, SET_PRIORITY, ENABLE... SET_TIMESLICE
		0x4808, 0x4819, 0x481B, 0x481C: k.submitGpfifo(c, cmd, io, extra)   # SUBMIT_GPFIFO, _RETRY, KICKOFF_PB, _RETRY
		0x4809: k.allocateObject(c, io)   # ALLOC_OBJ_CTX
		0x480B, 0x480C: nvOk   # ZCULL_BIND, SET_ERROR_NOTIFIER
		0x4818, 0x481A: k.allocateGpfifo(c, io)   # ALLOC_GPFIFO_EX, _EX2
		0x4714:   # SET_USER_DATA
			k.gpu.channels[c].userData = get64(io, 0)
			nvOk
		0x4715:   # GET_USER_DATA
			put64(io, 0, k.gpu.channels[c].userData)
			nvOk
		0x0002, 0x0003: nvOk   # GET_SYNCPOINT, GET_WAITBASE
		_: nvNotImplemented

# ALLOC_GPFIFO_EX(2): the channel's fence, its syncpoint and its value now
fn allocateGpfifo(mut k Kernel, c i64, mut io u8[]):
	id = k.gpu.channels[c].syncpoint
	put32(io, 12, id)
	put32(io, 16, k.gpu.syncpointMaxima[id])
	nvOk

fn allocateObject(mut k Kernel, c i64, io u8[]):
	class = get32(io, 0)
	known = [
		maxwell.classThreeD,
		maxwell.classCompute,
		maxwell.classCopy,
		maxwell.classTwoD,
		maxwell.classInline
	]
	nvOk if class in known else nvBadParameter

# SUBMIT_GPFIFO (yuzu's SubmitGPFIFOImpl): the entries come in the second buffer, else follow
# the 24-byte argument, or for KICKOFF_PB lie in guest memory at the argument's address. The
# fence returned is always the channel's syncpoint and the value it has once the increments the
# flags promise are done.
fn submitGpfifo(mut k Kernel, c i64, cmd i64, mut io u8[], extra u8[]):
	count = get32(io, 8)
	flags = get32(io, 12)
	if flags & flagFenceWait != 0:
		if flags & flagIncrementValue != 0: return nvBadParameter
		if not k.gpu.hasReachedSyncpoint(get32(io, 16), get32(io, 20)):
			k.gpu.note("a submission waits for a value syncpoint {get32(io, 16)} has not reached")
	entries = io[submitHeaderSize..].copy()
	if not extra.isEmpty: entries = extra.copy()
	elif cmd == 0x481B: entries = getBytes(get64(io, 0), count * 8)
	id = k.gpu.channels[c].syncpoint
	increments = 2 if flags & flagFenceIncrement != 0 else 0
	if flags & flagIncrementValue != 0: increments += get32(io, 20)
	put32(io, 16, id)
	put32(io, 20, k.gpu.reserveSyncpoint(id, increments))
	k.gpu.timestamp = k.now() * 10_000 / 192
	k.gpu.submit(c, entries[..(count * 8).min(len)])
	if flags & flagFenceIncrement != 0:
		loop 2:
			k.gpu.incrementSyncpoint(id)
	k.gpu.settleSyncpoint(id)
	k.signalSyncpointEvents()
	nvOk
