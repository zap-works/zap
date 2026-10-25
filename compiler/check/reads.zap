# What a function reads of a read parameter, as paths relative to it ("$.name"; "$" the value as a
# whole): a field read through it, what a call it is given to reads of its own parameter, and the
# whole value where it is used otherwise; in a method, a field named alone is a part of the
# receiver ("self"). A function whose body the summary cannot follow reads all of it. The borrow
# check reads it at a call given a name that borrows, so the call uses only those parts of what
# the name borrows (irownuses.zap). Found on demand and kept, a function met again through a cycle
# of calls reading the whole.

alias nodes = c.nodes
alias tys = c.types

# the paths fnd reads through its parameter param
fn readsThrough(mut c Checker, fnd NodeId, param str) str[]:
	key = effectKey(fnd, param)
	if c.reads.get(key) is known: return known.copy()
	if nodes[fnd].sub().isEmpty or nodes[fnd].hasFlag(flagExtern) or c.opaqueFunction(fnd):
		return ["$"]
	c.reads[key.copy()] = ["$"]
	fields = []
	if param == "self":
		fields = c.receiverFields(fnd) ?? return ["$"]
	out = PathSet()
	c.readBody(fnd)
	c.noteReads(nodes[fnd].sub()[0], none, none, param, fields, out)
	c.reads[key] = out.paths.copy()
	out.paths

# the field names of a method's receiver, none when they are not known
fn receiverFields(mut c Checker, md NodeId) str[]?:
	for d in c.decls:
		if nodes[d].kind != nImplDecl or md not in nodes[d].kids: continue
		sd = try c.findTypeDecl(nodes[d].text)
		return nodes[sd].kids.map(nodes[it].text.copy())
	none

fn noteReads(
	mut c Checker,
	e NodeId,
	parent NodeId?,
	grand NodeId?,
	param str,
	fields str[],
	mut out PathSet
):
	if out.has("$"): return
	if nodes[e].kind == nIdent:
		if nodes[e].text == param:
			c.noteParamRead(e, parent, grand, out)
		elif nodes[e].text in fields:
			out.add("$.{nodes[e].text}")
	for kid in nodes[e].kids:
		c.noteReads(kid, e, parent, param, fields, out)
	for sbAt in 0..nodes[e].sub().len:
		sb = nodes[e].sub()[sbAt]
		c.noteReads(sb, e, parent, param, fields, out)

# what the use e of the parameter reads of it, by where it is: a field read, a method called on
# it, an argument of a call, or else the whole value
fn noteParamRead(mut c Checker, e NodeId, parent NodeId?, grand NodeId?, mut out PathSet):
	if parent is p:
		k = nodes[p].kind
		if k == nField and nodes[p].kids[0] == e:
			if grand is g and nodes[g].kind == nCall and nodes[g].kids[0] == p:
				if c.calledMethod(p) is md:
					out.addAll(c.readsThrough(md, "self"))
					return
			elif c.isFieldOf(e, nodes[p].text):
				out.add("$.{nodes[p].text}")
				return
		elif k == nCall and nodes[p].kids[0] != e and c.calledDecl(p) is fnd:
			for i in 0..c.argCount(p):
				if c.argAt(p, i) == e and i < nodes[fnd].kids.len and
					nodes[nodes[fnd].kids[i]].ival == modeRead:
					out.addAll(c.readsThrough(fnd, nodes[nodes[fnd].kids[i]].text.copy()))
					return
	out.add("$")

# whether name is a field of the struct e is (not a getter of a built-in type: `xs.first` reads
# the elements)
fn isFieldOf(mut c Checker, e NodeId, name str):
	t = c.receiverType(e)
	c.tKind(t) == tStruct and c.fieldIndexOf(declOf(tys, t), name) >= 0
