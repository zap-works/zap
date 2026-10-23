# hid, the controls (switchbrew: HID services): an applet resource whose shared memory a game
# maps and polls, and the commands that set up the pads, touch and sensors. What the memory
# carries is hidinput.zap's.

sharedMemorySize = 0x4_0000

fn hidServer(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		0: k.offer(res, "IAppletResource")
		1, 11, 21, 31, 40, 41, 50, 91, 100, 102, 103, 104, 107, 109: pass
		101: res.u32(0)
		106:
			_, h = k.newEvent(false)
			res.copied.push(h)
		66, 67, 69, 70, 72, 73, 75, 76, 78, 79, 81: pass   # the six-axis sensor's settings
		68, 82: res.u8(0)
		71, 74:
			res.u32(0)
			res.u32(0)
		77, 80: res.u32(0)
		120, 122, 123, 124, 125, 128, 130, 132: pass
		121, 129: res.u64(0)
		131: res.u8(0)
		200:   # a vibration device's info: a linear resonant actuator, its side unknown
			res.u32(1)
			res.u32(0)
		201, 206, 207, 209, 210: pass
		202: res.bytes(zeros(16))   # no vibration under way
		203: k.offer(res, "IActiveVibrationDeviceList")
		204: pass
		208: res.u32(0)
		211, 205: res.u8(1)
		301, 302, 304, 305, 307: pass
		303: res.u8(0)
		_: k.unwritten(i, req)

fn vibrationDevices(mut k Kernel, i i64, req Request, mut res Response):
	if req.command != 0: k.unwritten(i, req)

fn appletResource(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		0:
			res.copied.push(k.newSharedMemory(sharedMemorySize, zeros(sharedMemorySize)))
			k.hidMemory = k.sharedMemory.len - 1
		_: k.unwritten(i, req)
