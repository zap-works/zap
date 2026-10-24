# `lockstep` in ZAP_RUN: each translated function the dispatcher enters runs, its stores noted
# (memory's journal), its memory put back, then the interpreter runs the
# same thread from the same state to the place the function left at; the registers, flags and the
# bytes either wrote must agree, else the run stops naming the function and the first difference.
# The thread goes on from the interpreter's state. Slow: a diagnostic of the translation.

fn lockstepWord():
	TraceWord(
		"lockstep",
		"recomp.switch runs each translated function entered on the interpreter too and stops at the first difference (lockstep=n: from turn n)"
	)

pub mut lockstep = lockstepWord().on() and lockstepFrom() < 0

# the turn `lockstep=n` starts checking at (the frontend counts them), -1 without one
pub fn lockstepFrom() i64:
	i64.parse(lockstepWord().value() ?? "") ?? -1

# while journaling, each byte a store is about to change and its value before, in order (a byte
# stored twice is there twice): lists, which clear at once however long the last run made them
mut journaling = false
mut journalAt i64[] = []
mut journalWas u8[] = []

fn noteBytes(at i64, n i64):
	for a in at..at + n:
		journalAt.push(a)
		journalWas.push(window.load8(a))

fn clearJournal():
	journalAt.clear()
	journalWas.clear()

# each byte the journal names with its value now, and with its value before the journal began
fn journalBytes() ({i64: u8}, {i64: u8}):
	now {i64: u8} = {}
	was {i64: u8} = {}
	for k in journalAt.len - 1..-1 step -1:
		now[journalAt[k]] = window.load8(journalAt[k])
		was[journalAt[k]] = journalWas[k]
	(now, was)

# memory put back as it was before the journal began
fn undoJournal():
	for k in journalAt.len - 1..-1 step -1:
		window.store8(journalAt[k], journalWas[k])

# Runs the translated function f on c and the interpreter on a copy from the same state, compares
# them and leaves c as the interpreter left it.
pub fn lockstepRun(mut c Cpu, f i64, mut code Decoded):
	start = c.copy()
	clearJournal()
	journaling = true
	functions[f].run(mut ref c)
	journaling = false
	if c.pc == start.pc and not c.isHalted and c.budget == start.budget: return   # it ran nothing
	translated, _ = journalBytes()
	undoJournal()
	model = start.copy()
	clearJournal()
	journaling = true
	# the translated code pays a block's instructions on entering it: the interpreter runs no more
	# than that, and stops where the registers agree (a loop passes the place several times)
	charged = start.budget - c.budget + 64
	steps = 0
	compared = model.copy()
	while not model.isHalted and steps < charged:
		code.runAt(model, model.pc)
		steps += 1
		if model.pc == c.pc and model.x[arm64.sp] == c.x[arm64.sp]:
			compared = model.copy()
			if model.x == c.x: break
	if not model.isHalted and steps >= charged: model = compared.copy()
	journaling = false
	interpreted, was = journalBytes()
	said = differences(c, model, translated, interpreted, was)
	if not said.isEmpty:
		fail("lockstep: f{functions[f].at:x} entered at {start.pc:x}, left at {c.pc:x} after {steps} interpreted: {said.join("; ")}")
	model.budget = c.budget
	c = model.copy()

# what differs between the translated run (c, the bytes it stored as it left them) and the
# interpreter's (model, the bytes it stored as it left them and as they were before both; memory
# is as it left it)
fn differences(c Cpu, model Cpu, translated {i64: u8}, interpreted {i64: u8}, was {i64: u8}) str[]:
	out = []
	if c.pc != model.pc or c.isHalted != model.isHalted:
		out.push(
			"pc {c.pc:x} halted {c.isHalted}, interpreted {model.pc:x} halted {model.isHalted}"
		)
	for r in 0..=arm64.sp:
		if c.x[r] != model.x[r]: out.push("x{r} {c.x[r]:x}, interpreted {model.x[r]:x}")
	if c.nzcv() != model.nzcv(): out.push("nzcv {c.nzcv():x}, interpreted {model.nzcv():x}")
	for k in 0..c.q.len:
		if c.q[k] != model.q[k]: out.push("q word {k} {c.q[k]:x}, interpreted {model.q[k]:x}")
	for a, v in translated:
		if v != window.load8(a): out.push("byte {a:x} {v:x}, interpreted {window.load8(a):x}")
	for a, v in interpreted:
		if a not in translated and v != was[a]: out.push("byte {a:x} unchanged, interpreted {v:x}")
	out[..out.len.min(12)].copy()
