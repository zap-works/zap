# Mutability inferred (spec 2.4): a binding written without `mut` is mutable when what follows it
# in its block changes it. Found when the binding is checked, its value's type known and before
# it is added, so what a mutable binding decides (a copy of a referenced value, a number's type,
# the facts kept of an immutable one) is decided as if `mut` were written; the bit is the let's
# own flagMut, which the ownership pass and the IR read.

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# whether the statements after the let s in the block being checked change its name (of type ty)
fn changedLater(mut c Checker, s NodeId, ty TypeId):
	if c.openBlocks.isEmpty or nodes[s].hasFlag(flagInternal) or nodes[s].text == "_": return false
	value = nodes[s].kids(kidIds)[0]
	if nodes[value].kind == nUnary and nodes[value].ival == unMutRef or
		c.tKind(ty) == tRef and tys[ty].bits == 1:
		return false   # a mut ref binding: a change through it changes the place it lends
	b = c.openBlocks[len - 1]
	at = c.openAt[len - 1]
	if at >= nodes[b].kids(kidIds).len or nodes[b].kids(kidIds)[at] != s: return false
	name = nodes[s].text.copy()
	c.indexMentions(b)
	for k in (c.openMentions[len - 1].byName.get(nameOf(nodes, s)) ?? []).copy():
		if k > at and c.changesName(nodes[b].kids(kidIds)[k], name, ty): return true
	false

# the block b's statements named by each name, in order, made once on the first let that asks: a
# statement changes a name only if it mentions it (an identifier, or a let of it), so the walk
# of a let reaches those statements alone
fn indexMentions(mut c Checker, b NodeId):
	if c.openIndexed[len - 1]: return
	c.openIndexed[len - 1] = true
	for k in 0..nodes[b].kids(kidIds).len:
		noteNames(nodes, kidIds, nodes[b].kids(kidIds)[k], k, c.openMentions[len - 1].byName)

# statement k noted under the names e and everything under it mention (once a name)
fn noteNames(ns Node[], ks NodeId[], e NodeId, k i64, mut byName {i64: i64[]}):
	if ns[e].kind == nIdent or ns[e].kind == nLet:
		addUnder(byName, numberedName(ns, e), k, once = true)
	for kid in ns[e].kids(ks):
		noteNames(ns, ks, kid, k, byName)
	for kid in ns[e].sub():
		noteNames(ns, ks, kid, k, byName)

# whether e changes the variable name (of type elem) or a part of it: as the text tells
# (syntax/changes.zap), or by a call of a method changing it or handing it to a `mut` parameter
fn changesName(mut c Checker, e NodeId, name str, elem TypeId) bool:
	if textChanges(nodes, kidIds, e, name): return true
	if nodes[e].kind == nCall and c.callChangesName(e, name, elem): return true
	for kidAt in 0..nodes[e].kids(kidIds).len:
		kid = nodes[e].kids(kidIds)[kidAt]
		if c.changesName(kid, name, elem): return true
	for kidAt in 0..nodes[e].sub().len:
		kid = nodes[e].sub()[kidAt]
		if c.changesName(kid, name, elem): return true
	false

# whether the call e changes the variable name: a changing method called on it or a part of it,
# or it or a part of it handed to a function's mut parameter
fn callChangesName(mut c Checker, e NodeId, name str, elem TypeId):
	callee = nodes[e].kids(kidIds)[0]
	if nodes[callee].kind == nField and nodes[callee].kids(kidIds).len == 1:
		recv = nodes[callee].kids(kidIds)[0]
		m = nodes[callee].text.copy()   # (checking a part's type changes c)
		mNumber = nameOf(nodes, callee)
		if c.rootName(recv) == name:
			if c.partType(recv, elem) is pt:
				t = pt
				if nodes[callee].hasFlag(flagSafe) and c.tKind(pt) == tOption:
					t = tys[pt].inner ?? pt   # a ?. call's method is the value's
				return c.methodChanges(t, m)
			# a part whose type the text does not tell: any function of the name changing what it
			# is called on
			return c.methodIsMutating(m) or c.mutParamsOf(m) & 1 != 0
		if m == "fromBytes" and c.isReader(elem) and nodes[e].kids(kidIds).len == 2 and
			c.rootName(nodes[e].kids(kidIds)[1]) == name:
			return true   # T.fromBytes(r) advances the Reader r
		# a type's or a module's function takes the arguments from its first parameter on, a
		# method from its second (its receiver may be bound after the name)
		t = nodes[recv].text
		if nodes[recv].kind == nIdent and t != "" and not (t[0] >= 'A' and t[0] <= 'Z') and
			c.lookupVar(t) < 0 and c.findImportByAlias(c.curMod, t) is imp:
			# a module's function: its own parameters, not those of every method of its name
			fd = c.findDeclInModule(nodes[imp].text, nFnDecl, m, mNumber) ?? return false
			return c.lendsMut(e, name, mutMask(nodes, kidIds, fd, 0, 0), 0)
		named = nodes[recv].kind == nIdent and t != "" and
			(t[0] >= 'A' and t[0] <= 'Z' or t == "rt")
		return c.lendsMut(e, name, c.mutParamsOf(m), 0 if named else 1)
	if nodes[callee].kind != nIdent: return false
	if nodes[callee].text == "str" and nodes[e].kids(kidIds).len == 2 and c.tKind(elem) == tList and
		isSameType(tys, tys[elem].inner ?? tyError, tyInt(8, false)):
		arg = nodes[e].kids(kidIds)[1]
		if nodes[arg].kind == nUnary and nodes[arg].ival == unMove and
			c.rootName(nodes[arg].kids(kidIds)[0]) == name:
			return true   # str(move bytes): the bytes become the text, their place []
	fd = c.lookupDecl(nFnDecl, "", nodes[callee].text.copy(), nodes[e].line, nodes[e].col) ??
		return c.siblingLendsMut(e, name, nodes[callee].text)
	for j in 1..nodes[e].kids(kidIds).len:
		arg = nodes[e].kids(kidIds)[j]
		if j - 1 < nodes[fd].kids(kidIds).len and
			nodes[nodes[fd].kids(kidIds)[j - 1]].ival == modeMut and
			c.rootName(arg) == name:
			return true
	false

