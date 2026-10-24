# The applet manager (switchbrew: Applet Manager services): appletOE gives an application its
# IApplicationProxy, which hands out the controllers an application runs under. The application
# is always in focus, running on a handheld console with one user.

# the AppletMessage values (libnx) the queue carries, and the focus states
messageFocusStateChanged = 15
focusInFocus = 1

# the Result a queue with nothing to give answers, and a channel with no data
resultNoMessages = 0x680
resultNoDataInChannel = 0x280

# the launch parameter the home menu leaves for an application started by a user: the account
# selection (switchbrew: Applet Manager services#LaunchParameter), 0x88 bytes
launchParameterMagic = 0xC794_97CA
launchParameterSize = 0x88

pub type Applet:
	messages i64[] = []   # AppletMessage values not yet received
	messageEvent i64 = -1   # signaled while messages wait; made when first asked for
	poppedAccount bool = false

# a message queued for the application, its event signaled
fn pushMessage(mut k Kernel, message i64):
	k.applet.messages.push(message)
	if k.applet.messageEvent >= 0: k.setEvent(k.applet.messageEvent, true)

# a handle to the message event
fn messageEventHandle(mut k Kernel) i64:
	if k.applet.messageEvent < 0:
		e, h = k.newEvent(not k.applet.messages.isEmpty)
		k.applet.messageEvent = e
		return h
	k.add(.Event(k.applet.messageEvent))

# appletOE: the proxy for an application
fn appletOE(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		0:
			k.offer(res, "IApplicationProxy")
			k.pushMessage(messageFocusStateChanged)
		_: k.unwritten(i, req)

fn applicationProxy(mut k Kernel, i i64, req Request, mut res Response):
	names = {
		0: "ICommonStateGetter",
		1: "ISelfController",
		2: "IWindowController",
		3: "IAudioController",
		4: "IDisplayController",
		10: "IProcessWindingController",
		11: "ILibraryAppletCreator",
		20: "IApplicationFunctions",
		1000: "IDebugFunctions"
	}
	if names.get(req.command) is name: k.offer(res, name)
	else: k.unwritten(i, req)

fn commonStateGetter(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		0: res.copied.push(k.messageEventHandle())
		1:
			if k.applet.messages.isEmpty: return res.fail(resultNoMessages)
			res.u32(k.applet.messages.remove(0))
			if k.applet.messages.isEmpty: k.setEvent(k.applet.messageEvent, false)
		3, 4: pass
		5: res.u8(0)   # OperationMode: handheld
		6: res.u32(0)   # PerformanceMode: handheld
		8: res.u8(0)   # BootMode: normal
		9: res.u8(focusInFocus)
		10, 11, 12: pass
		60:
			res.u32(1280)
			res.u32(720)
		_: k.unwritten(i, req)

fn selfController(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		0, 1, 2, 3, 4: pass
		9:   # GetLibraryAppletLaunchableEvent: signaled, an application may launch applets
			_, h = k.newEvent(true)
			res.copied.push(h)
		10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 50, 51, 60, 62, 64, 65, 68: pass
		40: res.u64(k.createLayer())   # CreateManagedDisplayLayer
		63: res.u32(0)
		69: res.u8(0)
		90: res.u64(0)
		91:
			_, h = k.newEvent(false)
			res.copied.push(h)
		_: k.unwritten(i, req)

fn windowController(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		1: res.u64(appletResourceUserId)
		10, 11, 12: pass
		_: k.unwritten(i, req)

# the identifier hid and others know the application by
pub appletResourceUserId = 0x1

fn audioController(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		0, 3, 4: pass
		1, 2: res.u32(0x3F80_0000)   # the expected master volume: 1.0
		_: k.unwritten(i, req)

fn libraryAppletCreator(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		1: pass
		2: res.u8(0)
		10:
			s = k.subService(res, "IStorage")
			k.services[s].data = zeros(req.arg(0, 8))
		_: k.unwritten(i, req)

# an IStorage: its bytes opened for access through an accessor that names it
fn storage(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		0:
			s = k.subService(res, "IStorageAccessor")
			k.services[s].value = i
		_: k.unwritten(i, req)

fn storageAccessor(mut k Kernel, i i64, req Request, mut res Response):
	target = k.services[i].value
	size = k.services[target].data.len
	match req.command:
		0: res.u64(size)
		10, 11:
			at = req.arg(0, 8)
			if at < 0 or at > size: return res.fail(resultStorageOutOfRange)
			if req.command == 10:
				bytes = req.sent(0)
				if at + bytes.len > size: return res.fail(resultStorageOutOfRange)
				for j, b in bytes:
					k.services[target].data[at + j] = b
			else:
				buf = req.receive(0)
				n = buf.size.min(size - at)
				putBytes(buf.at, k.services[target].data[at..at + n])
		_: k.unwritten(i, req)

# the Result for an access past a storage's end (am 2)
resultStorageOutOfRange = 0x4E02

fn applicationFunctions(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		1: k.popLaunchParameter(req.arg(0, 4), res)
		20:
			k.ensureSaveData(k.programId, saveAccount, req.arg(0, 8), 0)
			res.u64(0)
		21: res.u64(languageCode(1))
		22: pass
		23:
			res.bytes("1.0.0".bytes())
			res.align(16)
		30, 31, 32, 33: pass
		40: res.u8(1)
		50:
			res.u64(0x5A5A_0000_0000_0001)
			res.u64(0x0123_4567_89AB_CDEF)
		60: pass
		65: res.u8(0)
		66, 67, 90: pass
		210:   # an event the game polls until it is signaled (SavageWindRecomp's finding)
			_, h = k.newEvent(true)
			res.copied.push(h)
		_: k.unwritten(i, req)

# the account selection once for kind 2 (the user's own storage, 1, is empty)
fn popLaunchParameter(mut k Kernel, kind i64, mut res Response):
	if kind != 2 or k.applet.poppedAccount: return res.fail(resultNoDataInChannel)
	k.applet.poppedAccount = true
	s = k.subService(res, "IStorage")
	data u8[] = zeros(launchParameterSize)
	data.setU32le(0, u32(launchParameterMagic))
	data.setU32le(4, 1)
	data.setU64le(8, u64(userId))
	data.setU64le(16, 0)
	k.services[s].data = data

fn debugFunctions(mut k Kernel, i i64, req Request, mut res Response):
	k.unwritten(i, req)
