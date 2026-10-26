# Machine-code emission for Windows x86-64: a byte assembler with labels and data references,
# and a writer for a minimal PE executable with kernel32 imports. Byte
# buffers are lists of ints in 0..255.

pub fxLabel = 0
pub fxData = 1
pub fxImport = 2
pub fxTable = 3   # a jump table's entry: a label's distance from the table's (target: label << 32 | table)

pub type Asm:
	code u8[] = []
	data u8[] = []   # literals, descriptors, the runtime's slots, import tables
	bss i64 = 0   # the bytes of zero storage after the data (the module variables), in no file
	labelPos i32[] = []   # label -> code offset, -1 while unknown
	labelJumps i32[] = []   # label -> how many jumps or address loads name it
	fixKind u8[] = []   # fixups: kind, position of the 4-byte field in code, target
	fixAt i32[] = []
	fixTarget i64[] = []
	fixJump u8[] = []   # per fixup: 1 a jmp's, 2 a jcc's (asmRelax may make them short), else 0
	padAt i64[] = []   # where each loop top's padding to 32 bytes starts, and its length
	padLen i64[] = []
	imports str[] = []   # imported function names, in IAT order
	importDlls str[] = []   # the DLL of each import
	lastStoreDisp i64 = 0   # the frame slot rax was just stored to, and the code position
	lastStoreEnd i64 = -1   #   right after that store: a reload of the same slot there is skipped
	lastJmpEnd i64 = -1   # the code position right after the last unconditional jump
	lastJmpTarget i64 = -1   #   and its label: a jump to the label placed there is removed
	endJmpEnd i64 = -1   # the same kept across labels placed there (each lands past the jump)
	endJmpTarget i64 = -1
	endJmpLabels i64[] = []   # the labels placed there so far: they move back with the jump
	lastWidenStart i64 = -1   # cvtss2sd xmm0, xmm0; movq rax, xmm0 just emitted from here to
	lastWidenEnd i64 = -1   #   there: a consumer of the f64 in xmm0 (or of the f32) drops it
	lastLabelEnd i64 = -1   # the code position of the last label placed (a peephole over the
#   previous instruction must not cross it)
	lastRaxFromEnd i64 = -1   # right after `mov rax, R`: a load through rax folds R in
	lastRaxFromReg i64 = -1   #   (R as an x64 register number)
	lastRaxToEnd i64 = -1   # right after `mov R, rax`: a `mov rax, R` there is dropped
	lastRaxToReg i64 = -1
	lastQmovEnd i64 = -1   # right after `movq rax, xmm0` (lastQmovToRax) or `movq xmm0, rax`: the
	lastQmovToRax bool = false   #   move back is dropped (the two registers hold the same bits)
	lastXStoreEnd i64 = -1   # right after `movsd/movss [rbp+disp], xmmX`: a load of that slot there
	lastXStoreDisp i64 = 0   #   is dropped (into xmmX) or becomes a register move
	lastXStoreReg i64 = -1
	lastXStorePfx i64 = 0
	lastAddRcxEnd i64 = -1   # right after `add rax, rcx` making an address: a byte load folds it in
	unwindAt i64[] = []   # where each region of code the unwinder tells apart starts, ascending
	unwindKind i64[] = []   #   and how it keeps the stack: its UNWIND_INFO's index, or unwindLeaf
	# the UNWIND_INFOs (version 1, then the codes): the shared one first, unwindFrame's (rbp
	# pushed at 1 and made the frame at 4), then each frame on rsp, once per distinct one
	# (unwindInfoOf)
	unwindInfos i64[,] = [[1, 4, 2, 5, 4, 3, 1, 0x50]]
	unwindInfoOf {str: i64} = {}
	addresses i64[] = []   # the data's words that hold an address in the image (patchAddress)
	libcNames str[] = []   # the C library's functions the program needs, and the data words
	libcAt i64[] = []   #   the dynamic linker fills with their addresses (ccall.zap, elf.zap)
	labelFloor i64 = 0   # the labels made before the function being emitted, and those of
	placedBelow i64[] = []   #   them it placed (sameCode.zap)
	fnMade i64[] = []   # the functions' labels fnLabel made, in order, and their keys
	fnMadeKeys str[] = []
	regionsNoting bool = false   # while a function's code is kept (keptCode.zap): each region
	regionsNoted i64[] = []   #   asked for, its start and kind

