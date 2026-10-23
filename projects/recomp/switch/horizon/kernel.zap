# Horizon's kernel as the game sees it through its supervisor calls (HLE): the process's address
# space, its kernel objects reached by handles, its threads run one at a time on the host's one
# thread, and the services behind its IPC sessions. Time is virtual by default: the counter moves
# with the instructions run, so a run repeats exactly; `realTime` ties it to the host's clock.

import recomp.switch.cpu

# Results (switchbrew: Error codes): the kernel's module 1, its description in bits 9 and up
pub resultSuccess = 0
pub resultInvalidSize = 0xCA01
pub resultInvalidAddress = 0xCC01
pub resultOutOfMemory = 0xD001
pub resultInvalidHandle = 0xE401
pub resultTimedOut = 0xEA01
pub resultCancelled = 0xEC01
pub resultInvalidEnum = 0xF001
pub resultNotFound = 0xF201
pub resultInvalidState = 0xFA01

# the handles that mean "this thread" and "this process"
pub currentThread = 0xFFFF_8000
pub currentProcess = 0xFFFF_8001

pub type Object:
	Thread(index i64)
	Event(index i64)   # Kernel.events: a readable and a writable handle share one
	Session(service i64)   # an IPC session to a service object of Kernel.services
	Port(name str)
	SharedMemory(index i64)   # Kernel.sharedMemory
	TransferMemory(at i64, size i64)
	Process

# Memory a service shares with the process: where the process mapped it (-1 before), where the
# service writes it.
pub type Shared:
	size i64
	mappedAt i64 = -1

pub type Kernel:
	space Space = Space()
	modules Module[] = []
	objects {i64: Object} = {}
	events bool[] = []   # whether each event is signaled
	sharedMemory Shared[] = []
	nextHandle i64 = 0xD000
	threads Thread[] = []
	current i64 = 0   # the running thread's index
	ticks i64 = 0   # the counter, at 19.2 MHz
	realTime bool = false
	startMs i64 = 0
	log str[] = []   # what the program printed with svcOutputDebugString, a line each
	exited bool = false
	traceCalls bool = false   # each supervisor call and IPC request noted in the log
	programId u64 = 0
	services Service[] = []
	code cpu.Decoded = cpu.Decoded()

	# a new handle to the object
	fn add(move o Object):
		h = nextHandle
		nextHandle += 1
		objects[h] = o
		h

	# the object a handle names (the pseudo-handles resolved), none when it names nothing
	fn object(h i64) Object?:
		if h == currentThread: return .Thread(current)
		if h == currentProcess: return .Process
		if objects.get(h) is o: return o.copy()
		none

	# the counter's value now
	fn now():
		if realTime: ticks = (clockMs() - startMs) * (cpu.counterHz / 1000)
		ticks

# argument n of thread i's call (x registers), and as its low 32 bits
pub fn arg(k Kernel, i i64, n i64) u64:
	k.threads[i].c.x[n]

pub fn arg32(k Kernel, i i64, n i64) i64:
	k.threads[i].c.x[n] & 0xFFFF_FFFF

# thread i's call answered: its result in w0
pub fn reply(mut k Kernel, i i64, result i64):
	k.threads[i].c.x[0] = u64(result)

# output n of thread i's call (x1 and on)
pub fn output(mut k Kernel, i i64, n i64, v u64):
	k.threads[i].c.x[n] = v
