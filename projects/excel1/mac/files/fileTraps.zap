# long: the File Manager's traps, one arm each
#
# The File Manager's traps over the prepared volumes: each a parameter block at A0 (ioResult at
# 16, ioNamePtr 18, ioVRefNum 22, then a file's ioRefNum 24, ioPermssn 27, ioBuffer 32, ioReqCount
# 36, ioActCount 40, ioPosMode 44 and ioPosOffset 46), the result in ioResult and D0. Volume -1 is
# the first prepared disk (the application's), -2 the second; writes stay in memory.

import cpu

eofErr = -39
fnfErr = -43
rfNumErr = -51
paramErr = -50
nsvErr = -35
ioErr = -36

pub mut defaultVolume = -1

fn volumeName(vRefNum i64) str:
	v = volumes()
	match vRefNum:
		-1, 1: v[0].copy()
		-2, 2: v[1].copy()
		0: volumeName(defaultVolume)
		_: v[0].copy()

fn volumeNumber(name str):
	for i, v in volumes():
		if v == name: return -1 - i
	0

# the volume and the file's name a block names: "volume:name", or the name on ioVRefNum's volume
fn fileOf(pb u32):
	namePtr = cpu.read32(pb + 18)
	name = str(pascalAt(namePtr)) if namePtr != 0 else ""
	match name.indexOf(":"):
		at:
			(name[..at].copy(), name[at + 1..].copy())
		none: (volumeName(word(pb + 22)), name.copy())

fn finish(pb u32, e i64):
	setWord(pb + 16, e)
	cpu.d0 = u32.wrap(e)
	e

fn openTrap(pb u32, isResource bool):
	volume, name = fileOf(pb)
	match openFork(volume, name, isResource):
		refNum:
			setWord(pb + 24, refNum)
			finish(pb, 0)
		none: finish(pb, fnfErr)

fn position(f OpenFork, mode i64, offset i64):
	match mode & 3:
		1: offset
		2: f.bytes.len + offset
		3: f.position + offset
		_: f.position

# where the block's position mode and offset put the fork's mark, -1 for a fork not open
fn markOf(refNum i64, mode i64, offset i64):
	f = openForks.get(refNum) ?? return -1
	position(f, mode, offset)

fn forkLength(refNum i64):
	f = openForks.get(refNum) ?? return 0
	f.bytes.len

fn forkBytes(refNum i64, at i64, n i64):
	f = openForks.get(refNum) ?? return []
	f.bytes[at..at + n].copy()

fn readTrap(pb u32):
	refNum = word(pb + 24)
	buffer = cpu.read32(pb + 32)
	count = i64(cpu.read32(pb + 36))
	mode = word(pb + 44)
	offset = i64(i32.wrap(i64(cpu.read32(pb + 46))))
	at = markOf(refNum, mode, offset)
	if at < 0: return finish(pb, rfNumErr)
	n = (forkLength(refNum) - at).clamp(0, count)
	if traceTraps: eprint("  read {refNum}: {n} of {count} bytes at {at:x} (mode {mode}, offset {offset:x}) to {buffer:x}")
	moveIn(buffer, forkBytes(refNum, at, n))
	setPosition(refNum, at + n)
	cpu.write32(pb + 40, n)
	cpu.write32(pb + 46, u32(at + n))
	finish(pb, eofErr if n < count else 0)

fn moveIn(buffer u32, data u8[]):
	noteWritten(buffer, data.len)
	b = i64(address(buffer))
	for i in 0..data.len:
		cpu.mem[b + i] = data[i]

fn setPosition(refNum i64, at i64):
	if refNum in openForks: openForks[refNum].position = at

fn writeTrap(pb u32):
	refNum = word(pb + 24)
	buffer = cpu.read32(pb + 32)
	count = i64(cpu.read32(pb + 36))
	mode = word(pb + 44)
	offset = i64(i32.wrap(i64(cpu.read32(pb + 46))))
	data = (0..count).map(u8(cpu.read8(buffer + u32(it))))
	at = markOf(refNum, mode, offset)
	if at < 0: return finish(pb, rfNumErr)
	while forkLength(refNum) < at + count:
		openForks[refNum].bytes.push(0)
	for i in 0..count:
		openForks[refNum].bytes[at + i] = data[i]
	openForks[refNum].position = at + count
	openForks[refNum].isChanged = true
	cpu.write32(pb + 40, count)
	cpu.write32(pb + 46, u32(at + count))
	finish(pb, 0)

fn eofTrap(pb u32, isSet bool):
	refNum = word(pb + 24)
	if refNum not in openForks: return finish(pb, rfNumErr)
	if not isSet:
		cpu.write32(pb + 28, u32(forkLength(refNum)))
		return finish(pb, 0)
	size = i64(cpu.read32(pb + 28))
	while forkLength(refNum) < size:
		openForks[refNum].bytes.push(0)
	openForks[refNum].bytes.truncate(size)
	finish(pb, 0)

