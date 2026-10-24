# The executable of Linux, on x64 or arm64: a static ELF that needs no loader, no library and no
# linker (but for a program that calls a library's functions, below). Laid out as the PE is (asmWritePe), so the runtime's image base and the debug table hold
# for all: the headers and the code from imageBase (read, execute), the code at imageBase +
# sectRva; the data and after it the zero storage at imageBase + dataRva (read, write). The data's
# bytes follow the code's in the file at a 4 KB page (dataFileOffsetOf), and dataRva is 64 KB past
# them: a segment's place and its file offset agree to 64 KB, so the pages of any kernel (4, 16 or
# 64 KB) map it, and no page holds both the code and the data. x64's carries the unwind
# tables the PE has (asmWriteUnwind), their place in the runtime's slots 7 and 8, for its walk of
# the stack (runtime/core/linux/x64/).
#
# A loadable build (loadable.zap) is the same image, mapped by the program that loads it.
#
# An Android app's program (appBuild) is the same image as a shared object its process's loader
# places anywhere: the code reaches the data and itself by distance alone, so what moves is the
# data's words that hold an address (Asm.addresses, the image's own place among them in slot 11),
# each a relative relocation. Its tables ride in the headers' page: the one symbol it exports (the
# entry, ANativeActivity_onCreate), its hash, the relocations and the dynamic section, which
# Android's loader finds through the section headers at the file's end.
#
# A program that calls a C library's functions (ccall.zap) is dynamically linked instead: its
# interpreter, the C library as its one needed library, and the symbols it takes from it (dlopen
# and dlsym, which load the others when the program runs), each a relocation of the data word the
# stubs read. The tables ride in the headers' page as an app's do.

import fs

elfAlign = 65_536

# where the data starts in the file, after code of codeLen bytes
fn dataFileOffsetOf(codeLen i64):
	(sectRva + codeLen).alignUp(sectAlign)

# where the data starts in the image, after code of codeLen bytes
fn dataRvaOf(codeLen i64):
	dataFileOffsetOf(codeLen) + (elfAlign if onLinux() else 0)

# the runtime's slots that hold the place of x64's unwind table and its count of entries, and an
# app's image's place (runtime/core/linux/app/)
unwindTableSlot = 7
unwindCountSlot = 8
imageBaseSlot = 11

# The code's fixups resolved and the file written, execution starting at entryLabel (the globals
# at the data's offset globals); false when the file could not be written.
fn asmWriteElf(mut a Asm, path str, entryLabel i64, globals i64):
	dataRva = dataRvaOf(a.code.len)
	if not onArm():
		at, size = a.asmWriteUnwind(dataRva)
		a.patchAddress(globals + unwindTableSlot * 8, dataRva + at)
		patch64(a.data, globals + unwindCountSlot * 8, size / 12)
	if appBuild:
		a.patchAddress(globals + imageBaseSlot * 8, 0)
	bytesAlign(a.data, 16)
	bssAt = a.data.len.alignUp(16)
	a.patchAddress(globals + moduleVariablesSlot * 8, dataRva + bssAt)
	if onArm():
		for i, kind in a.fixKind:
			a.a64Resolve(kind, a.fixAt[i], a.fixTarget[i], dataRva, bssAt)
	else:
		a.asmWriteFixups(sectRva, dataRva, bssAt, [])
	entry = imageBase + sectRva + a.labelPos[entryLabel]
	at = dataFileOffsetOf(a.code.len)
	tables = DynamicTables()
	if loadableBuild:
		pass   # (mapped by the program that loads it, not by the system)
	elif appBuild:
		tables = a.dynamicTables(entry, dataRva)
	elif not a.libcNames.isEmpty:
		tables = a.loaderTables(dataRva)
	f = []
	headers = 3 + (0 if tables.dynamic.isEmpty else 1) + (0 if tables.interp.isEmpty else 1)
	elfHeader(f, entry, tables.sections.len / 64, headers)
	if not tables.interp.isEmpty:
		size = tables.interp.len
		elfSegment(f, 3, 4, tables.interpAt, imageBase + tables.interpAt, size, size)   # PT_INTERP
	elfSegment(f, 1, 5, 0, imageBase, sectRva + a.code.len, sectRva + a.code.len)   # PT_LOAD, R X
	elfSegment(f, 1, 6, at, imageBase + dataRva, a.data.len, bssAt + a.bss)   # PT_LOAD, R W
	if not tables.dynamic.isEmpty:
		dynamicAt = tables.dynamicAt
		size = tables.dynamic.len
		elfSegment(f, 2, 4, dynamicAt, imageBase + dynamicAt, size, size)   # PT_DYNAMIC
	elfSegment(f, 1_685_382_481, 6, 0, 0, 0, 0)   # PT_GNU_STACK: not executable
	f.extend(tables.headed)
	f.extend(zeros(sectRva - f.len))
	f.extend(a.code)
	f.extend(zeros(at - f.len))
	f.extend(a.data)
	if not tables.sections.isEmpty:
		f.extend(zeros(f.len.alignUp(8) - f.len))
		patch64(f, 40, f.len)   # e_shoff
		f.extend(tables.sections)
		f.extend(tables.names)
	writeExecutable(path, f) and (appBuild or loadableBuild or fs.canRun(path))

