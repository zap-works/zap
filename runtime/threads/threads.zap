# System threads: the atomics, the data parallelism of `.parallel()`, the background jobs and
# the channels between a job and the thread that started it.

# ---------- atomics ----------

# An integer that several system threads change at once: Atomic(v) starts at v, copies are the
# same integer, and every operation is one atomic instruction.
pub shared type Atomic:
	value i64

	# the value now
	fn load() i64:
		value   # an aligned word is read whole

	# sets the value
	mut fn store(v i64):
		value = v

	# adds n and returns the value before
	fn add(n i64) i64:
		__xadd(__addr(value), n)

	# becomes new when it holds old; whether it did
	fn compareSwap(old i64, new i64) bool:
		__cmpxchg(__addr(value), old, new) == old

# ---------- system threads: data parallelism ----------
# parallelMap(n, f) computes f(0) .. f(n-1) on every processor at once and returns the results
# in order. The closure runs on several threads at the same time: it must only read what it
# captured (it may build and return anything). Every thread allocates from a heap of its own;
# printing and float formatting stay on the main thread for now.
#
# The worker threads are created once (one per processor beyond the main thread). Each parallel
# step is a job of the pool: a record in a queue the workers take work from, handing out its
# indices until none is left. The thread that made it works on it too and waits only for its own
# job's last index, never for a round of all the workers: a job whose indices run out frees each
# worker for the next job at once, and jobs from several threads (a parallel step inside
# another's work, a stream read while it is made) share the workers. A thread created per call
# would cost its start-up latency on every step of a program that runs many.

poolJobRoom = 256   # the queue's room: jobs open at once
mut poolWorkers = 0   # the workers started
mut poolWake i64 = 0   # a semaphore counting the wake-ups owed to the workers
mut poolLock = 0   # 1 while a thread changes the queue or a job's counts (a word the end never drops)
mut poolQueue i64[] = []   # the open jobs' records, oldest first (room for poolJobRoom: never grown)
mut poolStarted = false
mut poolUp = 0   # the workers that started running their closure (changed atomically)

# A job's record (rtAlloc'd, poolJob* the offsets of its words): the address of the closure every
# thread runs (it hands out the job's indices and returns once none is left), the threads inside
# it, whether it still hands out work, and the event its maker waits on.
poolJobRun = 0
poolJobInside = 8
poolJobOpen = 16
poolJobEvent = 24
poolJobSize = 32

# The workers made, once: under the lock, as two threads may run their first parallel step at
# once. Back when every worker runs: a thread starts a while after CreateThread, and a program
# that ends before then would end with workers not yet running.
fn startPool():
	if poolStarted: return
	lockPool()
	if poolStarted:
		unlockPool()
		return
	arenaPause()   # the workers outlive any arena
	poolWake = CreateSemaphoreA(0, 0, 1_073_741_824, 0)
	poolQueue.reserve(poolJobRoom)
	for i in 0..cpuCount() - 1:
		idx = i
		if not startThread(():
			poolWorker(idx)
		):
			fail("cannot create a worker thread")
		poolWorkers += 1
	waitUntilUp(__addr(poolUp), poolWorkers)
	poolStarted = true
	threadsEnd = endThreads
	arenaResume()
	unlockPool()

# a worker's life: wait to be woken, then work on the open jobs until none is left
fn poolWorker(idx i64):
	_ = idx
	_ = __xadd(__addr(poolUp), 1)   # counted as started
	loop:
		WaitForSingleObject(poolWake, -1)
		takeRemoteFrees()
		loop:
			job = poolEnter()
			if job == 0: break
			__callRec(__ld64(job + poolJobRun))
			poolLeave(job, true)

fn lockPool():
	lockWord(__addr(poolLock))

fn unlockPool():
	__st64(__addr(poolLock), fenced(0))

# back once the word at counts n threads started
fn waitUntilUp(at i64, n i64):
	while __ld64(at) < n:
		_ = SwitchToThread()

# The program's end, before its module variables are dropped: the pool's and the background
# jobs' locks taken for good, so that a worker woken late (a parallel step wakes every worker,
# and some wake after its last index) or done with a job waits on its lock until the process
# ends instead of reading the queues being dropped. Every parallel step is over by then: its
# maker waited for it. A background thread starts a while after CreateThread (long on a loaded
# machine), so the end also waits until every one made has started.
fn closeWorkers():
	if poolStarted:
		lockPool()
	if jobSignal != 0:
		lockJobs()
		waitUntilUp(__addr(jobsUp), jobThreads)

