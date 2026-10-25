# The GPU lowering of expressions: operators, matches, calls and methods (irgpu.zap).

import shader

alias nodes = w.c.nodes
alias kidIds = w.c.kidIds
alias tys = w.c.types

# the type of part k of a value of type t
fn glPartTy(w GpuLower, t shader.Ty, k i64):
	if t.base == shader.bStruct and t.arr < 0: return w.structs.members[t.sid][k]
	t.elemOf()

# whether a field is a matrix's `m` (its numbers, column by column)
fn glMatrixArray(mut w GpuLower, e NodeId) bool ? shader.GpuError:
	nodes[e].kind == nField and nodes[e].text == "m" and
		(try w.glTy(nodes[nodes[e].kids(kidIds)[0]].ty, e)).isMatrix()

# ---------- expressions ----------

# an expression's value in a vreg (-1 for one of unit type)
fn glExpr(mut w GpuLower, e NodeId) i64 ? shader.GpuError:
	n = nodes[e].copy()
	k = n.kind
	if k == nInt or k == nFloat: return try w.glNumber(e)
	if k == nBool: return w.glBool(n.ival == 1)
	if k == nIdent: return try w.glName(e)
	if k == nField: return try w.glField(e)
	if k == nIndex: return try w.glIndex(e)
	if k == nCall: return try w.glCall(e)
	if k == nUnary: return try w.glUnary(e)
	if k == nBinary: return try w.glBinary(e)
	if k == nStructLit: return try w.glStructLit(e)
	if k == nArray:
		# its elements, the rest of a fixed array zero (`mut m f32[16]`: all of it)
		t = try w.glTyOfNode(e)
		if n.kids(kidIds).isEmpty: return w.glConst(t, 0)
		elements = (try w.glExprs(n.kids(kidIds))).map(w.glAs(it, t.elemOf()))
		while elements.len < t.arr:
			elements.push(w.glConst(t.elemOf(), 0))
		return w.glMake(t, elements)
	if k == nMatch: return try w.glMatch(e)
	if k == nBlock: return try w.glBlock(e)
	if k == nDeref: return try w.glExpr(n.kids(kidIds)[0])
	w.glStop(e, compileError("GpuValue", []))

# the values of expressions, in their order
fn glExprs(mut w GpuLower, es NodeId[]) i64[] ? shader.GpuError:
	values = []
	for e in es:
		values.push(try w.glExpr(e))
	values

# a number's literal, of the type the checker gave it (2 where a float is wanted is 2.0)
fn glNumber(mut w GpuLower, e NodeId) i64 ? shader.GpuError:
	t = try w.glTyOfNode(e)
	text = nodes[e].text
	if t.base == shader.bFloat:
		value = f64.parse(text) ?? f64(i64.parse(text) ?? 0)
		return w.glConst(t, i64(value.toBits()))
	w.glConst(t, i64.parse(text) ?? 0)

# a local, a parameter, a constant (its value), or what the GPU gives (pixelPosition)
fn glName(mut w GpuLower, e NodeId) i64 ? shader.GpuError:
	name = nodes[e].text.copy()
	if w.glLookup(name) is v:
		if v < 0: return w.glStop(e, compileError("StageParametersRead", ["{name}"]))
		return v
	if (try w.glMemoryKey(e)) is key: return w.glStageRead(key, try w.glTyOfNode(e), -1, e)
	if w.c.findDeclByGlobalName(nConstDecl, name) is d:
		return w.glAs(try w.glExpr(nodes[d].kids(kidIds)[0]), try w.glTyOfNode(e))
	if gpuValues.any(.name == name): return w.glStageRead(name, try w.glTyOfNode(e), -1, e)
	w.glStop(e, compileError("GpuValue", []))