# the ELF header of a 64-bit little-endian executable for the machine, phnum program headers
# after it; of a shared object (sections > 0, the last its names), and its section headers
fn elfHeader(mut f u8[], entry i64, sections i64, phnum i64):
	f.extend([0x7F, 0x45, 0x4C, 0x46, 2, 1, 1, 0])   # "\x7fELF", 64 bits, little-endian, version 1
	f.extend(zeros(8))
	kind = 3 if sections > 0 else 2   # ET_DYN or ET_EXEC
	bytesPut32(f, kind + (183 if onArm() else 62) * 65_536)   # EM_AARCH64 or EM_X86_64
	bytesPut32(f, 1)   # e_version
	bytesPut64(f, entry)
	bytesPut64(f, 64)   # e_phoff: right after this header
	bytesPut64(f, 0)   # e_shoff: none, or set once the file is laid out
	bytesPut32(f, 0)   # e_flags
	bytesPut32(f, 64 + 56 * 65_536)   # e_ehsize, e_phentsize
	if sections == 0:
		bytesPut32(f, phnum)   # e_phnum, e_shentsize 0
		bytesPut32(f, 0)   # e_shnum, e_shstrndx
		return
	bytesPut32(f, phnum + 64 * 65_536)   # e_phnum, e_shentsize
	bytesPut32(f, sections + (sections - 1) * 65_536)   # e_shnum, e_shstrndx

fn elfSegment(mut f u8[], kind i64, flags i64, offset i64, vaddr i64, fileSize i64, memSize i64):
	bytesPut32(f, kind)
	bytesPut32(f, flags)
	bytesPut64(f, offset)
	bytesPut64(f, vaddr)
	bytesPut64(f, vaddr)
	bytesPut64(f, fileSize)
	bytesPut64(f, memSize)
	bytesPut64(f, elfAlign if kind == 1 else 16)

# A shared object's tables: the bytes after its program headers (headed: the symbols, their
# names, the hash, the relocations, then the dynamic section at dynamicAt), and its section
# headers and their names, which follow the image in the file
type DynamicTables:
	interp u8[] = []   # a dynamic executable's interpreter, at interpAt in the file
	interpAt i64 = 0
	headed u8[] = []
	dynamic u8[] = []
	dynamicAt i64 = 0
	sections u8[] = []
	names u8[] = []

# where a shared object's tables start: past the ELF header and its four program headers
dynamicTablesAt = 64 + 4 * 56

# the program headers a dynamic executable has: the interpreter's, two to load, the dynamic section
# and the stack's
loaderTablesAt = 64 + 5 * 56

# the interpreter that loads the C library, and the libraries a program needs for dlopen: glibc's
# (the libdl one is where glibc before 2.34 keeps it)
fn loaderInterpreter():
	"/lib/ld-linux-aarch64.so.1" if onArm() else "/lib64/ld-linux-x86-64.so.2"

neededLibraries = ["libdl.so.2", "libc.so.6"]

# the names put in the string table, ended by zeros; where each starts
fn putNames(mut names u8[], put str[]):
	at = []
	for name in put:
		at.push(names.len)
		bytesPutStr(names, name)
		names.push(0)
	at