# the program's end once a pool or a background thread started (coreterminal.zap's threadsEnd):
# with waitJobs, every background job done first
fn endThreads(waitJobs bool):
	if waitJobs:
		waitJobsDone()
	closeWorkers()

# the oldest job still handing out work, entered (0: none)
fn poolEnter() i64:
	lockPool()
	job = 0
	for j in poolQueue:
		if __ld64(j + poolJobOpen) != 0:
			__st64(j + poolJobInside, __ld64(j + poolJobInside) + 1)
			job = j
			break
	unlockPool()
	job

# a thread is out of the job: its closure returned (no index left to hand out, so the job closes)
# or its maker finishes it; the last one out, once it is closed, wakes the maker
fn poolLeave(job i64, ran bool):
	lockPool()
	if ran:
		__st64(job + poolJobOpen, 0)
	left = __ld64(job + poolJobInside) - 1
	__st64(job + poolJobInside, left)
	if left == 0 and __ld64(job + poolJobOpen) == 0:
		# under the lock: a maker not inside (a stream's) frees the record and closes the event
		# as soon as it sees no thread inside
		SetEvent(__ld64(job + poolJobEvent))
	unlockPool()

# A job that runs the closure at address run on the workers (and on the maker when it counts
# itself inside: it then runs the closure too before finishing)
fn poolStart(run i64, makerInside bool) i64:
	startPool()
	arenaPause()   # the record is freed by poolFinish, whatever arena is open there
	job = rtAlloc(poolJobSize)
	arenaResume()
	__st64(job + poolJobRun, run)
	__st64(job + poolJobInside, 1 if makerInside else 0)
	__st64(job + poolJobOpen, 1)
	__st64(job + poolJobEvent, CreateEventA(0, false, false, 0))
	lockPool()
	if poolQueue.len == poolJobRoom:
		unlockPool()
		fail("more than {poolJobRoom} parallel steps open at once")
	poolQueue.push(job)
	unlockPool()
	if poolWorkers > 0:
		_ = ReleaseSemaphore(poolWake, poolWorkers, 0)
	job

# The job made by poolStart closed (its indices handed out, or given up), out of the queue, its
# maker out of it when it was inside, back once no thread is inside; its record freed
fn poolFinish(job i64, makerInside bool):
	lockPool()
	__st64(job + poolJobOpen, 0)
	if poolQueue.indexOf(job) is k:
		_ = poolQueue.remove(k)
	if makerInside:
		__st64(job + poolJobInside, __ld64(job + poolJobInside) - 1)
	waiting = __ld64(job + poolJobInside) > 0
	unlockPool()
	if waiting:
		WaitForSingleObject(__ld64(job + poolJobEvent), -1)
	CloseHandle(__ld64(job + poolJobEvent))
	rtFree(job)

# the processors the system reports (at least 1)
pub fn cpuCount() i64:
	match env.get("NUMBER_OF_PROCESSORS"):
		s:
			n = i64.parse(s) ?? 1
			if n < 1: return 1
			return n
		none: return 1

# how many parts a parallel pipeline's source is cut into (`xs.parallel()...`): four for each
# processor, so that parts of uneven work still keep them all busy. Read first on the thread that
# starts the pipeline, before any worker does.
mut chunkCount i64 = 0

fn parallelChunks() i64:
	if chunkCount == 0:
		chunkCount = cpuCount() * 4
	chunkCount

# runs round on the pool's workers and on this thread, back once every thread is out of it
fn runOnPool(round fn()):
	job = poolStart(__addr(round), true)
	round()   # this thread works too
	poolFinish(job, true)

# parallelDo(n, f): f(0) .. f(n - 1) on every processor at once, each index once (a parallel for's
# parts: `for x in xs.parallel() { ... }`)
fn parallelDo(n i64, f fn(i64)):
	if n <= 0: return
	next = Atomic(0)
	step = batchOf(n)
	round = ():
		i = next.add(step)
		while i < n:
			for j in i..(i + step).min(n):
				f(j)
			i = next.add(step)
	runOnPool(round)

