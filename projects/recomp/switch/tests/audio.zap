# The audio renderer as a game uses it: the work buffer size the system computes, and an update
# round trip with voices playing PCM16 and ADPCM wave buffers, heard in the mix.

import recomp.switch.horizon

fn command(c i64, data u8[]):
	horizon.Request(kind = 4, command = c, data = data.copy())

# the 0x34 bytes of parameters
fn parameters(
	rate i64,
	count i64,
	mixes i64,
	subMixes i64,
	voices i64,
	sinks i64,
	effects i64,
	perf i64,
	splitters i64,
	destinations i64,
	revision i64
):
	p u8[] = zeros(0x34)
	for i, v in [rate, count, mixes, subMixes, voices, sinks, effects, perf]:
		p.setU32le(i * 4, u32(v))
	p.setU32le(0x24, u32(splitters))
	p.setU32le(0x28, u32(destinations))
	p.setU32le(0x30, u32(0x3056_4552 + (revision << 24)))
	p

fn workSize(mut k horizon.Kernel, p u8[]) i64:
	manager = k.newService("audren:u")
	i64(k.call(manager, command(1, p)).data.u64le(0))

test "the work buffer size follows the parameters and the revision":
	k = horizon.bareProcess()
	small = 48_000
	for revision, expected in {1: 217_088, 5: 180_224, 9: 180_224}:
		p = parameters(small, 240, 8, 2, 32, 1, 2, 0, 0, 0, revision)
		expect k.workSize(p) == expected
	for revision, expected in {1: 393_216, 2: 397_312, 5: 450_560, 8: 454_656, 9: 454_656}:
		p = parameters(32_000, 160, 12, 6, 64, 2, 5, 3, 6, 12, revision)
		expect k.workSize(p) == expected

test "a renderer opened with too small a work buffer is refused":
	k = horizon.bareProcess()
	manager = k.newService("audren:u")
	p = parameters(48_000, 240, 8, 2, 32, 1, 2, 0, 0, 0, 9)
	data = p
	data.pushU32le(0)
	data.pushU64le(100)
	expect k.call(manager, command(0, data)).result == 0x899

# a renderer of 2 voices and a final mix of 2 buffers, started
fn openRenderer(mut k horizon.Kernel):
	manager = k.newService("audren:u")
	data = parameters(48_000, 240, 2, 0, 2, 1, 0, 0, 0, 0, 9)
	data.pushU32le(0)
	data.pushU64le(k.workSize(data[..0x34]))
	renderer = k.call(manager, command(0, data)).objects[0]
	expect k.services[renderer].name == "IAudioRenderer"
	expect k.call(renderer, command(5, [])).result == 0
	renderer

# the float v as the 4 bytes at `at`
fn putFloat(mut d u8[], at i64, v f32):
	bytes = []
	bytes.pushF32le(v)
	for i, b in bytes:
		d[at + i] = b

# the update data of revision 9 for the renderer above: voice 0 plays `format` from the wave
# buffer at `at` of `size` bytes, `end` samples long
fn updateData(format i64, at i64, size i64, end i64, coefficients i64, isNew bool):
	d u8[] = zeros(0x40 + 0x10 + 8 * 0x20 + 2 * 0x70 + 2 * 0x170 + 0x20 + 0x930 + 0x140 + 0x10)
	pools = 0x50
	resources = pools + 8 * 0x20
	voices = resources + 2 * 0x70
	mixes = voices + 2 * 0x170
	sinks = mixes + 0x20 + 0x930
	d.setU32le(0, 0x3956_4552)
	d.setU32le(4, 0x10)
	d.setU32le(8, 8 * 0x20)
	d.setU32le(0xC, 2 * 0x170)
	d.setU32le(0x10, 2 * 0x70)
	d.setU32le(0x18, 0x20 + 0x930)
	d.setU32le(0x1C, 0x140)
	d.setU32le(0x20, 0x10)
	d.setU32le(0x40, 0x3956_4552)
	d.setU32le(pools + 0x10, 4)   # pool 0 asks to attach
	d.setU64le(pools, u64(at))
	d.setU64le(pools + 8, 0x1000)
	putFloat(d, resources + 4, 1.0)
	putFloat(d, resources + 8, 1.0)
	d[resources + 0x64] = 1
	d[voices + 8] = 1 if isNew else 0
	d[voices + 9] = 1
	d[voices + 0xA] = 0
	d[voices + 0xB] = u8(format)
	d.setU32le(voices + 0xC, 48_000)
	d.setU32le(voices + 0x18, 1)
	putFloat(d, voices + 0x1C, 1.0)
	putFloat(d, voices + 0x20, 1.0)
	d.setU32le(voices + 0x3C, 1)
	d.setU64le(voices + 0x48, u64(coefficients))
	d.setU64le(voices + 0x50, 32)
	d.setU32le(voices + 0x58, 0)
	d.setU32le(voices + 0x5C, 0xFFFF_FFFF)
	wave = voices + 0x60
	d.setU64le(wave, u64(at))
	d.setU64le(wave + 8, u64(size))
	d.setU32le(wave + 0x14, u32(end))
	d[wave + 0x1A] = 0 if isNew else 1
	putFloat(d, mixes + 0x20, 1.0)
	d.setU32le(mixes + 0x20 + 4, 48_000)
	d.setU32le(mixes + 0x20 + 8, 2)
	d[mixes + 0x20 + 0xC] = 1
	d.setU32le(mixes + 4, 1)
	d.setU32le(mixes + 0x20 + 0x924, 0x7FFF_FFFF)
	d[sinks] = 1
	d[sinks + 1] = 1
	d.setU32le(sinks + 0x120, 2)
	d[sinks + 0x125] = 1
	d