# The C library's functions the program calls (a.libcNames), each an undefined symbol (numbered
# from first) and a relocation that writes its address in the data word its stubs read (a.libcAt)
fn putImports(
	a Asm,
	mut symbols u8[],
	mut names u8[],
	mut relocations u8[],
	first i64,
	dataRva i64
):
	glob = 1025 if onArm() else 6   # R_AARCH64_GLOB_DAT, R_X86_64_GLOB_DAT
	for i, name in a.libcNames:
		bytesPut32(symbols, names.len)
		bytesPut32(symbols, 0x12)   # STB_GLOBAL, STT_FUNC; undefined
		bytesPut64(symbols, 0)
		bytesPut64(symbols, 0)
		bytesPutStr(names, name)
		names.push(0)
		bytesPut64(relocations, imageBase + dataRva + a.libcAt[i])
		bytesPut64(relocations, (first + i) << 32 | glob)
		bytesPut64(relocations, 0)

# The tables of a dynamic executable whose data is at dataRva: its interpreter, an undefined symbol
# for each C library function the program needs (a.libcNames) with a relocation that writes its
# address in the data word the stubs read (a.libcAt), and the dynamic section that names them.
fn loaderTables(a Asm, dataRva i64):
	t = DynamicTables()
	t.interp.extend(loaderInterpreter().bytes())
	t.interp.push(0)
	symbols u8[] = zeros(24)
	names u8[] = [0]
	needed = putNames(names, neededLibraries)
	relocations = []
	a.putImports(symbols, names, relocations, 1, dataRva)
	hash = []
	for word in [1, a.libcNames.len + 1, 0]:   # one bucket, empty: the executable defines none
		bytesPut32(hash, word)
	loop a.libcNames.len + 1:
		bytesPut32(hash, 0)
	relocationBytes = relocations.len
	nameBytes = names.len
	parts = [symbols, names, hash, relocations]
	places = []
	t.interpAt = loaderTablesAt
	t.headed.extend(t.interp)
	for part in parts:
		bytesAlign(t.headed, 8)
		places.push(loaderTablesAt + t.headed.len)
		t.headed.extend(part)
	bytesAlign(t.headed, 16)
	t.dynamicAt = loaderTablesAt + t.headed.len
	entries = []
	for at in needed:
		entries.push((1, at))   # DT_NEEDED
	entries.extend(
		[
			(4, imageBase + places[2]),   # DT_HASH
			(5, imageBase + places[1]),   # DT_STRTAB
			(6, imageBase + places[0]),   # DT_SYMTAB
			(7, imageBase + places[3]),   # DT_RELA
			(8, relocationBytes),   # DT_RELASZ
			(9, 24),   # DT_RELAENT
			(10, nameBytes),   # DT_STRSZ
			(11, 24),   # DT_SYMENT
			(0, 0)   # DT_NULL
		]
	)
	for (tag, value) in entries:
		bytesPut64(t.dynamic, tag)
		bytesPut64(t.dynamic, value)
	t.headed.extend(t.dynamic)
	t

# the symbol an Android app's program exports, and the name its loader knows it by
appEntrySymbol = "ANativeActivity_onCreate"
appLibrary = "libmain.so"

# the libraries an app's program needs when it calls a C library's functions: bionic's, whose
# dlopen and dlsym load the others (the system's libandroid.so...)
appNeededLibraries = ["libdl.so", "libc.so"]

