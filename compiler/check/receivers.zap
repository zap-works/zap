# Type checker, receivers: a method written in its type's block that is not `pub` and does not
# write `mut fn` changes its receiver when its body does (spec 5.2). The bodies of those methods
# are checked before the other bodies (checkBlockMethods), each as one that reads its receiver
# until a change of it is met (receiverChange): then it is `mut` and the body goes again. A mode
# read before its body is checked has the body checked then (receiverChanges, checkBodyNow); a
# body that read it as reading before it was found changing goes again too (reopenReader). zap
# fmt drops a written `mut` where the body gives it alike.

alias nodes = c.nodes
alias kidIds = c.kidIds

receiverOpen = 0   # not checked yet
receiverChecking = 1
receiverDone = 2

# whether fnd is a method of a type's block whose receiver its body tells: not `pub`, no `mut`
# written (a generic function taking self first, for one with type parameters of its own)
fn receiverInferred(c Checker, fnd NodeId):
	if nodes[fnd].kind != nFnDecl or nodes[fnd].ival != methodInBlock or
		nodes[fnd].hasFlag(flagPub | flagMut):
		return false
	nodes[fnd].names(kidIds).isEmpty or nodes[nodes[fnd].kids(kidIds)[0]].ival != modeMut

# The block methods whose receivers are inferred, open before any instance copies them
fn openReceivers(mut c Checker):
	for d in c.decls[c.freshDecls..]:
		k = nodes[d].kind
		if k == nFnDecl and c.receiverInferred(d):
			c.receiverState[d] = receiverOpen
		elif k == nImplDecl and nodes[d].origin(kidIds) == none:
			for m in nodes[d].kids(kidIds):
				if not c.receiverInferred(m): continue
				c.receiverState[m] = receiverOpen
				if nodes[d].names(kidIds).isEmpty: c.methodImpl[m] = d

# the method whose receiver's state fnd's stands for (itself, or the generic's method fnd copies)
fn receiverKey(c Checker, fnd NodeId) NodeId?:
	key = c.receiverOf.get(fnd) ?? fnd
	if c.receiverState.get(key) == none: return none
	key

# copy, an instance's copy of the method m, kept in step with it
fn noteReceiverCopy(mut c Checker, copy NodeId, m NodeId):
	if c.receiverState.get(m) != none: c.receiverOf[copy] = m

# Every block method whose receiver is inferred checked, before the other bodies; a body opened
# again (reopenReader) is checked again
fn checkBlockMethods(mut c Checker):
	going = true
	while going:
		going = false
		for d in c.decls[c.freshDecls..].copy():
			if nodes[d].kind != nImplDecl or nodes[d].origin(kidIds) != none or
				not nodes[d].names(kidIds).isEmpty:
				continue
			for m in nodes[d].kids(kidIds).copy():
				if (c.receiverState.get(m) ?? -1) == receiverOpen:
					c.checkOpenBody(m)
					going = true

# the generic d's methods whose receivers its definition check told: done, or tried when it waits
# for another's (one that waits for it then reads it as it stands)
fn receiversTried(mut c Checker, d NodeId):
	state = receiverChecking if c.deferred else receiverDone
	if nodes[d].kind == nFnDecl and c.receiverState.get(d) != none:
		c.receiverState[d] = state
	elif nodes[d].kind == nImplDecl:
		for m in nodes[d].kids(kidIds):
			if c.receiverState.get(m) != none: c.receiverState[m] = state

# every generic method's receiver told once the definitions are checked
fn receiversDefined(mut c Checker):
	for d in c.decls[c.freshDecls..]:
		k = nodes[d].kind
		if k == nFnDecl and c.receiverState.get(d) != none:
			c.receiverState[d] = receiverDone
		elif k == nImplDecl and not nodes[d].names(kidIds).isEmpty:
			for m in nodes[d].kids(kidIds):
				if c.receiverState.get(m) != none: c.receiverState[m] = receiverDone

# whether the method m changes its receiver, read by the body being checked: an open method's
# body checked first (a generic's definition check deferred instead, made again after it)
fn receiverChanges(mut c Checker, m NodeId):
	key = c.receiverKey(m) ?? return nodes[m].hasFlag(flagMut)
	state = c.receiverState.get(key) ?? receiverDone
	if state == receiverOpen and c.receiversOpen and c.methodImpl.get(key) != none:
		if c.atDefinition:
			c.earlyResults.push(key)
			c.deferred = true
		else:
			c.checkBodyNow(key)
			state = receiverDone
	elif state == receiverOpen and c.atDefinition and c.receiverKey(c.curFn ?? key) != key:
		c.deferred = true   # another generic's: its definition check first
		return c.receiverIsMut(key)
	if c.curFn is reader and reader != key:
		if state != receiverDone or c.bodyReopens(reader):
			match c.receiverReaders.get(key):
				mut readers:
					if reader not in readers: readers.push(reader)
				none: c.receiverReaders[key] = [reader]
	c.receiverIsMut(key)

fn receiverIsMut(c Checker, m NodeId):
	if nodes[m].ival == methodInBlock and not nodes[m].names(kidIds).isEmpty:
		return nodes[nodes[m].kids(kidIds)[0]].ival == modeMut   # (self its first parameter)
	nodes[m].hasFlag(flagMut)

# whether body f is one checked when needed, which goes again when what it read changes
fn bodyReopens(c Checker, f NodeId):
	c.resultState.get(f) != none or c.receiverState.get(f) != none and c.methodImpl.get(f) != none

