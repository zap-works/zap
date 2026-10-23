# Waiting and waking: events, svcWaitSynchronization over handles, the user-space mutex's slow
# path (svcArbitrateLock and Unlock: the word holds the owner's handle, bit 30 set while others
# wait), condition variables (svcWaitProcessWideKeyAtomic and SignalProcessWideKey: the key's
# word is 1 while threads wait) and the address arbiter (svcWaitForAddress, SignalToAddress).

import recomp.switch.cpu

waitersBit = 0x4000_0000

fn word(at i64) i64:
	i64(cpu.memory.load(at, 2))

fn setWord(at i64, v i64):
	cpu.memory.store(at, 2, u64(v & 0xFFFF_FFFF))

# a wait's time out from svc's nanoseconds: -1 forever
fn deadline(mut k Kernel, ns i64) i64:
	-1 if ns < 0 else k.now() + ns * 192 / 10_000

# whether the handle's object counts as signaled for svcWaitSynchronization
fn signaled(k Kernel, h i64) bool:
	match k.object(h):
		Event(e): k.events[e]
		Thread(i): k.threads[i].exited
		_: false

fn signalEvent(mut k Kernel, i i64):
	h = k.arg32(i, 0)
	e = k.eventOf(h) ?? return k.reply(i, resultInvalidHandle)
	k.events[e] = true
	k.signalObject(h)
	k.reply(i, resultSuccess)

fn clearEvent(mut k Kernel, i i64):
	e = k.eventOf(k.arg32(i, 0)) ?? return k.reply(i, resultInvalidHandle)
	k.events[e] = false
	k.reply(i, resultSuccess)

fn eventOf(k Kernel, h i64) i64?:
	if k.object(h) is Event(e): return e
	none

# the threads waiting on any handle that is now signaled woken, x1 the handle's index
pub fn signalObject(mut k Kernel, h i64):
	for t in 0..k.threads.len:
		hs i64[] = []
		if k.threads[t].waiting is Handles(list): hs = list.copy()
		for j, w in hs:
			if k.signaled(w):
				k.wake(t, resultSuccess)
				k.output(t, 1, u64(j))
				break

fn waitSynchronization(mut k Kernel, i i64):
	count = i64(k.arg(i, 2))
	at = i64(k.arg(i, 1))
	handles i64[] = (0..count).map(word(at + it * 4))
	for j, h in handles:
		if k.signaled(h): return k.answer(i, u64(j))
	timeout = i64(k.arg(i, 3))
	if timeout == 0: return k.reply(i, resultTimedOut)
	k.threads[i].waiting = .Handles(handles)
	k.threads[i].wakeAt = k.deadline(timeout)

fn arbitrateLock(mut k Kernel, i i64):
	owner = k.arg32(i, 0)
	at = i64(k.arg(i, 1))
	k.reply(i, resultSuccess)
	if word(at) != owner | waitersBit: return
	k.threads[i].waiting = .Mutex(at)

# the mutex at `at` handed to its most urgent waiter, or freed
fn unlock(mut k Kernel, at i64):
	winner = -1
	others = 0
	for t in 0..k.threads.len:
		if k.threads[t].waiting is Mutex(a) and a == at:
			if winner < 0 or k.threads[t].priority < k.threads[winner].priority: winner = t
			others += 1
	if winner < 0: return setWord(at, 0)
	setWord(at, k.threads[winner].handle | (waitersBit if others > 1 else 0))
	k.wake(winner, resultSuccess)

fn waitConditionVariable(mut k Kernel, i i64):
	mutex = i64(k.arg(i, 0))
	key = i64(k.arg(i, 1))
	tag = k.arg32(i, 2)
	timeout = i64(k.arg(i, 3))
	k.unlock(mutex)
	setWord(key, 1)
	k.threads[i].waiting = .CondVar(key, mutex, tag)
	k.threads[i].wakeAt = k.deadline(timeout)

# the most urgent thread waiting on the key, none when none waits
fn keyWaiter(k Kernel, key i64) i64?:
	best = -1
	for t in 0..k.threads.len:
		if k.threads[t].waiting is CondVar(kk, _, _) and kk == key:
			if best < 0 or k.threads[t].priority < k.threads[best].priority: best = t
	if best < 0: return none
	best

# up to `count` (-1 all) of the key's waiters woken in priority order, each taking its mutex back
# or waiting for it
fn signalConditionVariable(mut k Kernel, i i64):
	key = i64(k.arg(i, 0))
	count = i64(i32(u32(k.arg32(i, 1))))
	woken = 0
	while count < 0 or woken < count:
		t = k.keyWaiter(key) ?? break
		woken += 1
		mutex, tag = match k.threads[t].waiting:
			CondVar(_, m, g): (m, g)
			_: (0, 0)
		k.threads[t].wakeAt = -1
		held = word(mutex)
		if held == 0:
			setWord(mutex, tag)
			k.wake(t, resultSuccess)
		else:
			setWord(mutex, held | waitersBit)
			k.threads[t].waiting = .Mutex(mutex)
			k.reply(t, resultSuccess)
	if k.keyWaiter(key) == none: setWord(key, 0)
	k.reply(i, resultSuccess)

# svcWaitForAddress: type 0 waits while the word is below the value, 1 decrements it first when
# below, 2 waits while it equals the value
fn waitForAddress(mut k Kernel, i i64):
	at = i64(k.arg(i, 0))
	kind = i64(k.arg(i, 1))
	value = i64(i32(u32(k.arg32(i, 2))))
	timeout = i64(k.arg(i, 3))
	current = i64(i32(u32(word(at))))
	waits = current == value if kind == 2 else current < value
	if not waits: return k.reply(i, resultInvalidState)
	if kind == 1: setWord(at, current - 1)
	k.reply(i, resultSuccess)
	k.threads[i].waiting = .Address(at)
	k.threads[i].wakeAt = k.deadline(timeout)

# svcSignalToAddress: type 0 wakes, 1 increments the word if it equals the value then wakes, 2
# the same when it equals the value; up to `count` (-1 all) of the address's waiters
fn signalToAddress(mut k Kernel, i i64):
	at = i64(k.arg(i, 0))
	kind = i64(k.arg(i, 1))
	value = i64(i32(u32(k.arg32(i, 2))))
	count = i64(i32(u32(k.arg32(i, 3))))
	if kind >= 1:
		if i64(i32(u32(word(at)))) != value: return k.reply(i, resultInvalidState)
		setWord(at, value + 1)
	woken = 0
	for t in 0..k.threads.len:
		if count >= 0 and woken >= count: break
		if k.threads[t].waiting is Address(a) and a == at:
			k.wake(t, resultSuccess)
			woken += 1
	k.reply(i, resultSuccess)

fn mapSharedMemory(mut k Kernel, i i64):
	at = i64(k.arg(i, 1))
	size = i64(k.arg(i, 2))
	s = match k.object(k.arg32(i, 0)):
		SharedMemory(index): index
		_: return k.reply(i, resultInvalidHandle)
	k.sharedMemory[s].mappedAt = at
	k.space.map(at, size, typeShared, permRead | permWrite)
	k.reply(i, resultSuccess)