# What the stage writes that e names (a compute stage's): a module's variable of a GPU file, its
# group's memory (zapW_<name>), or a part's field, a storage buffer (zapP<part>_<field>); none for
# anything else.
fn glMemoryKey(mut w GpuLower, e NodeId) (str?) ? shader.GpuError:
	n = nodes[e]
	if n.kind == nIdent:
		if w.glLookup(n.text) != none: return none
		d = w.c.findDeclByGlobalName(nConstDecl, n.text) ?? return none
		if not nodes[d].hasFlag(flagMut): return none
		key = "zapW_{n.text}"
		if w.groupMemory.get(key) == none:
			w.c.enterModuleOf(d)
			t = nodes[nodes[d].kids(kidIds)[0]].ty if nodes[d].types().isEmpty
				else w.c.resolveType(nodes[d].types()[0])
			w.groupMemory[key.copy()] = try w.glTy(t, e)
		return key
	if n.kind != nField or nodes[n.kids(kidIds)[0]].kind != nIdent: return none
	k = partOfName(w.glLookup(nodes[n.kids(kidIds)[0]].text) ?? return none)
	if k < 0: return none
	"zapP{k}_{n.text}"

# the variant number of an enum's variant named by e (`.Clamp`, `Wrap.Clamp`), or none
fn glVariant(w GpuLower, e NodeId) i64?:
	t = try nodes[e].ty
	if tys[t].kind != tEnum: return none
	base = nodes[e].kids(kidIds)[0]
	if not nodes[e].hasFlag(flagDotVariant) and
		(
			nodes[base].kind != nIdent or w.glLookup(nodes[base].text) != none or
				kindOf(tys, nodes[base].ty) == tEnum
		):
		return none
	match nodes[declOf(tys, t)].kids(kidIds).findIndex(nodes[it].text == nodes[e].text):
		i: i64(i)
		none: none

# x.f: an enum's variant, a size, a part's parameter (read where it is), a struct's field, a
# vector's component, a matrix's numbers (`m`, as an array)
fn glField(mut w GpuLower, e NodeId) i64 ? shader.GpuError:
	if w.glVariant(e) is variant: return w.glInt(variant)
	base = nodes[e].kids(kidIds)[0]
	if (try w.glMemoryKey(e)) is key:
		try w.glFieldIndex(nodes[base].ty, nodes[e].text.copy(), e)
		return w.glStageRead(key, try w.glTyOfNode(e), -1, e)
	bt = try w.glTy(nodes[base].ty, e)
	if nodes[e].hasFlag(flagSize) and bt.arr > 0: return w.glInt(bt.arr)
	whole = try w.glExpr(base)
	if try w.glMatrixArray(e):
		n = bt.rows
		t = shader.scalar(shader.bFloat)
		numbers = []
		for c in 0..n:
			column = w.glPart(whole, c, t.withRows(n))
			for r in 0..n:
				numbers.push(w.glPart(column, r, t))
		return w.glMake(t.arrayOf(n * n), numbers)
	i = try w.glFieldIndex(nodes[base].ty, nodes[e].text.copy(), e)
	w.glPart(whole, i, w.glPartTy(bt, i))

# What the stage is given or writes that `key` names (glMemoryKey), read where it is: the
# value of type t, or its element at `index` (a uniform's read once in a block)
fn glStageRead(mut w GpuLower, key str, t shader.Ty, index i64, e NodeId):
	if w.glTakenBefore(.op == irStageIn and .key == key and .b == index, index) is r: return r
	r = w.glV(t)
	w.glPut(
		IrInst(
			op = irStageIn,
			dst = r,
			key = key.copy(),
			b = index,
			line = nodes[e].line,
			col = nodes[e].col
		)
	)
	r

