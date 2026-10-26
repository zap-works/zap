# The shortest forms of a fallback (spec 6.4, 6.5) the checker notes for zap fmt (canon.zap):
# `r ?? fail(error)` of a str error is `r ?? fail`, and `x ?? return none` of an optional in a
# function whose result is an optional is `try x`.

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# `x.copy()` (e): noted for zap fmt as `x`, which the program's check with the notes applied
# takes back where its ownership check refuses it (verifyNotes): kept where neither a borrow nor
# a move would serve
fn noteCopyDropped(mut c Checker, e NodeId):
	if not noting or not c.subst.names.isEmpty: return
	callee = nodes[e].kids(kidIds)[0]
	recv = nodes[callee].kids(kidIds)[0]
	if nodes[recv].kind in [nStr, nInterp, nArray, nMapLit]: return   # a literal's copy is a block of its own
	line = nodes[callee].line
	col = nodes[callee].col - 1   # the `.` before copy
	if col < 1 or c.sourceAt(line, col, 7) != copyCall: return
	c.canonNote(noteReplace, line, col, 7, "")

copyCall = ".copy()"

# `r ?? fail(error)`, r's error a str: noted as `r ?? fail`
fn noteFailAlone(mut c Checker, rhs NodeId, lt TypeId):
	if not noting or nodes[rhs].kind != nCall or nodes[rhs].kids(kidIds).len != 2: return
	callee = nodes[rhs].kids(kidIds)[0]
	arg = nodes[rhs].kids(kidIds)[1]
	if nodes[callee].kind != nIdent or nodes[callee].text != "fail" or nodes[arg].kind != nIdent or
		nodes[arg].text != errorWord or c.lookupVar("fail") >= 0:
		return
	if c.tKind(tys[lt].err ?? tyError) != tStr or
		c.sourceAt(nodes[callee].line, nodes[callee].col, 11) != "fail(error)":
		return
	c.canonNote(noteReplace, nodes[callee].line, nodes[callee].col, 11, "fail")

# `x ?? return none` (e), x an optional, in a function whose result is an optional: noted as
# `try x` where x is a chain of names, fields, calls and indexes standing alone on the left
fn noteTryOptional(mut c Checker, e NodeId, lt TypeId):
	rhs = nodes[e].kids(kidIds)[1]
	if not noting or c.tKind(lt) != tOption or nodes[rhs].kind != nReturn or
		nodes[rhs].kids(kidIds).len != 1 or nodes[nodes[rhs].kids(kidIds)[0]].kind != nNone:
		return
	if c.findingResult():
		c.tryForms.push(e)   # written so once the result found is an optional (settleOpenTries)
		return
	if c.inferringRet or not c.lamStack.isEmpty or c.tKind(c.currentRet ?? tyUnit) != tOption:
		return
	c.noteTryForm(e)

# the `x ?? return none` e noted as `try x`, x standing alone on its left
fn noteTryForm(mut c Checker, e NodeId):
	line = nodes[e].line
	text = c.sourceAt(line, 1, 100_000)
	op = nodes[e].col - 1
	tail = " ?? return none"
	if op < 1 or op > text.len or not text[op - 1..].startsWith(tail): return
	start = chainStart(text, op - 1)
	if start < 0 or not standsAlone(text, start) or c.notedAt(line, start + 1): return
	c.canonNote(noteReplace, line, op, tail.len, "")
	c.canonNote(noteReplace, line, start + 1, 0, "try ")

# where the chain of names, fields, calls and indexes ending at end (exclusive) starts, or -1
fn chainStart(text str, end i64):
	i = end
	while i > 0:
		b = text[i - 1]
		if b.isWordByte() or b == '.':
			i -= 1
		elif b == ')' or b == ']':
			open = openerOf(text, i - 1)
			if open < 0: return -1
			i = open
		else:
			break
	if i == end or not text[i].isWordStart(): return -1
	i

# the index of the bracket that the `)` or `]` at i closes, strings skipped, or -1
fn openerOf(s str, i i64):
	kinds = byteKinds(s)
	depth = 0
	k = i
	while k >= 0:
		if kinds[k] == byteCode and (s[k] == ')' or s[k] == ']'):
			depth += 1
		elif kinds[k] == byteCode and (s[k] == '(' or s[k] == '['):
			depth -= 1
			if depth == 0: return k
		k -= 1
	-1

# whether the operand at start is a whole value of its place: the line's start, or after an
# opening bracket, a comma, an assignment or `return`
fn standsAlone(text str, start i64):
	before = text[..start].trimmedEnd()
	if before.trimmed().isEmpty or before.endsWith("return"): return true
	if before.isEmpty: return true
	last = before[len - 1]
	if last in ['(', '[', ',']: return true
	last == '=' and before.len >= 2 and before[len - 2] not in ['=', '<', '>', '!']