# How a region of code keeps the stack, for the system's unwinder: a frame on rbp (push rbp; mov
# rbp, rsp at its start, rbp the frame from then on: the generated helpers), a frame on rsp of its
# own (asmRspFrame: the functions), or
# nothing (a leaf: its return address on top throughout, which the unwinder assumes of code
# without an entry). The code before the first region (the start's) has no entry either.
pub unwindFrame = 0
pub unwindLeaf = -1

pub fn byteOf(v i64, i i64) i64:
	((v >> (8 * i)) & 255)

pub fn bytesPut32(mut b u8[], v i64):
	for i in 0..4:
		b.push(u8(byteOf(v, i)))

pub fn bytesPut64(mut b u8[], v i64):
	for i in 0..8:
		b.push(u8(byteOf(v, i)))

pub fn bytesPutStr(mut b u8[], s str):
	b.extend(s.bytes())

pub fn bytesAlign(mut b u8[], a i64):
	while b.len % a != 0:
		b.push(0)

pub fn patch32(mut b u8[], at i64, v i64):
	for i in 0..4:
		b[at + i] = u8(byteOf(v, i))

pub fn patch64(mut b u8[], at i64, v i64):
	for i in 0..8:
		b[at + i] = u8(byteOf(v, i))

# the data's word at `at` made the address of rva in the image loaded at its base; a shared
# object, which its loader moves, has it relocated (asmWriteElf)
pub fn patchAddress(mut a Asm, at i64, rva i64):
	patch64(a.data, at, imageBase + rva)
	a.addresses.push(at)

pub fn asmNewLabel(mut a Asm) i64:
	a.labelJumps.push(0)
	a.labelPos.push(-1)
	a.labelPos.len - 1

# the jump just emitted, when it goes to label: dropped with its fixup, the code then falling
# there (the labels placed past it move back with it); whether it was
pub fn asmDropJumpTo(mut a Asm, label i64) bool:
	if a.endJmpEnd != a.code.len or a.endJmpTarget != label or a.fixAt.isEmpty or
		a.fixAt[len - 1] != a.code.len - 4:
		return false
	a.code.truncate(a.code.len - 5)
	a.fixKind.pop()
	a.fixAt.pop()
	a.fixTarget.pop()
	a.fixJump.pop()
	a.labelJumps[label] -= 1
	a.endJmpEnd = -1
	for l in a.endJmpLabels:
		a.labelPos[l] = i32(a.code.len)
	true

pub fn asmPlace(mut a Asm, label i64):
	if not a.asmDropJumpTo(label) and a.endJmpEnd == a.code.len:
		a.endJmpLabels.push(label)
	n = a.code.len
	f = a.fixAt.len
	if a.lastJmpEnd == n and f >= 2 and a.fixAt[f - 1] == n - 4 and a.fixAt[f - 2] == n - 9 and
		a.fixTarget[f - 2] == label and a.fixKind[f - 2] == fxLabel and a.code[n - 11] == 0x0F and
		(a.code[n - 10] & 0xF0) == 0x80 and a.lastLabelEnd != n - 5:
		# `jcc here; jmp M; here:` is `j!cc M`
		a.code.truncate(n - 5)
		a.fixKind.pop()
		a.fixAt.pop()
		a.fixJump.pop()
		target = a.fixTarget.pop() ?? label
		a.code[n - 10] ^= 1
		a.fixTarget[f - 2] = target
		a.labelJumps[label] -= 1
	if label < a.labelFloor:
		a.placedBelow.push(label)
	a.labelPos[label] = i32(a.code.len)
	a.lastStoreEnd = -1   # a jump may land here with another rax
	a.lastJmpEnd = -1
	a.lastLabelEnd = a.code.len

