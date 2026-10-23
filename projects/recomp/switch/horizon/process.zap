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
	cpu.memory = cpu.Memory(bytes = zeros(spanSize(space, codeBase)), base = codeBase)
	Kernel(space = space, startMs = clockMs())

# the main thread at entry with x0 = arg and x1 = handleArg, its stack at the stack region's end
fn startMain(mut k Kernel, entry i64, arg u64) i64:
	top = k.space.stackAt + k.space.stackSize
	k.space.map(top - mainStackSize, mainStackSize, typeStack, permRead | permWrite)
	h = k.createThread(entry, arg, top, 44) ?? 0
	k.threads[len - 1].started = true
	h

# A homebrew NRO's process, started; why not when it cannot be.
pub fn launchNro(path str, heapMax i64) Kernel ? str:
	file = fs.readBytes(path) ?? return "cannot read {path}"
	k = newProcess(file.len + 0x10_0000, heapMax)
	m = try loadNro(k.space, fs.fileName(path), file, codeBase)
	k.modules.push(m.copy())
	config = m.at + m.size
	k.space.map(config, pageSize, typeCodeData, permRead | permWrite)
	k.space.map(k.space.heapAt, heapMax, typeHeap, permRead | permWrite)
	k.space.heapSize = heapMax
	argv = config + 0x800
	name = fs.fileName(path).bytes()
	for i, b in name:
		cpu.memory.store(argv + i, 0, u64(b))
	h = k.startMain(m.at, u64(config))
	k.threads[0].c.x[1] = u64(-1)
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