# list.zap's sortedOrder on every processor: parts sorted at once, then merged pairwise level by
# level, each merge cut into as many pieces as the level has fewer merges than parts, every piece
# at once (a short list is sorted on this thread)
fn sortedOrderParallel<K Ord>(keys K[]) i64[]:
	n = keys.len
	parts = parallelChunks()
	if n < 4096 or parts < 2: return sortedOrder(keys)
	order = (0..n).map(i: i)
	spare = zeros(n)
	a = __ld64(__addr(order))
	b = __ld64(__addr(spare))
	size = (n + parts - 1) / parts
	parallelDo(parts, p:
		sortSpan(keys, a, b, (p * size).min(n), ((p + 1) * size).min(n))
	)
	src = a
	dst = b
	width = size
	while width < n:
		from = src
		to = dst
		w = width
		merges = (n + 2 * w - 1) / (2 * w)
		pieces = (parts / merges).max(1)
		parallelDo(merges * pieces, t:
			lo = t / pieces * 2 * w
			mid = (lo + w).min(n)
			hi = (lo + 2 * w).min(n)
			piece = t % pieces
			k0 = (hi - lo) * piece / pieces
			k1 = (hi - lo) * (piece + 1) / pieces
			i0 = coRank(keys, from, k0, lo, mid, hi)
			i1 = coRank(keys, from, k1, lo, mid, hi)
			mergeFrom(keys, from, to, lo + i0, lo + i1, mid + k0 - i0, mid + k1 - i1, lo + k0)
		)
		src = to
		dst = from
		width *= 2
	if src != a:
		__memcpy(a, src, n * 8)
	order

# list.zap's listSortByKeys on every processor (`xs.parallel().sortedBy(f)`)
fn listSortByKeysParallel<T, K Ord>(xs T[], move keys K[]) T[]:
	order = sortedOrderParallel(keys)
	(0..order.len).parallel().map(i: xs[order[i]].copy())

# how many indices of n a thread takes at a time: about eight turns per processor, so that one
# atomic step serves many cheap elements while uneven ones still spread
fn batchOf(n i64) i64:
	(n / (cpuCount() * 8)).max(1)

# the parts' elements in order, in one list: each part's elements are moved over and its block
# freed (the lists a parallel pipeline's parts made)
fn listJoinParts<T>(move parts T[,]) T[]:
	out T[] = []
	stride = __stride(__zeroElem(out))
	n = listLen(parts)
	items = __ld64(__addr(parts))
	total = 0
	for i in 0..n:
		total += __ld64(items + i * 24 + 8)
	if total > 0:
		out.reserve(total)
	at = 0
	for i in 0..n:
		p = items + i * 24
		m = __ld64(p + 8)
		if m > 0:
			__memcpy(__ld64(__addr(out)) + at * stride, __ld64(p), m * stride)
		rtFree(__ld64(p))
		__st64(p, 0)
		__st64(p + 8, 0)
		__st64(p + 16, 0)
		at += m
	__st64(__addr(out) + 8, total)
	out

# the groups of the parts of a parallel groupBy as one map: the parts in order, so a key's
# elements stay in their original order
fn mapMergeGroups<K Hash, T>(parts {K: T[]}[]) {K: T[]}:
	out {K: T[]} = {}
	for p in parts:
		for k in p.keys():
			for x in p[k]:
				mapGroupAdd(out, k, x)
	out

# the counts of the parts of a parallel countBy as one map
fn mapMergeCounts<K Hash>(parts {K: i64}[]) {K: i64}:
	out {K: i64} = {}
	for p in parts:
		for k in p.keys():
			mapAdd(out, k, p[k])
	out

# parallelMap(n, f): [f(0), ..., f(n - 1)] computed on every processor at once (system threads); f
# must not change what it captures
fn parallelMap<T>(n i64, f fn(i64) T) T[]:
	out T[] = []
	if n <= 0: return out
	# the results are written by index from every thread at once, into room made beforehand
	stride = __stride(__zeroElem(out))
	out.reserve(n)
	items = __ld64(__addr(out))
	next = Atomic(0)
	step = batchOf(n)
	round = ():
		i = next.add(step)
		while i < n:
			for j in i..(i + step).min(n):
				r = f(j)
				__memcpy(items + j * stride, __addr(r), stride)
				__forget(r)
			i = next.add(step)
	runOnPool(round)
	__st64(__addr(out) + 8, n)
	out

