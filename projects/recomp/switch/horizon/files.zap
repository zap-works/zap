# fsp-srv, the file system service (switchbrew: Filesystem services): the game's RomFS as the
# image a game reads (built from the extracted romfs/ dir), its save data and the SD card as
# dirs of the host under out/ (git ignores it). The paths a client sends are the guest's, '/'
# below the file system's root.

import fs
import recomp.switch.package

# where the host keeps what the console would, beside the game's files (its title dir, which an
# app's files dir is on a phone): save/<program id>/<kind>-<user>-<index> and sd/

# the SaveDataType of an account's save data, the kind games open first
pub saveAccount = 0

# the Results (switchbrew: Error codes) of module 2, fs
resultPathNotFound = 0x202
resultPathAlreadyExists = 0x402
resultTargetNotFound = 0x7_D402
resultInvalidPath = 0x2_EE02
resultFsOutOfRange = 0xB_BA02

entryDirectory = 0
entryFile = 1

# The files a process sees: the RomFS image of the game, built when it is first opened.
pub type Files:
	rom package.RomImage = package.RomImage(root = "")
	romBuilt bool = false
	fonts SharedFonts = SharedFonts()
	fontsLoaded bool = false

# the game's RomFS dir
fn romfsDir(k Kernel):
	fs.join(k.titleDir, "romfs")

# the host dir of a save data
pub fn saveDir(k Kernel, programId u64, kind i64, user i64, index i64) str:
	"{k.titleDir}/save/{programId:016x}/{kind}-{user:x}-{index}"

# a save data made if it is not there yet
pub fn ensureSaveData(k Kernel, programId u64, kind i64, user i64, index i64):
	_ = fs.createDir(k.saveDir(programId, kind, user, index))

# The host path of a guest path below a file system's dir; none for a path that leaves it.
fn hostPath(root str, path str) str?:
	if path.split("/").any(it == ".."): return none
	relative = path.copy()
	while relative.startsWith("/"):
		relative = relative[1..].copy()
	fs.join(root, relative)

# a buffer's bytes up to the NUL that ends a path
fn pathOf(bytes u8[]):
	end = bytes.indexOf(0) ?? bytes.len
	bytes[..end].text().copy()

# a dir's file system: its host dir kept in the service's path
fn newFileSystem(mut k Kernel, mut res Response, dir str):
	s = k.subService(res, "IFileSystem")
	k.services[s].path = dir.copy()
	_ = fs.createDir(dir)

fn fileSystemService(mut k Kernel, i i64, req Request, mut res Response):
	match req.command:
		1: pass
		18: k.newFileSystem(res, "{k.titleDir}/sd")
		22: k.ensureSaveData(
			k.programId,
			req.data[0x20],
			req.arg(8, 8),
			req.arg(0x22, 2)
		)
		51, 53: k.openSaveData(req, res)
		200: k.offer(res, "IFsStorage")
		203: res.fail(resultTargetNotFound)
		1003, 1004, 1006: pass
		1005: res.u32(0)
		_: k.unwritten(i, req)

# OpenSaveDataFileSystem: a space (u8), then the SaveDataAttribute (0x40 bytes at 8): the
# program (0 for this one), the user (u128), a system id, the type (u8), a rank and the index.
# The program's own save data is there from its launch, as the system makes it then; another's
# only if it was made.
fn openSaveData(mut k Kernel, req Request, mut res Response):
	program = u64(req.arg(8, 8))
	owner = k.programId if program == 0 else program
	dir = k.saveDir(owner, req.data[0x28], req.arg(16, 8), req.arg(0x2A, 2))
	if fs.isDir(dir) or owner == k.programId: k.newFileSystem(res, dir)
	else: res.fail(resultTargetNotFound)

# the RomFS image, built on first use
fn romImage(mut k Kernel):
	if not k.files.romBuilt:
		k.files.rom = package.buildRomImage(k.romfsDir())
		k.files.romBuilt = true
	k.files.rom.copy()

# an IStorage over the RomFS image: Read, Flush, GetSize
fn fsStorage(mut k Kernel, i i64, req Request, mut res Response):
	img = k.romImage()
	match req.command:
		0:
			offset = req.arg(0, 8)
			size = req.arg(8, 8)
			if offset < 0 or size < 0 or offset + size > img.romImageSize():
				return res.fail(resultFsOutOfRange)
			bytes = img.readRomImage(offset, size)
			if bytes.len < size: k.log.push("  storage read at {offset:x} gave {bytes.len:x} of {size:x} bytes")
			req.receive(0).putBuffer(bytes)
		2: pass
		4: res.u64(img.romImageSize())
		_: k.unwritten(i, req)

