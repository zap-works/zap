# The files of a load parsed on every processor, as Go parses a package's files at once: each file
# is lexed and parsed (or read from the parse cache) apart from the program, into an arena of its
# own, by a job (parseApart); this thread appends them to the program's arena in the files' order
# (appendParsed), as each is ready, so the program is the same node for node as one parsed a file
# at a time. A job owns what it receives (a channel carries values) and the compiler refuses one
# that reads or changes a module variable that can change (JobEffect), so the asks are made, and
# the notes of what was parsed applied, on this thread.

# the file asked for at a place of the load
type ParseAt:
	at i64
	ask ParseAsk

# the file parsed for a place
type ParsedAt:
	at i64
	part ParsedApart

# the files of a load on their way: the jobs, what they give back, and the parsed files by their
# places as they arrive (none started below parseJobsFrom files: they are parsed here, as asked)
type ParseRun:
	asks ParseAsk[]
	done Channel<ParsedAt>
	jobs Background<bool>[]
	slots ParsedApart[]
	arrived bool[]

# fewer files than this are parsed on this thread (a job's start costs more than they do)
parseJobsFrom = 4

# a job's work: each file sent, parsed, until none is left
fn parseJob(sends Channel<ParseAt>, done Channel<ParsedAt>):
	inbox = sends
	outbox = done
	while true:
		item = inbox.receive() ?? break
		outbox.send(ParsedAt(at = item.at, part = item.ask.parseApart()))
	true

# the files asked for sent to jobs on the other processors (this one merges what they give back)
fn startParsing(move asks ParseAsk[]):
	run = ParseRun(asks = [], done = Channel<ParsedAt>(), jobs = [], slots = [], arrived = [])
	if asks.len < parseJobsFrom or cpuCount() < 2:
		run.asks = move asks
		return run
	sends = Channel<ParseAt>()
	count = asks.len
	asks.reverse()
	for at in 0..count:
		sends.send(ParseAt(at, ask = asks.pop() ?? fail("a file asked for is missing")))
	sends.close()
	loop (cpuCount() - 1).min(count):
		s = sends
		d = run.done
		run.jobs.push(background((): parseJob(s, d)))
	loop count:
		run.slots.push(emptyParsed())
	run.arrived = fill(count, false)
	run

fn emptyParsed():
	ParsedApart(
		file = "",
		cache = "",
		nodes = [],
		kidIds = NodeLists(),
		decls = [],
		notes = ParseNotes(),
		entry = "",
		ok = false
	)

# the file at place i parsed: the job's, waited for, or parsed here
fn parsedAt(mut run ParseRun, i i64):
	if run.jobs.isEmpty: return run.asks[i].parseApart()
	while not run.arrived[i]:
		item = run.done.receive() ?? fail("a file lost on its way to its parse")
		run.slots[item.at] = move item.part
		run.arrived[item.at] = true
	move run.slots[i]

# the run over: the jobs, which have nothing left to take, ended
fn finishParsing(run ParseRun):
	for job in run.jobs:
		while not job.isDone:
			sleepMs(0)
