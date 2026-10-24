# Builds loaded into the running program (`zap build --loadable`, spec 13.1): another build of
# some of the program's modules and more code beside them, mapped next to the program, its
# references to the state led to the program's variables of the same names (the table its build
# wrote), so its code reads and changes the program's module variables; then its main runs once,
# called as a function value is. A program too large to build at once is built as several such
# builds. The image is Windows' PE here, Linux's ELF in linux/loaded.zap.

extern fn LoadLibraryA(name u8[]) i64
extern fn GetProcAddress(module i64, name u8[]) i64
extern fn RtlAddFunctionTable(table i64, count i64, base i64) bool
extern fn FlushInstructionCache(process i64, base i64, size i64) bool
extern fn GetCurrentProcess() i64
extern fn VirtualProtect(addr i64, size i64, protect i64, out old u32) bool

# The build whose executable is at path (its .load file beside it) loaded and its main run; why
# not when it cannot be.
pub fn loadBuild(path str) ? str:
	image = readFile(path) ?? return "cannot read {path}"
	info = readFile("{path}.load") ?? return "cannot read {path}.load"
	p = sPtr(info)
	if info.len < 16 or not info.startsWith("ZLOD"): return "{path}.load is no loadable build's"
	tableLen = __ld32(p + 8)
	if info.len < 16 + tableLen: return "{path}.load is cut short"
	places = try reachedPlaces(path, info[12..12 + tableLen])
	at = p + 12 + tableLen
	count = __ld32(at)
	if info.len < 16 + tableLen + count * 16: return "{path}.load is cut short"
	base, size = mappedImage(image)
	if base == 0: return "no room for {path} within reach of the program"
	for k in 0..count:
		reference = at + 4 + k * 16
		v = __ld32(reference + 8)
		state = __globals() + __ld32(reference + 12) if v == 0xFFFF_FFFF
			else places[v] + __ld32(reference + 12)
		if not leadTo(base + __ld32(reference), __ld32(reference + 4), state):
			return "{path} lies out of reach of the state"
	try boundLibrary(path, info, 16 + tableLen + count * 16, base)
	makeRunnable(base, size)
	main = zeroBytes(16)   # a function value: its code, no environment
	__st64(__ld64(__addr(main)), base + __ld32(p + 4))
	__callRec(__ld64(__addr(main)))

# The words of the C library's functions a loaded build calls (its .load file's last list, from
# `at`) given their addresses; why not when it is cut short or the program cannot find one.
fn boundLibrary(path str, info str, at i64, base i64) ? str:
	if info.len < at + 4: return "{path}.load is cut short"
	p = sPtr(info)
	next = at + 4
	loop __ld32(p + at):
		if info.len < next + 8 or info.len < next + 8 + __ld32(p + next + 4):
			return "{path}.load is cut short"
		name = info[next + 8..next + 8 + __ld32(p + next + 4)]
		if not bindLibrary(base + __ld32(p + next), name):
			return "{path} calls {name}, which this program cannot find"
		next += 8 + name.len

# the word at the address of the C library's function name (a Linux build's; Windows' imports
# are its PE's): Linux's static program has none, an app finds it in its process
fn bindLibrary(word i64, name str) bool:
	_ = word
	_ = name
	false

# The addresses of the variables a loaded build reaches (its table's lines: name, type, place,
# size), each the program's variable of that name; why not when the program has none of the name
# or lays it out otherwise (another type or size).
fn reachedPlaces(path str, reached str) i64[] ? str:
	own {str: str} = {}
	for line in programTable().lines():
		fields = line.split("	")
		if fields.len == 4: own[fields[0]] = line
	places = []
	for line in reached.lines():
		fields = line.split("	")
		mine = own.get(fields[0]) ??
			return "{path} reaches {fields[0]}, which this program does not have"
		theirs = mine.split("	")
		if theirs[1] != fields[1] or theirs[3] != fields[3]:
			return "{path} lays out {fields[0]} otherwise than this program (built from other sources)"
		places.push(gv(slotModuleVariables) + (i64.parse(theirs[2]) ?? 0))
	places

# the table of the program's module variables its build wrote (compiler's loadable.zap): its
# length, then its lines
fn programTable() str:
	p = gv(slotStateTable)
	if p == 0: return ""
	n = __ld32(p)
	bytes = zeroBytes(n)
	__memcpy(__ld64(__addr(bytes)), p + 4, n)
	str(move bytes)