# an IFileSystem over a host dir (the service's path)
fn fileSystem(mut k Kernel, i i64, req Request, mut res Response):
	root = k.services[i].path.copy()
	guest = pathOf(req.sent(0))
	path = hostPath(root, guest) ?? return res.fail(resultInvalidPath)
	if root == "{k.titleDir}/sd" and k.selfName != "" and guest.endsWith("/{k.selfName}"):
		path = k.selfPath.copy()
	exists = fs.exists(path)
	isDir = fs.isDir(path)
	match req.command:
		0:
			if exists: return res.fail(resultPathAlreadyExists)
			bytes u8[] = zeros(req.arg(8, 8))
			_ = fs.writeBytes(path, bytes)
		1:
			if not exists or isDir: return res.fail(resultPathNotFound)
			_ = fs.deleteFile(path)
		2:
			if exists: return res.fail(resultPathAlreadyExists)
			_ = fs.createDir(path)
		3, 4:
			if not isDir: return res.fail(resultPathNotFound)
			_ = fs.deleteTree(path)
		5, 6: renameEntry(root, path, req, res)
		7:
			if not exists: return res.fail(resultPathNotFound)
			res.u32(entryDirectory if isDir else entryFile)
		8:
			if not exists or isDir: return res.fail(resultPathNotFound)
			s = k.subService(res, "IFile")
			k.services[s].path = path
		9:
			if not isDir: return res.fail(resultPathNotFound)
			s = k.subService(res, "IDirectory")
			k.services[s].path = path
			k.services[s].data = [u8(req.arg(0, 4))]
		10: pass
		11, 12: res.u64(0x40_0000_0000)
		13:
			if not isDir: return res.fail(resultPathNotFound)
			_ = fs.deleteTree(path)
			_ = fs.createDir(path)
		_: k.unwritten(i, req)

# RenameFile and RenameDirectory: the old path in the first buffer, the new one in the second
fn renameEntry(root str, from str, req Request, mut res Response):
	to = hostPath(root, pathOf(req.sent(1))) ?? return res.fail(resultInvalidPath)
	if not fs.exists(from): return res.fail(resultPathNotFound)
	if fs.exists(to): return res.fail(resultPathAlreadyExists)
	_ = fs.moveFile(from, to)

# an IFile: Read, Write (option, offset, size), Flush, SetSize, GetSize; the file's host path in
# the service's path
fn file(mut k Kernel, i i64, req Request, mut res Response):
	path = k.services[i].path.copy()
	bytes = fs.readBytes(path) ?? []
	match req.command:
		0:
			offset = req.arg(8, 8)
			n = req.arg(16, 8).min(bytes.len - offset).max(0)
			if offset < bytes.len: req.receive(0).putBuffer(bytes[offset..offset + n])
			res.u64(n)
		1:
			offset = req.arg(8, 8)
			data = req.sent(0)
			while bytes.len < offset + data.len:
				bytes.push(0)
			for j, b in data:
				bytes[offset + j] = b
			_ = fs.writeBytes(path, bytes)
		2: pass
		3:
			size = req.arg(0, 8)
			while bytes.len < size:
				bytes.push(0)
			_ = fs.writeBytes(path, bytes[..size])
		4: res.u64(bytes.len)
		_: k.unwritten(i, req)

# whether a dir's entry passes the OpenDirectory filter (bit 0 dirs, bit 1 files)
fn entryWanted(dir str, name str, filter i64):
	isDir = fs.isDir(fs.join(dir, name))
	filter & (1 if isDir else 2) != 0

# one 0x310-byte entry of an IDirectory's Read: the name, the type at 0x304, the size at 0x308
fn directoryEntry(dir str, name str):
	entry u8[] = zeros(0x310)
	for c, b in name.bytes():
		entry[c] = b
	isDir = fs.isDir(fs.join(dir, name))
	entry[0x304] = u8(entryDirectory if isDir else entryFile)
	if not isDir: entry.setU64le(0x308, u64((fs.open(fs.join(dir, name)) ?? return entry).len))
	entry

# an IDirectory: Read the next entries, GetEntryCount; the cursor in the service's value, the
# filter in its data
fn directory(mut k Kernel, i i64, req Request, mut res Response):
	dir = k.services[i].path.copy()
	filter = i64(k.services[i].data[0])
	names = (fs.list(dir) ?? []).sorted().filter(entryWanted(dir, it, filter))
	match req.command:
		0:
			out = req.receive(0)
			first = k.services[i].value
			count = (names.len - first).min(out.size / 0x310).max(0)
			entries = []
			for j in 0..count:
				entries.extend(directoryEntry(dir, names[first + j]))
			out.putBuffer(entries)
			k.services[i].value = first + count
			res.u64(count)
		1: res.u64(names.len)
		_: k.unwritten(i, req)
