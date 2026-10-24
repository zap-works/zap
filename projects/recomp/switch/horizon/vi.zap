# vi:m, vi:s and vi:u, the display services (switchbrew: Display services): the roots hand out
# IApplicationDisplayService, which lists and opens the one display, makes layers and gives a
# layer's native window, the binder id its buffers are queued through (binder.zap). The console
# is handheld: a 1280 by 720 display.

displayWidth = 1280
displayHeight = 720
displayName = "Default"
displayId = 1
displayNameSize = 0x40

# the native window's tag (a parcel of the binder's id, switchbrew: Display services)
nativeWindowMagic = 2

# one frame at 60 Hz in the 19.2 MHz counter
vsyncTicks = 320_000

# the command of each root that gets the display service
rootCommands = {"vi:u": 0, "vi:s": 1, "vi:m": 2}

fn displayRoot(mut k Kernel, i i64, req Request, mut res Response):
	if rootCommands.get(k.services[i].name) is command and command == req.command:
		return k.offer(res, "IApplicationDisplayService")
	k.unwritten(i, req)

# the native window parcel of a layer: the binder id queues go through
fn nativeWindow(layer i64):
	w = ParcelWriter()
	w.write32(nativeWindowMagic)
	w.write32(1)
	w.write32(layer)
	loop 3:
		w.write32(0)
	w.data.extend("dispdrv\0".bytes())
	w.write32(0)
	w.write32(0)
	w.finish(4)

# the layer's native window put in the caller's buffer: its size
fn putNativeWindow(k Kernel, req Request, layer i64):
	window = nativeWindow(layer)
	req.receive(0).putBuffer(window)
	window.len

# the display's description (switchbrew: DisplayInfo)
fn displayInfo():
	out u8[] = displayName.bytes().copy()
	while out.len < displayNameSize:
		out.push(0)
	out.pushU64le(1)   # limited layers, as a byte and its padding
	out.pushU64le(1)
	out.pushU64le(displayWidth)
	out.pushU64le(displayHeight)
	out

# a layer made: its id
fn createLayer(mut k Kernel):
	layer = k.display.nextLayer
	k.display.nextLayer += 1
	k.display.layers.push(layer)
	layer

fn applicationDisplay(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		100, 103: k.offer(res, "IHOSBinderDriver")
		101, 102: k.offer(res, "IApplicationDisplayService")
		1000:
			req.receive(0).putBuffer(displayInfo())
			res.u64(1)
		1010, 1011: res.u64(displayId)
		1020: pass
		1102:
			res.u64(displayWidth)
			res.u64(displayHeight)
		2010: res.u64(k.createLayer())
		2011, 2101, 6000, 6001, 6002, 7000: pass
		2020:
			layer = req.arg(displayNameSize, 8)
			k.display.layers.push(layer)
			res.u64(k.putNativeWindow(req, layer))
		2021, 2031: pass
		2030, 2012:
			layer = k.createLayer()
			res.u64(layer)
			res.u64(k.putNativeWindow(req, layer))
		5202, 5203: res.copied.push(k.vsyncHandle())
		_: k.unwritten(i, req)

# a handle to the vsync event, made when first asked for and signaled on the first frame
fn vsyncHandle(mut k Kernel) i64:
	if k.display.vsyncEvent < 0:
		e, h = k.newEvent(true)
		k.display.vsyncEvent = e
		k.display.vsyncAt = k.now() + vsyncTicks
		return h
	k.add(.Event(k.display.vsyncEvent))

# The vsync event signaled when its frame's time has come (the counter is virtual: it moves with
# the instructions run).
fn pulseVsync(mut k Kernel):
	if k.display.vsyncEvent < 0 or k.now() < k.display.vsyncAt: return
	k.display.vsyncAt = k.now() + vsyncTicks
	k.setEvent(k.display.vsyncEvent, true)
