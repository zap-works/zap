# /dev/nvhost-gpu, a GPU channel (switchbrew: NV services#nvhost-gpu): the client allocates a
# GPFIFO, makes objects of the classes it will use, and submits GPFIFO entries, which name the
# pushbuffers the GPU reads (maxwell/pushbuffer.zap). `object` is the channel's index in the GPU.
# The work runs when it is submitted, so a fence the submission asks for is already reached.

import recomp.switch.maxwell

# SUBMIT_GPFIFO's flags
flagFenceWait = 1
flagFenceGet = 2

submitHeaderSize = 24

fn channelIoctl(mut k Kernel, c i64, cmd i64, mut io u8[], extra u8[]) i64:
	if c < 0: return nvInvalidState
	match cmd:
		0x4801, 0x4803, 0x4805, 0x480D, 0x480E, 0x480F, 0x4810, 0x4811, 0x4812, 0x481D, 0x0007:
			nvOk   # SET_NVMAP_FD, SET_TIMEOUT, ALLOC_GPFIFO, SET_PRIORITY, ENABLE... SET_TIMESLICE
		0x4808, 0x4819, 0x481B, 0x481C: k.submitGpfifo(c, io, extra)   # SUBMIT_GPFIFO, _RETRY, SUBMIT_GPFIFO2, _RETRY
		0x4809: k.allocateObject(c, io)   # ALLOC_OBJ_CTX
		0x480B, 0x480C: nvOk   # ZCULL_BIND, SET_ERROR_NOTIFIER
		0x4818, 0x481A: k.allocateGpfifo(c, io)   # ALLOC_GPFIFO_EX, _EX2
		0x0002, 0x0003: nvOk   # GET_SYNCPOINT, GET_WAITBASE
		_: nvNotImplemented

# ALLOC_GPFIFO_EX(2): the channel's fence, its syncpoint and its value now
fn allocateGpfifo(mut k Kernel, c i64, mut io u8[]):
	id = k.gpu.channels[c].syncpoint
	put32(io, 12, id)
	put32(io, 16, k.gpu.syncpoints[id])
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

# SUBMIT_GPFIFO: the entries follow the 24-byte argument, or come in the second buffer; with the
# fence-get flag the channel's syncpoint is raised once more after them and the fence says to
# what value
fn submitGpfifo(mut k Kernel, c i64, mut io u8[], extra u8[]):
	count = get32(io, 8)
	flags = get32(io, 12)
	entries = extra.copy() if not extra.isEmpty else io[submitHeaderSize..].copy()
	k.gpu.timestamp = k.now() * 10_000 / 192
	k.gpu.submit(c, entries[..(count * 8).min(len)])
	if flags & flagFenceGet != 0:
		id = k.gpu.channels[c].syncpoint
		k.gpu.incrementSyncpoint(id)
		put32(io, 16, id)
		put32(io, 20, k.gpu.syncpoints[id])
	k.signalSyncpointEvents()
	nvOk
