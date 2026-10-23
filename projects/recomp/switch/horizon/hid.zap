# hid, the controls (switchbrew: HID services): an applet resource whose shared memory a game
# maps and polls, and the commands that set up the pads, touch and sensors. What the memory
# carries is hidinput.zap's.

sharedMemorySize = 0x4_0000

fn hidServer(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		0: k.offer(res, "IAppletResource")
		11, 21, 31, 40, 41, 50, 91, 100, 102, 103, 104, 107, 109: pass
		101: res.u32(0)
		106:
			_, h = k.newEvent(false)
			res.copied.push(h)
		120, 122, 123, 124, 125, 128, 130, 132: pass
		121, 129: res.u64(0)
		131: res.u8(0)
		204: pass
		205: res.u8(1)
		301, 302, 304, 305, 307: pass
		303: res.u8(0)
		_: k.unwritten(i, req)

fn appletResource(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		0:
			res.copied.push(k.newSharedMemory(sharedMemorySize, zeros(sharedMemorySize)))
			k.hidMemory = k.sharedMemory.len - 1
		_: k.unwritten(i, req)