# xs[i]: an element of an array (a part's storage buffer or texture array where it is), a
# matrix's number (m.m[i]: column i / n, row i % n), a vector's component, a matrix's column
fn glIndex(mut w GpuLower, e NodeId) i64 ? shader.GpuError:
	base = nodes[e].kids(kidIds)[0]
	int = shader.scalar(shader.bInt)
	i = w.glAs(try w.glExpr(nodes[e].kids(kidIds)[1]), int)
	if (try w.glMemoryKey(base)) is key: return w.glStageRead(key, try w.glTyOfNode(e), i, e)
	if nodes[base].kind == nField:
		if try w.glMatrixArray(base):
			m = try w.glExpr(nodes[base].kids(kidIds)[0])
			n = w.glInt(w.tys[m].rows)
			column = w.glV(w.tys[m].elemOf())
			w.glPut(IrInst(op = irPart, dst = column, a = m, b = w.glOp(irDiv, int, i, n)))
			r = w.glV(shader.scalar(shader.bFloat))
			w.glPut(IrInst(op = irPart, dst = r, a = column, b = w.glOp(irRem, int, i, n)))
			return r
	whole = try w.glExpr(base)
	r = w.glV(w.tys[whole].elemOf())
	w.glPut(IrInst(op = irPart, dst = r, a = whole, b = i))
	r

fn glUnary(mut w GpuLower, e NodeId) i64 ? shader.GpuError:
	op = nodes[e].ival
	v = try w.glExpr(nodes[e].kids(kidIds)[0])
	if op in [unMove, unRef, unMutRef]: return v
	t = try w.glTyOfNode(e)
	if op == unNeg: return w.glOp(irFNeg if t.base == shader.bFloat else irNeg, t, v, -1)
	if op == unNot or op == unBnot: return w.glOp(irNot, t, v, -1)
	w.glStop(e, compileError("GpuValue", []))

# a binary operator's operation of the form, for numbers of base `base` (-1 none)
fn glArith(op i64, base i64):
	f = base == shader.bFloat
	if op == binAdd: return irFAdd if f else irAdd
	if op == binSub: return irFSub if f else irSub
	if op == binMul: return irFMul if f else irMul
	if op == binDiv: return irFDiv if f else irDiv
	if op == binMod: return irRem
	if op == binBand: return irAnd
	if op == binBor: return irOr
	if op == binBxor: return irXor
	if op == binShl: return irShl
	if op == binShr: return irShr
	-1

fn glBinary(mut w GpuLower, e NodeId) i64 ? shader.GpuError:
	op = nodes[e].ival
	if op == binAnd or op == binOr: return try w.glShortCircuit(e)
	a = try w.glExpr(nodes[e].kids(kidIds)[0])
	b = try w.glExpr(nodes[e].kids(kidIds)[1])
	t = try w.glTyOfNode(e)
	if isCompareOp(op): return w.glCompare(irCondOf(op), a, b)
	if op == binMatmul: return w.glOp(irMatMul, t, a, b)
	if op == binPow and t.base == shader.bFloat: return w.glBuiltinOf("pow", t, [a, b])
	try w.glArithOf(op, t, a, b, e)

# a op b of type t (a number meeting a vector or a matrix stays one: the operation spreads it;
# a shift's count is as it is)
fn glArithOf(mut w GpuLower, op i64, t shader.Ty, a i64, b i64, e NodeId) i64 ? shader.GpuError:
	code = glArith(op, t.base)
	if code < 0: return w.glStop(e, compileError("GpuOperator", ["{binName(op)}"]))
	shift = op == binShl or op == binShr
	ca = w.glAs(a, shader.scalar(t.base)) if w.tys[a].isScalar() and not t.isScalar()
		else w.glAs(a, t)
	cb = w.glAs(b, shader.scalar(w.tys[b].base if shift else t.base)) if shift or
		w.tys[b].isScalar() and not t.isScalar()
		else w.glAs(b, t)
	r = w.glV(t)
	w.glPut(IrInst(op = code, dst = r, a = ca, b = cb, uns = t.base == shader.bUint))
	r

# a comparison of a and b (b as a's type), a bool
fn glCompare(mut w GpuLower, cond i64, a i64, b i64):
	at = w.tys[a]
	r = w.glV(shader.scalar(shader.bBool))
	w.glPut(IrInst(op = irSet, dst = r, a, b = w.glAs(b, at), cond, uns = at.base == shader.bUint))
	r

