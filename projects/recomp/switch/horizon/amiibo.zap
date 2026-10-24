# nfp:user, the amiibo reader (switchbrew: NFC services#nfp:user): the Pro Controller of player 1
# is its one device, and no figure is ever placed on it, so a detection searches forever. The
# interface's own state (State) and the device's (DeviceState) are kept in the object's value as
# deviceState, or -1 when it is not initialized.

stateNotInitialized = 0
stateInitialized = 1
deviceInitialized = 0
deviceSearching = 1

fn amiiboManager(mut k Kernel, i i64, req Request, mut res Response):
	if req.command != 0: return k.unwritten(i, req)
	s = k.subService(res, "INfpUser")
	k.services[s].value = -1

fn amiiboUser(mut k Kernel, i i64, req Request, mut res Response):
	device = k.services[i].value
	match req.command:
		0: k.services[i].value = deviceInitialized
		1: k.services[i].value = -1
		2:   # the devices: player 1's npad
			req.receive(0).putBuffer(zeros(8))
			res.u32(1)
		3: k.services[i].value = deviceSearching
		4: k.services[i].value = deviceInitialized
		6, 10, 11: pass   # unmount, flush, restore
		17, 18, 23:   # a figure placed, removed, the reader's availability changed
			_, h = k.newEvent(false)
			res.copied.push(h)
		19: res.u32(stateNotInitialized if device < 0 else stateInitialized)
		20: res.u32(device.max(0))
		21: res.u32(0)   # the device's npad id
		_: k.unwritten(i, req)