# A label every jump to which is already emitted (the end of an inlined body): when none is
# left after a jump to it falls through, nothing lands here but the code above, so the
# peepholes over the previous instruction stay valid.
pub fn asmPlaceEnd(mut a Asm, label i64):
	saved = a.lastLabelEnd
	a.asmPlace(label)
	if a.labelJumps[label] == 0:
		a.lastLabelEnd = saved

# a region of code from here on, keeping the stack as kind says
pub fn asmUnwindRegion(mut a Asm, kind i64):
	a.asmUnwindRegionAt(a.code.len, kind)

# the same from the code position start (none of the code there yet in a region of its own)
pub fn asmUnwindRegionAt(mut a Asm, start i64, kind i64):
	if a.regionsNoting: a.regionsNoted.extend([start, kind])
	n = a.unwindAt.len
	if n > 0 and a.unwindAt[n - 1] >= start:
		if a.unwindAt[n - 1] > start:
			exit(1, "x64: a region of code before the last one")
		a.unwindKind[n - 1] = kind
		return
	a.unwindAt.push(start)
	a.unwindKind.push(kind)

# The unwind information of a frame on rsp made at the start of a region: the registers pushed
# (x64 numbers), then alloc bytes taken; ends says where each of those instructions ends, from the
# region's start (the allocation's last, when there is one). Its kind for asmUnwindRegion.
pub fn asmRspFrame(mut a Asm, pushed i64[], ends i64[], alloc i64) i64:
	codes = []
	if alloc > 0:
		end = ends[pushed.len]
		if alloc <= 128:
			codes.extend([end, (alloc - 8) / 8 << 4 | 2])   # UWOP_ALLOC_SMALL
		elif alloc < 524_288:
			codes.extend([end, 1, byteOf(alloc / 8, 0), byteOf(alloc / 8, 1)])   # UWOP_ALLOC_LARGE
		else:
			codes.extend([end, 0x11])
			codes.extend((0..4).map(byteOf(alloc, it)))
	i = pushed.len - 1
	while i >= 0:
		codes.extend([ends[i], pushed[i] << 4])   # UWOP_PUSH_NONVOL, the last pushed first
		i -= 1
	count = codes.len / 2
	if count % 2 == 1:
		codes.extend([0, 0])   # the codes take an even count of slots
	info = [1, ends.last ?? 0, count, 0]
	info.extend(codes)
	a.asmUnwindInfo(info)

# the kind of a region whose UNWIND_INFO is info: its index, the info added when new
pub fn asmUnwindInfo(mut a Asm, info i64[]) i64:
	key = unwindInfoKey(info)
	if a.unwindInfoOf.get(key) is k: return k
	a.unwindInfos.push(info.copy())
	a.unwindInfoOf[key] = a.unwindInfos.len - 1
	a.unwindInfos.len - 1

# info's key in unwindInfoOf
pub fn unwindInfoKey(info i64[]) str:
	info.map(str(it)).join(",")

# The exception directory, in the data: the unwind informations, then a RUNTIME_FUNCTION (start,
# end, its unwind information) per region of code but a leaf, which the system's unwinder reads
# (RtlVirtualUnwind: the error traces' walk of the stack). Its offset in the data and its size.
fn asmWriteUnwind(mut a Asm, dataRva i64):
	bytesAlign(a.data, 4)
	infoAt = []
	for info in a.unwindInfos:
		infoAt.push(a.data.len)
		for b in info:
			a.data.push(u8(b))
	at = a.data.len
	for i, start in a.unwindAt:
		end = a.unwindAt[i + 1] if i + 1 < a.unwindAt.len else a.code.len
		if a.unwindKind[i] == unwindLeaf or end == start: continue
		bytesPut32(a.data, sectRva + start)
		bytesPut32(a.data, sectRva + end)
		bytesPut32(a.data, dataRva + infoAt[a.unwindKind[i]])
	(at, a.data.len - at)

# The fixups at the places in keep (ascending) kept, each at its new code position in at (indexed
# like the fixups were).
fn keepFixups(mut a Asm, keep i64[], at i32[]):
	kinds = (0..keep.len).parallel().map(k: a.fixKind[keep[k]])
	places = (0..keep.len).parallel().map(k: at[keep[k]])
	targets = (0..keep.len).parallel().map(k: a.fixTarget[keep[k]])
	jumps = (0..keep.len).parallel().map(k: a.fixJump[keep[k]])
	a.fixKind = kinds
	a.fixAt = places
	a.fixTarget = targets
	a.fixJump = jumps