# a and b, a or b: b only when a does not decide
fn glShortCircuit(mut w GpuLower, e NodeId) i64 ? shader.GpuError:
	isAnd = nodes[e].ival == binAnd
	r = w.glV(shader.scalar(shader.bBool))
	w.glPut(IrInst(op = irCopy, dst = r, a = try w.glExpr(nodes[e].kids(kidIds)[0])))
	right = w.f.irBlock()
	end = w.f.irBlock()
	w.f.merges.push(IrMerge(header = w.f.cur, merge = end))
	if isAnd:
		w.glBranch(r, right, end)
	else:
		w.glBranch(r, end, right)
	w.f.irEnter(right)
	w.glPut(IrInst(op = irCopy, dst = r, a = try w.glExpr(nodes[e].kids(kidIds)[1])))
	w.f.irJoin(end)
	r

# T(...): a vector of its numbers, a matrix of its numbers (`m`, column by column), a struct's or
# a tuple's fields in their order
fn glStructLit(mut w GpuLower, e NodeId) i64 ? shader.GpuError:
	t = try w.glTyOfNode(e)
	st = nodes[e].ty
	kids = nodes[e].kids(kidIds).copy()
	names = nodes[e].names().copy()
	f = shader.scalar(shader.bFloat)
	if t.isMatrix():
		n = t.rows
		array = kids[0]
		numbers = []
		if nodes[array].kind == nArray:
			elements = nodes[array].kids(kidIds).copy()
			numbers = (try w.glExprs(elements)).map(w.glAs(it, f))
		else:
			a = try w.glExpr(array)
			numbers = (0..n * n).map(w.glPart(a, it, f))
		columns = (0..n).map(w.glMake(t.elemOf(), numbers[it * n..it * n + n]))
		return w.glMake(t, columns)
	count = t.rows if t.isVector() else w.structs.members[t.sid].len
	parts = fill(count, -1)
	for i, kid in kids:
		field = (try w.glFieldIndex(st, names[i].copy(), e)) if i < names.len and names[i] != ""
			else i
		parts[field] = w.glAs(try w.glExpr(kid), w.glPartTy(t, field))
	if t.isVector():
		if w.glSwizzleOf(parts) is r: return r
	w.glMake(t, parts)

# a vector made of components of one vector: that vector's swizzle (v.zyx), none otherwise
fn glSwizzleOf(mut w GpuLower, parts i64[]) i64?:
	source = -1
	letters = ""
	for p in parts:
		d = try w.glDefOf(p)
		if d.op != irPart or d.b >= 0 or not w.tys[d.a].isVector() or
			source >= 0 and d.a != source:
			return none
		source = d.a
		letters += shader.swizzleSets[0][d.imm..d.imm + 1]
	r = w.glV(w.tys[source].withRows(parts.len))
	w.glPut(IrInst(op = irSwizzle, dst = r, a = source, key = letters))
	r

# the instruction of the block being filled that gave v its value, if one did
fn glDefOf(w GpuLower, v i64) IrInst?:
	insts = w.f.blocks[w.f.cur].insts
	i = insts.len - 1
	while i >= 0:
		if insts[i].dst == v: return insts[i].copy()
		i -= 1
	none

# a match: the bindings the checker writes (a swizzle's `$swizzle` taken apart), c ? a : b, or
# arms over an enum's variants, literals, bindings and `_`, tested in turn (each test a branch of
# its own inside the one before it)
fn glMatch(mut w GpuLower, e NodeId) i64 ? shader.GpuError:
	subject = try w.glExpr(nodes[e].kids(kidIds)[0])
	t = try w.glTyOfNode(e)
	result = -1 if t.base == shader.bVoid else w.glV(t)
	try w.glArms(e, subject, result, 1)
	result

