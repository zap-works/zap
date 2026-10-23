# An Android app's sound (engine/audio/device.zap's, in an app): an AAudio stream of stereo
# floats at the system's rate, low latency, written a burst at a time, each write waiting for its
# room (the device's client holds the stream, its period the burst); the Windows calls of the
# audio thread (COM, the multimedia class) are nothing here.

extern "libaaudio.so" fn AAudio_createStreamBuilder(builder u8[]) i32
extern "libaaudio.so" fn AAudioStreamBuilder_setFormat(builder i64, format i64)
extern "libaaudio.so" fn AAudioStreamBuilder_setChannelCount(builder i64, channels i64)
extern "libaaudio.so" fn AAudioStreamBuilder_setPerformanceMode(builder i64, mode i64)
extern "libaaudio.so" fn AAudioStreamBuilder_openStream(builder i64, stream u8[]) i32
extern "libaaudio.so" fn AAudioStreamBuilder_delete(builder i64) i32
extern "libaaudio.so" fn AAudioStream_requestStart(stream i64) i32
extern "libaaudio.so" fn AAudioStream_getSampleRate(stream i64) i32
extern "libaaudio.so" fn AAudioStream_getFramesPerBurst(stream i64) i32
extern "libaaudio.so" fn AAudioStream_getBufferSizeInFrames(stream i64) i32
extern "libaaudio.so" fn AAudioStream_write(
	stream i64,
	buffer u8[],
	frames i64,
	timeoutNanos i64
) i32
extern "libaaudio.so" fn AAudioStream_close(stream i64) i32

formatFloat = 2   # AAUDIO_FORMAT_PCM_FLOAT
lowLatency = 12   # AAUDIO_PERFORMANCE_MODE_LOW_LATENCY
writeTimeoutNanos = 1_000_000_000

# Opens the stream; on failure the device holds why.
pub fn openOutput() OutputDevice:
	d = OutputDevice()
	slot = fill(8, u8(0))
	if AAudio_createStreamBuilder(slot) < 0:
		d.failure = "AAudio_createStreamBuilder failed"
		return d
	builder = slot.i64le(0)
	AAudioStreamBuilder_setFormat(builder, formatFloat)
	AAudioStreamBuilder_setChannelCount(builder, 2)
	AAudioStreamBuilder_setPerformanceMode(builder, lowLatency)
	opened = AAudioStreamBuilder_openStream(builder, slot)
	_ = AAudioStreamBuilder_delete(builder)
	if opened < 0:
		d.failure = "AAudioStreamBuilder_openStream failed ({opened})"
		return d
	d.client = slot.i64le(0)
	d.rate = i64(AAudioStream_getSampleRate(d.client))
	d.period = i64(AAudioStream_getFramesPerBurst(d.client)).max(64)
	d.bufferFrames = i64(AAudioStream_getBufferSizeInFrames(d.client))
	if AAudioStream_requestStart(d.client) < 0:
		d.closeOutput()
		d.failure = "AAudioStream_requestStart failed"
	d

pub fn isOpen(d OutputDevice) bool:
	d.client != 0

pub fn closeOutput(mut d OutputDevice):
	if d.client != 0: _ = AAudioStream_close(d.client)
	d.client = 0

# the system's output follows the device itself
pub fn hasDefaultChanged(d OutputDevice) bool:
	d.client == 0 and d.period < 0

# a burst: the write that follows waits for its room
pub fn framesFree(mut d OutputDevice) i64:
	d.period

# the write waits instead
pub fn waitForDevice(d OutputDevice, ms i64):
	pass

# Writes n frames of stereo floats (out[0 .. 2n]); false when the stream is gone.
pub fn writeFrames(mut d OutputDevice, out f32[], n i64) bool:
	if n <= 0: return true
	deviceBytes(out, n, 2, true, 32, d.bytes)
	AAudioStream_write(d.client, d.bytes, n, writeTimeoutNanos) >= 0
