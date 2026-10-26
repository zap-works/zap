# A generic's body is lowered only per instance, where a type parameter is a type of the program;
# at its definition, where T stands for any type that is not Copy, a value of T this code does
# not own is never given away: a borrowed parameter (MoveOfBorrowed), a part of a place
# (MoveOfPart). The places given: what is returned (the body's value too), an argument to a
# `move` parameter, a field of a literal, an element of a list literal, what a list's push takes.
# So is, in any function, a value in one owned word (a box, a map, an optional of one), which the
# lowered form gives as the word itself.

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

fn checkDefinitionGives(mut c Checker, fnd NodeId):
	c.checkLentGiven(fnd, false)

# the owned words a function that is not generic gives away without owning them
fn checkWordsGiven(mut c Checker, fnd NodeId):
	if nodes[fnd].mod() == "derive": return
	c.checkLentGiven(fnd, true)

# whether a value of type t is one owned word: a box (not a counted one, which a copy counts), a
# map, or an optional of one
fn ownedWord(c Checker, t TypeId) bool:
	k = c.tKind(t)
	if k == tOption: return c.ownedWord(tys[t].inner ?? tyError)
	k == tMap or k == tBox and not tys[t].counted

# the values given away by fnd without owning them: of the owned words (words), else of the
# type parameters that are not Copy
fn checkLentGiven(mut c Checker, fnd NodeId, words bool):
	if nodes[fnd].sub().isEmpty or nodes[fnd].mod() == "rt": return   # (the runtime's by hand)
	lent = []   # the names it only borrows: its parameters but those it takes `move`
	for p in nodes[fnd].kids(kidIds):
		if nodes[p].ival != modeMove:
			lent.push(nodes[p].text.copy())
	body = nodes[fnd].sub()[0]
	c.definitionGivesIn(body, lent, words)
	kids = nodes[body].kids(kidIds).copy()
	if not words and c.tKind(c.fnRetType(fnd)) != tUnit and not kids.isEmpty:
		last = kids[len - 1]
		if nodes[last].kind == nExprStmt:
			c.definitionGiven(nodes[last].kids(kidIds)[0], lent, words)

fn definitionGivesIn(mut c Checker, e NodeId, mut lent str[], words bool):
	k = nodes[e].kind
	if k == nLet and nodes[e].text in lent:
		lent.remove(lent.indexOf(nodes[e].text) ?? 0)   # bound again: a value of its own
	if k == nReturn and not nodes[e].kids(kidIds).isEmpty:
		c.definitionGiven(nodes[e].kids(kidIds)[0], lent, words)
	if k == nStructLit or k == nArray:
		for kidAt in 0..nodes[e].kids(kidIds).len:
			kid = nodes[e].kids(kidIds)[kidAt]
			c.definitionGiven(kid, lent, words)
	if k == nCall and not nodes[e].kids(kidIds).isEmpty:
		callee = nodes[e].kids(kidIds)[0]
		if nodes[callee].kind == nIdent and
			c.findFunc(nodes[callee].text, nameOf(nodes, callee)) is fnd:
			for i in 0..c.argCount(e):
				if i < nodes[fnd].kids(kidIds).len and
					nodes[nodes[fnd].kids(kidIds)[i]].ival == modeMove:
					c.definitionGiven(c.argAt(e, i), lent, words)
		if nodes[callee].kind == nField and nodes[callee].text == "push" and c.argCount(e) == 1:
			c.definitionGiven(c.argAt(e, 0), lent, words)
	for kidAt in 0..nodes[e].kids(kidIds).len:
		kid = nodes[e].kids(kidIds)[kidAt]
		c.definitionGivesIn(kid, lent, words)
	for bAt in 0..nodes[e].sub().len:
		b = nodes[e].sub()[bAt]
		c.definitionGivesIn(b, lent, words)