# ---------- system threads: a parallel map read in order ----------
# `for x in src.parallel().map(f)` reads parallelStream(n, f): the pool makes f(0), f(1)... at
# most `window` results ahead of the reader, each into its slot, and the reader takes them in
# order, each as soon as it is made, while the threads go on with the next ones (no round waits
# for the slowest). A thread waits for a free slot, and the reader for its result, asleep on a
# semaphore and an event (no spinning). Leaving the loop early gives the rest up.

# the threads at work on a stream: its shared words (streamNext...) and its job, given up and
# waited for when the stream goes
type StreamRun:
	rec i64
	job i64

	mut fn drop():
		if job != 0:
			__st64(rec + streamGivenUp, 1)
			_ = ReleaseSemaphore(__ld64(rec + streamFree), 1_000_000, 0)   # the threads waiting wake
			poolFinish(job, false)
		CloseHandle(__ld64(rec + streamFree))
		CloseHandle(__ld64(rec + streamMade))
		rtFree(rec)

streamNext = 0   # the next index to hand out
streamGivenUp = 8   # 1 once the reader left
streamFree = 16   # a semaphore counting the free slots
streamMade = 24   # an event set after each result
streamReady = 32   # a word per slot from here: 1 once its result is in

# A stream of count results made on the pool, read by next() in order. Its run goes first, so
# the threads are done with the slots before they go.
type InOrder<T>:
	run StreamRun
	slots T[]
	task Box<Task>
	window i64
	count i64
	at i64 = 0

	# the next result, once it is made
	mut fn next() T:
		k = at % window
		ready = run.rec + streamReady + k * 8
		while fenced(__ld64(ready)) == 0:
			WaitForSingleObject(__ld64(run.rec + streamMade), -1)
		v = __at(slots, k)
		__memset(__ld64(__addr(slots)) + k * __stride(v), 0, __stride(v))   # moved out: not dropped there
		__st64(ready, 0)
		at += 1
		_ = ReleaseSemaphore(__ld64(run.rec + streamFree), 1, 0)   # the slot is free for the threads
		v

fn parallelStream<T>(n i64, move f fn(i64) T) InOrder<T>:
	window = (cpuCount() * 2).max(2)
	slots T[] = []
	stride = __stride(__zeroElem(slots))
	arenaPause()   # the stream's blocks are freed when it goes, whatever arena is open there
	slots.reserve(window)
	rec = rtAlloc(streamReady + window * 8)
	items = __ld64(__addr(slots))
	__memset(items, 0, window * stride)
	__st64(__addr(slots) + 8, window)
	__st64(rec + streamFree, CreateSemaphoreA(0, window, 1_073_741_824, 0))
	__st64(rec + streamMade, CreateEventA(0, false, false, 0))
	work = move f
	task = Box(Task(run = ():
		streamWork(rec, items, n, window, stride, work)
	))
	arenaResume()
	job = poolStart(__addr(task.run), false) if n > 0 else 0
	InOrder<T>(run = StreamRun(rec, job), slots, task, window, count = n.max(0))

# a thread's share of a stream: a free slot waited for, the next index taken, its result
# written to its slot and the slot's word set after it (__fence keeps the stores in order)
fn streamWork<T>(rec i64, items i64, n i64, window i64, stride i64, f fn(i64) T):
	loop:
		WaitForSingleObject(__ld64(rec + streamFree), -1)
		i = __xadd(rec + streamNext, 1)
		if i >= n or __ld64(rec + streamGivenUp) != 0:
			_ = ReleaseSemaphore(__ld64(rec + streamFree), 1, 0)   # the slot to the next waiting
			return
		r = f(i)
		k = i % window
		__memcpy(items + k * stride, __addr(r), stride)
		__forget(r)
		__st64(rec + streamReady + k * 8, fenced(1))
		SetEvent(__ld64(rec + streamMade))

# ---------- system threads: background work ----------
# background(f) runs f on a system thread while the caller goes on (a game makes its world's
# chunks so while it draws): the caller reads isDone when it likes, a frame loop each frame, and
# takes the result once with tryReceive(). f owns what it captured (moved in) and its result
# moves out to the caller. The jobs wait in a queue served by worker threads of their own, one
# per processor less one, created with the first job and kept apart from parallelMap's pool,
# whose rounds would otherwise wait behind them.