# The tables of the app's program whose entry is at the address entry, its data at dataRva: the
# entry exported, the C library's functions it calls imported (a.libcNames, as a dynamic
# executable's, each a relocation of the data word its stubs read), and the relative relocations
# of the data's addresses
fn dynamicTables(a Asm, entry i64, dataRva i64):
	t = DynamicTables()
	symbols u8[] = zeros(24)
	bytesPut32(symbols, 1)   # st_name: the entry's, after the names' first zero
	bytesPut32(symbols, 0x12 + 1 * 65_536)   # STB_GLOBAL, STT_FUNC; in section 1, the code
	bytesPut64(symbols, entry)
	bytesPut64(symbols, 0)   # st_size
	names u8[] = [0]
	bytesPutStr(names, appEntrySymbol)
	names.push(0)
	soname = names.len
	bytesPutStr(names, appLibrary)
	names.push(0)
	needed = putNames(names, [] if a.libcNames.isEmpty else appNeededLibraries)
	relocations = []
	a.putImports(symbols, names, relocations, 2, dataRva)
	count = 2 + a.libcNames.len
	hash = []
	for word in [1, count, 1]:   # one bucket, holding the entry; no chain (the imports are found by name)
		bytesPut32(hash, word)
	loop count:
		bytesPut32(hash, 0)
	relative = 1027 if onArm() else 8   # R_AARCH64_RELATIVE, R_X86_64_RELATIVE
	for at in a.addresses:
		bytesPut64(relocations, imageBase + dataRva + at)
		bytesPut64(relocations, relative)
		bytesPut64(relocations, a.data.i64le(at))
	sizes = [symbols.len, names.len, hash.len, relocations.len]
	parts = [symbols, names, hash, relocations]
	places = []
	for part in parts:
		bytesAlign(t.headed, 8)
		places.push(dynamicTablesAt + t.headed.len)
		t.headed.extend(part)
	bytesAlign(t.headed, 16)   # (as its program header says)
	t.dynamicAt = dynamicTablesAt + t.headed.len
	entries = [
		(4, imageBase + places[2]),   # DT_HASH
		(5, imageBase + places[1]),   # DT_STRTAB
		(6, imageBase + places[0]),   # DT_SYMTAB
		(7, imageBase + places[3]),   # DT_RELA
		(8, sizes[3]),   # DT_RELASZ
		(9, 24),   # DT_RELAENT
		(10, sizes[1]),   # DT_STRSZ
		(11, 24),   # DT_SYMENT
		(14, soname),   # DT_SONAME
		(0, 0)   # DT_NULL
	]
	for at in needed.reversed():
		entries.insert(0, (1, at))   # DT_NEEDED
	for (tag, value) in entries:
		bytesPut64(t.dynamic, tag)
		bytesPut64(t.dynamic, value)
	t.headed.extend(t.dynamic)
	t.appendSections(a, places, sizes, dataRva)
	t

# the section headers (the one its loader reads is the dynamic section, its names' link): the code,
# the tables at places of their sizes, the data, then the headers' own names, after them in the file
fn appendSections(mut t DynamicTables, a Asm, places i64[], sizes i64[], dataRva i64):
	dataAt = dataFileOffsetOf(a.code.len)
	t.section("", 0, 0, 0, 0, 0, 0)
	t.section(".text", 1, 6, sectRva, sectRva, a.code.len, 0)
	t.section(".dynsym", 11, 2, places[0], places[0], sizes[0], 3 + 1 * 65_536)
	t.section(".dynstr", 3, 2, places[1], places[1], sizes[1], 0)
	t.section(".hash", 5, 2, places[2], places[2], sizes[2], 2)
	t.section(".rela.dyn", 4, 2, places[3], places[3], sizes[3], 2)
	t.section(".dynamic", 6, 2, t.dynamicAt, t.dynamicAt, t.dynamic.len, 3)
	t.section(".data", 1, 3, dataRva, dataAt, a.data.len, 0)
	namesAt = (dataAt + a.data.len).alignUp(8) + 9 * 64
	t.section(".shstrtab", 3, 0, -1, namesAt, t.names.len + 10, 0)

# a section header: its name, type and flags, its place in the image (rva; -1 none) and in the
# file, its size, and its link and info (info in the high half); a table's entries have the size
# of its type's
fn section(mut t DynamicTables, name str, kind i64, flags i64, rva i64, at i64, size i64, link i64):
	bytesPut32(t.sections, t.names.len)
	t.names.extend(name.bytes())
	t.names.push(0)
	bytesPut32(t.sections, kind)
	bytesPut64(t.sections, flags)
	bytesPut64(t.sections, 0 if rva <= 0 else imageBase + rva)
	bytesPut64(t.sections, at)
	bytesPut64(t.sections, size)
	bytesPut64(t.sections, link)   # sh_link, sh_info
	bytesPut64(t.sections, 1 if kind == 3 else 16 if kind == 1 else 8)   # sh_addralign
	entry = match kind:
		11, 4: 24   # a symbol, a relocation
		5: 4   # a hash's word
		6: 16   # a dynamic entry
		_: 0
	bytesPut64(t.sections, entry)