# arm i of match e and the arms after it
fn glArms(mut w GpuLower, e NodeId, subject i64, result i64, i i64) ? shader.GpuError:
	arm = nodes[e].kids(kidIds)[i]
	pattern = nodes[arm].kids(kidIds)[0]
	pk = nodes[pattern].ival
	last = i == nodes[e].kids(kidIds).len - 1 or pk == patWildcard or
		pk == patBind and nodes[pattern].kids(kidIds).isEmpty
	if last:
		try w.glArm(arm, subject, result)
		return
	yes = w.f.irBlock()
	no = w.f.irBlock()
	end = w.f.irBlock()
	w.f.merges.push(IrMerge(header = w.f.cur, merge = end))
	w.glBranch(try w.glArmTest(subject, pattern, e), yes, no)
	w.f.irEnter(yes)
	try w.glArm(arm, subject, result)
	w.f.irJumpTo(end)
	w.f.irEnter(no)
	try w.glArms(e, subject, result, i + 1)
	w.f.irJoin(end)

# an arm's code, its value given to result
fn glArm(mut w GpuLower, arm NodeId, subject i64, result i64) ? shader.GpuError:
	pattern = nodes[arm].kids(kidIds)[0]
	mark = w.names.len
	if nodes[pattern].ival == patBind:
		w.glDeclare(nodes[pattern].text, subject)
	value = (try w.glExpr(nodes[arm].kids(kidIds)[1])) if nodes[arm].sub().isEmpty
		else try w.glBlock(nodes[arm].sub()[0])
	if result >= 0 and value >= 0:
		rt = w.tys[result]
		w.glPut(IrInst(op = irCopy, dst = result, a = w.glAs(value, rt)))
	w.glScopeEnd(mark)

# whether an arm's pattern takes the subject: a variant of its enum, a literal
fn glArmTest(mut w GpuLower, subject i64, pattern NodeId, e NodeId) i64 ? shader.GpuError:
	pk = nodes[pattern].ival
	value = -1
	if pk == patCtor and nodes[pattern].kids(kidIds).isEmpty:
		name = nodes[pattern].text[(nodes[pattern].text.lastIndexOf(".") ?? -1) + 1..len]
		variants = nodes[w.glDeclOf(nodes[nodes[e].kids(kidIds)[0]].ty)].kids(kidIds)
		match variants.findIndex(nodes[it].text == name):
			variant:
				value = w.glInt(variant)
			none: return w.glStop(pattern, compileError("GpuMatch", []))
	elif pk == patLit:
		literal = nodes[pattern].kids(kidIds)[0]
		if nodes[literal].kind == nBool:
			return subject if nodes[literal].ival == 1
				else w.glOp(irNot, shader.scalar(shader.bBool), subject, -1)
		value = try w.glExpr(literal)
	else:
		return w.glStop(pattern, compileError("GpuMatch", []))
	w.glCompare(irEq, subject, value)

# ---------- calls ----------

# the number types a conversion's name makes (f32(x), x.toF32(), the checker's widening)
gpuConversions = [
	"f32",
	"f64",
	"i32",
	"i64",
	"u32",
	"u64",
	"n32",
	"n64",
	"toF32",
	"toF64",
	"toI32",
	"toI64",
	"toU32",
	"toU64"
]