# The field of the code, of the kind given (the compiler's loadable.zap: x64's 32-bit
# displacement; AArch64's adrp, its page's add, its ldr of a double word), led to target; false
# when it cannot reach it
fn leadTo(field i64, kind i64, target i64) bool:
	if kind == 0:
		rel = target - (field + 4)
		if rel < -2_147_483_648 or rel > 2_147_483_647: return false
		__st32(field, rel)
		return true
	word = __ld32(field)
	if kind == 1:
		pages = (target >> 12) - (field >> 12)
		if pages < -1_048_576 or pages >= 1_048_576: return false
		__st32(field, word & 0x9F00_001F | (pages & 3) << 29 | ((pages >> 2) & 0x7_FFFF) << 5)
		return true
	offset = target & 0xFFF
	if kind == 3:
		if offset & 7 != 0: return false
		offset >>= 3
	__st32(field, word & 0xFFC0_03FF | offset << 10)
	true

# The PE at p mapped beside the program, its imports bound and its unwind table given to the
# system: where it is and its size; (0, 0) when it cannot be
fn mappedImage(image str) (i64, i64):
	p = sPtr(image)
	headers = p + __ld32(p + 60)
	optional = headers + 24
	size = __ld32(optional + 56)
	base = reserveNear(size)
	if base == 0: return (0, 0)
	section = optional + __ld16(headers + 20)
	loop __ld16(headers + 6):
		# the file holds SizeOfRawData bytes of a section, its VirtualSize may be more: zero pages
		__memcpy(
			base + __ld32(section + 12),
			p + __ld32(section + 20),
			__ld32(section + 8).min(__ld32(section + 16))
		)
		section += 40
	if not bindImports(base, __ld32(optional + 120)): return (0, 0)
	_ = RtlAddFunctionTable(base + __ld32(optional + 136), __ld32(optional + 140) / 12, base)
	(base, size)

# the build written at base, size bytes, made runnable, the processor seeing its code
fn makeRunnable(base i64, size i64):
	_ = VirtualProtect(base, size, 64, out _)   # PAGE_EXECUTE_READWRITE
	_ = FlushInstructionCache(GetCurrentProcess(), base, size)

# room for a build within reach of the program's state (x64's 32-bit displacement: 1.9 GB of the
# program's image either way, within AArch64's 4 GB), readable and writable (runnable once
# written: makeRunnable). The first load claims the reach whole (address space only, above the
# image when it is free, else below, halving until a span is), and the builds are committed inside
# it in order: left to the heap, whose big blocks reserve a gigabyte of room each, bottom up, the
# reach is taken by the time a few builds have been read. 0 when the claimed reach is spent.
fn reserveNear(size i64) i64:
	if gv(slotLoadedEnd) == 0: claimReach()
	at = gv(slotLoadedNext)
	if at == 0 or at + size > gv(slotLoadedEnd): return 0
	if not commitPages(at, size): return 0
	gset(slotLoadedNext, (at + size).alignUp(reserveStep))
	at

fn claimReach():
	own = GetModuleHandleA(0)
	reach = 1_900_000_000
	span = (reach - 16_777_216) & ~(reserveStep - 1)
	while span >= 64 * reserveStep:
		step = (span / 4) & ~(reserveStep - 1)   # (an app's neighbours, libraries, sit close)
		at = own + 16_777_216
		while at + span <= own + reach:
			if reservePagesAt(at, span): return claimed(at, span)
			at += step
		at = (own - span) & ~(reserveStep - 1)
		while at > 0 and at >= own - reach:
			if reservePagesAt(at, span): return claimed(at, span)
			at -= step
		span = (span / 2) & ~(reserveStep - 1)
	gset(slotLoadedEnd, -1)   # nothing to claim: every load fails

fn claimed(at i64, span i64):
	gset(slotLoadedNext, at)
	gset(slotLoadedEnd, at + span)

reserveStep = 65_536   # the system's granularity of reservations

# the import table at the RVA bound: each function's address written in its slot
fn bindImports(base i64, table i64) bool:
	d = base + table
	while __ld32(d + 12) != 0:
		dll = LoadLibraryA(cBytesZ(base + __ld32(d + 12)))
		if dll == 0: return false
		names = base + __ld32(d)
		slots = base + __ld32(d + 16)
		while __ld64(names) != 0:
			__st64(slots, GetProcAddress(dll, cBytesZ(base + __ld64(names) + 2)))
			names += 8
			slots += 8
		d += 20
	true

# the NUL-terminated string at p, its NUL kept (for the system's calls)
fn cBytesZ(p i64) u8[]:
	b = cBytes(p)
	b.push(0)
	b