# A change of the variable v met in the body being checked: whether it is the receiver of a
# method written in its block whose mode the body tells, the change then taken (the caller makes
# no error of its own). With `mut fn` written the change is only noted, for zap fmt.
fn receiverChange(mut c Checker, v i64, line i64, col i64):
	if not c.vars[v].isField and c.vars[v].name != "self": return false
	fnd = c.curFn ?? return false
	if nodes[fnd].ival != methodInBlock: return false
	inLambda = c.isCapturedVar(v)
	if c.vars[v].isMut:
		if inLambda:
			c.receiverUntold = true
		elif not c.changeVia:
			c.receiverSeen = true
		return false
	name = nodes[fnd].text2(kidIds).copy() if nodes[fnd].text2(kidIds) != ""
		else nodes[fnd].text.copy()
	if nodes[fnd].hasFlag(flagPub):
		c.errorAt(line, col, compileError("PubMethodChanges", [name]))
		return true
	key = c.receiverKey(fnd) ?? return false
	if inLambda:
		c.errorAt(line, col, compileError("ReceiverUntold", [name, "inside a lambda"]))
		return true
	if (c.receiverState.get(key) ?? -1) == receiverDone and not c.bodyReopens(key):
		c.errorAt(line, col, compileError("ReceiverUntold", [name, "in this instance only"]))
		return true
	c.receiverChanged = true
	true

# receiverChange for v when it is a variable (-1: none)
fn receiverNamed(mut c Checker, v i64, line i64, col i64):
	v >= 0 and c.receiverChange(v, line, col)

# At the end of a round of fnd's body: whether it found its receiver changed, and is then mut
# (with the copies of it and the mut parameters' table), the bodies that read it as reading it
# going again
fn receiverFound(mut c Checker, fnd NodeId):
	if not c.receiverChanged: return false
	c.receiverChanged = false
	key = c.receiverKey(fnd) ?? return false
	c.makeReceiverMut(fnd)
	c.makeReceiverMut(key)
	for copy, of in c.receiverOf:
		if of == key: c.makeReceiverMut(copy)
	if not c.mutParams.isEmpty:
		c.addMutParams(key, 1, true)
	for reader in c.receiverReaders.get(key) ?? []:
		c.reopenReader(reader, key)
	true

fn makeReceiverMut(mut c Checker, m NodeId):
	if nodes[m].ival == methodInBlock and not nodes[m].names(kidIds).isEmpty:
		nodes[nodes[m].kids(kidIds)[0]].ival = modeMut
	else:
		nodes[m].flags |= flagMut

# reader read key's receiver as read before key was found changing it: checked again (now when
# its check is under way, its next round)
fn reopenReader(mut c Checker, reader NodeId, key NodeId):
	if c.errors > 0: return   # (its errors are reported once)
	if not c.bodyReopens(reader):
		if key not in c.receiverStale: c.receiverStale.push(key)
		return
	if (c.resultState.get(reader) ?? -1) == resultChecking or
		(c.receiverState.get(reader) ?? -1) == receiverChecking:
		if reader not in c.receiverAgain: c.receiverAgain.push(reader)
		return
	if (c.receiverState.get(reader) ?? -1) == receiverDone and not c.receiverIsMut(reader):
		c.receiverState[reader] = receiverOpen
	if c.resultState.get(reader) is state and state != resultOpen:
		c.resultState[reader] = resultOpen
		if not nodes[reader].types(kidIds).isEmpty and
			nodes[nodes[reader].types(kidIds)[0]].hasFlag(flagInternal):
			nodes[reader].nodePart(kidIds).types.clear()   # found, found again

# the methods found changing their receivers after a body that cannot go again read them as
# reading: an error each, once the body that found it is checked (a round's errors may go)
fn reportStaleReceivers(mut c Checker):
	for key in c.receiverStale.copy():
		name = nodes[key].text2(kidIds).copy() if nodes[key].text2(kidIds) != ""
			else nodes[key].text.copy()
		c.errorAt(
			nodes[key].line,
			nodes[key].col,
			compileError("ReceiverUntold", [name, "after another body read it as reading it"])
		)
	c.receiverStale.clear()

# whether the round of fnd's body just checked goes again for its receiver: it found it changed,
# or a mode it read was found otherwise later
fn receiverAgainFor(mut c Checker, fnd NodeId):
	if c.receiverFound(fnd): return true
	at = c.receiverAgain.indexOf(fnd) ?? return false
	c.receiverAgain.remove(at)
	true

# zap fmt: the `mut` of `mut fn` dropped off a block's method that is not `pub` where its body
# changes its receiver as an inferred one's is told: not only in a lambda, not only by calls of
# the block methods whose modes could be inferred (two that call each other would read)
fn noteReceiverWritten(mut c Checker, fnd NodeId, errorsBefore i64):
	if not noting or not c.receiverSeen or c.receiverUntold or c.errors != errorsBefore: return
	if nodes[fnd].ival != methodInBlock or nodes[fnd].hasFlag(flagPub) or c.trialCopy == fnd or
		c.receiverOf.get(fnd) != none or not c.subst.names.isEmpty and not c.atDefinition:
		return
	written = nodes[fnd].hasFlag(flagMut) if nodes[fnd].names(kidIds).isEmpty
		else nodes[nodes[fnd].kids(kidIds)[0]].ival == modeMut
	line = nodes[fnd].line
	col = nodes[fnd].col
	if not written or c.receiverState.get(fnd) != none or col <= 4: return
	if c.sourceAt(line, col - 4, 4) != "mut ": return
	c.canonNote(noteReplace, line, col - 4, 4, "", syntax = true)