# f(args): discard(), a conversion, a function (of a GPU file, std's, the runtime's: some the
# GPU's own operations), a method of a value, a function of the runtime the checker calls
fn glCall(mut w GpuLower, e NodeId) i64 ? shader.GpuError:
	callee = nodes[e].kids(kidIds)[0]
	args = nodes[e].kidsFrom(kidIds, 1).copy()
	if nodes[e].hasFlag(flagRangeConversion):
		return w.glAs(try w.glExpr(args[0]), try w.glTyOfNode(e))
	if nodes[e].hasFlag(flagMethod) and not nodes[callee].names().isEmpty:
		# a method the checker made a call of the runtime's function: the receiver first
		recv = try w.glExpr(args[0])
		fnd = w.c.findFunc(nodes[callee].text)
		return try w.glMethod(nodes[callee].names()[0].copy(), recv, args[1..].copy(), e, fnd)
	if nodes[callee].kind == nField:
		obj = nodes[callee].kids(kidIds)[0]
		if nodes[obj].kind == nIdent and nodes[obj].text == "$rt":
			return try w.glRuntimeCall(
				w.c.findDeclInModule("rt", nFnDecl, nodes[callee].text),
				args,
				e
			)
		if nodes[callee].text == "fromBits" and nodes[obj].kind == nIdent and
			nodes[obj].ty == none and
			w.c.tKind(typeOf(nodes, e)) == tFloat:
			# f32.fromBits(u): the float whose bits u holds
			return w.glOp(irBitsToFloat, try w.glTyOfNode(e), try w.glExpr(args[0]), -1)
		if w.c.derivedMethod(e, nodes[callee].text) is family and
			(family == "tobits" or family == "frombits"):
			# a struct packed into a word and back: the function derive.zap wrote
			t = typeOf(nodes, e) if family == "frombits" else w.glReceiverType(obj)
			fnd = w.c.derivedFunction(family, t) ??
				return w.glStop(e, compileError("GpuCall", []))
			return try w.glCallFn(fnd, [], args if family == "frombits" else [obj], e)
		rt = w.glReceiverType(obj)
		md = w.c.findMethod(tys[rt].name, nodes[callee].text)
		return try w.glMethod(nodes[callee].text.copy(), try w.glExpr(obj), args, e, md)
	if nodes[callee].kind != nIdent: return w.glStop(e, compileError("GpuCall", []))
	name = nodes[callee].text
	if (name == "discard" or name == "barrier") and args.isEmpty:
		op = irDiscard if name == "discard" else irBarrier
		w.glPut(IrInst(op, line = nodes[e].line, col = nodes[e].col))
		return -1
	if name in gpuConversions and args.len == 1:
		return w.glAs(try w.glExpr(args[0]), try w.glTyOfNode(e))
	try w.glRuntimeCall(w.c.findFunc(name), args, e)

# a call of a function: the runtime's makers and products of matrices are the GPU's own
# operations, any other function is called
fn glRuntimeCall(mut w GpuLower, found NodeId?, args NodeId[], e NodeId) i64 ? shader.GpuError:
	fnd = found ?? return w.glStop(e, compileError("GpuCall", []))
	t = try w.glTyOfNode(e)
	name = nodes[fnd].text2().copy()
	if nodes[fnd].mod() == "rt" and name.startsWith("mat") and t.isMatrix() or
		name.startsWith("mat") and name.len > 4 and name[4..].startsWith("Times"):
		values = try w.glExprs(args)
		if "Times" in name: return w.glOp(irMatMul, t, values[0], values[1])
		if "Columns" in name: return w.glMake(t, values)
		if "Diagonal" in name:
			return w.glDiagonal(t, w.glAs(values[0], shader.scalar(shader.bFloat)))
		if "OfMat" in name: return w.glResized(t, values[0])
	try w.glCallFn(fnd, [], args, e)

# the matrix of type t with k on its diagonal, 0 elsewhere
fn glDiagonal(mut w GpuLower, t shader.Ty, k i64) i64:
	zero = w.glFloat(0.0)
	n = t.rows
	w.glMake(t, (0..n).map(c: w.glMake(t.elemOf(), (0..n).map(k if it == c else zero))))

