# Type checker, zap fmt's trials of written types (spec 2.4): a function's bindings that write
# their type (`n i64 = 0`, `x f32 = 0.0`, `ok bool = false`) are checked again without it, on a
# copy of its body as parsed, once every body is checked. The types go where every node of the
# copy gets the type it got, with no error: all of them together, else each alone. What a trial
# makes goes with it (resulttrials.zap's marks).

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

type LetTrial:
	origin NodeId
	parsed NodeId   # its declaration as parsed, copied again for each trial
	impl NodeId?   # a method's

# with zap fmt's notes on: the function fnd's trial, when it binds a name with its type written
fn openLetTrial(mut c Checker, fnd NodeId, impl NodeId?):
	if not noting or nodes[fnd].kind != nFnDecl or not nodes[fnd].names().isEmpty or
		nodes[fnd].sub().isEmpty or nodes[fnd].text == "main" or nodes[fnd].text2() == "main" or
		nodes[fnd].mod() == "rt" or nodes[fnd].mod() == "derive" or isGpuFile(nodes[fnd].file()):
		return
	if c.typedLets(nodes[fnd].sub()[0]).isEmpty: return
	c.letTrials.push(LetTrial(origin = fnd, parsed = cloneTree(nodes, kidIds, fnd), impl))

# the lets under e that bind a new name with its type written and a value that names no type of
# its own: a literal (a number, a bool, a text), an empty list or map
fn typedLets(c Checker, e NodeId) NodeId[]:
	out = []
	if nodes[e].kind == nLet and not nodes[e].types().isEmpty and
		not nodes[e].kids(kidIds).isEmpty and
		not nodes[nodes[e].types()[0]].hasFlag(flagInternal) and nodes[e].text != "_" and
		not nodes[e].text.startsWith("$") and not nodes[e].hasFlag(flagCompound) and
		c.untypedValue(nodes[e].kids(kidIds)[0]):
		out.push(e)
	for k in nodes[e].kids(kidIds):
		out.extend(c.typedLets(k))
	for k in nodes[e].sub():
		out.extend(c.typedLets(k))
	out

# whether e, as parsed, is a value whose type its place may give: a literal, a negated number,
# `[]`, `{}` (a `none` takes its type from a later assignment, which the lowering reads apart)
fn untypedValue(c Checker, e NodeId):
	k = nodes[e].kind
	if k in [nInt, nFloat, nBool, nStr]: return true
	if k == nUnary and nodes[e].kids(kidIds).len == 1:
		return nodes[nodes[e].kids(kidIds)[0]].kind in [nInt, nFloat]
	(k == nArray or k == nMapLit) and nodes[e].kids(kidIds).isEmpty

fn runLetTrials(mut c Checker):
	if c.errors > 0: return
	for i in 0..c.letTrials.len:
		trial = c.letTrials[i].copy()
		c.enterModuleOf(trial.origin)
		lets = c.typedLets(nodes[trial.parsed].sub()[0])
		every = (0..lets.len).filter(not c.writesClaim(nodes[lets[it]].types()[0])).map(it)
		for k in c.letsAlike(trial, every, 2):
			c.noteTypeDropped(lets[k])

# the lets of ks (indexes into the trial's typed lets) whose types go alike: all of them when they
# do together, else those of each half, down to depth halvings
fn letsAlike(mut c Checker, trial LetTrial, ks i64[], depth i64) i64[]:
	if ks.isEmpty: return []
	if c.letsGoAlike(trial, ks): return ks.copy()
	if depth == 0 or ks.len == 1: return []
	half = ks.len / 2
	out = c.letsAlike(trial, ks[..half], depth - 1)
	out.extend(c.letsAlike(trial, ks[half..], depth - 1))
	out

# whether the written type te claims what the compiler proves where it is bound (a range, n32, n64,
# a defined type): kept, even where the value has that type anyway
fn writesClaim(mut c Checker, te NodeId) bool:
	if nodes[te].kind == nTyRange: return true
	if nodes[te].kind == nTyName:
		if nodes[te].text == "n32" or nodes[te].text == "n64": return true
		if c.lookupDecl(
			nStructDecl,
			nodes[te].text2(),
			nodes[te].text,
			nodes[te].line,
			nodes[te].col
		) is d and
			nodes[d].hasFlag(flagTypeAlias):
			return true
	nodes[te].types().any(c.writesClaim(it)) or nodes[te].kids(kidIds).any(c.writesClaim(it))

# whether a copy of the trial's function without the written types of its typed lets at indexes
# ks checks with no error, every node of the same type as the function's own
fn letsGoAlike(mut c Checker, trial LetTrial, ks i64[]):
	copy = cloneTree(nodes, kidIds, trial.parsed)
	lets = c.typedLets(nodes[copy].sub()[0])
	for k in ks:
		nodes[lets[k]].nodePart().types = []
	marks = c.checkMarks()
	inferred = c.resultState.get(trial.origin) != none
	if inferred: c.resultState[copy] = resultChecking
	c.asideCopy = copy
	saved = c.putBodyAside()
	c.enterScope()
	match trial.impl:
		impl: c.checkFnBody(copy, c.implTypeOf(impl), c.receiverIsMut(trial.origin))
		none: c.checkFnBody(copy, none, false)
	c.exitScope()
	c.pending.clear()
	c.takeBodyBack(saved)
	c.asideCopy = none
	c.resultState.remove(copy)
	clean = c.errors == marks.errors
	c.backToMarks(marks)
	clean and c.sameTyped(nodes[trial.origin].sub()[0], nodes[copy].sub()[0])

# whether the checked trees a and b have the same nodes, each of the same type
fn sameTyped(c Checker, a NodeId, b NodeId) bool:
	if c.readAsLiteral(a, b) or c.readAsLiteral(b, a):
		return isSameType(tys, typeOf(nodes, a), typeOf(nodes, b))
	if nodes[a].kind != nodes[b].kind or nodes[a].kids(kidIds).len != nodes[b].kids(kidIds).len or
		nodes[a].sub().len != nodes[b].sub().len:
		return false
	match nodes[a].ty:
		ta:
			tb = nodes[b].ty ?? return false
			if not isSameType(tys, ta, tb): return false
		none:
			if nodes[b].ty != none: return false
	for i in 0..nodes[a].kids(kidIds).len:
		if not c.sameTyped(nodes[a].kids(kidIds)[i], nodes[b].kids(kidIds)[i]): return false
	for i in 0..nodes[a].sub().len:
		if not c.sameTyped(nodes[a].sub()[i], nodes[b].sub()[i]): return false
	true

# whether a is a name and b the number it reads as a literal (a binding of numbers alone, checkExprRawIdent)
fn readAsLiteral(c Checker, a NodeId, b NodeId):
	nodes[a].kind == nIdent and (nodes[b].kind == nInt or nodes[b].kind == nFloat) and
		nodes[a].ty != none and nodes[b].ty != none

# the let s's written type noted for zap fmt as gone: `x T = v` is `x = v`
fn noteTypeDropped(mut c Checker, s NodeId):
	line = nodes[s].line
	src = c.file if c.curFile == "" else c.curFile
	text = sourceLineOf(src, line)
	code = codeOf(text)
	name = nodes[s].text
	p = code.len - code.trimmedStart().len
	if code[p..].startsWith("mut "):
		p += 4
	start = p + name.len
	eq = code.indexOf(" = ") ?? -1
	if eq <= start or text[p..start] != name or text[start] != ' ': return
	c.canonNote(noteReplace, line, start + 1, eq - start, "")