# a bare call no function the module sees declares: a sibling method inside an impl (its receiver
# first), else a built-in, which changes no argument (another module's pub names are not seen)
fn siblingLendsMut(mut c Checker, e NodeId, name str, m str):
	impl = c.implType ?? return false
	md = c.findMethod(tys[impl].name, m) ?? return false
	c.lendsMut(e, name, mutMask(nodes, kidIds, md, 1 if nodes[md].hasFlag(flagMut) else 0, 1), 1)

# whether the method m of a value of type t changes it
fn methodChanges(mut c Checker, t0 TypeId, m str):
	t = innerOf(tys, t0) if c.tKind(t0) == tBox else t0   # a box's methods are its value's
	k = c.tKind(t)
	if k == tStruct or k == tEnum:
		if c.findMethod(tys[t].name, m) is md: return c.receiverChanges(md)
	if m == "next" and c.isRuntimeType(t, "Random"): return true   # next(range): nextInt or nextFloat
	c.methodIsMutating(m) or c.receiverFunctions(t, m.copy()).any(c.takesMutFirst(it))

# the type of the place e, the variable at its root of type t: through the fields of a struct
# that is no generic's and the elements or slices of a list, an array or a text; none when the
# text does not tell it
fn partType(mut c Checker, e NodeId, t TypeId) TypeId?:
	k = nodes[e].kind
	if k == nIdent: return t
	if k != nField and k != nIndex: return none
	whole = try c.partType(nodes[e].kids(kidIds)[0], t)
	wt = c.derefType(whole)
	wk = c.tKind(wt)
	if k == nField:
		if wk != tStruct or nodes[e].hasFlag(flagSafe): return none
		d = declOf(tys, wt)
		if not nodes[d].names().isEmpty: return none
		f = try c.kidNamed(d, nodes[e].text)
		return c.resolveType(nodes[f].types()[0])
	ranged = nodes[e].kids(kidIds).len == 2 and nodes[nodes[e].kids(kidIds)[1]].kind == nRange
	if wk == tStr: return tyStr if ranged else tyInt(8, false)
	if wk != tList and wk != tArray or tys[wt].inner == none: return none
	if ranged: return wt
	innerOf(tys, wt)

# whether an argument of the call e is name or a part of it and stands for a parameter of mask (a
# bit each), the first argument for parameter first
fn lendsMut(c Checker, e NodeId, name str, mask i64, first i64):
	if mask == 0: return false
	for j in 1..nodes[e].kids(kidIds).len:
		at = j - 1 + first
		if at < 63 and mask & (1 << at) != 0 and c.rootName(nodes[e].kids(kidIds)[j]) == name:
			return true
	false

# the mut parameters of the functions named m that the caller sees (a private one of another
# module is none of them), a bit for each argument of a method's call (the receiver first: a
# method's `mut self` or a function's first parameter); those past 62 not told. The table is
# made on the first ask of each stage, of the declarations not in it yet.
fn mutParamsOf(mut c Checker, m str):
	if c.mutParamsStage != c.freshDecls:
		for i in c.mutParamsTo..c.decls.len:
			d = c.decls[i]
			k = nodes[d].kind
			if k == nFnDecl:
				# (a type's method goes with the type; the runtime's private functions are std's too)
				seen = c.declIsPub(d) or c.takesSelf(d) or nodes[d].mod() == "rt"
				c.noteMutParams(d, 0, 0, seen)
			elif k == nImplDecl or k == nBoundDecl:
				for f in nodes[d].kids(kidIds):
					# (its self taken out of the parameters; a bound's: what a value of a type
					# parameter is called with)
					c.noteMutParams(f, 1 if nodes[f].hasFlag(flagMut) else 0, 1, true)
		c.mutParamsTo = c.decls.len
		c.mutParamsStage = c.freshDecls
		c.mutParams["$"] = 0   # made, if no function has one
	mask = c.mutParams.get(m) ?? 0
	for own in c.ownModules():
		mask |= c.mutParams.get(privateMutKey(own, m)) ?? 0
	mask

fn noteMutParams(mut c Checker, fd NodeId, first i64, shift i64, seen bool):
	c.addMutParams(fd, mutMask(nodes, kidIds, fd, first, shift), seen)

# fd's mut parameters, a bit each from bit shift on, over the bits of first
fn mutMask(ns Node[], nsKids NodeId[], fd NodeId, first i64, shift i64):
	mask = first
	for j in 0..ns[fd].kids(nsKids).len.min(62):
		if ns[ns[fd].kids(nsKids)[j]].ival == modeMut:
			mask |= 1 << (j + shift)
	mask

# the mask joined to the function fd's names in the table: names any module sees when seen (a pub
# function, a type's method), else names its own module's alone
fn addMutParams(mut c Checker, fd NodeId, mask i64, seen bool):
	for word in [nodes[fd].text.copy(), nodes[fd].text2().copy()]:
		if word == "": continue
		key = word.copy() if seen else privateMutKey(nodes[fd].mod(), word)
		c.mutParams[key] = (c.mutParams.get(key) ?? 0) | mask

fn privateMutKey(mod str, name str):
	"{mod}\t{name}"
