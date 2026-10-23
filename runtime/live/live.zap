# The program's half of `zap run --live` (spec 13.1): a build made with `--live` enters each
# function through its slot, a word of the data holding where its body is. When zap writes the
# path of a new build to the file ZAP_LIVE names, a thread of the program maps that build into the
# program's memory beside it, its references to the program's state (the global slots and the
# module variables, the same layout in both builds) led to the running program's, and every
# function's slot, in each build loaded so far, then leads to the new body: what runs keeps its
# state, its threads, its window and its GPU's objects.

extern fn LoadLibraryA(name u8[]) i64
extern fn GetProcAddress(module i64, name u8[]) i64
extern fn RtlAddFunctionTable(table i64, count i64, base i64) bool
extern fn FlushInstructionCache(process i64, base i64, size i64) bool
extern fn GetCurrentProcess() i64
extern fn VirtualProtect(addr i64, size i64, protect i64, out old u32) bool

# set by zap run --live: the file it writes the next build's path to
pub fn liveVariable() InternalVariable:
	InternalVariable("ZAP_LIVE")

# a function's body (past the jump through its slot) and its slot, as RVAs of its build
type LiveSlot:
	key str
	body i64
	slot i64

# what a build's .live file says of it
type LiveBuild:
	dataRva i64
	slots LiveSlot[]
	fixes i64[]   # the RVAs of the code's 32-bit references into the state

# the builds loaded, the program's own first, and where each is: the watcher's own (no module
# variable, so a build without --live keeps its layout)
type LiveBuilds:
	builds LiveBuild[]
	bases i64[]

# called at the start of a build made with --live: the thread that waits for the next build
fn liveStart():
	request = liveVariable().value() ?? return
	own = readLiveBuild("{exePath()}.live") ?? return
	arenaPause()   # the thread outlives any arena
	task = Box(Task(run = ():
		liveWatch(request, LiveBuilds(builds = [own.copy()], bases = [GetModuleHandleA(0)]))
	))
	h = CreateThread(0, 0, __osThreadEntry(), taskRecord(task), 0, 0)
	if h != 0:
		CloseHandle(h)
	__forget(task)   # the thread reads it while it runs, to the program's end

# The request file read every 50 ms: a path not loaded yet is loaded, and the answer written
# beside the request (`<request>.done`): `swapped <path>` or `failed <path>`. A build zap has not
# put in place yet (the path or its .live file cannot be read) is waited for, not failed: zap
# moves each file whole to its name before it names the build.
fn liveWatch(request str, move loaded LiveBuilds):
	live = move loaded
	last = ""
	loop:
		sleepMs(50)
		asked = (readFile(request) ?? "").trimmed().copy()
		if asked == "" or asked == last: continue
		image = readFile(asked) ?? continue
		info = readFile("{asked}.live") ?? continue
		# the answer is written before the swap is visible: a program that ends on the new
		# function's first call has still been answered
		if live.liveLoad(image, info) is ready:
			_ = writeFile("{request}.done", "swapped {asked}")
			live.livePublish(move ready)
		else:
			_ = writeFile("{request}.done", "failed {asked}")
		last = asked

# a .live file read: `data <rva>`, `slot <body> <slot> <key>`, `fix <rva>` lines (the rest is
# zap's); none when it cannot be read
fn readLiveBuild(path str) LiveBuild?:
	parseLiveBuild(readFile(path) ?? return none)

# what a .live file's text says of its build; none when it names no data
fn parseLiveBuild(text str) LiveBuild?:
	b = LiveBuild(dataRva = 0, slots = [], fixes = [])
	for line in text.lines():
		parts = line.trimmed().split(" ")
		if parts.len >= 2 and parts[0] == "data":
			b.dataRva = i64.parse(parts[1]) ?? 0
		elif parts.len >= 4 and parts[0] == "slot":
			b.slots.push(
				LiveSlot(
					key = parts[3].copy(),
					body = i64.parse(parts[1]) ?? 0,
					slot = i64.parse(parts[2]) ?? 0
				)
			)
		elif parts.len >= 2 and parts[0] == "fix":
			b.fixes.push(i64.parse(parts[1]) ?? 0)
	none if b.dataRva == 0 else b

