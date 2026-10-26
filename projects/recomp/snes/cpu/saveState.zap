# A save state taken where the CPU is at an instruction's start (console/saveState.zap): saved,
# or loaded and gone on with as a task switch goes on (interrupts.zap), the program unwinding to
# `reset`, which interprets from the loaded place; the 65816's stack in work RAM holds the returns.

import recomp.snes.console

fn cpuFields(mut f console.StateFile):
	a = f.word(a)
	x = f.word(x)
	y = f.word(y)
	s = f.word(s)
	d = f.word(d)
	dbr = f.byte(dbr)
	n = f.isSet(n)
	v = f.isSet(v)
	z = f.isSet(z)
	c = f.isSet(c)
	irqDisabled = f.isSet(irqDisabled)
	decimal = f.isSet(decimal)
	e = f.isSet(e)
	widthsNow = f.long(widthsNow)
	resumeAt = f.long(resumeAt)
	resumeWidths = f.byte(resumeWidths)

fn machineFields(mut f console.StateFile):
	cpuFields(f)
	console.consoleFields(f)

# The request the frame's end armed, at the instruction start resumeAt: whether the code returns,
# unwinding (a state was loaded).
fn actOnState() bool:
	path, loading = console.takeStateRequest()
	if path.isEmpty: return false
	if not loading:
		f = console.savingState()
		_ = console.headerMismatch(f)
		machineFields(f)
		console.writeState(path, f)
		return false
	saved = console.stateBytes(path) ?? return false
	f = console.StateFile(loading = true, reader = Reader(d = saved))
	if console.headerMismatch(f) is why:
		console.refuseState(path, why)
		return false
	before = console.savingState()
	machineFields(before)
	machineFields(f)
	if not f.isWhole():
		console.refuseState(path, "it is cut short or too long")
		back = console.StateFile(loading = true, reader = Reader(d = before.out))
		machineFields(back)
		return false
	interruptStacks = []
	leftForGood = false
	switched = true
	ret = unwinding
	true