fn fposTrap(pb u32, isSet bool):
	refNum = word(pb + 24)
	if refNum not in openForks: return finish(pb, rfNumErr)
	if not isSet:
		cpu.write32(pb + 46, u32(markOf(refNum, 0, 0)))
		cpu.write32(pb + 36, 0)
		cpu.write32(pb + 40, 0)
		setWord(pb + 44, 0)
		return finish(pb, 0)
	mode = word(pb + 44)
	offset = i64(i32.wrap(i64(cpu.read32(pb + 46))))
	at = markOf(refNum, mode, offset)
	if at > forkLength(refNum): return finish(pb, eofErr)
	setPosition(refNum, at)
	cpu.write32(pb + 46, u32(at))
	finish(pb, 0)

fn volumeInfo(pb u32):
	index = word(pb + 28)
	vRefNum = -index if index > 0 else word(pb + 22)
	name = volumeName(vRefNum if vRefNum != 0 else defaultVolume)
	if index > volumes().len: return finish(pb, nsvErr)
	at = cpu.read32(pb + 18)
	if at != 0: writePascal(at, name.bytes())
	setWord(pb + 22, volumeNumber(name))
	cpu.write32(pb + 30, 0)
	cpu.write32(pb + 34, 0)
	setWord(pb + 38, 0)
	setWord(pb + 40, 5)
	setWord(pb + 42, 4)
	setWord(pb + 44, 12)
	setWord(pb + 46, 391)
	cpu.write32(pb + 48, 1024)
	cpu.write32(pb + 52, 8192)
	setWord(pb + 56, 16)
	cpu.write32(pb + 58, 100)
	setWord(pb + 62, 13)
	finish(pb, 0)

# GetFileInfo: the file named, or the n-th of the volume when ioFDirIndex is n > 0 (its name then
# written to ioNamePtr), its Finder information, fork sizes and dates
fn getFileInfo(pb u32):
	index = word(pb + 28)
	volume = volumeName(word(pb + 22))
	name = ""
	if index > 0:
		names = filesOn(volume)
		if index > names.len: return finish(pb, fnfErr)
		name = names[index - 1].copy()
		at = cpu.read32(pb + 18)
		if at != 0: writePascal(at, name.bytes())
	else:
		volume, name = fileOf(pb)
	info = fileInfo(volume, name)
	if traceTraps: eprint("  file info of \"{name}\" on {volume} (index {index}, volume {word(pb + 22)}): {info.len} bytes")
	if info.len < 34: return finish(pb, fnfErr)
	cpu.write8(pb + 30, u32(info[24]) & 0x7F)
	cpu.write8(pb + 31, 0)
	for i in 0..16:
		cpu.write8(pb + 32 + u32(i), info[i])
	cpu.write32(pb + 48, info.u32be(26))
	dataSize = forkSize(volume, name, false)
	resourceSize = forkSize(volume, name, true)
	setWord(pb + 52, info.u16be(30))
	cpu.write32(pb + 54, u32(dataSize))
	cpu.write32(pb + 58, u32((dataSize + 1023) & ~1023))
	setWord(pb + 62, info.u16be(32))
	cpu.write32(pb + 64, u32(resourceSize))
	cpu.write32(pb + 68, u32((resourceSize + 1023) & ~1023))
	cpu.write32(pb + 72, info.u32be(16))
	cpu.write32(pb + 76, info.u32be(20))
	finish(pb, 0)

pub fn fileTrap(index i64, trapWord i64, back u32) u32:
	pb = cpu.a0
	# a device driver's call (a negative reference number)
	isDriverCall = index >= 2 and index <= 6 and word(pb + 24) < 0
	if isDriverCall:
		finish(pb, driverCall(index, pb))
		return back
	match index:
		0x00: openTrap(pb, false)
		0x0A: openTrap(pb, true)
		0x01:
			closeFork(word(pb + 24))
			finish(pb, 0)
		0x02: readTrap(pb)
		0x03: writeTrap(pb)
		0x07: volumeInfo(pb)
		0x0C: getFileInfo(pb)
		0x0D: finish(pb, 0)
		0x11: eofTrap(pb, false)
		0x12: eofTrap(pb, true)
		0x13, 0x17, 0x45: finish(pb, 0)
		0x14:
			at = cpu.read32(pb + 18)
			if at != 0: writePascal(at, volumeName(defaultVolume).bytes())
			setWord(pb + 22, defaultVolume)
			finish(pb, 0)
		0x15:
			v = word(pb + 22)
			if v != 0: defaultVolume = v
			finish(pb, 0)
		0x18: fposTrap(pb, false)
		0x44: fposTrap(pb, true)
		_: return unimplemented(trapWord, back)
	back