# e given away: an error when its type is an owned word (words), else a type parameter that is not
# Copy, and this code does not own it
fn definitionGiven(mut c Checker, e NodeId, lent str[], words bool):
	t = typeOf(nodes, e)
	refused = c.ownedWord(t) if words else c.standInIndex(t) >= 0 and not c.isPlainType(t)
	if not refused: return
	k = nodes[e].kind
	if k == nIdent and nodes[e].text in lent:
		c.errorAt(
			nodes[e].line,
			nodes[e].col,
			compileError("MoveOfBorrowed", ["{nodes[e].text}"]) + c.copyBoundHint(t)
		)
	elif k in [nField, nIndex, nDeref]:
		found, below = c.placePath(e)
		head = ""
		if found is r:
			head = nodes[r].text.copy()
		if not c.atDefinition and head not in lent: return   # a local's part: taken out (spec 4.1)
		belongs = "the value behind this reference belongs to someone else" if head == ""
			else "'{head}{below}' belongs to '{head}'"
		c.errorAt(
			nodes[e].line,
			nodes[e].col,
			compileError("MoveOfPart", ["{belongs}"]) + c.copyBoundHint(t)
		)

# ---------- zap fmt: a written `move` the place's owner's last use makes implied ----------

# `move x.f` where x is a local of this function that no later statement names, outside a
# loop: the part moves out without the `move` (the lowered form's check takes it), so zap fmt
# drops the word
fn noteImpliedMoves(mut c Checker, fnd NodeId):
	if not noting or nodes[fnd].sub().isEmpty: return
	locals = []
	for p in nodes[fnd].kids(kidIds):
		if nodes[p].ival == modeMove:
			locals.push(nodes[p].text.copy())
	c.impliedMovesIn(nodes[fnd].sub()[0], locals, [])

fn impliedMovesIn(mut c Checker, b NodeId, mut locals str[], after NodeId[]):
	kids = nodes[b].kids(kidIds).copy()
	for i, s in kids:
		later = kids[i + 1..].copy()
		later.extend(after)
		if nodes[s].kind == nLet and not nodes[s].kids(kidIds).isEmpty and
			nodes[s].text not in locals:
			locals.push(nodes[s].text.copy())
		if nodes[s].kind == nFor or nodes[s].kind == nWhile: continue   # a later turn may read it
		c.impliedMovesOf(s, locals, later)
		for subAt in 0..nodes[s].sub().len:
			sub = nodes[s].sub()[subAt]
			if nodes[sub].kind == nBlock:
				c.impliedMovesIn(sub, locals, later)

fn impliedMovesOf(mut c Checker, e NodeId, locals str[], later NodeId[]):
	k = nodes[e].kind
	if k == nCall and nodes[e].hasFlag(flagInternal) and nodes[e].kids(kidIds).len == 1 and
		nodes[nodes[e].kids(kidIds)[0]].kind == nField and
		nodes[nodes[e].kids(kidIds)[0]].text == "take":
		place = nodes[nodes[e].kids(kidIds)[0]].kids(kidIds)[0]
		root = place
		while nodes[root].kind == nField or nodes[root].kind == nIndex:
			root = nodes[root].kids(kidIds)[0]
		name = nodes[root].text.copy()
		if root != place and nodes[root].kind == nIdent and name in locals and
			not later.any(mentions(nodes, kidIds, it, false, name)) and
			not c.copiesFreely(typeOf(nodes, place)):
			line = nodes[e].line
			src = c.file.copy() if c.curFile == "" else c.curFile.copy()
			text = sourceLineOf(src, line)
			at = nodes[e].col - 1
			if nodes[root].line == line and nodes[root].col > nodes[e].col and at >= 0 and
				at + 5 <= text.len and text[at..at + 5] == "move ":
				c.canonNote(noteReplace, line, at + 1, nodes[root].col - nodes[e].col, "")
	for kidAt in 0..nodes[e].kids(kidIds).len:
		kid = nodes[e].kids(kidIds)[kidAt]
		c.impliedMovesOf(kid, locals, later)
