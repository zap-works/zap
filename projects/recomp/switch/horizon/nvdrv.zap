# nvdrv, nvdrv:a, nvdrv:s and nvdrv:t, the driver of the GPU and its neighbours (switchbrew: NV
# services): a client opens device nodes by path and sends them ioctls. The request number holds
# the direction (bits 30-31), the size of the argument (16-29), the device's type byte (8-15) and
# the command (0-7); each device below (nvMap.zap, nvCtrl.zap, nvgpu.zap, nvas.zap) is given the
# bytes the client sent, which it changes into the bytes the client gets back, and answers with
# an error code.

import recomp.switch.maxwell

# NvResult: the codes ioctls and Open answer with
nvOk = 0
nvNotImplemented = 1
nvNotSupported = 2
nvBadParameter = 4
nvTimeout = 5
nvInvalidState = 8
nvBadValue = 11
nvFileOperationFailed = 0x3_0003

# the device nodes this driver has
nvDevices = [
	"/dev/nvmap",
	"/dev/nvhost-ctrl",
	"/dev/nvhost-ctrl-gpu",
	"/dev/nvhost-as-gpu",
	"/dev/nvhost-gpu"
]

# An open device: its node, and the state of the object behind it (a channel's or an address
# space's index in the GPU).
pub type NvDevice:
	path str
	object i64 = -1
	open bool = true

pub type Nv:
	devices NvDevice[] = []   # file descriptor n is devices[n - 1]
	handles NvHandle[] = []   # nvmap's: handle n is handles[n - 1]
	slots NvSlot[] = []   # nvhost-ctrl's event slots
	events {i64: i64} = {}   # the events QueryEvent gave, by descriptor and event id
	aruid i64 = 0

fn get32(io u8[], at i64) i64:
	io.u32le(at)

fn put32(mut io u8[], at i64, v i64):
	io.setU32le(at, v & 0xFFFF_FFFF)

fn get64(io u8[], at i64) i64:
	i64(io.u64le(at))

fn put64(mut io u8[], at i64, v i64):
	io.setU64le(at, u64(v))

fn nvdrv(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		0: k.nvOpen(req, res)
		1, 11, 12: res.u32(k.nvIoctl(req))
		2: res.u32(k.nvClose(req.arg(0, 4)))
		3, 5, 6, 7, 8, 9, 10, 13: res.u32(nvOk)
		4: k.nvQueryEvent(req, res)
		_: k.unwritten(i, req)

fn nvOpen(mut k Kernel, req Request, mut res Response):
	path = req.sent(0).text().copy()
	if k.traceCalls: k.log.push("  open {path}")
	if not (path in nvDevices):
		k.log.push("nvdrv: cannot open {path}")
		res.u32(0)
		return res.u32(nvFileOperationFailed)
	d = NvDevice(path.copy())
	if path == "/dev/nvhost-gpu": d.object = k.gpu.newChannel()
	if path == "/dev/nvhost-as-gpu": d.object = k.gpu.newSpace()
	k.nv.devices.push(d)
	res.u32(k.nv.devices.len)
	res.u32(nvOk)

fn nvClose(mut k Kernel, fd i64):
	if fd < 1 or fd > k.nv.devices.len: return nvBadParameter
	k.nv.devices[fd - 1].open = false
	nvOk

# the open device behind a file descriptor, none for one that was never opened or was closed
fn nvDevice(k Kernel, fd i64) NvDevice?:
	if fd < 1 or fd > k.nv.devices.len or not k.nv.devices[fd - 1].open: return none
	k.nv.devices[fd - 1].copy()

# Ioctl (1), Ioctl2 (11: a second input buffer) and Ioctl3 (12: a second output buffer): the
# argument is padded to the size the request number gives, changed by the device, and written
# back whatever the error.
fn nvIoctl(mut k Kernel, req Request):
	fd = req.arg(0, 4)
	cmd = req.arg(4, 4)
	device = k.nvDevice(fd) ?? return nvBadParameter
	io = req.sent(0)
	while io.len < (cmd >> 16) & 0x3FFF:
		io.push(0)
	extra = req.sent(1) if req.command == 11 else []
	before = io[..io.len.min(48)].map("{it:02x}").join("")
	error = k.deviceIoctl(fd, device, cmd & 0xFFFF, io, extra)
	if k.traceCalls:
		after = io[..io.len.min(48)].map("{it:02x}").join("")
		k.log.push("  ioctl {device.path} {cmd:08x}: error {error:x}")
		k.log.push("    {before}")
		k.log.push("    {after}")
	req.receive(0).putBuffer(io)
	error

# the ioctl to the device's own file
fn deviceIoctl(mut k Kernel, fd i64, device NvDevice, cmd i64, mut io u8[], extra u8[]) i64:
	match device.path:
		"/dev/nvmap": k.nvmapIoctl(cmd, io)
		"/dev/nvhost-ctrl": k.ctrlIoctl(cmd, io)
		"/dev/nvhost-ctrl-gpu": k.ctrlGpuIoctl(cmd, io)
		"/dev/nvhost-as-gpu": k.addressSpaceIoctl(device.object, cmd, io)
		"/dev/nvhost-gpu": k.channelIoctl(device.object, cmd, io, extra)
		_: nvNotSupported

# QueryEvent (switchbrew: NV services, the event ids): an event handle for the device and id; the
# same event each time. nvhost-ctrl's ids name a slot.
fn nvQueryEvent(mut k Kernel, req Request, mut res Response):
	fd = req.arg(0, 4)
	id = req.arg(4, 4)
	device = k.nvDevice(fd) ?? return res.u32(nvBadParameter)
	if device.path == "/dev/nvhost-ctrl":
		slot = k.ctrlSlotOfEvent(id)
		if slot < 0: return res.u32(nvBadParameter)
		res.copied.push(k.slotEventHandle(slot))
		return res.u32(nvOk)
	key = fd * 0x1_0000_0000 + id
	if k.nv.events.get(key) is e: res.copied.push(k.add(.Event(e)))
	else:
		e, h = k.newEvent(false)
		k.nv.events[key] = e
		res.copied.push(h)
	res.u32(nvOk)
