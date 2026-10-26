# Functions as values: what a borrowing lambda captures by pointer, the system-convention
# entries of callbacks and the wrappers of named functions used as closures.

alias nodes = g.c.nodes
alias tys = g.c.types

# whether a borrowing lambda copies a capture of this type into its environment (small plain
# values) rather than pointing at the caller's value; a scalar that owns something (a map, a
# box, a shared value) is pointed at like an aggregate, since a copy of the word would be a
# second owner
fn capByValue(mut g Gen, t TypeId):
	(g.c.isScalar(t) and not g.isOwningType(t)) or g.isVec(t)

# whether the borrowing lambda e points at its ci-th capture: an aggregate, or a variable its
# body changes
fn capByPointer(mut g Gen, e NodeId, ci i64):
	g.irFlagged(e, flagBorrowLambda) and
		(not g.capByValue(nodes[e].ints()[ci]) or nodes[e].names2()[ci] in nodes[e].bounds())

# the label of the entry with the system's convention that calls the named function, planned
# when new
fn callbackLabel(mut g Gen, name str, ft TypeId) i64:
	g.plannedLabel("$callback:{name}", ft)

# the label of the generated function key (a wrapper of a function of type ft), planned with the
# other generated functions when it is new
fn plannedLabel(mut g Gen, key str, ft TypeId):
	exists = key in g.fnLabels
	label = fnLabel(g.fnLabels, g.a, key)
	if not exists:
		g.planned.push(Planned(key = key.copy(), t = ft, offs = [], types = [], tags = []))
	label

# `$callback:name`: the arguments of the system's convention (callbackRegs, then the stack) pushed
# as a Zap call takes them, the registers the system expects kept
fn genCallbackFunction(mut g Gen, name str, ft TypeId):
	entry = fnLabel(g.fnLabels, g.a, "$callback:{name}")
	g.a.asmPlace(entry)
	g.a.framePrologue()
	g.a.emN([0x53, 0x56, 0x57, 0x41, 0x54, 0x41, 0x55, 0x41, 0x56, 0x41, 0x57])   # push rbx, rsi, rdi, r12..r15
	if onLinux(): g.x64CallbackEnter()
	# the parameter types and the name are read through g at each use: emitting changes g
	np = tys[ft].params.len
	argRegs, stackAt = callbackRegs()
	for i in 0..np:
		if i < 4 and g.tyK(tys[ft].params[i]) == tFloat:
			g.a.emN([0x66, 0x48, 0x0F, 0x7E, 0xC0 | (i << 3)])   # movq rax, xmm_i
			g.a.pushRax()
		elif i < argRegs.len:
			r = argRegs[i]
			if r >= 8:
				g.a.em1(0x41)
			g.a.em1(0x50 | (r & 7))   # push the register
		else:
			g.a.memOp(true, 0x8B, -1, 0, 5, -1, stackAt + 8 * (i - argRegs.len))   # mov rax, [rbp+...]
			g.a.pushRax()
	g.a.callLabel(fnLabel(g.fnLabels, g.a, name))
	g.a.addRsp(8 * np)
	if g.tyK(tys[ft].ret) == tFloat:
		g.a.emN([0x66, 0x48, 0x0F, 0x6E, 0xC0])   # movq xmm0, rax
	if onLinux(): g.x64CallbackLeave()
	g.a.emN([0x41, 0x5F, 0x41, 0x5E, 0x41, 0x5D, 0x41, 0x5C, 0x5F, 0x5E, 0x5B])   # pop r15..r12, rdi, rsi, rbx
	g.a.em1(0x5D)   # pop rbp
	g.a.em1(0xC3)   # ret

# the label of the wrapper of the named function as a value, planned when new (written with the
# other planned functions)
fn irFnValueLabel(mut g Gen, name str, ft TypeId) i64:
	g.plannedLabel("$fnval:{name}", ft)

# `$fnval:name`: called as a closure is (the environment deepest, then the arguments, then the
# hidden result address), it calls the function with the arguments pushed again in its order
fn genFnValueWrapper(mut g Gen, name str, ft TypeId):
	wrap = fnLabel(g.fnLabels, g.a, "$fnval:{name}")
	g.a.asmPlace(wrap)
	g.a.framePrologue()
	# the parameter types and the name are read through g at each use: emitting changes g
	np = tys[ft].params.len
	ret = retOf(tys, ft)
	hidden = 0
	if not g.c.isScalar(ret):
		hidden = 8
	# the wrapper's args: [rbp+16+hidden ... ] env is deepest; re-push params in order
	total = (0..np).sum(g.paramSlot(tys[ft].params[it], modeRead))
	off = 16 + hidden + total - 8
	# walk params in order, each at decreasing offsets
	cur = off
	i = 0
	while i < np:
		sz = g.paramSlot(tys[ft].params[i], modeRead)
		cur = 16 + hidden + total - sz
		# offset of param i: 16 + hidden + sum of sizes after i
		after = ((i + 1)..np).sum(g.paramSlot(tys[ft].params[it], modeRead))
		base = 16 + hidden + after
		# copy sz bytes from [rbp+base] onto the stack
		g.subRsp(sz)
		g.leaRaxRbp(base)
		g.a.em3(0x48, 0x89, 0xE1)   # mov rcx, rsp
		g.copyBytes(sz)
		i += 1
	_ = off
	_ = cur
	if hidden > 0:
		g.a.loadRaxFromRbp(16)
		g.a.pushRax()
	g.a.callLabel(fnLabel(g.fnLabels, g.a, name))
	g.a.addRsp(total + hidden)
	g.a.em3(0x48, 0x89, 0xEC)
	g.a.em1(0x5D)
	g.a.em1(0xC3)
