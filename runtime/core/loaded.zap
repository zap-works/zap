# Builds loaded into the running program (`zap build --loadable`, spec 13.1): another build of
# some of the program's modules and more code beside them, mapped next to the program, its
# references to the state led to the program's variables of the same names (the table its build
# wrote), so its code reads and changes the program's module variables; then its main runs once. A
# program too large to build at once is built as several such builds. Windows x64's only
# (linux/loaded.zap refuses).

extern loaded fn loadedMain()
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
	if info.len < 16 + tableLen + count * 12: return "{path}.load is cut short"
	base, size = mappedImage(sPtr(image))
	if base == 0: return "no room for {path} within reach of the program"
	for k in 0..count:
		reference = at + 4 + k * 12
		v = __ld32(reference + 4)
		state = __globals() + __ld32(reference + 8) if v == 0xFFFF_FFFF
			else places[v] + __ld32(reference + 8)
		if not leadTo(base + __ld32(reference), state):
			return "{path} lies out of reach of the state"
	makeRunnable(base, size)
	bindExtern(loadedMain, base + __ld32(p + 4))
	loadedMain()

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

# the 32-bit displacement at field led to target; false when it cannot reach it
fn leadTo(field i64, target i64) bool:
	rel = target - (field + 4)
	if rel < -2_147_483_648 or rel > 2_147_483_647: return false
	__st32(field, rel)
	true

# The PE at p mapped beside the program, its imports bound and its unwind table given to the
# system: where it is and its size; (0, 0) when it cannot be
fn mappedImage(p i64) (i64, i64):
	headers = p + __ld32(p + 60)
	optional = headers + 24
	size = __ld32(optional + 56)
	base = reserveNear(size)
	if base == 0: return (0, 0)
	section = optional + __ld16(headers + 20)
	loop __ld16(headers + 6):
		__memcpy(base + __ld32(section + 12), p + __ld32(section + 20), __ld32(section + 8))
		section += 40
	if not bindImports(base, __ld32(optional + 120)): return (0, 0)
	_ = RtlAddFunctionTable(base + __ld32(optional + 136), __ld32(optional + 140) / 12, base)
	(base, size)

# the build written at base, size bytes, made runnable, the processor seeing its code
fn makeRunnable(base i64, size i64):
	_ = VirtualProtect(base, size, 64, out _)   # PAGE_EXECUTE_READWRITE
	_ = FlushInstructionCache(GetCurrentProcess(), base, size)

# room for a build within reach of the program's state (a 32-bit displacement: 1.9 GB of the
# program's image either way), readable and writable (runnable once written: makeRunnable),
# packed after the builds above the program, then before those below it; 0 when there is none
fn reserveNear(size i64) i64:
	own = GetModuleHandleA(0)
	reach = 1_900_000_000
	at = gv(slotReservedAbove) if gv(slotReservedAbove) != 0 else own + 16_777_216
	while at + size < own + reach:
		if reserveAt(at, size) is got:
			gset(slotReservedAbove, (got + size).alignUp(reserveStep))
			return got
		at += reserveStep
	at = (gv(slotReservedBelow) if gv(slotReservedBelow) != 0 else own) - size.alignUp(reserveStep)
	while at > own - reach:
		if reserveAt(at, size) is got:
			gset(slotReservedBelow, got)
			return got
		at -= reserveStep
	0

reserveStep = 65_536   # the system's granularity of reservations

# size bytes reserved and committed at `at`, none when the place is taken
fn reserveAt(at i64, size i64) i64?:
	got = VirtualAlloc(at, size, 12_288, 4)   # MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE
	none if got == 0 else got

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
