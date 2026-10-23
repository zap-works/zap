# The process's threads: each a guest Cpu with its own stack and thread-local page, run in turns
# on the host's one thread. A thread runs until it calls the kernel, then goes on, or waits
# (sleep, a handle, a mutex, a condition variable, an address) until what it waits for happens
# or its time runs out; a thread that runs a full slice without calling the kernel yields too, so
# a spin on memory lets the others move. The turns are deterministic.

import recomp.switch.cpu

# instructions a thread runs before the next one's turn
slice = 20_000

pub type Waiting:
	Nothing
	Sleep
	Handles(handles i64[])   # svcWaitSynchronization
	Mutex(address i64)   # svcArbitrateLock
	CondVar(key i64, mutex i64, tag i64)   # svcWaitProcessWideKeyAtomic
	Address(address i64)   # svcWaitForAddress

pub type Thread:
	c cpu.Cpu = cpu.Cpu()
	handle i64 = 0
	id i64 = 0
	priority i64 = 44
	started bool = false
	exited bool = false
	waiting Waiting = .Nothing
	wakeAt i64 = -1   # the tick its wait times out at, -1 for never
	tls i64 = 0

	fn runnable():
		started and not exited and waiting == .Nothing

# A new thread at entry with x0 = arg, its stack's top at stackTop; its handle, none when no
# thread-local page is left.
pub fn createThread(mut k Kernel, entry i64, arg u64, stackTop i64, priority i64) i64?:
	if k.space.tlsAt + pageSize > k.space.tlsEnd: return none
	tls = k.space.tlsAt
	k.space.tlsAt += pageSize
	k.space.map(tls, pageSize, typeThreadLocal, permRead | permWrite)
	t = Thread(priority, id = k.threads.len + 1, tls)
	t.c.pc = entry
	t.c.x[0] = arg
	t.c.x[cpuSp()] = u64(stackTop)
	t.c.tpidrro = u64(tls)
	index = k.threads.len
	k.threads.push(t)
	h = k.add(.Thread(index))
	k.threads[index].handle = h
	h

fn cpuSp():
	32

# a thread's wait ended, the result its svc returns in w0
pub fn wake(mut k Kernel, t i64, result i64):
	k.threads[t].waiting = .Nothing
	k.threads[t].wakeAt = -1
	k.reply(t, result)

# the waits whose time ran out ended with resultTimedOut (a sleep's with success)
fn timeOut(mut k Kernel):
	now = k.now()
	for t in 0..k.threads.len:
		w = k.threads[t].wakeAt
		if k.threads[t].waiting == .Nothing or w < 0 or w > now: continue
		slept = k.threads[t].waiting == .Sleep
		k.wake(t, resultSuccess if slept else resultTimedOut)

# the next thread to run after the current one, round robin; none when all wait
fn nextRunnable(k Kernel) i64?:
	n = k.threads.len
	for step in 1..=n:
		i = (k.current + step) % n
		if k.threads[i].runnable(): return i
	none

# The process run until it exits or every thread waits forever; `limit` instructions at most.
pub fn runProcess(mut k Kernel, limit i64) str:
	k.runFor(-1, limit)

# The process run for `ticks` of its counter (-1: until it ends), `limit` instructions at most;
# why it stopped.
pub fn runFor(mut k Kernel, ticks i64, limit i64) str:
	ran = 0
	until = k.now() + ticks
	while ran < limit and not k.exited and (ticks < 0 or k.now() < until):
		k.timeOut()
		k.pulseVsync()
		next = k.nextRunnable() ?? k.skipToWake() ?? return "every thread waits: {k.waits()}"
		k.current = next
		k.audioTick()
		if k.now() >= k.nextHidSample:
			k.sampleHid()
			k.nextHidSample = k.now() + hidPeriod
		cpu.counter = u64(k.now())
		steps = cpu.runThread(mut ref k.threads[next].c, mut ref k.code, slice)
		ran += steps
		k.ticks += steps / 50 + 1
		why = k.threads[next].c.halted.copy()
		if why == "": continue
		k.threads[next].c.halted = ""
		k.threads[next].c.isHalted = false
		if why.startsWith("svc "):
			k.supervisorCall(next, i64.parse("0x{why[4..]}") ?? -1)
		else:
			c = k.threads[next].c
			blocks = (0..c.trail.len).map(c.trail[(c.trailAt + it) % len]).map("{it:x}").join(" ")
			return "thread {k.threads[next].id} stopped at {c.pc:x} ({cpu.memory.load(c.pc, 2):08x}): {why}; blocks before: {blocks}"
	"exited" if k.exited else "ran {ran} instructions"

# what each started thread that has not exited waits for, and where
fn waits(k Kernel) str:
	live = k.threads.filter(it.started and not it.exited)
	live.map("t{it.id} at {it.c.pc:x} {it.waiting} until {it.wakeAt}").join("; ")

# when every thread waits, the clock moved from timeout to timeout (and vsync to vsync, which
# may wake no one) until one wakes a thread: that thread
fn skipToWake(mut k Kernel) i64?:
	while not k.realTime:
		soonest = -1
		for t in k.threads:
			if t.waiting != .Nothing and t.wakeAt >= 0 and (soonest < 0 or t.wakeAt < soonest):
				soonest = t.wakeAt
		if k.display.vsyncEvent >= 0 and (soonest < 0 or k.display.vsyncAt < soonest):
			soonest = k.display.vsyncAt
		if soonest < 0: return none
		k.ticks = k.ticks.max(soonest)
		k.timeOut()
		k.pulseVsync()
		if k.nextRunnable() is t: return t
	none