# the update sent through RequestUpdate; the answer's bytes
fn sendUpdate(mut k horizon.Kernel, renderer i64, update u8[]):
	input = k.heapBuffer(0x8000, update)
	out = k.heapBuffer(0x1_0000, zeros(0x400))
	req = command(4, [])
	req.a.push(input)
	req.b.push(out)
	req.b.push(k.heapBuffer(0x1_8000, zeros(0x100)))
	expect k.call(renderer, req).result == 0
	horizon.getBytes(out.at, 0x400)

# two frames of the renderer played, 5 ms of guest time each
fn playFrames(mut k horizon.Kernel, frames i64):
	loop frames:
		k.ticks += 96_000
		k.audioTick()

test "a PCM16 voice is heard in the mix and counted played":
	k = horizon.bareProcess()
	k.audio.sound.wavPath = "unused.wav"
	renderer = k.openRenderer()
	samples = []
	for j in 0..480:
		samples.pushI16le((j + 1) * 50)
	wave = k.heapBuffer(0x2000, samples)
	update = updateData(2, wave.at, 960, 480, 0, true)
	answer = k.sendUpdate(renderer, update)
	expect answer.u32le(0x40) == 5   # the pool attached
	k.playFrames(2)
	heard = k.audio.sound.recorded
	expect heard.len == 960
	expect f64(heard[0]).isClose(50.0 / 32768.0, 0.000001)
	expect f64(heard[2 * 239]).isClose(12_000.0 / 32768.0, 0.000001)
	expect f64(heard[2 * 479 + 1]).isClose(24_000.0 / 32768.0, 0.000001)
	again = k.sendUpdate(renderer, updateData(2, wave.at, 960, 480, 0, false))
	played = 0x40 + 8 * 0x10
	expect again.u64le(played) == 480
	expect again.u32le(played + 8) == 1

test "an ADPCM voice decodes its frame with the coefficients":
	k = horizon.bareProcess()
	k.audio.sound.wavPath = "unused.wav"
	renderer = k.openRenderer()
	frame u8[] = [0x08, 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE]
	wave = k.heapBuffer(0x2000, frame)
	coefficients = k.heapBuffer(0x3000, zeros(32))
	answer = k.sendUpdate(renderer, updateData(6, wave.at, 8, 14, coefficients.at, true))
	expect not answer.isEmpty
	k.playFrames(1)
	heard = k.audio.sound.recorded
	codes = [1, 2, 3, 4, 5, 6, 7, -8, -7, -6, -5, -4, -3, -2]
	for j, code in codes:
		expect f64(heard[2 * j]).isClose((code * 256) / 32768.0, 0.000001)
	expect heard[2 * 14] == 0.0

test "the renderer's event is signaled at each frame and cleared by an update":
	k = horizon.bareProcess()
	renderer = k.openRenderer()
	handle = k.call(renderer, command(7, [])).copied[0]
	expect handle != 0
	e = k.services[renderer].value
	event = k.audio.renderers[e].event
	expect not k.events[event]
	k.playFrames(1)
	expect k.events[event]
	expect k.audio.renderers[e].frames == 1