# A job that runs on another thread: its result is in a cell of its own (a word that turns 1
# when the result is in, 2 once the caller gave the job up before it, then the result's bytes),
# handed over to the caller by tryReceive(). The one of the two that leaves last frees the cell.
pub type Background<T>:
	job JobCell

	# whether the result is in (until it is received)
	fn isDone() bool:
		job.cell != 0 and fenced(__ld64(job.cell)) == 1

	# The result, once: none while the job still runs (or after it was received).
	mut fn tryReceive() T?:
		if not self.isDone: return none
		out T[] = []
		takeResult(job.cell, out)
		job.cell = 0
		out.pop()

# a job's cell as its caller holds it, given up when it goes
type JobCell:
	cell i64
	gone fn(i64)   # the result in the cell dropped and the cell freed

	mut fn drop():
		if cell != 0 and __cmpxchg(cell, 0, 2) != 0:
			gone(cell)

mut jobQueue Box<Task>[] = []   # the jobs not started yet, oldest first
mut jobThreads = 0   # the background threads started, the grower too
mut jobLock = 0   # 1 while a thread changes the queue (a word the end never drops)
mut jobSignal i64 = 0   # a semaphore counting the jobs waiting
mut jobsLive = 0   # the jobs queued or running, their tasks not dropped yet (changed atomically)
mut jobsUp = 0   # the background threads that started running their closure (changed atomically)
mut jobsBusy = 0   # the background threads running a job (changed atomically)
mut jobsQueued = 0   # the jobs not started yet (changed atomically)
mut growSignal i64 = 0   # a semaphore released to wake the thread that starts more background threads
mut jobsBlocked = 0   # the threads inside a wait for something outside the program (changed atomically)
jobWorkerLimit = 256

# Starts f on a background thread; tryReceive() the result once isDone says it is in.
pub fn background<T>(move f fn() T) Background<T>:
	sample T[] = []
	stride = __stride(__zeroElem(sample))
	cell = rtAlloc(8 + stride)
	__st64(cell, 0)
	work = move f
	gone = (at i64):
		out T[] = []
		takeResult(at, out)
	jobGone = gone.copy()
	task = Box(Task(run = ():
		r = work()
		__memcpy(cell + 8, __addr(r), stride)
		__forget(r)   # its bytes are in the cell now
		if __cmpxchg(cell, 0, 1) == 2:   # after them; given up: the result goes with the cell
			jobGone(cell)
	))
	arenaPause()   # the queue outlives any arena
	startJobWorkers()
	_ = __xadd(__addr(jobsLive), 1)
	lockJobs()
	jobQueue.push(task)
	unlockJobs()
	arenaResume()
	_ = __xadd(__addr(jobsQueued), 1)
	_ = ReleaseSemaphore(jobSignal, 1, 0)
	growJobWorkers()
	Background<T>(job = JobCell(cell, gone))

# the result in the cell at moved into out, the cell freed
fn takeResult<T>(at i64, mut out T[]):
	out.reserve(1)
	__memcpy(__ld64(__addr(out)), at + 8, __stride(__zeroElem(out)))
	__st64(__addr(out) + 8, 1)
	rtFree(at)

# the background threads made, once: under the lock, as two threads may start their first job at
# once
fn startJobWorkers():
	if jobSignal != 0: return
	lockJobs()
	if jobSignal != 0:
		unlockJobs()
		return
	jobSignal = CreateSemaphoreA(0, 0, 1_073_741_824, 0)
	threadsEnd = endThreads
	loop (cpuCount() - 1).max(1):
		spawnJobWorker()
	growSignal = CreateSemaphoreA(0, 0, 1_073_741_824, 0)
	launch(():
		jobGrower()
	)
	unlockJobs()

# one more background thread, under the jobs' lock
fn spawnJobWorker():
	launch(():
		jobWorker()
	)

# a background thread running run
fn launch(move run fn()):
	if not startThread(run):
		fail("cannot create a background thread")
	jobThreads += 1

# a background worker's life: wait for a job, take it from the queue, run it, drop it
fn jobWorker():
	_ = __xadd(__addr(jobsUp), 1)   # counted as started
	loop:
		WaitForSingleObject(jobSignal, -1)
		_ = __xadd(__addr(jobsBusy), 1)
		runJob()
		_ = __xadd(__addr(jobsBusy), -1)
		_ = __xadd(__addr(jobsLive), -1)   # after the task is dropped