fn addFix(mut a Asm, kind i64, target i64):
	a.fixKind.push(u8(kind))
	a.fixAt.push(i32(a.code.len))
	a.fixTarget.push(target)
	a.fixJump.push(0)
	bytesPut32(a.code, 0)

# n bytes of NOPs at the end of code, as few instructions as fit
pub fn nopsInto(mut code u8[], n i64):
	left = n
	while left > 0:
		k = left.min(9)
		code.extend(nopsOf[k - 1])
		left -= k

nopsOf u8[,] = [
	[0x90],
	[0x66, 0x90],
	[0x0F, 0x1F, 0x00],
	[0x0F, 0x1F, 0x40, 0x00],
	[0x0F, 0x1F, 0x44, 0x00, 0x00],
	[0x66, 0x0F, 0x1F, 0x44, 0x00, 0x00],
	[0x0F, 0x1F, 0x80, 0x00, 0x00, 0x00, 0x00],
	[0x0F, 0x1F, 0x84, 0x00, 0x00, 0x00, 0x00, 0x00],
	[0x66, 0x0F, 0x1F, 0x84, 0x00, 0x00, 0x00, 0x00, 0x00]]

# Emits a rel32 field referring to a label (the opcode bytes go first).
pub fn asmRel32Label(mut a Asm, label i64):
	a.labelJumps[label] += 1
	a.addFix(fxLabel, label)

# a jump table's entry here: the distance of label from the table's label
pub fn asmTableEntry(mut a Asm, label i64, table i64):
	a.labelJumps[label] += 1
	a.addFix(fxTable, label << 32 | table)

# Emits a disp32 field referring to the data area at the given offset (RIP-relative).
pub fn asmDisp32Data(mut a Asm, dataOffset i64):
	a.addFix(fxData, dataOffset)

# Returns the IAT slot index of an import, registering it on first use.
pub fn asmImport(mut a Asm, dll str, name str) i64:
	i = a.imports.indexOf(name) ?? -1
	if i >= 0: return i
	a.imports.push(name.copy())   # the table keeps its own names, once each
	a.importDlls.push(dll.copy())
	a.imports.len - 1

# Emits a disp32 field referring to the IAT slot of an import (RIP-relative).
pub fn asmDisp32Import(mut a Asm, slot i64):
	a.addFix(fxImport, slot)

# a memory operand's base that is rip: its displacement a data offset (the instruction must end
# with it, no immediate after)
pub ripBase = -2

# a data offset from here on names the zero storage after the data (asmBssZero)
pub bssBase = 1 << 30

# n bytes of zero storage, 8-aligned, placed after the initialized data: memory the file holds no
# bytes for (the loader zeroes it); its data offset, from bssBase
pub fn asmBssZero(mut a Asm, n i64) i64:
	a.bss = a.bss.alignUp(8)
	off = bssBase + a.bss
	a.bss += n
	off

# Data helpers: append bytes to the data area and return their offset.
pub fn asmDataZero(mut a Asm, n i64) i64:
	off = a.data.len
	a.data.extend(zeros(n))
	off

sectRva = 4096
fileAlign = 512
sectAlign = 4096

