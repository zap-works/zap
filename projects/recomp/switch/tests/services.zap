# Horizon's services answering requests made here (no guest code): the applet's message queue, the
# language, the clock and calendar, save data on the host and the shared fonts.
#   needs: projects/recomp/switch/rom/firmware/fonts/nintendo_ext_003.ttf

import fs
import recomp.switch.horizon
import recomp.switch.package

fn command(c i64, data u8[]):
	horizon.Request(kind = 4, command = c, data = data.copy())

fn plain(c i64):
	command(c, [])

fn newKernel():
	horizon.newProcess(0x1_0000, 0x20_0000)

# a buffer of the bytes put in the guest heap at `offset`
fn bufferAt(k horizon.Kernel, offset i64, bytes u8[]):
	at = k.space.heapAt + offset
	horizon.putBytes(at, bytes)
	horizon.Buffer(at, size = bytes.len)

test "the application proxy's state getter queues the focus message once":
	k = newKernel()
	proxy = k.call(k.newService("appletOE"), plain(0)).objects[0]
	getter = k.call(proxy, plain(0)).objects[0]
	event = k.call(getter, plain(0))
	expect event.copied.len == 1
	expect k.events[0]
	expect k.call(getter, plain(1)).data.u32le(0) == 15
	expect not k.events[0]
	expect k.call(getter, plain(1)).result == 0x680
	expect k.call(getter, plain(9)).data[0] == 1

test "the launch parameter is the preselected user, once":
	k = newKernel()
	proxy = k.call(k.newService("appletOE"), plain(0)).objects[0]
	functions = k.call(proxy, plain(20)).objects[0]
	expect k.call(functions, command(1, [1, 0, 0, 0])).result == 0x280
	storage = k.call(functions, command(1, [2, 0, 0, 0])).objects[0]
	expect k.services[storage].data.len == 0x88
	expect k.services[storage].data.u32le(0) == 0xC794_97CA
	expect k.call(functions, command(1, [2, 0, 0, 0])).result == 0x280

test "the language is American English":
	k = newKernel()
	code = k.call(k.newService("set"), plain(0)).data.u64le(0)
	expect code == 0x53_552D_6E65

test "a time of the clock is a calendar date in UTC":
	k = newKernel()
	service = k.call(k.newService("time:u"), plain(3)).objects[0]
	time = []
	time.pushU64le(1_771_117_261)
	d = k.call(service, command(101, time)).data
	expect d.u16le(0) == 2026
	expect d[2] == 2 and d[3] == 15
	expect d[4] == 1 and d[5] == 1 and d[6] == 1
	expect d.u32le(8) == 0
	expect d.u32le(12) == 45

test "a calendar date becomes a time again":
	k = newKernel()
	service = k.call(k.newService("time:u"), plain(3)).objects[0]
	calendar u8[] = [0xEA, 0x07, 2, 15, 1, 1, 1, 0]
	out = k.bufferAt(0, zeros(8))
	req = command(202, calendar)
	req.b.push(out)
	expect k.call(service, req).data.u32le(0) == 1
	expect horizon.getBytes(out.at, 8).u64le(0) == 1_771_117_261

# the save data of a program made up for this test
testProgram = 0x0100_0000_DEAD_0000

test "another program's save data is not found until made; the program's own holds the bytes written to a file":
	k = newKernel()
	k.programId = u64(testProgram)
	_ = fs.deleteTree(k.saveDir(u64(testProgram), 0, 0x1_0001, 0))
	service = k.newService("fsp-srv")
	other u8[] = zeros(0x48)
	other.setU64le(8, testProgram + 1)
	other.setU64le(16, 0x1_0001)
	expect k.call(service, command(51, other)).result == 0x7_D402
	attribute u8[] = zeros(0x48)
	attribute.setU64le(16, 0x1_0001)
	made u8[] = zeros(0x40)
	made.setU64le(8, 0x1_0001)
	expect k.call(service, command(22, made)).result == 0
	system = k.call(service, command(51, attribute)).objects[0]
	path = k.bufferAt(0, "/save.dat".bytes())
	create u8[] = zeros(16)
	create.setU64le(8, 4)
	req = command(0, create)
	req.a.push(path)
	expect k.call(system, req).result == 0
	open = command(8, [3, 0, 0, 0])
	open.a.push(path)
	file = k.call(system, open).objects[0]
	write = command(1, zeros(24))
	write.data.setU64le(8, 1)
	write.data.setU64le(16, 3)
	write.a.push(k.bufferAt(0x100, [7, 8, 9]))
	expect k.call(file, write).result == 0
	size = k.call(file, plain(4)).data.u64le(0)
	expect size == 4
	into = k.bufferAt(0x200, zeros(4))
	read = command(0, zeros(24))
	read.data.setU64le(16, 4)
	read.b.push(into)
	expect k.call(file, read).data.u64le(0) == 4
	expect horizon.getBytes(into.at, 4) == [0, 7, 8, 9]
	_ = fs.deleteTree(k.saveDir(u64(testProgram), 0, 0x1_0001, 0))

test "the shared fonts are the firmware's, as BFTTF in one shared memory":
	k = newKernel()
	k.titleDir = "projects/recomp/switch/rom/01007ef00011e000"
	service = k.newService("pl:u")
	types = k.bufferAt(0, zeros(28))
	offsets = k.bufferAt(0x100, zeros(28))
	sizes = k.bufferAt(0x200, zeros(28))
	req = plain(5)
	req.b.push(types)
	req.b.push(offsets)
	req.b.push(sizes)
	answer = k.call(service, req)
	expect answer.data[0] == 1
	expect answer.data.u32le(4) == 7
	memory = k.call(service, plain(4))
	expect memory.copied.len == 1
	extension = 5
	at = i64(horizon.getBytes(offsets.at, 28).u32le(extension * 4))
	size = i64(horizon.getBytes(sizes.at, 28).u32le(extension * 4))
	bfttf = k.sharedMemory[0].contents[at..at + size]
	font = package.decodeBfttf(bfttf) ?? []
	original = fs.readBytes("projects/recomp/switch/rom/firmware/fonts/nintendo_ext_003.ttf") ?? []
	expect font == original