# A thread about to wait for something outside the program (a socket, another machine) says so
# with blockingBegin() and blockingEnd() after: while jobs queue up and fewer than a processor's
# worth of the background threads are free to run them, one more thread starts, so a job that
# waits on a socket never keeps back the job whose answer it waits for.
pub fn blockingBegin():
	_ = __xadd(__addr(jobsBlocked), 1)
	if __ld64(__addr(jobsQueued)) > 0:
		_ = ReleaseSemaphore(__ld64(__addr(growSignal)), 1, 0)

pub fn blockingEnd():
	_ = __xadd(__addr(jobsBlocked), -1)

# the thread that starts the background threads blockingBegin() asks for (a job may not change
# the queue's variables itself)
fn jobGrower():
	_ = __xadd(__addr(jobsUp), 1)   # counted as started
	loop:
		WaitForSingleObject(growSignal, -1)
		growJobWorkers()

# starts background threads while more jobs wait than threads are idle and the threads not
# waiting on something are fewer than the processors allow
fn growJobWorkers():
	lockJobs()
	workers = jobThreads - 1   # the grower is not one
	idle = workers - __ld64(__addr(jobsBusy))
	free = workers - __ld64(__addr(jobsBlocked))
	while jobQueue.len > idle and free < (cpuCount() - 1).max(1) and workers < jobWorkerLimit:
		spawnJobWorker()
		workers += 1
		idle += 1
		free += 1
	unlockJobs()

# the oldest job taken from the queue and run, its task dropped on return
fn runJob():
	lockJobs()
	job = jobQueue.remove(0)
	unlockJobs()
	_ = __xadd(__addr(jobsQueued), -1)
	__callRec(__addr(job.run))

# back once every background job has run and dropped its task (a result is ready before its
# task is gone: what is still allocated is counted after this)
pub fn waitJobsDone():
	while fenced(__ld64(__addr(jobsLive))) > 0:
		_ = SwitchToThread()

fn lockJobs():
	lockWord(__addr(jobLock))

fn unlockJobs():
	__st64(__addr(jobLock), fenced(0))

# ---------- channels ----------
# A Channel<T> is a shared queue of owned values: copies of a channel are the same channel (the
# last one to go frees it). `send` waits while the queue is full (a capacity of 0 never is),
# `receive` waits while it is empty, and both stop waiting once the channel is closed. An
# unbounded channel is a list that a background job and the thread that started it change under
# its lock (a system slim lock); a bounded one is a ring (below) that takes no lock. A wait
# sleeps until a change of the queue wakes it, its processor free meanwhile.