# Resolves fixups, builds the import tables and writes the PE file. `entryLabel` is the code
# label where execution starts. Two sections: .text (code, RX) at RVA 0x1000 and .data
# (literals, globals, imports, RW). Image base 0x140000000, no relocations, console
# subsystem, 64 MB of stack. The data word at variablesSlot is given the address of the zero
# storage (the module variables). Returns false if the file could not be written.
pub fn asmWritePe(mut a Asm, path str, entryLabel i64, variablesSlot i64) bool:
	codeLen = a.code.len
	dataRva = (sectRva + codeLen).alignUp(sectAlign)
	unwindAt, unwindSize = a.asmWriteUnwind(dataRva)
	bytesAlign(a.data, 16)
	n = a.imports.len
	# the DLLs in order of first use; each gets a descriptor, an INT and an IAT (the IATs are
	# contiguous so one directory entry covers them), each as the index of its first use in
	# a.importDlls
	dlls = (0..a.importDlls.len).filter((a.importDlls.indexOf(a.importDlls[it]) ?? -1) == it)
	descOff = a.data.len
	intOff = descOff + 20 * (dlls.len + 1)
	iatOff = intOff + 8 * (n + dlls.len)
	namesOff = iatOff + 8 * (n + dlls.len)
	names = []
	dllNameOff = []
	for d in dlls:
		dllNameOff.push(names.len)
		bytesPutStr(names, a.importDlls[d])
		names.push(0)
	nameOff = []
	for i in 0..n:
		bytesAlign(names, 2)
		nameOff.push(names.len)
		names.push(0)
		names.push(0)
		bytesPutStr(names, a.imports[i])
		names.push(0)
	importBlockLen = namesOff - descOff + names.len
	a.asmDataZero(importBlockLen)
	for i, name in names:
		a.data[namesOff + i] = name
	# the IAT slot (offset within data) of each import, laid out DLL by DLL
	iatSlot i64[] = zeros(n)

	codeRva = sectRva
	codeRaw = codeLen.alignUp(fileAlign)
	dataLen = a.data.len
	dataRaw = dataLen.alignUp(fileAlign)
	bssAt = dataLen.alignUp(16)   # the zero storage, in memory only
	dataSize = bssAt + a.bss if a.bss > 0 else dataLen
	a.patchAddress(variablesSlot, dataRva + bssAt)
	rva0 = dataRva
	intPos = intOff
	iatPos = iatOff
	for di, dll in dlls:
		patch32(a.data, descOff + 20 * di, rva0 + intPos)
		patch32(a.data, descOff + 20 * di + 12, rva0 + namesOff + dllNameOff[di])
		patch32(a.data, descOff + 20 * di + 16, rva0 + iatPos)
		for i in 0..n:
			if a.importDlls[i] != a.importDlls[dll]: continue
			entry = rva0 + namesOff + nameOff[i]
			patch64(a.data, intPos, entry)
			patch64(a.data, iatPos, entry)
			iatSlot[i] = iatPos
			intPos += 8
			iatPos += 8
		intPos += 8   # the terminators
		iatPos += 8

	a.asmWriteFixups(codeRva, dataRva, bssAt, iatSlot)

	entryRva = codeRva + a.labelPos[entryLabel]
	importDirRva = rva0 + descOff
	iatRva = rva0 + iatOff
	iatSize = 8 * (n + dlls.len)
	sizeOfHeaders = fileAlign

	f u8[] = asmWritePeHeader(
		a.bss,
		codeLen,
		codeRva,
		codeRaw,
		dataRva,
		dataRaw,
		dataSize,
		entryRva,
		importDirRva,
		dlls.len,
		unwindAt,
		unwindSize,
		iatRva,
		iatSize,
		sizeOfHeaders
	)
	while f.len < sizeOfHeaders:
		f.push(0)
	f.extend(a.code)
	while f.len < sizeOfHeaders + codeRaw:
		f.push(204)   # int3 padding
	f.extend(a.data)
	while f.len < sizeOfHeaders + codeRaw + dataRaw:
		f.push(0)
	writeExecutable(path, f)

fn asmWriteFixups(mut a Asm, codeRva i64, dataRva i64, bssAt i64, iatSlot i64[]):
	# resolve fixups: rel32 within the code, RIP-relative into the data section
	for i, kind in a.fixKind:
		at = a.fixAt[i]
		target = a.fixTarget[i]
		dest = 0
		if kind == fxTable:
			patch32(a.code, at, a.labelPos[target >> 32] - a.labelPos[target & 0xFFFF_FFFF])
			continue
		if kind == fxLabel:
			if a.labelPos[target] < 0:
				exit(1, "x64: unplaced label {target}")
			dest = codeRva + a.labelPos[target]
		elif kind == fxData:
			dest = dataRva + (bssAt + target - bssBase if target >= bssBase else target)
		else:
			dest = dataRva + iatSlot[target]
		rel = dest - (codeRva + at + 4)
		patch32(a.code, at, rel)

