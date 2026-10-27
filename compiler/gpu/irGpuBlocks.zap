# The GPU lowering of statements and blocks: lets, ifs, loops and stores (irGpu.zap).

import shader

alias nodes = w.c.nodes
alias kidIds = w.c.kidIds
alias tys = w.c.types

# a block's statements; the value of its last when that is an expression (-1 none)
fn glBlock(mut w GpuLower, b NodeId) i64 ? shader.GpuError:
	mark = w.names.len
	value = -1
	kids = nodes[b].kids(kidIds).copy()
	for i, s in kids:
		if w.f.irEnded(): break
		if i == kids.len - 1 and nodes[s].kind == nExprStmt:
			value = try w.glExpr(nodes[s].kids(kidIds)[0])
		else:
			try w.glStatement(s)
	w.glScopeEnd(mark)
	value

fn glStatement(mut w GpuLower, s NodeId) ? shader.GpuError:
	k = nodes[s].kind
	if k == nExprStmt:
		try w.glExpr(nodes[s].kids(kidIds)[0])
	elif k == nLet:
		try w.glLet(s)
	elif k == nAssign:
		value = try w.glExpr(nodes[s].kids(kidIds)[1])
		try w.glStore(nodes[s].kids(kidIds)[0], value)
	elif k == nReturn:
		if nodes[s].kids(kidIds).isEmpty:
			w.glPut(IrInst(op = irRet, a = -1))
		else:
			w.c.enterModuleOf(w.lowered())
			ret = try w.glTy(w.c.fnRetType(w.lowered()), s)
			v = try w.glExpr(nodes[s].kids(kidIds)[0])
			w.glPut(IrInst(op = irRet, a = w.glAs(v, ret)))
	elif k == nIf:
		try w.glIf(s)
	elif k == nWhile:
		try w.glWhile(s)
	elif k == nFor:
		try w.glFor(s)
	elif k == nBreak or k == nContinue:
		if w.breaks.isEmpty: return w.glStop(s, compileError("GpuStatement", []))
		w.f.irJumpTo(w.breaks[len - 1] if k == nBreak else w.conts[len - 1])
	elif k == nBlock:
		try w.glBlock(s)
	else:
		w.glStop(s, compileError("GpuStatement", []))

# `x = v`, `mut x = v`, `x T = v` (a new name, or a known one assigned), `x op= v` (its value the
# operation), `mut x T` (zero)
fn glLet(mut w GpuLower, s NodeId) ? shader.GpuError:
	name = nodes[s].text.copy()
	value = -1
	if not nodes[s].kids(kidIds).isEmpty:
		value = try w.glExpr(nodes[s].kids(kidIds)[0])
	else:
		w.c.enterModuleOf(w.lowered())
		t = try w.glTy(w.c.resolveType(nodes[s].types()[0]), s)
		value = w.glConst(t, 0)   # zero
	if w.glLookup(name) is v:
		if v >= 0 and nodes[s].canAssign():
			vt = w.tys[v]
			w.glPut(IrInst(op = irCopy, dst = v, a = w.glAs(value, vt)))
			return
	if not nodes[s].types().isEmpty:
		w.c.enterModuleOf(w.lowered())
		value = w.glAs(value, try w.glTy(w.c.resolveType(nodes[s].types()[0]), s))
	# a name of its own: its vreg changes as it does, never the value it was given
	valueTy = w.tys[value]
	own = w.glV(valueTy)
	w.glPut(IrInst(op = irCopy, dst = own, a = value))
	w.glDeclare(name, own)

# if c: then [else: other], its ways meeting after it
fn glIf(mut w GpuLower, s NodeId) ? shader.GpuError:
	c = try w.glExpr(nodes[s].kids(kidIds)[0])
	yes = w.f.irBlock()
	end = w.f.irBlock()
	no = w.f.irBlock() if nodes[s].sub().len > 1 else end
	w.f.merges.push(IrMerge(header = w.f.cur, merge = end))
	w.glBranch(c, yes, no)
	w.f.irEnter(yes)
	try w.glBlock(nodes[s].sub()[0])
	w.f.irJumpTo(end)
	if no != end:
		w.f.irEnter(no)
		try w.glBlock(nodes[s].sub()[1])
		w.f.irJumpTo(end)
	w.f.irEnter(end)

# A loop: its header (where its structure is noted), the block that tests whether it goes on,
# its body, its continue block (the step) and the block after it.
type GlLoop:
	head i64
	test i64
	body i64
	cont i64
	end i64

fn glLoopOpen(mut w GpuLower):
	l = GlLoop(
		head = w.f.irBlock(),
		test = w.f.irBlock(),
		body = w.f.irBlock(),
		cont = w.f.irBlock(),
		end = w.f.irBlock()
	)
	w.f.irJoin(l.head)
	w.f.merges.push(IrMerge(header = l.head, merge = l.end, cont = l.cont))
	w.f.irJoin(l.test)
	l

# the body (the test's block filled), then the step's block and the way back
fn glLoopBody(mut w GpuLower, l GlLoop, body NodeId) ? shader.GpuError:
	w.f.irEnter(l.body)
	w.breaks.push(l.end)
	w.conts.push(l.cont)
	try w.glBlock(body)
	w.breaks.pop()
	w.conts.pop()
	w.f.irJoin(l.cont)

fn glLoopClose(mut w GpuLower, l GlLoop):
	w.f.irJumpTo(l.head)
	w.f.irEnter(l.end)

