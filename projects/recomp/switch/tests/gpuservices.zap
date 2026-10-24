# The display and GPU services answering requests made here (no guest code): the layer's native
# window, the binder relay's buffer queue, nvdrv's devices and a GPFIFO submitted through the
# channel and address space it was set up with.

import recomp.switch.horizon
import recomp.switch.maxwell

fn command(c i64, data u8[]):
	horizon.Request(kind = 4, command = c, data = data.copy())

fn plain(c i64):
	command(c, [])

# a buffer of `size` bytes to receive an answer
fn spaceAt(k horizon.Kernel, offset i64, size i64):
	k.heapBuffer(offset, zeros(size))

# the parcel of a producer call: the interface token, then these words
fn parcel(words i64[]):
	data = []
	data.pushU32le(0x100)
	data.pushU32le(34)
	for c in "android.gui.IGraphicBufferProducer".bytes():
		data.push(c)
		data.push(0)
	data.extend([0, 0, 0, 0])
	for w in words:
		data.pushU32le(w)
	out = []
	out.pushU32le(data.len)
	out.pushU32le(16)
	out.pushU32le(0)
	out.pushU32le(16 + data.len)
	out.extend(data)
	out

# one transaction of the binder: the reply parcel's data (past its 16-byte header)
fn transact(mut k horizon.Kernel, binder i64, code i64, words i64[]):
	args = []
	args.pushU32le(1)
	args.pushU32le(code)
	args.pushU32le(0)
	req = command(0, args)
	req.a.push(k.heapBuffer(0x1000, parcel(words)))
	reply = k.spaceAt(0x2000, 0x400)
	req.b.push(reply)
	k.call(binder, req)
	whole = horizon.getBytes(reply.at, reply.size)
	whole[16..].copy()

# a flattened GraphicBuffer for a 1280 x 720 surface in nvmap handle 7 at offset 0x100
fn graphicBuffer():
	g u8[] = zeros(0x16C)
	g.setU32le(0, 0x4742_4652)
	g.setU32le(4, 1280)
	g.setU32le(8, 720)
	g.setU32le(0x0C, 1280)
	g.setU32le(0x10, 1)
	g.setU32le(0x2C, 7)   # the NvGraphicBuffer's nvmap id
	g.setU32le(0x5C + 0x1C, 0x100)   # its first plane's offset, layout (block linear) and block height
	g.setU32le(0x5C + 0x10, 3)
	g.setU32le(0x5C + 0x24, 4)
	g

# the words a then b
fn joined(a i64[], b i64[]):
	out i64[] = a.copy()
	out.extend(b)
	out

fn flattenedWords(bytes u8[]):
	words = [bytes.len, 0]
	for k in 0..bytes.len / 4:
		words.push(bytes.u32le(k * 4))
	words

test "a layer's native window carries the binder id of its buffers":
	k = horizon.bareProcess()
	root = k.newService("vi:u")
	display = k.call(root, plain(0)).objects[0]
	window = k.spaceAt(0, 0x100)
	req = command(2030, [0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0])
	req.b.push(window)
	made = k.call(display, req)
	layer = made.data.u64le(0)
	expect made.data.u64le(8) == 0x3C
	bytes = horizon.getBytes(window.at, 0x38)
	expect bytes.u32le(0x10) == 2 and bytes.u32le(0x18) == layer
	expect bytes[0x28..0x2F].text() == "dispdrv"

test "the display is handheld":
	k = horizon.bareProcess()
	root = k.call(k.newService("vi:s"), plain(1))
	expect root.objects.len == 1
	service = root.objects[0]
	expect k.call(service, plain(1011)).data.u64le(0) == 1
	size = k.call(service, plain(1102))
	expect size.data.u64le(0) == 1280 and size.data.u64le(8) == 720

test "a buffer is dequeued, queued and shown, and the one before it is free again":
	k = horizon.bareProcess()
	binder = k.call(k.call(k.newService("vi:u"), plain(0)).objects[0], plain(100)).objects[0]
	connected = k.transact(binder, 10, [0, 2, 0])
	expect connected.u32le(0) == 1280 and connected.u32le(16) == 0
	for slot in 0..2:
		set = k.transact(binder, 14, joined([slot, 1], flattenedWords(graphicBuffer())))
		expect set.u32le(0) == 0
	first = k.transact(binder, 3, [0, 1280, 720, 1, 0])
	expect first.u32le(0) == 0 and first.u32le(first.len - 4) == 0
	second = k.transact(binder, 3, [0, 1280, 720, 1, 0])
	expect second.u32le(0) == 1
	expect k.transact(binder, 3, [0, 1280, 720, 1, 0]).u32le(0) == 0xFFFF_FFF5
	input = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	queued = k.transact(binder, 7, joined([0, 0x54, 0], input))
	expect queued.u32le(16) == 0
	expect k.display.presented == 1
	shown = k.display.queue[0]
	expect shown.handle == 7 and shown.offset == 0x100 and shown.width == 1280
	expect shown.layout == 3 and shown.blockHeightLog2 == 4
	expect k.transact(binder, 7, joined([1, 0x54, 0], input)).u32le(16) == 0
	expect k.display.presented == 2
	expect k.display.slots[0].state == 0
	expect k.gpu.stats.frameDraws == [0, 0]

