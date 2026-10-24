# The passes of a round's functions run while the round's lowering goes on: each function lowered
# is sent to jobs on the other processors as soon as it is (irShip; one whose code is kept, which
# has none, is kept ready, and no job starts for a round of those alone), and irMakeAll waits for
# the last, then emits them in the order they were lowered. A job owns what it receives (a channel
# carries values) and the compiler refuses one that reads or changes a module variable that can
# change (JobEffect), so it can touch nothing the lowering writes; the output is the same whatever
# the threads do, since each function's passes read only that function and the emission's order is
# the lowering's.

# a function on its way through the passes, by its place in the round's made
type IrMadeAt:
	at i64
	m IrMade

# the jobs running the passes, what they are sent and what they give back
type IrPipe:
	sends Channel<IrMadeAt>
	done Channel<IrMadeAt>
	jobs Background<bool>[]

# the jobs (none while no function was sent), how many functions of the round were sent to them
# or kept ready (those whose code is kept: no passes), and those: this thread's alone
mut irPipeNow IrPipe? = none
mut irShipped = 0
mut irReady IrMadeAt[] = []

# a job's work: the passes of each function sent, until the round is over
fn irPassesJob(sends Channel<IrMadeAt>, done Channel<IrMadeAt>):
	inbox = sends
	outbox = done
	while true:
		item = inbox.receive() ?? break
		item.m.irPasses()
		outbox.send(move item)
	true

# a job on each processor but this one, which goes on lowering
fn irPipeStart():
	pipe = IrPipe(sends = Channel<IrMadeAt>(), done = Channel<IrMadeAt>(), jobs = [])
	loop (cpuCount() - 1).max(1):
		s = pipe.sends
		d = pipe.done
		pipe.jobs.push(background((): irPassesJob(s, d)))
	pipe

# the functions lowered since the last sent to the passes (their cache's form looked up first),
# numbered on from those sent before
fn irShip(mut g Gen):
	if g.made.isEmpty: return
	batch = move g.made
	g.made = []
	batch.reverse()
	while true:
		m = batch.pop() ?? break
		if m.code != none:
			irReady.push(IrMadeAt(at = irShipped, m = move m))
			irShipped += 1
			continue
		if irPipeNow == none:
			irPipeNow = irPipeStart()
		sends = (irPipeNow ?? fail("no passes started")).sends
		file = g.madeFile(m)
		m.irMadeReady(file)
		sends.send(IrMadeAt(at = irShipped, m = move m))
		irShipped += 1

# what stands in the round's made for a function at its passes
fn irMadeSent():
	IrMade(key = "", node = none, ret = tyUnit, f = newIrFn())

# m ready for its passes: its ownership verified after each when asked, its form as lowered
# shown when asked, the cache's form looked up (in the shard of file), and its target told
fn irMadeReady(mut m IrMade, file str):
	m.arm = onArm()
	m.f.check = IrOwnCheck(everyPass = irOwnEveryPass())
	if irLoweredWord().value() is which and (which == "" or which == m.key):
		eprint("{m.key}:")
		m.f.irOwnDump()
	if irCache.entry != "" and not m.passed:   # (a kept form is the passes' already)
		m.irCacheKey()
		m.irCacheLookup(file)

# the round's functions back from their passes, in the order they were lowered
fn irPipeDrain(mut g Gen):
	count = irShipped
	irShipped = 0
	ready = move irReady
	irReady = []
	made = []
	loop count:
		made.push(irMadeSent())
	sent = count - ready.len
	while true:
		item = ready.pop() ?? break
		made[item.at] = move item.m
	if sent == 0: return made
	inbox = (irPipeNow ?? fail("functions sent with no passes started")).sends
	outbox = (irPipeNow ?? fail("functions sent with no passes started")).done
	while true:   # this thread too, while some wait
		item = inbox.tryReceive() ?? break
		item.m.irPasses()
		outbox.send(move item)
	loop sent:
		item = outbox.receive() ?? fail("a function lost on its way through the passes")
		made[item.at] = move item.m
	made

# the jobs of the passes ended, once the last round is made (they wait for the next between
# rounds: a round's end waits for its functions, not for its jobs to end)
fn irPipeEnd():
	taken = move irPipeNow
	irPipeNow = none
	pipe = taken ?? return
	pipe.sends.close()
	for job in pipe.jobs:
		while not job.isDone:
			sleepMs(0)