fn glWhile(mut w GpuLower, s NodeId) ? shader.GpuError:
	l = w.glLoopOpen()
	c = try w.glExpr(nodes[s].kids(kidIds)[0])
	w.glBranch(c, l.body, l.end)
	try w.glLoopBody(l, nodes[s].sub()[0])
	w.glLoopClose(l)

# for i in lo..hi [step k] (a counter of the range's type), or over a fixed array's elements
fn glFor(mut w GpuLower, s NodeId) ? shader.GpuError:
	iter = nodes[s].kids(kidIds)[0]
	mark = w.names.len
	if nodes[iter].kind == nRange and nodes[iter].kids(kidIds).len >= 2:
		t = try w.glTyOfNode(iter)
		lo = try w.glExpr(nodes[iter].kids(kidIds)[0])
		hi = w.glAs(try w.glExpr(nodes[iter].kids(kidIds)[1]), t)
		step = w.glAs(
			try w.glExpr(nodes[iter].kids(kidIds)[2]),
			t
		) if nodes[iter].kids(kidIds).len >
			2
			else w.glConst(t, 1)
		down = nodes[iter].kids(kidIds).len > 2 and
			nodes[nodes[iter].kids(kidIds)[2]].kind == nInt and
			nodes[nodes[iter].kids(kidIds)[2]].text.startsWith("-")
		i = w.glV(t)
		w.glPut(IrInst(op = irCopy, dst = i, a = w.glAs(lo, t)))
		l = w.glLoopOpen()
		more = w.glV(shader.scalar(shader.bBool))
		w.glPut(IrInst(op = irSet, dst = more, a = i, b = hi, cond = irGt if down else irLt))
		w.glBranch(more, l.body, l.end)
		w.glDeclare(nodes[s].text, i)
		try w.glLoopBody(l, nodes[s].sub()[0])
		w.glPut(IrInst(op = irAdd, dst = i, a = i, b = step))
		w.glLoopClose(l)
		w.glScopeEnd(mark)
		return
	at = try w.glTyOfNode(iter)
	if at.arr <= 0: return w.glStop(s, compileError("GpuFor", []))
	xs = try w.glExpr(iter)
	int = shader.scalar(shader.bInt)
	i = w.glConst(int, 0)
	counter = w.glV(int)
	w.glPut(IrInst(op = irCopy, dst = counter, a = i))
	l = w.glLoopOpen()
	more = w.glV(shader.scalar(shader.bBool))
	w.glPut(IrInst(op = irSet, dst = more, a = counter, b = w.glInt(at.arr), cond = irLt))
	w.glBranch(more, l.body, l.end)
	w.f.irEnter(l.body)
	elem = w.glV(at.elemOf())
	w.glPut(IrInst(op = irPart, dst = elem, a = xs, b = counter))
	w.glDeclare(nodes[s].text, elem)
	try w.glLoopBody(l, nodes[s].sub()[0])
	w.glPut(IrInst(op = irAdd, dst = counter, a = counter, b = w.glInt(1)))
	w.glLoopClose(l)
	w.glScopeEnd(mark)

# ---------- places ----------

# target = value: a name, or a field, a component or an element of one, written in place
fn glStore(mut w GpuLower, target NodeId, value i64) ? shader.GpuError:
	n = nodes[target].copy()
	if n.kind == nIndex or n.kind == nIdent:
		# a compute stage's group memory or storage buffer (its element): written where it is
		key = try w.glMemoryKey(n.kids(kidIds)[0] if n.kind == nIndex else target)
		if key is k:
			t = try w.glTyOfNode(target)
			index = w.glAs(try w.glExpr(n.kids(kidIds)[1]), shader.scalar(shader.bInt)) if n.kind ==
				nIndex
				else -1
			w.glPut(
				IrInst(
					op = irStageOut,
					a = w.glAs(value, t),
					b = index,
					line = n.line,
					col = n.col,
					part = instPartOf(key = k.copy())
				)
			)
			return
	if n.kind == nIdent:
		v = w.glLookup(n.text) ?? -1
		if v < 0: return w.glStop(target, compileError("GpuReadOnly", ["{n.text}"]))
		if value != v:   # (a part changed in place: the value is the name's already)
			vt = w.tys[v]
			w.glPut(IrInst(op = irCopy, dst = v, a = w.glAs(value, vt)))
		return
	if n.kind == nDeref:
		try w.glStore(n.kids(kidIds)[0], value)
		return
	if n.kind != nField and n.kind != nIndex:
		return w.glStop(target, compileError("GpuStatement", []))
	base = n.kids(kidIds)[0]
	whole = try w.glExpr(base)   # the value it is part of, changed and stored back
	bt = w.tys[whole]
	inst = IrInst(op = irSetPart, dst = whole, a = whole)
	if n.kind == nField:
		if try w.glMatrixArray(target): return w.glStop(target, compileError("GpuStatement", []))
		inst.imm = try w.glFieldIndex(nodes[base].ty, n.text, target)
		inst.c = w.glAs(value, w.glPartTy(bt, inst.imm))
	else:
		inst.b = w.glAs(try w.glExpr(n.kids(kidIds)[1]), shader.scalar(shader.bInt))
		inst.c = w.glAs(value, bt.elemOf())
	w.glPut(inst)
	if nodes[base].kind in [nIdent, nField, nIndex, nDeref]:
		try w.glStore(base, whole)
