# Type checker, zap fmt's trials of written results (results.zap): a function that is not `pub`
# and writes its result is checked again as if it did not, on a copy of its body as parsed, once
# every body is checked (a body checked twice is not the same check: its calls are made the
# functions they found). The result is dropped where the copy gives it alike, with no error, and
# no cycle of calls through functions whose bodies give their results would hold it: that
# recursion asks for the result written. What a trial makes (instances, declarations, notes,
# errors) goes with it.

alias nodes = c.nodes
alias tys = c.types

type Trial:
	origin NodeId
	copy NodeId   # its declaration as parsed, checked by the trial
	impl NodeId?   # a method's

# with zap fmt's notes on: the function fnd whose result the body being checked asked
fn noteResultCall(mut c Checker, fnd NodeId):
	from = c.trialOrigin() ?? return
	match c.resultCalls.get(from):
		mut calls:
			if fnd not in calls: calls.push(fnd)
		none: c.resultCalls[from] = [fnd]

# the function whose body is being checked, a trial's copy read as its origin
fn trialOrigin(c Checker) NodeId?:
	at = try c.curFn
	if c.trialCopy == at:
		for trial in c.trials:
			if trial.copy == at: return trial.origin
	at

fn runTrials(mut c Checker):
	if c.errors > 0: return
	alike = []
	for i in 0..c.trials.len:
		if c.trialGivesAlike(i): alike.push(c.trials[i].origin)
	for d in c.withoutCycles(alike):
		if c.variantFns.get(d) != none: continue
		c.enterModuleOf(d)
		c.noteResultDropped(d)
	c.runLetTrials()

# how far the checker's lists went before a trial, which takes back what it made
type CheckMarks:
	decls i64
	instances i64
	derives i64
	lent i64
	arena i64
	rowFns i64
	fieldwise i64
	grads i64
	gradHelpers i64
	notes i64
	errors i64

fn checkMarks(c Checker):
	CheckMarks(
		decls = c.decls.len,
		instances = c.instances.len,
		derives = c.deriveTypes.len,
		lent = c.lentChecks.len,
		arena = c.arenaCalls.len,
		rowFns = c.rowFunctions.len,
		fieldwise = c.fieldwise.len,
		grads = c.gradAsks.len,
		gradHelpers = c.gradHelpers.len,
		notes = formNotes.len,
		errors = c.errors
	)

fn backToMarks(mut c Checker, m CheckMarks):
	c.errors = m.errors
	formNotes.truncate(m.notes)
	c.truncateDecls(m.decls)
	c.truncateInstances(m.instances)
	c.deriveTypes.truncate(m.derives)
	c.deriveKinds.truncate(m.derives)
	c.deriveDone.truncate(m.derives)
	c.lentChecks.truncate(m.lent)
	c.arenaCalls.truncate(m.arena)
	c.rowFunctions.truncate(m.rowFns)
	c.fieldwise.truncate(m.fieldwise)
	c.gradAsks.truncate(m.grads)
	c.gradHelpers.truncate(m.gradHelpers)

# whether trial i's copy, checked as if it wrote no result, gives the written one
fn trialGivesAlike(mut c Checker, i i64):
	origin = c.trials[i].origin
	copy = c.trials[i].copy
	impl = c.trials[i].impl
	marks = c.checkMarks()
	c.resultState[origin] = resultChecking   # a call of itself met, read as recursion
	c.trialCopy = copy
	c.trialAlike = false
	saved = c.putBodyAside()
	c.enterScope()
	match impl:
		impl: c.checkFnBody(copy, c.implTypeOf(impl), c.receiverIsMut(origin))   # (as found)
		none: c.checkFnBody(copy, none, false)
	c.exitScope()
	c.pending.clear()
	c.takeBodyBack(saved)
	alike = c.trialAlike and (c.resultState.get(origin) ?? -1) == resultChecking
	c.resultState.remove(origin)
	c.trialCopy = none
	c.backToMarks(marks)
	alike

# the functions of alike none of which a cycle of calls holds through the functions whose bodies
# give their results, these among them once dropped
fn withoutCycles(c Checker, alike NodeId[]):
	kept = alike.copy()
	changed = true
	while changed:
		open {NodeId: bool} = {}
		for d in c.resultState.keys():
			open[d] = true
		for d in kept:
			open[d] = true
		next = kept.filter(not c.callsItself(it, open))
		changed = next.len != kept.len
		kept = next
	kept

# whether d is reached again from its calls through the functions in open
fn callsItself(c Checker, d NodeId, open {NodeId: bool}):
	seen {NodeId: bool} = {}
	todo = (c.resultCalls.get(d) ?? []).copy()
	while not todo.isEmpty:
		f = todo.pop() ?? break
		if f == d: return true
		if f in seen or f not in open: continue
		seen[f] = true
		todo.extend(c.resultCalls.get(f) ?? [])
	false