# Channel<T>(capacity) holds up to capacity values (Channel<T>(), or 0: unbounded).
pub shared type Channel<T>:
	cap i64 = 0
	items T[] = []
	closed bool = false
	head i64 = 0
	lock i64 = 0   # an SRW lock, held while a thread changes the queue
	wake i64 = 0   # the word the sleeping threads wait on: a count of the changes that woke them
	changes i64 = 0   # how many times it did
	sleepers i64 = 0   # the threads asleep on `wake`, counted atomically (a ring's: for a value)
	roomSleepers i64 = 0   # a ring's sends asleep on `wake` for room
	slots T[] = []   # a bounded channel's ring, made at its first use
	stamps i64[] = []   # each slot's: its position when a send's turn, the position + 1 a receive's
	lap i64 = 0   # the positions' lap (0 until the ring is made)
	sent i64 = 0   # the next send's position
	taken i64 = 0   # the next receive's position

	# Queues a value; false when the channel is closed (the value is dropped).
	mut fn send(move v T) bool:
		if cap > 0:
			i = self.sendSlot() ?? return false
			slots[i] = v
			_ = fenced(__xadd(self.stampAt(i), 1))   # the receive's turn
			self.wakeSleepers(__addr(sleepers))
			return true
		AcquireSRWLockExclusive(__addr(lock))
		if closed:
			ReleaseSRWLockExclusive(__addr(lock))
			return false
		arenaPause()   # the queue outlives any arena
		items.push(v)
		arenaResume()
		self.unlockChanged()
		true

	# The next value; none once the channel is closed and drained.
	mut fn receive() T?:
		if cap > 0: return self.ringReceive(true)
		AcquireSRWLockExclusive(__addr(lock))
		while head == items.len and not closed:
			self.waitForChange("deadlock: receive on an empty channel with no job to send")
		v = takeHead()
		self.unlockChanged()
		v

	# The value at the head of the queue, without waiting; none when it is empty.
	mut fn tryReceive() T?:
		if cap > 0: return self.ringReceive(false)
		AcquireSRWLockExclusive(__addr(lock))
		v = takeHead()
		self.unlockChanged()
		v

	# the value at the head, taken under the lock
	mut fn takeHead() T?:
		if head == items.len: return none
		v = move items[head]
		head += 1
		if head == items.len:
			items.clear()
			head = 0
		v

	# the number of values waiting
	fn len() n64:
		if cap > 0: return n64(self.ringLen())
		AcquireSRWLockExclusive(__addr(lock))
		n = n64(items.len - head)
		ReleaseSRWLockExclusive(__addr(lock))
		n

	fn isEmpty() bool:
		if cap > 0: return self.ringLen() == 0
		AcquireSRWLockExclusive(__addr(lock))
		empty = items.len == head
		ReleaseSRWLockExclusive(__addr(lock))
		empty

	# no more values will be sent: receive gives none once the waiting ones are taken
	mut fn close():
		AcquireSRWLockExclusive(__addr(lock))
		closed = true
		self.unlockChanged()

	# the lock let go and the threads waiting on the queue woken to look at it again
	mut fn unlockChanged():
		changes += 1
		ReleaseSRWLockExclusive(__addr(lock))
		if __ld64(__addr(sleepers)) + __ld64(__addr(roomSleepers)) != 0: self.wakeAll()

	# A wait under the lock until the queue changes, while a background job lives, as it, or the
	# thread that started it, may answer (with none, nothing ever will): the change looked for a
	# moment, the lock let go, then asleep until a change wakes it.
	mut fn waitForChange(deadlock str):
		if __ld64(__addr(jobsLive)) == 0:
			ReleaseSRWLockExclusive(__addr(lock))
			fail(deadlock)
		seen = changes
		ReleaseSRWLockExclusive(__addr(lock))
		spins = 0
		while spins < channelSpins and __ld64(__addr(changes)) == seen:
			__pause()
			spins += 1
		if spins == channelSpins: self.sleepWhile(__addr(sleepers), __addr(changes), seen)
		AcquireSRWLockExclusive(__addr(lock))

	# Asleep on `wake` while the word at `word` still holds `seen` and the channel is open. The
	# sleeper is counted before it looks again, and a change is made by a locked operation before
	# the count is read (wakeAll), so one of the two sees the other; a wake between the reading of
	# `wake` and the sleep ends it at once. The poll ends a sleep nobody woke, so that a deadlock
	# is found when the last job ended meanwhile.
	mut fn sleepWhile(count i64, word i64, seen i64):
		_ = fenced(__xadd(count, 1))
		woken = __ld64(__addr(wake))
		if __ld64(word) == seen and __ld8(__addr(closed)) == 0:
			blockingBegin()
			_ = WaitOnAddress(__addr(wake), __addr(woken), 8, channelPollMs)
			blockingEnd()
		_ = __xadd(count, -1)

	# the sleeping threads woken to look at the queue again
	mut fn wakeAll():
		_ = __xadd(__addr(wake), 1)
		WakeByAddressAll(__addr(wake))

	# the ring made, once, by the first thread to use it
	mut fn ring():
		if fenced(__ld64(__addr(lap))) != 0: return
		AcquireSRWLockExclusive(__addr(lock))
		if lap == 0:
			arenaPause()   # the ring outlives any arena
			growZeroed(slots, cap)
			first i64[] = []
			for i in 0..cap:
				first.push(i)
			stamps = first
			arenaResume()
			l = 1
			while l <= cap:
				l *= 2
			__st64(__addr(lap), fenced(l))
		ReleaseSRWLockExclusive(__addr(lock))

	# the address of slot i's stamp
	fn stampAt(i i64) i64:
		__ld64(__addr(stamps)) + i * 8

	# the position after p
	fn nextPosition(p i64) i64:
		p + 1 if (p & (lap - 1)) + 1 < cap else (p & -lap) + lap

	# the index of the slot a send takes once the ring has room for it; none once the channel is
	# closed
	mut fn sendSlot() i64?:
		self.ring()
		loop:
			if __ld8(__addr(closed)) != 0: return none
			t = __ld64(__addr(sent))
			i = t & (lap - 1)
			at = self.stampAt(i)
			stamp = fenced(__ld64(at))
			if stamp == t:
				if __cmpxchg(__addr(sent), t, self.nextPosition(t)) == t: return i
			elif stamp + lap == t + 1:   # the value of the lap before still there: full
				self.waitStamp(
					at,
					stamp,
					"deadlock: send on a full channel with no job to receive",
					true
				)
			else:
				__pause()   # another send took t
		none

	# the next value of the ring, waiting for one when wait; none once the channel is closed and the
	# ring empty (or, not waiting, while it is empty)
	mut fn ringReceive(wait bool) T?:
		i = self.receiveSlot(wait) ?? return none
		v = move slots[i]
		_ = fenced(__xadd(self.stampAt(i), lap - 1))   # the next lap's send's turn
		if (i + 1) % ((cap + 1) / 2) == 0 or i + 1 == cap: self.wakeSleepers(__addr(roomSleepers))
		v

	# the index of the slot a receive takes once the ring holds a value (ringReceive's none)
	mut fn receiveSlot(wait bool) i64?:
		self.ring()
		loop:
			h = __ld64(__addr(taken))
			i = h & (lap - 1)
			at = self.stampAt(i)
			stamp = fenced(__ld64(at))
			if stamp == h + 1:
				if __cmpxchg(__addr(taken), h, self.nextPosition(h)) == h: return i
			elif stamp == h:   # empty, or a send at h still moving its value in
				if __ld8(__addr(closed)) != 0:
					if fenced(__ld64(at)) == h: return none
				elif not wait:
					return none
				else:
					self.waitStamp(
						at,
						h,
						"deadlock: receive on an empty channel with no job to send",
						false
					)
			else:
				__pause()   # another receive took h
		none

	# the values in the ring
	fn ringLen() i64:
		if fenced(__ld64(__addr(lap))) == 0: return 0
		loop:
			t = __ld64(__addr(sent))
			h = __ld64(__addr(taken))
			if __ld64(__addr(sent)) == t:
				hi = h & (lap - 1)
				ti = t & (lap - 1)
				if hi < ti: return ti - hi
				if hi > ti: return cap - hi + ti
				return 0 if t == h else cap
		0

	# A wait while the stamp at `at` stays seen and the channel open, while a background job lives
	# (with none, nothing ever changes it): the stamp looked at a moment, then asleep (sleepWhile).
	# No job left is a deadlock only if the stamp and the channel are still as seen after that:
	# the last job may have changed them since they were read (on a loaded machine, a long while).
	mut fn waitStamp(at i64, seen i64, deadlock str, room bool):
		if fenced(__ld64(__addr(jobsLive))) == 0 and __ld64(at) == seen and
			__ld8(__addr(closed)) == 0:
			fail(deadlock)
		spins = 0
		while spins < channelSpins:
			if __ld64(at) != seen or __ld8(__addr(closed)) != 0: return
			__pause()
			spins += 1
		self.sleepWhile(__addr(roomSleepers) if room else __addr(sleepers), at, seen)

	# the threads asleep on the ring that the count at `count` counts woken, once a stamp changed
	# (its locked add came before this reads the count)
	mut fn wakeSleepers(count i64):
		if __ld64(count) != 0: self.wakeAll()

# a wait's reads of the queue before it sleeps, a pause between two (x64's pause takes some hundred
# cycles): a few microseconds, so that a pipeline's steps that answer each other quickly seldom pay
# the system's sleep and wake-up, while a step that waits longer burns little (coroprimesieve:
# a sleep and a wake-up on a word are cheap enough that 30 reads beat 100 by 7% of its cycles)
channelSpins = 30

# the longest a sleeping wait goes without a look at whether a deadlock was reached
channelPollMs = 1000

# A bounded channel's ring (Vyukov's bounded queue, as crossbeam's array channel): cap slots,
# each with a stamp that says whose turn it is. A send or a receive takes its position by a
# compare-and-swap, moves its value and hands the slot on by its stamp: no lock. A position is a
# lap (a power of two past cap) and an index, the last index followed by the next lap's first.
# A wait for room or for a value looks at the stamp a moment, then sleeps on the `wake` word,
# counted in sleepers (roomSleepers for room): a send wakes the receives asleep once its
# value is in; a receive wakes the sends asleep only each half ring it frees, so a producer ahead
# of its consumer fills half a ring a wake-up instead of paying one a value.
