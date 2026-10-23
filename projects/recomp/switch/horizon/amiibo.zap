# nfp:user, the amiibo reader (switchbrew: NFC services#nfp:user): the Pro Controller of player 1
# is its one device, and no figure is ever placed on it, so detection starts and finds nothing.

stateInitialized = 1

fn amiiboManager(mut k Kernel, i i64, req Request, mut res Response):
	if req.command == 0: k.offer(res, "INfpUser")
	else: k.unwritten(i, req)

fn amiiboUser(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		0, 1, 3, 4, 6, 10, 11: pass   # initialize, finalize, detection, unmount, flush, restore
		2:   # the devices: player 1's npad
			req.receive(0).putBuffer(zeros(8))
			res.u32(1)
		17, 18, 23:   # a figure placed, removed, the reader's availability changed
			_, h = k.newEvent(false)
			res.copied.push(h)
		19, 20: res.u32(stateInitialized)
		21: res.u32(0)   # the device's npad id
		_: k.unwritten(i, req)
