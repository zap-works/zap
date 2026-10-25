# Unsigned integers are bits (spec 3.1): a hash, a mask, a file's bytes, arithmetic that wraps on
# purpose. A parameter, a local or a field written as a u16, u32 or u64 that no bit operation, shift,
# wrapping arithmetic or foreign call reads, and that goes into no other unsigned place, is a
# count or an index: a quantity, which is a natural (n32, n64). The checker says so as an error.
# Bytes (u8) are the data text and files are made of, never asked.

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# how the node that holds an expression reads it: as a quantity (compared, an index, a range's
# bound, converted to a signed integer or a float), as either (printed), or as anything else
quantityRead = 0
otherRead = 1
eitherRead = 2

# the parameters and locals of fnd written as unsigned integers that are quantities, reported
fn reportQuantities(mut c Checker, fnd NodeId):
	if nodes[fnd].sub().isEmpty or nodes[fnd].hasFlag(flagExtern) or nodes[fnd].hasFlag(flagGpu) or
		not nodes[fnd].names().isEmpty or not c.subst.names.isEmpty or c.inRuntimeOrDerived():
		return
	body = nodes[fnd].sub()[0]
	written = []
	for p in nodes[fnd].kids(kidIds):
		if p != fnd and nodes[p].kind == nParam and not nodes[p].types().isEmpty: written.push(p)
	c.writtenLets(body, written)
	for d in written:
		t = c.resolveType(nodes[d].types()[0])
		if c.tKind(t) != tInt or tys[t].isSigned or tys[t].bits == 8 or tys[t].ranged or
			isDefined(tys, t) or nodes[d].text == "_" or nodes[d].text == "self":
			continue
		reads = [0, 0, 0]
		c.countReads(body, nodes[d].text, otherRead, reads)
		if reads[quantityRead] > 0 and reads[otherRead] == 0:
			c.errorAt(
				nodes[d].line,
				nodes[d].col,
				compileError(
					"UnsignedQuantity",
					["{nodes[d].text}", "{c.showTy(t)}", "n64" if tys[t].bits == 64 else "n32"]
				)
			)

# the lets under e written with a type, pushed onto out (a lambda's are its own)
fn writtenLets(c Checker, e NodeId, mut out NodeId[]):
	k = nodes[e].kind
	if k == nLambda: return
	if k == nLet and not nodes[e].types().isEmpty and nodes[e].names().isEmpty: out.push(e)
	for kid in nodes[e].kids(kidIds):
		c.writtenLets(kid, out)
	for sb in nodes[e].sub():
		c.writtenLets(sb, out)

# the reads of name under e, counted by how they are read (how: the way e's holder reads it)
fn countReads(mut c Checker, e NodeId, name str, how i64, mut reads i64[]):
	k = nodes[e].kind
	if k == nIdent:
		if nodes[e].text == name: reads[how] += 1
		return
	if k == nCall and nodes[e].hasFlag(flagWrap) and nodes[nodes[e].kids(kidIds)[0]].kind == nField:
		# `i64.wrap(x)`: x's bits
		for kid in nodes[nodes[e].kids(kidIds)[0]].kids(kidIds):
			c.countReads(kid, name, otherRead, reads)
		return
	kidHow = otherRead
	if k == nBinary and nodes[e].ival >= binEq and nodes[e].ival <= binGe or k == nRange or
		c.convertsToQuantity(e):
		kidHow = quantityRead
	elif k == nInterp:
		kidHow = eitherRead
	for i in 0..nodes[e].kids(kidIds).len:
		kid = nodes[e].kids(kidIds)[i]
		c.countReads(kid, name, quantityRead if k == nIndex and i == 1 else kidHow, reads)
	for sb in nodes[e].sub():
		c.countReads(sb, name, otherRead, reads)

# whether e converts an integer into a signed integer or a float (written, or the checker's
# widening): its operand read as a quantity
fn convertsToQuantity(mut c Checker, e NodeId):
	if nodes[e].kind != nField or nodes[e].kids(kidIds).len != 1: return false
	m = nodes[e].text
	if m == "toF32" or m == "toF64": return true
	i = intConversions.indexOf(m) ?? return false
	i < 4

# A struct's field written as a u16, u32 or u64 (Field) and its reads in the program's bodies
type FieldReads:
	decl NodeId   # the struct
	field NodeId
	reads i64[]   # by how: quantityRead, otherRead, eitherRead