fn asmWritePeHeader(
	bss i64,
	codeLen i64,
	codeRva i64,
	codeRaw i64,
	dataRva i64,
	dataRaw i64,
	dataSize i64,
	entryRva i64,
	importDirRva i64,
	dllCount i64,
	unwindAt i64,
	unwindSize i64,
	iatRva i64,
	iatSize i64,
	sizeOfHeaders i64
):
	f u8[] = []
	f.push(77)   # 'M'
	f.push(90)   # 'Z'
	f.extend(zeros(58))   # the rest of the DOS header, up to e_lfanew
	bytesPut32(f, 64)   # e_lfanew
	bytesPutStr(f, "PE")
	f.push(0)
	f.push(0)
	bytesPut32(f, 34_404 + 2 * 65_536)   # Machine x64, NumberOfSections 2
	bytesPut32(f, 0)   # TimeDateStamp
	bytesPut32(f, 0)
	bytesPut32(f, 0)   # symbol table
	bytesPut32(f, 240 + 34 * 65_536)   # SizeOfOptionalHeader, Characteristics 0x0022
	bytesPut32(f, 523 + 14 * 65_536)   # PE32+, linker 14.0
	bytesPut32(f, codeRaw)   # SizeOfCode
	bytesPut32(f, dataRaw)   # SizeOfInitializedData
	bytesPut32(f, bss.alignUp(fileAlign))   # SizeOfUninitializedData
	bytesPut32(f, entryRva)
	bytesPut32(f, codeRva)   # BaseOfCode
	bytesPut64(f, imageBase)
	bytesPut32(f, sectAlign)
	bytesPut32(f, fileAlign)
	bytesPut32(f, 6)   # OS version 6.0
	bytesPut32(f, 0)   # image version
	bytesPut32(f, 6)   # subsystem version 6.0
	bytesPut32(f, 0)   # Win32VersionValue
	bytesPut32(f, (dataRva + dataSize).alignUp(sectAlign))   # SizeOfImage
	bytesPut32(f, sizeOfHeaders)
	bytesPut32(f, 0)   # CheckSum
	bytesPut32(f, 3 + 33_024 * 65_536)   # console; DllCharacteristics NX_COMPAT | TERMINAL_SERVER_AWARE
	bytesPut64(f, 67_108_864)   # stack reserve 64 MB
	bytesPut64(f, 1_048_576)   # stack commit
	bytesPut64(f, 1_048_576)   # heap reserve
	bytesPut64(f, 4096)   # heap commit
	bytesPut32(f, 0)   # LoaderFlags
	bytesPut32(f, 16)   # NumberOfRvaAndSizes
	for i in 0..16:
		if i == 1:
			bytesPut32(f, importDirRva)
			bytesPut32(f, 20 * (dllCount + 1))
		elif i == 3:
			bytesPut32(f, dataRva + unwindAt)
			bytesPut32(f, unwindSize)
		elif i == 12:
			bytesPut32(f, iatRva)
			bytesPut32(f, iatSize)
		else:
			bytesPut32(f, 0)
			bytesPut32(f, 0)
	bytesPutStr(f, ".text")
	f.extend(zeros(3))
	bytesPut32(f, codeLen)
	bytesPut32(f, codeRva)
	bytesPut32(f, codeRaw)
	bytesPut32(f, sizeOfHeaders)
	bytesPut32(f, 0)
	bytesPut32(f, 0)
	bytesPut32(f, 0)
	bytesPut32(f, 1_610_612_768)   # CODE | EXECUTE | READ
	bytesPutStr(f, ".data")
	f.extend(zeros(3))
	bytesPut32(f, dataSize)   # VirtualSize: the zero storage past the file's bytes
	bytesPut32(f, dataRva)
	bytesPut32(f, dataRaw)
	bytesPut32(f, sizeOfHeaders + codeRaw)
	bytesPut32(f, 0)
	bytesPut32(f, 0)
	bytesPut32(f, 0)
	bytesPut32(f, 3_221_225_536)   # INITIALIZED_DATA | READ | WRITE
	f
