# The player's own game and firmware opened into projects/recomp/switch/rom/ (never committed:
# .gitignore), from a dir that holds prod.keys (and title.keys), the game's NSP and the firmware
# (a zip, or its NCAs in a dir). Run from the repository root:
#
#   zap run projects/recomp/switch/tools/extract.zap <dir>
#
# writes rom/<title id>/exefs/ (each NSO stored whole, main.npdm), rom/<title id>/romfs/,
# rom/<title id>/control.nacp and info.txt (name, version, main's build id and the version the
# table knows it as), rom/firmware/version.txt and rom/firmware/fonts/ (the shared fonts as
# TrueType). A file already there with its size is not written again.

import fs
import recomp.switch.package

romDir = "projects/recomp/switch/rom"
chunk = 16 << 20

# the files of dir, and of the dirs in it, whose names end with ext
fn filesEnding(dir str, ext str):
	out = []
	for name in fs.list(dir) ?? []:
		path = fs.join(dir, name)
		if name.lower().endsWith(ext): out.push(path)
		elif fs.list(path) is inner:
			for n in inner:
				if n.lower().endsWith(ext): out.push(fs.join(path, n))
	out

# n bytes of the file read through `read` written to path, a chunk at a time
fn copyOut(path str, size i64, read fn(i64, i64) u8[]):
	if fs.open(path) is old and old.len == size: return
	_ = fs.createDir(fs.dirOf(path))
	fs.writeBytes(path, []) ?? fail("cannot write {path}: {error}")
	at = 0
	while at < size:
		n = (size - at).min(chunk)
		fs.appendBytes(path, read(at, n)) ?? fail("cannot write {path}: {error}")
		at += n

# the ExeFS's files written to dir, each NSO stored whole; main's build id
fn writeExefs(nca package.Nca, dir str):
	s = nca.pfsSection() ?? fail("the program NCA has no ExeFS")
	buildId = ""
	for e in nca.sectionFiles(s):
		bytes = nca.readData(s, e.at, e.size)
		if package.readNso(bytes) is nso:
			if e.name == "main": buildId = nso.buildId
			bytes = package.decompressNso(bytes) ?? fail("{e.name}: {error}")
		path = fs.join(dir, e.name)
		fs.createDir(dir) ?? fail("cannot make {dir}: {error}")
		_ = fs.writeChanged(path, bytes) ?? fail("cannot write {path}: {error}")
	buildId

# the RomFS's files written under dir; how many
fn writeRomfs(nca package.Nca, dir str):
	s = nca.romSection() ?? return 0
	files = package.romFiles((at, n): nca.readData(s, at, n))
	for i, f in files:
		copyOut(fs.join(dir, f.path), f.size, (at, n): nca.readData(s, f.at + at, n))
		if i % 1000 == 0: print("  romfs {i}/{files.len}")
	files.len

# a control NCA's control.nacp, written into dir; the game's name and display version
fn writeControl(nca package.Nca, dir str):
	s = nca.romSection() ?? return ("", "")
	for f in package.romFiles((at, n): nca.readData(s, at, n)):
		if f.path != "control.nacp": continue
		nacp = nca.readData(s, f.at, f.size)
		_ = fs.writeChanged(fs.join(dir, "control.nacp"), nacp) ??
			fail("cannot write control.nacp: {error}")
		return (nacp.cStringAt(0, 0x200), nacp.cStringAt(0x3060, 0x10))
	("", "")

# the game in the NSP opened into rom/<title id>/
fn extractGame(nsp str, mut keys package.Keys):
	file = fs.open(nsp) ?? fail("cannot read {nsp}: {error}")
	first = file.readAt(0, 16) ?? fail("{nsp} is empty")
	entries = package.readPfs(file.readAt(0, package.pfsHeaderSize(first)) ?? [], 0) ??
		fail("{nsp} is no NSP (PFS0)")
	for e in entries.filter(.name.endsWith(".tik")):
		keys.addTicket(file.readAt(e.at, e.size) ?? []) ?? fail("{e.name}: {error}")
	name = ""
	version = ""
	buildId = ""
	title = 0
	for e in entries.filter(.name.endsWith(".nca") and not .name.endsWith(".cnmt.nca")):
		nca = package.openNca(fs.open(nsp) ?? fail("cannot read {nsp}"), e.at, keys) ??
			fail("{e.name}: {error}")
		dir = fs.join(romDir, "{nca.titleId:016x}")
		if nca.content == package.contentProgram:
			title = i64(nca.titleId)
			buildId = nca.writeExefs(fs.join(dir, "exefs"))
			print("{e.name}: ExeFS, main {buildId}")
			print("{e.name}: RomFS, {nca.writeRomfs(fs.join(dir, "romfs"))} files")
		elif nca.content == package.contentControl:
			name, version = nca.writeControl(dir)
	known = package.knownBuild(buildId)
	info = "name {name}\nversion {version}\ntitle {title:016x}\nbuild {buildId}\nknown {known}\n"
	path = fs.join(romDir, "{title:016x}/info.txt")
	_ = fs.writeChanged(path, info.bytes()) ?? fail("cannot write {path}: {error}")
	print("{name} {version} ({title:016x}), main {buildId}: {known}")

# the firmware's NCAs: its zip unpacked into rom/firmware/nca, or the .nca files found in dir
fn firmwareNcas(dir str):
	for zip in filesEnding(dir, ".zip"):
		target = fs.join(romDir, "firmware/nca")
		if not fs.unpack(zip, target): fail("cannot unpack {zip}")
	out = filesEnding(dir, ".nca")
	out.extend(filesEnding(fs.join(romDir, "firmware/nca"), ".nca"))
	out

# the system version and the shared fonts written into rom/firmware/
fn extractFirmware(dir str, keys package.Keys):
	out = fs.join(romDir, "firmware")
	fonts = 0
	for path in firmwareNcas(dir):
		file = fs.open(path) ?? continue
		nca = package.openNca(file, 0, keys) ?? continue
		isFont = nca.titleId >= 0x0100_0000_0000_0810 and nca.titleId <= 0x0100_0000_0000_0815
		if nca.titleId != 0x0100_0000_0000_0809 and not isFont: continue
		s = nca.romSection() ?? continue
		for f in package.romFiles((at, n): nca.readData(s, at, n)):
			bytes = nca.readData(s, f.at, f.size)
			if isFont and f.path.endsWith(".bfttf"):
				ttf = package.decodeBfttf(bytes) ?? fail("{f.path} is no BFTTF")
				target = fs.join(out, "fonts/{fs.stem(f.path)}.ttf")
				_ = fs.createDir(fs.dirOf(target))
				_ = fs.writeChanged(target, ttf) ?? fail("cannot write {target}: {error}")
				fonts += 1
			elif f.path == "file":
				version = "{bytes[0]}.{bytes[1]}.{bytes[2]}"
				_ = fs.createDir(out)
				_ = fs.writeChanged(fs.join(out, "version.txt"), "{version}\n".bytes()) ??
					fail("cannot write version.txt")
				print("firmware {version}")
	print("{fonts} shared fonts")

dir = args.positional().first ?? fail("usage: zap run projects/recomp/switch/tools/extract.zap <dir with prod.keys, the NSP and the firmware>")
keys = package.readKeys(dir) ?? fail
nsps = filesEnding(dir, ".nsp")
if nsps.isEmpty: fail("no .nsp in {dir}")
for nsp in nsps:
	extractGame(nsp, keys)
extractFirmware(dir, keys)
