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
# or kept ready (those whose code is kept: no passes), and those back or ready by their places
# (the others stand in): this thread's alone
mut irPipeNow IrPipe? = none
mut irShipped = 0
mut irBack IrMade[] = []
mut irBackIn bool[] = []
# the instructions as lowered of the round's functions sent before each place, and in all
mut irSentBefore i64[] = []
mut irSentInsts = 0

# the first place of the round not yet held or passed over (irHeld.zap), and the source file and
# the runtime's flag its emission begins in, as the places before leave them
mut irHeldNext = 0
mut irHeldFile = ""
mut irHeldRt = false

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
	if irShipped == 0:
		irHeldFile = g.debugFiles[g.curFile].copy() if g.curFile >= 0 and
			g.curFile < g.debugFiles.len
			else ""
		irHeldRt = g.inRt
	batch = move g.made
	g.made = []
	batch.reverse()
	while true:
		m = batch.pop() ?? break
		irSentBefore.push(irSentInsts)
		if m.code != none:
			irBackPut(irShipped, move m)
			irShipped += 1
			continue
		irSentInsts += m.f.blocks.sum(.insts.len)
		if irPipeNow == none:
			irPipeNow = irPipeStart()
		sends = (irPipeNow ?? fail("no passes started")).sends
		file = g.madeFile(m)
		m.irMadeReady(file)
		sends.send(IrMadeAt(at = irShipped, m = move m))
		irShipped += 1
	g.irHoldBack()
	g.irFlightBounded()

# m back at its place of the round
fn irBackPut(at i64, move m IrMade):
	while irBack.len <= at:
		irBack.push(irMadeSent())
		irBackIn.push(false)
	irBack[at] = move m
	irBackIn[at] = true

# the functions back from their passes taken, their forms kept for the cache, and those in order
# from irHeldNext held (irHeld.zap)
fn irHoldBack(mut g Gen):
	if irPipeNow is pipe:
		outbox = pipe.done
		while true:
			item = outbox.tryReceive() ?? break
			item.m.irCacheStore()
			irBackPut(item.at, move item.m)
	g.irHoldInOrder()

# Past this many functions of the round sent and not yet held, or this many of their instructions
# but more than one function, this thread runs the passes of one waiting for them, else waits for
# one back: the lowering runs ahead of the passes by a bounded number of forms on any number of
# processors (on two, unbounded, it held thousands), and big functions' passes, some 600 bytes an
# instruction, do not all run at once (BotW's part of nine of 7,000 lines peaked at 0.7 GB).
irFlightMost = 64
irFlightInstsMost = 600_000

fn irFlightBounded(mut g Gen):
	while irShipped - irHeldNext > irFlightMost or
		irShipped - irHeldNext > 1 and irSentInsts - irSentBefore[irHeldNext] > irFlightInstsMost:
		pipe = irPipeNow ?? return
		inbox = pipe.sends
		outbox = pipe.done
		if not irPassesHere(inbox, outbox):
			item = outbox.receive() ?? fail("a function lost on its way through the passes")
			item.m.irCacheStore()
			irBackPut(item.at, move item.m)
		g.irHoldBack()

# the passes of one function waiting for them run on this thread: false when none waits
fn irPassesHere(inbox Channel<IrMadeAt>, outbox Channel<IrMadeAt>):
	item = inbox.tryReceive() ?? return false
	item.m.irPasses()
	outbox.send(move item)
	true

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
	irHeldNext = 0
	irSentBefore = []
	irSentInsts = 0
	made = move irBack
	irBack = []
	back = move irBackIn
	irBackIn = []
	while made.len < count:
		made.push(irMadeSent())
		back.push(false)
	sent = back.count(not it)
	if sent == 0: return made
	inbox = (irPipeNow ?? fail("functions sent with no passes started")).sends
	outbox = (irPipeNow ?? fail("functions sent with no passes started")).done
	while irPassesHere(inbox, outbox):   # this thread too, while some wait
		continue
	waitFrom = clockSeconds()
	loop sent:
		item = outbox.receive() ?? fail("a function lost on its way through the passes")
		made[item.at] = move item.m
	phaseRoundWaited(clockSeconds() - waitFrom, made[0].key if made.len == 1 else "")
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
