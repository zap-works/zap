# A process made and started: the guest memory's span laid out (space.zap), the executable loaded,
# the main thread created at its entry. A homebrew NRO is started as hbloader starts one: x0 the
# loader's configuration (switchbrew: Homebrew ABI), x1 -1, the heap given in it.

import fs
import recomp.switch.cpu

pub codeBase = 0x0800_0000
mainStackSize = 0x10_0000

# the homebrew ABI's configuration keys
keyEnd = 0
keyMainThreadHandle = 1
keyOverrideHeap = 3
keyArgv = 5
keyAppletType = 7
keyHosVersion = 16

# the firmware a homebrew is told it runs on (22.5.0)
hosVersion = 22 << 16 | 5 << 8

# A process for an executable of `codeSize` bytes with a heap of up to heapMax bytes: its kernel
# and memory, nothing loaded yet.
pub fn newProcess(codeSize i64, heapMax i64) Kernel:
	space = layout(codeBase, codeSize.alignUp(0x20_0000) + 0x10_0000, heapMax, 0x2000_0000)
	cpu.memory = cpu.newMemory(codeBase, space.spanSize(codeBase))
	Kernel(space, startMs = clockMs())

# A process with nothing loaded and a heap of 2 MiB mapped: the services asked with no guest code.
pub fn bareProcess() Kernel:
	k = newProcess(0x1_0000, 0x20_0000)
	k.space.map(k.space.heapAt, k.space.heapMax, typeHeap, permRead | permWrite)
	k

# a buffer of the bytes put in the heap at `offset`
pub fn heapBuffer(k Kernel, offset i64, bytes u8[]) Buffer:
	at = k.space.heapAt + offset
	putBytes(at, bytes)
	Buffer(at, size = bytes.len)

# the main thread at entry with x0 = arg and x1 = handleArg, its stack at the stack region's end
fn startMain(mut k Kernel, entry i64, arg u64):
	top = k.space.stackAt + k.space.stackSize
	k.space.map(top - mainStackSize, mainStackSize, typeStack, permRead | permWrite)
	h = k.createThread(entry, arg, top, 44) ?? 0
	k.threads[len - 1].started = true
	h

# A homebrew NRO's process, started; why not when it cannot be.
pub fn launchNro(path str, heapMax i64) Kernel ? str:
	file = fs.readBytes(path) ?? return "cannot read {path}"
	k = newProcess(file.len + 0x10_0000, heapMax)
	k.selfPath = path.copy()
	k.selfName = fs.fileName(path).copy()
	m = try k.space.loadNro(fs.fileName(path), file, codeBase)
	k.modules.push(m.copy())
	config = m.at + m.size
	k.space.map(config, pageSize, typeCodeData, permRead | permWrite)
	k.space.map(k.space.heapAt, heapMax, typeHeap, permRead | permWrite)
	k.space.heapSize = heapMax
	argv = config + 0x800
	name = fs.fileName(path).bytes()
	for i, b in name:
		cpu.memory.store(argv + i, 0, b)
	h = k.startMain(m.at, u64(config))
	k.threads[0].c.x[1] = u64(-1)
	# the homebrew returns to the loader through x30: there, svcExitProcess
	exit = config + 0x7F0
	cpu.memory.store(exit, 2, 0xD400_00E1)
	k.space.protect(config, pageSize, permRead | permWrite | permExecute)
	k.threads[0].c.x[30] = u64(exit)
	entries = [
		(keyMainThreadHandle, h, 0),
		(keyOverrideHeap, k.space.heapAt, heapMax),
		(keyArgv, 0, argv),
		(keyAppletType, 0, 0),
		(keyHosVersion, hosVersion, 0),
		(keyEnd, 0, 0)
	]
	for i, (key, v0, v1) in entries:
		at = config + i * 24
		cpu.memory.store(at, 2, u64(key))
		cpu.memory.store(at + 4, 2, 1 if key == keyMainThreadHandle else 0)   # mandatory
		cpu.memory.store(at + 8, 3, u64(v0))
		cpu.memory.store(at + 16, 3, u64(v1))
	k

# the order Horizon's loader places an ExeFS's modules in (rtld first: it starts the process)
exefsOrder = ["rtld", "main", "subsdk0", "subsdk1", "subsdk2", "subsdk3", "subsdk4", "sdk"]

# A game's process from its ExeFS dir (NSOs stored whole, main.npdm), started at rtld with
# x0 = 0 and x1 = the main thread's handle; its program id from programId.
pub fn launchExefs(dir str, heapMax i64, programId u64) Kernel ? str:
	files = exefsOrder.filter(fs.exists(fs.join(dir, it)))
	if files.isEmpty: return "no NSO in {dir}"
	sizes = files.map((fs.readBytes(fs.join(dir, it)) ?? []).len)
	k = newProcess(sizes.sum() + files.len * 0x10_0000, heapMax)
	k.programId = programId
	k.titleDir = fs.dirOf(fs.normalize(dir)).copy()
	at = codeBase
	for name in files:
		file = fs.readBytes(fs.join(dir, name)) ?? return "cannot read {name}"
		m = try k.space.loadNso(name, file, at)
		at = (m.at + m.size).alignUp(0x10_0000)
		k.modules.push(m)
	h = k.startMain(codeBase, 0)
	k.threads[0].c.x[1] = u64(h)
	k

# a homebrew's heap, and a game's (what an application's memory pool gives it: 3.2 GB)
homebrewHeap = 0x1000_0000
gameHeap = 0xC800_0000

# the program id an ExeFS's main.npdm gives its process (its ACI0 section's), 0 without one
fn npdmProgramId(dir str) u64:
	npdm = fs.readBytes(fs.join(dir, "main.npdm")) ?? return 0
	if npdm.len < 0x80: return 0
	aci = i64(npdm.u32le(0x70))
	if aci + 0x18 > npdm.len or not npdm.matchesAt(aci, "ACI0"): return 0
	npdm.u64le(aci + 0x10)

# The process of a homebrew NRO or a game's ExeFS dir, started.
pub fn launch(path str) Kernel ? str:
	if path.endsWith(".nro"): return launchNro(path, homebrewHeap)
	launchExefs(path, gameHeap, npdmProgramId(path))