# the fields of the program's structs written as unsigned integers that every read in the
# program reads as a quantity, reported once every body is checked. A struct laid out for the
# system or a foreign function receives, and a field of a name read where its struct is unknown or
# in a GPU body, is bits.
fn reportQuantityFields(mut c Checker):
	if c.errors > 0: return
	fields = []
	for d in c.decls:
		if nodes[d].kind != nStructDecl or not nodes[d].names().isEmpty or
			nodes[d].hasFlag(flagExtern) or nodes[d].mod() in ["rt", "derive"]:
			continue
		c.enterModuleOf(d)
		for f in nodes[d].kids(kidIds).copy():
			t = c.resolveType(nodes[f].types()[0])
			if c.tKind(t) == tInt and not tys[t].isSigned and tys[t].bits > 8 and
				not tys[t].ranged and not isDefined(tys, t):
				fields.push(FieldReads(decl = d, field = f, reads = [0, 0, 0]))
	if fields.isEmpty: return
	foreign = []
	gone = []
	for d in c.decls:
		if nodes[d].kind == nFnDecl and nodes[d].hasFlag(flagExtern):
			c.enterModuleOf(d)
			for p in nodes[d].kids(kidIds).copy():
				if not nodes[p].types().isEmpty:
					c.foreignStructs(c.resolveType(nodes[p].types()[0]), foreign)
		gpu = nodes[d].hasFlag(flagGpu)
		for kid in nodes[d].kids(kidIds):
			c.countFieldReads(kid, otherRead, gpu, fields, gone)
		for sb in nodes[d].sub():
			c.countFieldReads(sb, otherRead, gpu, fields, gone)
	for fr in fields:
		f = fr.field
		if fr.reads[quantityRead] == 0 or fr.reads[otherRead] > 0 or fr.decl in foreign or
			nodes[f].text in gone:
			continue
		c.enterModuleOf(fr.decl)
		t = c.resolveType(nodes[f].types()[0])
		c.errorAt(
			nodes[f].line,
			nodes[f].col,
			compileError(
				"UnsignedQuantity",
				["{nodes[f].text}", "{c.showTy(t)}", "n64" if tys[t].bits == 64 else "n32"]
			)
		)

# the struct declarations a foreign function receives through t, nested ones too, onto out
fn foreignStructs(mut c Checker, t TypeId, mut out NodeId[]):
	u = c.derefType(t)
	if c.tKind(u) != tStruct or declOf(tys, u) in out: return
	d = declOf(tys, u)
	out.push(d)
	for f in nodes[d].kids(kidIds).copy():
		c.enterModuleOf(d)
		c.foreignStructs(c.resolveType(nodes[f].types()[0]), out)

# the reads under e of the fields, counted by how they are read (how: the way e's holder reads
# it); a field's name read where its struct is unknown, or in a GPU body, goes onto gone
fn countFieldReads(
	mut c Checker,
	e NodeId,
	how i64,
	gpu bool,
	mut fields FieldReads[],
	mut gone str[]
):
	k = nodes[e].kind
	if k == nField and nodes[e].kids(kidIds).len == 1 and
		fields.any(nodes[.field].text == nodes[e].text):
		t = c.derefType(typeOf(nodes, nodes[e].kids(kidIds)[0]))
		if gpu or c.tKind(t) != tStruct:
			gone.push(nodes[e].text.copy())
		elif fields.findIndex(.decl == declOf(tys, t) and nodes[.field].text == nodes[e].text) is i:
			fields[i].reads[how] += 1
	kidHow = otherRead
	if k == nBinary and nodes[e].ival >= binEq and nodes[e].ival <= binGe or k == nRange or
		c.convertsToQuantity(e):
		kidHow = quantityRead
	elif k == nInterp:
		kidHow = eitherRead
	for i in 0..nodes[e].kids(kidIds).len:
		kid = nodes[e].kids(kidIds)[i]
		if k == nCall and i == 0 and nodes[kid].kind == nField:
			# a method's name: its receiver is read
			c.countFieldReads(nodes[kid].kids(kidIds)[0], otherRead, gpu, fields, gone)
			continue
		kidHow2 = quantityRead if k == nIndex and i == 1 else kidHow
		c.countFieldReads(kid, kidHow2, gpu, fields, gone)
	for sb in nodes[e].sub():
		c.countFieldReads(sb, otherRead, gpu, fields, gone)
