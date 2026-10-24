# A system thread of the runtime's own (the Android app's input reader, the threads layer's
# workers), the smallest start: a closure run once, no result, no pool. The runtime's, not the
# program's: a program starts threads with runtime/threads.

# a system thread's record: the closure it runs, first, where the entry stub reads it
type Task:
	run fn()

# the address of a thread's record, which CreateThread hands the entry stub (a plain struct
# crosses into no extern: spec 10)
fn taskRecord(task Box<Task>) i64:
	__ld64(__addr(task))

# what a thread does first: nothing, except on Linux (faults.zap)
fn threadStarted():
	pass

# the spin lock at the word at: taken once it turns from 0 to 1
fn lockWord(at i64):
	while __cmpxchg(at, 0, 1) != 0:
		_ = SwitchToThread()

mut threadRecords Box<Task>[] = []   # the records of the threads started, alive until the process ends
mut threadRecordsLock = 0   # 1 while a thread adds a record

# Starts run on a system thread of its own; false when the system cannot start one. The thread
# starts a while after the call: a caller that must know it runs counts it from inside run.
fn startThread(move run fn()) bool:
	arenaPause()   # the thread outlives any arena
	task = Box(Task(run = ():
		threadStarted()
		run()
	))
	h = CreateThread(0, 0, __osThreadEntry(), taskRecord(task), 0, 0)
	if h != 0:
		CloseHandle(h)
		lockWord(__addr(threadRecordsLock))
		threadRecords.push(task)
		__st64(__addr(threadRecordsLock), fenced(0))
	arenaResume()
	h != 0