# nvdrv's Ioctl: the status and the argument as it came back
fn ioctl(mut k horizon.Kernel, nv i64, fd i64, cmd i64, io u8[]):
	args = []
	args.pushU32le(fd)
	args.pushU32le(cmd)
	req = command(1, args)
	req.a.push(k.heapBuffer(0x1000, io))
	out = k.spaceAt(0x2000, io.len.max(4))
	req.b.push(out)
	res = k.call(nv, req)
	(res.data.u32le(0), horizon.getBytes(out.at, out.size))

# Open: the file descriptor
fn open(mut k horizon.Kernel, nv i64, path str):
	req = command(0, [])
	req.a.push(k.heapBuffer(0x3000, path.bytes()))
	res = k.call(nv, req)
	expect res.data.u32le(4) == 0
	i64(res.data.u32le(0))

test "nvmap makes handles that report their size":
	k = horizon.bareProcess()
	nv = k.newService("nvdrv")
	fd = k.open(nv, "/dev/nvmap")
	size u8[] = zeros(8)
	size.setU32le(0, 0x4000)
	error, made = k.ioctl(nv, fd, 0xC008_0101, size)
	expect error == 0 and made.u32le(4) == 1
	param u8[] = zeros(12)
	param.setU32le(0, 1)
	param.setU32le(4, 1)
	_, answered = k.ioctl(nv, fd, 0xC00C_0109, param)
	expect answered.u32le(8) == 0x4000
	expect k.open(nv, "/dev/nvhost-gpu") == 2
	req = command(0, [])
	req.a.push(k.heapBuffer(0x3000, "/dev/missing".bytes()))
	expect k.call(nv, req).data.u32le(4) == 0x3_0003

test "the GPU reports itself as a Tegra X1":
	k = horizon.bareProcess()
	nv = k.newService("nvdrv:a")
	fd = k.open(nv, "/dev/nvhost-ctrl-gpu")
	error, chars = k.ioctl(nv, fd, 0xC0B0_4705, zeros(0xB0))
	expect error == 0
	expect chars.u64le(0) == 0xA0
	expect chars.u32le(16) == 0x120 and chars.u32le(20) == 0xB
	expect chars.u32le(16 + 88) == 0x902D and chars.u32le(16 + 92) == 0xB197
	expect chars.u64le(16 + 144) == 0x62_3032_6D67
	_, masks = k.ioctl(nv, fd, 0xC018_4706, zeros(24))
	expect masks.u32le(16) == 3

test "a pushbuffer submitted through a channel runs in the address space it is bound to":
	k = horizon.bareProcess()
	nv = k.newService("nvdrv")
	map = k.open(nv, "/dev/nvmap")
	space = k.open(nv, "/dev/nvhost-as-gpu")
	channel = k.open(nv, "/dev/nvhost-gpu")
	made u8[] = zeros(8)
	made.setU32le(0, 0x2000)
	k.ioctl(nv, map, 0xC008_0101, made)
	given u8[] = zeros(32)
	given.setU32le(0, 1)
	given.setU64le(24, u64(k.space.heapAt))
	k.ioctl(nv, map, 0xC020_0104, given)
	mapping u8[] = zeros(40)
	mapping.setU32le(8, 1)
	mapping.setU32le(12, 0x1_0000)
	error, mapped = k.ioctl(nv, space, 0xC028_4106, mapping)
	expect error == 0
	at = i64(mapped.u64le(32))
	bind u8[] = zeros(4)
	bind.setU32le(0, u32(channel))
	k.ioctl(nv, space, 0x4004_4101, bind)
	# SetObject of the copy class, then a release of 0x77 at +0x100
	words = []
	for w in [
		1 << 29 | 1 << 16,
		maxwell.classCopy,
		1 << 29 | 4 << 16 | 4,
		at >> 32,
		(at + 0x100) & 0xFFFF_FFFF,
		0x77,
		2
	]:
		words.pushU32le(w)
	horizon.putBytes(k.space.heapAt, words)
	entry = []
	entry.pushU32le(at & 0xFFFF_FFFF)
	entry.pushU32le(0x7 << 10 | at >> 32)
	submit u8[] = zeros(24)
	submit.setU32le(8, 1)
	submit.setU32le(12, 2)
	submit.extend(entry)
	error, answer = k.ioctl(nv, channel, 0xC018_4808, submit)
	expect error == 0
	expect horizon.getBytes(k.space.heapAt + 0x100, 4).u32le(0) == 0x77
	expect answer.u32le(20) == 1