# matrix m as one of type t: its upper left corner, the rest of the identity
fn glResized(mut w GpuLower, t shader.Ty, m i64) i64:
	f = shader.scalar(shader.bFloat)
	n = t.rows
	from = w.tys[m].rows
	columns = []
	for c in 0..n:
		if c < from:
			column = w.glPart(m, c, f.withRows(from))
			if from >= n:
				r = w.glV(f.withRows(n))
				w.glPut(
					IrInst(
						op = irSwizzle,
						dst = r,
						a = column,
						key = shader.swizzleSets[0][0..n].copy()
					)
				)
				columns.push(r)
			else:
				numbers = (0..n).map(
					w.glPart(column, it, f) if it < from else w.glFloat(1.0 if it == c else 0.0)
				)
				columns.push(w.glMake(f.withRows(n), numbers))
		else:
			columns.push(w.glMake(f.withRows(n), (0..n).map(w.glFloat(1.0 if it == c else 0.0))))
	w.glMake(t, columns)

# a texture's read (gpucheck.zap checked it): its arguments lowered but for its constants,
# which the instruction carries packed in imm
fn glTexture(mut w GpuLower, m str, t shader.Ty, recv i64, args NodeId[]) i64 ? shader.GpuError:
	kind = w.tys[recv].sid
	roles = ["level"]
	if shader.textureMethodOf(m, kind) is f:
		roles = f.textureRoles(kind, args.len > f.textureRoles(kind, false).len)
	values = []
	k = shader.TextureConstants()
	for i, a in args:
		if not shader.isTextureConstant(roles[i]):
			values.push(try w.glExpr(a))
		elif w.c.textureConstant(a, roles[i], kind) is c:
			k.component += c.component
			if c.offset:
				k = shader.TextureConstants(..c, component = k.component)
	# an image's store and atomics are kept whether or not their value is read (as an instruction
	# that may stop is: trap), a store giving none
	writes = m == "store" or m in shader.atomicMethods or m == "atomicCompareExchange"
	r = -1 if t.base == shader.bVoid else w.glV(t)
	w.glPut(
		IrInst(
			op = irTexture,
			dst = r,
			a = recv,
			args = values,
			key = m.copy(),
			imm = k.packTextureConstants(),
			trap = writes
		)
	)
	r

# recv.m(args): a conversion, a tuple's part taken, a texture's read, a built-in function of
# numbers and vectors (field by field, a number spread over the widest vector), withZ and withW,
# dot, or the function fnd taking the value first
fn glMethod(
	mut w GpuLower,
	move m str,
	recv i64,
	args NodeId[],
	e NodeId,
	found NodeId?
) i64 ? shader.GpuError:
	t = try w.glTyOfNode(e)
	if m in gpuConversions or m in intConversions: return w.glAs(recv, t)
	if m == "take" or m == "copy": return recv
	if m == "toBits" and w.tys[recv].base == shader.bFloat: return w.glOp(irFloatBits, t, recv, -1)
	rt = w.tys[recv]
	if rt.base == shader.bSampler: return w.glTexture(m, t, recv, args)
	if m == "dot": return w.glOp(irMatMul, t, recv, try w.glExpr(args[0]))
	if m == "withZ" or m == "withW":
		return w.glMake(t, [recv, w.glAs(try w.glExpr(args[0]), shader.scalar(shader.bFloat))])
	if gpuLaneArity(m) >= 0:
		values = [recv]
		values.extend((try w.glExprs(args)).map(w.glAs(it, shader.scalar(shader.bInt))))
		return w.glLaneOp(m, t, values, e)
	if m == "bit" or m == "bits": return try w.glBitRead(m, recv, args)
	if shader.builtinFunctions.any(.zap == m):
		values = [recv]
		values.extend(try w.glExprs(args))
		return w.glBuiltinOf(m, t, values)
	fnd = found ?? return w.glStop(e, compileError("ShaderUnknownFunction", ["{m}"]))
	try w.glCallFn(fnd, [recv], args, e)