# a build mapped and ready, not yet entered by any call: its place and where its functions are
type LiveLoaded:
	build LiveBuild
	base i64
	bodies {str: i64}

# The build (its executable's bytes and its .live file's text) mapped beside the program
# (liveImage), its references to the state led to the program's, and its own slots led to its
# functions; none when it cannot be (nothing of the program has changed yet: livePublish does)
fn liveLoad(live LiveBuilds, image str, info str) LiveLoaded?:
	b = parseLiveBuild(info) ?? return none
	base, size = live.liveImage(sPtr(image))
	if base == 0: return none
	state = live.bases[0] + live.builds[0].dataRva
	for fix in b.fixes:
		liveFix(base + fix, fix, b.dataRva, state)
	bodies {str: i64} = {}
	for s in b.slots:
		__st64(base + s.slot, base + s.body)
		bodies[s.key.copy()] = base + s.body
	liveRunnable(base, size)
	LiveLoaded(build = b, base, bodies)

# every slot of every build loaded so far led to the functions of the new one
fn livePublish(mut live LiveBuilds, move loaded LiveLoaded):
	for i, built in live.builds:
		for s in built.slots:
			if loaded.bodies.get(s.key) is body:
				__st64(live.bases[i] + s.slot, body)   # one aligned word: a call sees the old or the new
	live.builds.push(loaded.build.copy())
	live.bases.push(loaded.base)

# The PE at p mapped beside the program, its imports bound and its unwind table given to the
# system: where it is and its size; (0, 0) when it cannot be (linux/live.zap maps an ELF)
fn liveImage(live LiveBuilds, p i64) (i64, i64):
	headers = p + __ld32(p + 60)
	optional = headers + 24
	size = __ld32(optional + 56)
	base = live.liveReserve(size)
	if base == 0: return (0, 0)
	section = optional + __ld16(headers + 20)
	loop __ld16(headers + 6):
		__memcpy(base + __ld32(section + 12), p + __ld32(section + 20), __ld32(section + 8))
		section += 40
	if not liveImports(base, __ld32(optional + 120)): return (0, 0)
	_ = RtlAddFunctionTable(base + __ld32(optional + 136), __ld32(optional + 140) / 12, base)
	(base, size)

# The reference of the code at field (rva in its build, whose data is at dataRva) led to the same
# place in the running program's state: x64's 32-bit displacement (linux/arm64/ has AArch64's)
fn liveFix(field i64, rva i64, dataRva i64, state i64):
	rel = __ld32(field)
	if rel >= 2_147_483_648:
		rel -= 4_294_967_296
	at = rva + 4 + rel - dataRva   # the place in the state
	__st32(field, state + at - (field + 4))

# the build written at base, size bytes, made runnable, the processor seeing its code
fn liveRunnable(base i64, size i64):
	_ = VirtualProtect(base, size, 64, out _)   # PAGE_EXECUTE_READWRITE
	_ = FlushInstructionCache(GetCurrentProcess(), base, size)

# room for a build within reach of the program's state (a 32-bit displacement), readable and
# writable (runnable once written: liveRunnable); 0 when there is none
fn liveReserve(live LiveBuilds, size i64) i64:
	own = live.bases[0]
	hint = own + 16_777_216 * (live.bases.len + 1)
	while hint < own + 1_879_048_192:
		at = VirtualAlloc(hint, size, 12_288, 4)   # MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE
		if at != 0: return at
		hint += 16_777_216
	0

# the import table at the RVA bound: each function's address written in its slot
fn liveImports(base i64, table i64) bool:
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
