# NCA3, the content archive: a 0xC00-byte header sealed in XTS by the console's header key
# (sectors of 0x200, Nintendo's big-endian tweak), then up to four sections (an ExeFS or a
# control's PFS0, a RomFS), each sealed in CTR by a key from the header's key area or, for a
# title with rights, by the title key. The header's fields at switchbrew.org/wiki/NCA.

import cipher
import fs

headerSize = 0xC00
mediaUnit = 0x200

# the header's content types (0x205)
pub contentProgram = 0
pub contentMeta = 1
pub contentControl = 2
pub contentData = 4

pub type Section:
	index i64
	at i64   # from the NCA's start
	size i64
	isPfs bool   # else a RomFS
	encrypted bool
	counter u8[]   # the CTR counter's upper 8 bytes
	dataAt i64   # where the PFS0 or the RomFS's level 3 starts, from the section's start
	dataSize i64

# An NCA opened in a file: its header's fields and its sections, and the key that opens them.
pub type Nca:
	file fs.File
	base i64   # where the NCA starts in the file
	content i64
	titleId u64
	generation i64
	rightsId str   # 32 hex digits, "" when the NCA has no rights
	key u8[]   # the CTR key of the sections
	sections Section[] = []

	# n bytes at `at` of a section, decrypted
	fn read(s Section, at i64, n i64):
		start = s.at + at
		aligned = start - start % 16
		raw = file.readAt(base + aligned, n + start - aligned) ?? return []
		if s.encrypted:
			counter u8[] = s.counter.copy()
			counter.pushU64be(aligned / 16)
			aes = cipher.aes128(key)
			aes.ctrInPlace(raw, counter)
		raw[start - aligned..].copy()

	# n bytes at `at` of a section's PFS0 or RomFS
	fn readData(s Section, at i64, n i64):
		read(s, s.dataAt + at, n)

	# the first section that is a PFS0 (an ExeFS, a control's or a meta's files)
	fn pfsSection() Section?:
		for s in sections:
			if s.isPfs: return s.copy()
		none

	# the first section that is a RomFS
	fn romSection() Section?:
		for s in sections:
			if not s.isPfs: return s.copy()
		none

# the header's 0xC00 bytes, decrypted
fn openHeader(file fs.File, base i64, keys Keys) u8[] ? str:
	sealed = file.readAt(base, headerSize) ?? return "the NCA at {base} is cut short"
	key = try keys.get("header_key")
	cipher.decryptXts(key, sealed, 0, mediaUnit)

# the key generation's index of a master key (generations 0 and 1 both use the first)
fn masterIndex(header u8[]):
	gen = i64(header[0x206]).max(i64(header[0x220]))
	(gen - 1).max(0)

# the CTR key: the title key when the NCA has rights, else the key area's third key unwrapped by
# its key area key
fn sectionKey(header u8[], keys Keys, rightsId str, gen i64) u8[] ? str:
	if rightsId != "":
		return (keys.titles.get(rightsId) ?? return "no title key for rights id {rightsId}: dump title.keys with Lockpick_RCM, or keep the NSP's ticket").copy()
	kind = ["application", "ocean", "system"][i64(header[0x207]).min(2)]
	kek = try keys.get("key_area_key_{kind}_{generationName(gen)}")
	area = cipher.aes128(kek).decryptEcb(header[0x300..0x340].copy())
	area[0x20..0x30].copy()

# a section's place, kind and counter from its entry and its 0x200-byte header
fn readSection(header u8[], i i64) Section?:
	entry = 0x240 + i * 16
	start = i64(header.u32le(entry)) * mediaUnit
	end = i64(header.u32le(entry + 4)) * mediaUnit
	if end <= start: return none
	fsh = 0x400 + i * 0x200
	isPfs = header[fsh + 2] == 1
	counter u8[] = (0..8).map(header[fsh + 0x147 - it])
	dataAt = 0
	dataSize = end - start
	if isPfs:
		dataAt = i64(header.u64le(fsh + 0x40))
		dataSize = i64(header.u64le(fsh + 0x48))
	elif header.matchesAt(fsh + 8, "IVFC"):
		level = fsh + 0x18 + 5 * 0x18
		dataAt = i64(header.u64le(level))
		dataSize = i64(header.u64le(level + 8))
	Section(
		index = i,
		at = start,
		size = end - start,
		isPfs,
		encrypted = header[fsh + 4] == 3,
		counter,
		dataAt,
		dataSize
	)

# The NCA at `base` in the file, opened with the keys; why not, when it cannot be.
pub fn openNca(move file fs.File, base i64, keys Keys) Nca ? str:
	header = try file.openHeader(base, keys)
	if not header.matchesAt(0x200, "NCA3"):
		return "the NCA at {base} is not NCA3 (wrong header_key?)"
	rights = header[0x230..0x240].copy()
	rightsId = "" if rights.all(it == 0) else rights.map("{it:02x}").join("")
	gen = masterIndex(header)
	key = try sectionKey(header, keys, rightsId, gen)
	sections = []
	for i in 0..4:
		if readSection(header, i) is s: sections.push(s)
	Nca(
		file,
		base,
		content = header[0x205],
		titleId = header.u64le(0x210),
		generation = gen,
		rightsId,
		key,
		sections
	)

# The files of a section that is a PFS0.
pub fn sectionFiles(nca Nca, s Section) Entry[]:
	first = nca.readData(s, 0, 16)
	if first.len < 16: return []
	head = nca.readData(s, 0, pfsHeaderSize(first))
	readPfs(head, 0) ?? []