# x.bit(n), x.bits(from, count) as the CPU reads them (irBitField): (x >> from) & mask, the
# shift logical and the mask ((1 << (count - 1)) << 1) - 1, all the bits for the whole width
fn glBitRead(mut w GpuLower, m str, x i64, args NodeId[]) i64 ? shader.GpuError:
	t = w.tys[x]
	one = w.glConst(t, 1)
	from = w.glAs(try w.glExpr(args[0]), t)
	down = w.glV(t)
	w.glPut(IrInst(op = irShr, dst = down, a = x, b = from, uns = true))
	if m == "bit": return w.glCompare(irNe, w.glOp(irAnd, t, down, one), w.glConst(t, 0))
	count = w.glAs(try w.glExpr(args[1]), t)
	top = w.glOp(irShl, t, w.glOp(irShl, t, one, w.glOp(irSub, t, count, one)), one)
	w.glOp(irAnd, t, down, w.glOp(irSub, t, top, one))

# the type of a method's receiver (refs read through)
fn glReceiverType(w GpuLower, obj NodeId):
	t = typeOf(nodes, obj)
	while tys[t].kind == tRef:
		t = innerOf(tys, t)
	t

# an operation across the lanes that run together (shader.laneFunctions) of values giving t
fn glLaneOp(mut w GpuLower, move m str, t shader.Ty, values i64[], e NodeId):
	r = w.glV(t)
	w.glPut(
		IrInst(
			op = irBuiltin,
			dst = r,
			args = values.copy(),
			key = m,
			line = nodes[e].line,
			col = nodes[e].col
		)
	)
	r

# a built-in function of values (the receiver first) giving t: a number spread over the widest
# vector among them, but for refract's ratio
fn glBuiltinOf(mut w GpuLower, m str, t shader.Ty, values i64[]):
	widest = 1
	for v in values:
		widest = widest.max(w.tys[v].rows if w.tys[v].isVector() else 1)
	spread = []
	for i, v in values:
		vt = w.tys[v]
		if m == "refract" and i == 2 or widest == 1 or not vt.isScalar():
			spread.push(v)
		else:
			spread.push(w.glAs(v, shader.vector(vt.base, widest)))
	r = w.glV(t)
	w.glPut(IrInst(op = irBuiltin, dst = r, args = spread, key = m.copy()))
	r

# a call of function fnd with the values `pre` (a method's receiver) and then the arguments: an
# argument for a part's parameter is not passed, its fields read where they are
fn glCallFn(mut w GpuLower, fnd NodeId, pre i64[], args NodeId[], e NodeId) i64 ? shader.GpuError:
	if fnd == w.fnd: return w.glStop(e, compileError("GpuCall", []))
	types = w.glParamTypes(fnd)
	if types.len != pre.len + args.len: return w.glStop(e, compileError("GpuCall", []))
	values = []
	for i, pt in types:
		if w.glPartOf(pt) >= 0:
			if i < pre.len or nodes[args[i - pre.len]].kind != nIdent or
				partOfName(w.glLookup(nodes[args[i - pre.len]].text) ?? -1) < 0:
				return w.glStop(e, compileError("StageParameters", ["{typeStr(tys, pt)}"]))
			continue
		want = try w.glTy(pt, nodes[fnd].kids(kidIds)[i])
		if want.base == shader.bSampler and want.arr >= 0:
			return w.glStop(nodes[fnd].kids(kidIds)[i], compileError("TextureArrayRead", []))
		if want.base == shader.bSampler and i >= pre.len and
			nodes[args[i - pre.len]].kind == nIndex:
			return w.glStop(e, compileError("TextureOfArrayRead", ["{nodes[fnd].text2()}"]))
		v = pre[i] if i < pre.len else try w.glExpr(args[i - pre.len])
		values.push(w.glAs(v, want))
	if fnd not in w.todo and not w.fns.any(.decl == fnd):
		w.todo.push(fnd)
	w.c.enterModuleOf(fnd)
	ret = try w.glTy(w.c.fnRetType(fnd), e)
	r = -1 if ret.base == shader.bVoid else w.glV(ret)
	w.glPut(IrInst(op = irCall, dst = r, args = values, key = w.glFnName(fnd)))
	r

# ---------- for the writers (irspirv.zap, irhlsl.zap) ----------
