# The package formats read from bytes made here: a PFS0, a RomFS of a dir and two files, an NSO
# with a compressed segment, a BFTTF.

import fs
import lz4
import recomp.switch.package

# a PFS0 of the named files' bytes
fn pfsOf(files (str, u8[])[]):
	names = []
	offsets = []
	for (name, _) in files:
		offsets.push(names.len)
		names.extend(name.bytes())
		names.push(0)
	out = []
	out.extend("PFS0".bytes())
	out.pushU32le(files.len)
	out.pushU32le(names.len)
	out.pushU32le(0)
	at = 0
	for i, (_, bytes) in files:
		out.pushU64le(at)
		out.pushU64le(bytes.len)
		out.pushU32le(offsets[i])
		out.pushU32le(0)
		at += bytes.len
	out.extend(names)
	for (_, bytes) in files:
		out.extend(bytes)
	out

test "a PFS0's files are found by name, offset and size":
	pfs = pfsOf([("main", [1, 2, 3]), ("main.npdm", [4, 5])])
	entries = package.readPfs(pfs, 0) ?? []
	expect entries.map(.name) == ["main", "main.npdm"]
	expect pfs[entries[1].at] == 4 and entries[1].size == 2
	expect package.pfsHeaderSize(pfs) == entries[0].at

# a dir or file entry's name, padded to 4 bytes
fn pushName(mut t u8[], name str):
	t.pushU32le(name.len)
	t.extend(name.bytes())
	while t.len % 4 != 0:
		t.push(0)

test "a RomFS is walked into paths below its root":
	none32 = 0xFFFF_FFFF
	dirs = []
	# the root (its child dir "data" at 0x18, its file "a.txt" at 0)
	for v in [0, none32, 0x18, 0, none32]:
		dirs.pushU32le(v)
	dirs.pushName("")
	for v in [0, none32, none32, 0x28, none32]:
		dirs.pushU32le(v)
	dirs.pushName("data")
	files = []
	files.pushU32le(0)
	files.pushU32le(none32)
	files.pushU64le(0)
	files.pushU64le(2)
	files.pushU32le(none32)
	files.pushName("a.txt")
	files.pushU32le(0x18)
	files.pushU32le(none32)
	files.pushU64le(2)
	files.pushU64le(3)
	files.pushU32le(none32)
	files.pushName("b.bin")
	head = []
	dirsAt = 0x50
	filesAt = dirsAt + dirs.len
	dataAt = filesAt + files.len
	for v in [0x50, dirsAt, 0, dirsAt, dirs.len, filesAt, 0, filesAt, files.len, dataAt]:
		head.pushU64le(v)
	rom = head
	rom.extend(dirs)
	rom.extend(files)
	rom.extend([7, 7, 9, 9, 9])
	found = package.romFiles((at, n): (0..n).map(rom[at + it]))
	expect found.map(.path) == ["a.txt", "data/b.bin"]
	expect found[1].at == dataAt + 2 and found[1].size == 3

test "an NSO's compressed segment is stored whole where it lies in memory":
	text u8[] = (0..64).map(u8(it % 4))
	packed = lz4.encodeBlock(text)
	nso u8[] = zeros(0x100)
	nso.setU32le(0, 0x304F_534E)   # "NSO0"
	nso.setU32le(0x0C, 1)
	nso.setU32le(0x10, 0x100)
	nso.setU32le(0x14, 0)
	nso.setU32le(0x18, 64)
	for i in 1..3:
		nso.setU32le(0x10 + i * 0x10, u32(0x100 + packed.len))
		nso.setU32le(0x14 + i * 0x10, 0x1000 * i)
	nso.setU32le(0x60, u32(packed.len))
	nso[0x40] = 0xAB
	nso.extend(packed)
	whole = package.decompressNso(nso) ?? []
	expect (package.readNso(nso)?.buildId ?? "").startsWith("ab00")
	expect whole.u32le(0x0C) == 0
	expect whole[0x100..0x140] == text[..64]

test "a BFTTF's words are xored back into the font":
	key = 0x4962_1806
	b = []
	b.pushU32be(0x7F9A_0218 ^ key)
	b.pushU32be(8 ^ key)
	b.pushU32be(0x1111_1111 ^ key)
	b.pushU32be(0x2222_2222 ^ key)
	font = package.decodeBfttf(b) ?? []
	expect font.len == 8 and font.u32le(0) == 0x1111_1111 and font.u32le(4) == 0x2222_2222

test "a font encoded as a BFTTF decodes back, padded to whole words":
	ttf u8[] = [1, 2, 3, 4, 5, 6]
	encoded = package.encodeBfttf(ttf)
	expect encoded.len == 16
	decoded = package.decodeBfttf(encoded) ?? []
	expect decoded == ttf

test "the RomFS image of a dir is walked into its files and reads back their bytes":
	root = "projects/recomp/switch/out/tests/romfsImage"
	_ = fs.deleteTree(root)
	_ = fs.createDir("{root}/data/deep")
	a u8[] = [1, 2, 3]
	_ = fs.writeBytes("{root}/a.txt", a)
	b u8[] = [9, 8, 7, 6, 5]
	_ = fs.writeBytes("{root}/data/b.bin", b)
	c u8[] = [4]
	_ = fs.writeBytes("{root}/data/deep/c.bin", c)
	img = package.buildRomImage(root)
	size = img.romImageSize()
	read = (at i64, n i64): img.readRomImage(at, n)
	found = package.romFiles(read)
	expect found.map(.path) == ["a.txt", "data/b.bin", "data/deep/c.bin"]
	expect read(found[1].at, found[1].size) == b
	expect read(found[2].at, 1) == c
	expect size == found[2].at + 1
