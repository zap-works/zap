# Destroying and copying a value are generated per type, like the layout: `$drop:<descriptor>`
# takes the address of a value (pushed) and frees what it owns; `$copy:<descriptor>` takes a
# source and a destination address (pushed in that order) and writes a deep copy. A struct
# visits its owning fields, an enum the fields of the variant in the tag, an option or a result
# its payload, a list its elements then its buffer, a map the four lists of its table, a closure
# hands its environment to the function the environment's header names (see envFnLabel). No
# type descriptor is read at run time. Planned when first needed (field types resolve under the
# generic substitution in force), written once per type after the program's functions.

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

fn isOwningType(mut g Gen, t TypeId):
	if g.owning.get(t) is known: return known
	owns = not g.c.isPlainType(t)   # (its fields' types resolved again: made again)
	if g.c.subst.names.isEmpty:
		g.owning[t] = owns
	owns

# rax = address of a value of type t: drop it (frees what it owns)
fn emitDropAt(mut g Gen, t TypeId):
	if not g.isOwningType(t): return
	k = g.tyK(t)
	if k == tStr or (isListKind(k) and g.c.isPlainType(g.listElem(t))):
		# a str, or a list of plain elements: one buffer, owned when the capacity is above 0 (a
		# short str's is negative: its bytes are in its header)
		skip = g.a.asmNewLabel()
		g.a.em4(0x48, 0x8B, 0x48, 0x10)   # mov rcx, [rax+16]  (cap)
		g.a.em3(0x48, 0x85, 0xC9)   # test rcx, rcx
		g.a.jccLabel(0x8E, skip)   # jle
		g.a.em3(0x48, 0x8B, 0x00)   # mov rax, [rax]     (the buffer)
		g.a.testRax()
		g.a.jccLabel(0x84, skip)
		g.callRtWith("rtFree", [0])
		g.a.asmPlace(skip)
		return
	g.argWord(0, 0, 1)
	if k == tFn:
		g.a.callLabel(g.closureStubLabel("$dropClosure"))
	else:
		g.a.callLabel(g.typeFnLabel(t, true))
	g.argsTaken(1)

# rax = source address, rcx = destination address, both of type t: a deep copy
fn emitCopyAt(mut g Gen, t TypeId):
	if not g.isOwningType(t):
		g.copyBytes(g.sizeOf(t))
		return
	k = g.tyK(t)
	if k == tStr:
		g.callRtWith("strCopyRaw", [0, 1])
		return
	if isListKind(k) and g.c.isPlainType(g.listElem(t)):
		g.a.em1(0xBA)   # mov edx, the stride
		g.a.emit32(g.c.elemStride(g.listElem(t)))
		g.callRtWith("listCopyRaw", [0, 1, 2])
		return
	g.argWord(0, 0, 2)
	g.argWord(1, 1, 2)
	if k == tFn:
		g.a.callLabel(g.closureStubLabel("$copyClosure"))
	else:
		g.a.callLabel(g.typeFnLabel(t, false))
	g.argsTaken(2)

# drop the value of type t at [rbx+off] (rbx holds the block being dropped)
fn dropAtRbx(mut g Gen, off i64, t TypeId):
	g.a.em3(0x48, 0x89, 0xD8)   # mov rax, rbx
	g.addRaxImm(off)
	g.emitDropAt(t)

# deep-copy the value of type t at [rbx+off] to [r13+off] (source and new block)
fn copyRbxToR13(mut g Gen, off i64, t TypeId):
	g.a.em3(0x48, 0x89, 0xD8)   # mov rax, rbx
	g.addRaxImm(off)
	g.a.em3(0x4C, 0x89, 0xE9)   # mov rcx, r13
	g.addRcxImm(off)
	g.emitCopyAt(t)

# rax = a new block of n bytes
fn rtAllocImm(mut g Gen, n i64):
	g.a.movRaxImm(n)
	g.a.pushRax()
	g.callRtNamed("rtAlloc", 8)

# the block at rbx goes back to the allocator
fn rtFreeRbx(mut g Gen):
	g.a.em1(0x53)   # push rbx
	g.callRtNamed("rtFree", 8)

fn isListKind(k i64):
	k == tList

# The owning parts of a value of type t: an offset, a type and a tag each (the tag is the
# variant of an enum field, 1 for the ok payload of a result, 0 otherwise). A list gives its
# element stride and type; a map the two typed lists of its table.
fn typeParts(mut g Gen, t TypeId, mut offs i64[], mut types TypeId[], mut tags i64[]):
	k = g.tyK(t)
	if k == tStruct:
		dcl = declOf(tys, t)
		fo = g.c.structFieldOffsets(dcl)
		# the fields are read through g at each step: resolveType changes g.c
		for i in 0..g.c.nodes[dcl].kids(g.c.kidIds).len:
			ft = g.c.resolveType(nodes[nodes[dcl].kids(kidIds)[i]].types()[0])
			if g.isOwningType(ft):
				offs.push(fo[i])
				types.push(ft)
				tags.push(0)
	elif k == tEnum:
		dcl = declOf(tys, t)
		for vi in 0..g.c.nodes[dcl].kids(g.c.kidIds).len:
			vr = nodes[dcl].kids(kidIds)[vi]
			fo = g.c.variantFieldOffsets(dcl, vr)
			for i in 0..g.c.nodes[vr].kids(g.c.kidIds).len:
				ft = g.c.resolveType(nodes[nodes[vr].kids(kidIds)[i]].types()[0])
				if g.isOwningType(ft):
					offs.push(fo[i])
					types.push(ft)
					tags.push(vi)
	elif k == tOption:
		offs.push(g.c.optionPayload(t))
		types.push(innerOf(tys, t))
		tags.push(1)
	elif k == tBox:
		offs.push(0)
		types.push(innerOf(tys, t))
		tags.push(0)
	elif k == tResult:
		offs.push(g.c.resultPayload(t))
		types.push(innerOf(tys, t))
		tags.push(1)
		offs.push(g.c.resultPayload(t))
		types.push(errOf(tys, t))
		tags.push(0)
	elif k == tMap:
		offs.push(0)
		types.push(tyList(tys, tys[t].inner))
		tags.push(0)
		offs.push(24)
		types.push(tyList(tys, tys[t].val))
		tags.push(0)
	elif isListKind(k):
		elem = g.listElem(t)
		offs.push(g.c.elemStride(elem))
		types.push(elem)
		tags.push(0)
	elif k == tArray:
		elem = innerOf(tys, t)
		stride = g.c.elemStride(elem)
		for i in 0..g.c.types[t].bits:
			offs.push(i * stride)
			types.push(elem)
			tags.push(0)
	else:
		die("x64: no drop or copy for {typeStr(tys, t)}")

# the runtime's table behind a {K: V}: the instance MapTable<K, V> (map.zap)
fn mapTableType(mut g Gen, t TypeId) TypeId:
	if g.isTextWindow(innerOf(tys, t)):
		text = g.findStructTemplate("rt__TextTable")   # a key in one word (textmap.zap)
		inst = g.c.programInstantiate(text, [valOf(tys, t)])
		return tyOfDecl(tys, nodes, inst)
	tmpl = g.findStructTemplate("rt__MapTable")
	inst = g.c.programInstantiate(tmpl, [innerOf(tys, t), valOf(tys, t)])
	tyOfDecl(tys, nodes, inst)

fn findStructTemplate(g Gen, name str):
	for d in g.c.decls:
		if nodes[d].kind == nStructDecl and nodes[d].text == name and not nodes[d].names().isEmpty:
			return d
	die("x64: no template {name}")
	0

# the label of `$drop:` (drop = true) or `$copy:` for the type, planned on first use
fn typeFnLabel(mut g Gen, t TypeId, drop bool):
	key = "$copy:{g.descriptor(t)}"
	if drop:
		key = "$drop:{g.descriptor(t)}"
	exists = key in g.fnLabels
	g.noteAsk(KeptAsk(keptDrop if drop else keptCopy, types = [i64(t)], made = not exists))
	label = fnLabel(g.fnLabels, g.a, key)
	if g.codeNoting: g.labelsNoted.extend([label, i64(t), 1 if drop else 0])
	if exists: return label
	offs = []
	types = []
	tags = []
	g.typeParts(t, offs, types, tags)
	g.planned.push(Planned(key, t, offs, types, tags))
	label

# the two stubs every closure shares, planned on first use
fn closureStubLabel(mut g Gen, move key str):
	exists = key in g.fnLabels
	g.noteAsk(KeptAsk(keptStub, key.copy(), made = not exists))
	label = fnLabel(g.fnLabels, g.a, key)
	if not exists:
		g.planned.push(Planned(key, t = none, offs = [], types = [], tags = []))
	label

# The function of a closure's environment, named by the environment's header word: called
# with (env, op) pushed, op 0 drops the captures and frees the block, op 1 returns a copy of
# the block. One per lambda (the captures are its layout).
fn envFnLabel(mut g Gen, envTypes TypeId[], envSize i64):
	key = "$env:{g.envs}"
	g.envs += 1
	g.asksSpoiled = g.asksSpoiled or g.asksNoting   # (one a lambda: never asked for again)
	label = fnLabel(g.fnLabels, g.a, key)
	offs = []
	types = []
	pos = 0
	for ct in envTypes:
		if g.isOwningType(ct):
			offs.push(8 + pos)
			types.push(ct)
		pos += g.c.slotSize(ct)
	g.planned.push(Planned(key, t = none, envSize, offs, types, tags = []))
	label

# A generated function still to emit: its label's key, the type (none for a closure stub and
# an environment), an environment's size, the offsets of its owning parts (a list: [stride]),
# their types (a list: [elem]) and their variant tags (enum fields; 1 the ok payload of a result).
type Planned:
	key str
	t TypeId?
	envSize i64 = 0
	offs i64[]
	types TypeId[]
	tags i64[]

# writes every planned function; one may plan others (an element type, a field type)
fn genDropFunctions(mut g Gen):
	while not g.planned.isEmpty:
		# taken out first: the entry leaves the plan, generating may plan more
		next = g.planned.pop() ?? Planned(key = "", t = none, offs = [], types = [], tags = [])
		r = g.beginFunction()
		g.genPlanned(next)
		g.endFunction(next.key, r)

# the planned function's code
fn genPlanned(mut g Gen, next Planned):
	if onArm():
		g.a64GenPlanned(next)
		return
	key = next.key
	t = next.t ?? tyError
	offs = next.offs
	types = next.types
	tags = next.tags
	if key == "$dropClosure":
		g.genDropClosure()
	elif key == "$copyClosure":
		g.genCopyClosure()
	elif key.startsWith("$env:"):
		g.genEnvFunction(key, next.envSize, offs, types)
	elif key.startsWith("$fnval:"):
		g.genFnValueWrapper(key[7..], t)
	elif key.startsWith("$callback:"):
		g.genCallbackFunction(key[10..], t)
	elif key.startsWith("$drop:"):
		g.genDropFunction(t, offs, types, tags)
	else:
		g.genCopyFunction(t, offs, types, tags)

# `$drop:T(p)`: p at [rbp+16], kept in rbx
fn genDropFunction(mut g Gen, t TypeId, offs i64[], types TypeId[], tags i64[]):
	g.genHelperPrologue(fnLabel(g.fnLabels, g.a, "$drop:{g.descriptor(t)}"))
	g.a.em4(0x48, 0x8B, 0x5D, 0x10)   # mov rbx, [rbp+16]
	k = g.tyK(t)
	done = g.a.asmNewLabel()
	if k == tStruct and nodes[declOf(tys, t)].hasFlag(flagDrop):
		g.callDropFunction(t, done)
	if k == tStruct or k == tArray:
		for i, off in offs:
			g.dropAtRbx(off, types[i])
	elif k == tOption:
		g.skipNone(t, done)
		g.dropAtRbx(offs[0], types[0])
	elif k == tResult:
		isErr = g.a.asmNewLabel()
		g.jumpOnTag(resultTag(), 1, false, isErr)
		g.dropAtRbx(offs[0], types[0])
		g.a.jmpLabel(done)
		g.a.asmPlace(isErr)
		g.dropAtRbx(offs[1], types[1])
	elif k == tEnum:
		i = 0
		while i < offs.len:
			# the owning fields of one variant, guarded by its tag
			tag = tags[i]
			next = g.a.asmNewLabel()
			g.jumpOnTag(g.c.enumTag(declOf(tys, t)), tag, false, next)
			while i < offs.len and tags[i] == tag:
				g.dropAtRbx(offs[i], types[i])
				i += 1
			g.a.jmpLabel(done)
			g.a.asmPlace(next)
	elif k == tBox and tys[t].counted:
		g.a.em3(0x48, 0x8B, 0x1B)   # mov rbx, [rbx]  (the value)
		g.a.em3(0x48, 0x85, 0xDB)   # test rbx, rbx
		g.a.jccLabel(0x84, done)
		g.a.emN([0xF0, 0x48, 0x83, 0x6B, 0xF8, 0x01])   # lock sub qword [rbx-8], 1
		g.a.jccLabel(0x85, done)   # other owners remain
		g.dropAtRbx(0, types[0])
		g.a.em4(0x48, 0x8D, 0x43, 0xF8)   # lea rax, [rbx-8]  (the block)
		g.a.pushRax()
		g.callRtNamed("rtFree", 8)
	elif k == tBox or k == tMap:
		# the block a box points to, or a map's table (its layout is map.zap's): its own drop,
		# then the block itself
		g.a.em3(0x48, 0x8B, 0x1B)   # mov rbx, [rbx]
		g.a.em3(0x48, 0x85, 0xDB)   # test rbx, rbx
		g.a.jccLabel(0x84, done)
		g.dropAtRbx(0, types[0] if k == tBox else g.mapTableType(t))
		g.rtFreeRbx()
	else:
		elem = types[0]
		stride = offs[0]
		g.a.em4(0x48, 0x83, 0x7B, 0x10)   # cmp qword [rbx+16], 0  (a window owns nothing)
		g.a.em1(0x00)
		g.a.jccLabel(0x84, done)
		top = g.a.asmNewLabel()
		end = g.a.asmNewLabel()
		g.a.em4(0x4C, 0x8B, 0x6B, 0x08)   # mov r13, [rbx+8]  (length)
		g.a.em3(0x4D, 0x69, 0xED)   # imul r13, r13, stride
		g.a.emit32(stride)
		g.a.em3(0x4C, 0x03, 0x2B)   # add r13, [rbx]    (the end of the elements)
		g.a.em3(0x4C, 0x8B, 0x33)   # mov r14, [rbx]    (the first element)
		g.placeLoopTop(top)
		g.a.em3(0x4D, 0x39, 0xEE)   # cmp r14, r13
		g.a.jccLabel(0x83, end)
		g.a.em3(0x4C, 0x89, 0xF0)   # mov rax, r14
		g.emitDropAt(elem)
		g.a.em3(0x49, 0x81, 0xC6)   # add r14, stride
		g.a.emit32(stride)
		g.a.jmpLabel(top)
		g.a.asmPlace(end)
		g.a.em3(0x48, 0x8B, 0x03)   # mov rax, [rbx]  (the buffer)
		g.a.testRax()
		g.a.jccLabel(0x84, done)
		g.a.pushRax()
		g.callRtNamed("rtFree", 8)
	g.a.asmPlace(done)
	g.genHelperEpilogue()

# on to done when the optional t at rbx is none: its tag 0, or its niche the absent value
fn skipNone(mut g Gen, t TypeId, done i64):
	spot = g.c.optionTag(t)
	g.jumpOnTag(spot, spot.absent, true, done)

# on to label when the tag spot of the value at rbx holds v (equal), or when it does not
fn jumpOnTag(mut g Gen, spot TagSpot, v i64, equal bool, label i64):
	bits = spotBits(v, spot.size)
	if spot.size == 8 and (bits < -2_147_483_648 or bits > 2_147_483_647):
		g.a.movRaxImm(bits)
		g.a.em3(0x48, 0x39, 0x83)   # cmp [rbx+off], rax
		g.a.emit32(spot.off)
	else:
		if spot.size == 2:
			g.a.em1(0x66)
		if spot.size == 8:
			g.a.em1(0x48)
		g.a.em1(0x80 if spot.size == 1 else 0x81)
		g.a.em1(0xBB)   # cmp [rbx+off], imm
		g.a.emit32(spot.off)
		if spot.size == 1:
			g.a.em1(bits)
		elif spot.size == 2:
			g.a.em1(bits & 0xFF)
			g.a.em1(bits >> 8)
		else:
			g.a.emit32(bits)
	g.a.jccLabel(0x84 if equal else 0x85, label)

# The type's drop function on the value at rbx (pushed: it takes the stack convention), when the
# value is live (its live word set, dropLiveOffset): the empty value `move` leaves in a place
# releases nothing (and then owns nothing: the fields are skipped too, to done).
fn callDropFunction(mut g Gen, t TypeId, done i64):
	call = g.a.asmNewLabel()
	g.a.em3(0x48, 0x83, 0xBB)   # cmp qword [rbx+live], 0
	g.a.emit32(g.c.dropLiveOffset(declOf(tys, t)))
	g.a.em1(0)
	g.a.jccLabel(0x85, call)
	g.a.jmpLabel(done)
	g.a.asmPlace(call)
	g.a.em1(0x53)   # push rbx
	g.a.callLabel(fnLabel(g.fnLabels, g.a, "{tys[t].name}_drop"))
	g.a.addRsp(8)

# `$copy:T(src, dst)`: src at [rbp+24] kept in rbx, dst at [rbp+16] kept in r13
fn genCopyFunction(mut g Gen, t TypeId, offs i64[], types TypeId[], tags i64[]):
	g.genHelperPrologue(fnLabel(g.fnLabels, g.a, "$copy:{g.descriptor(t)}"))
	g.a.em4(0x48, 0x8B, 0x5D, 0x18)   # mov rbx, [rbp+24]
	g.a.em4(0x4C, 0x8B, 0x6D, 0x10)   # mov r13, [rbp+16]
	k = g.tyK(t)
	done = g.a.asmNewLabel()
	if k in [tStruct, tArray, tOption, tResult, tEnum]:
		# the whole value bitwise, then the owning parts replaced by deep copies
		g.a.em3(0x48, 0x89, 0xD8)   # mov rax, rbx
		g.a.em3(0x4C, 0x89, 0xE9)   # mov rcx, r13
		g.copyBytes(g.sizeOf(t))
		if k == tOption:
			g.skipNone(t, done)
		i = 0
		while i < offs.len:
			guarded = k == tEnum or k == tResult
			tag = tags[i]
			next = g.a.asmNewLabel()
			if guarded and k == tResult:
				g.jumpOnTag(resultTag(), 1, tag == 0, next)   # an error's: anything but 1
			elif guarded:
				g.jumpOnTag(g.c.enumTag(declOf(tys, t)), tag, false, next)
			while i < offs.len and (tags[i] == tag or not guarded):
				if g.isOwningType(types[i]):
					g.copyRbxToR13(offs[i], types[i])
				i += 1
			if guarded:
				g.a.jmpLabel(done)
				g.a.asmPlace(next)
	elif k == tBox and tys[t].counted:
		# another owner of the same value: the pointer, one more in the count
		skip = g.a.asmNewLabel()
		g.a.em3(0x48, 0x8B, 0x1B)   # mov rbx, [rbx]  (the value)
		g.a.em4(0x49, 0x89, 0x5D, 0x00)   # mov [r13], rbx
		g.a.em3(0x48, 0x85, 0xDB)   # test rbx, rbx
		g.a.jccLabel(0x84, skip)
		g.a.emN([0xF0, 0x48, 0x83, 0x43, 0xF8, 0x01])   # lock add qword [rbx-8], 1
		g.a.asmPlace(skip)
	elif k == tBox:
		g.a.em3(0x48, 0x8B, 0x1B)   # mov rbx, [rbx]  (the source block)
		g.rtAllocImm(g.sizeOf(types[0]))
		g.a.em4(0x49, 0x89, 0x45, 0x00)   # mov [r13], rax
		g.a.em3(0x49, 0x89, 0xC5)   # mov r13, rax  (the new block)
		g.a.em3(0x48, 0x89, 0xD8)   # mov rax, rbx
		g.a.em3(0x4C, 0x89, 0xE9)   # mov rcx, r13
		g.emitCopyAt(types[0])
	elif k == tMap:
		g.a.em3(0x48, 0x8B, 0x1B)   # mov rbx, [rbx]  (the source table)
		g.a.emN([0x49, 0xC7, 0x45, 0x00, 0, 0, 0, 0])   # mov qword [r13], 0
		g.a.em3(0x48, 0x85, 0xDB)   # test rbx, rbx
		g.a.jccLabel(0x84, done)
		tt = g.mapTableType(t)
		g.rtAllocImm(g.sizeOf(tt))
		g.a.em4(0x49, 0x89, 0x45, 0x00)   # mov [r13], rax
		g.a.em3(0x48, 0x89, 0xC1)   # mov rcx, rax  (the new table)
		g.a.em3(0x48, 0x89, 0xD8)   # mov rax, rbx
		g.emitCopyAt(tt)   # the table's own deep copy
	else:
		elem = types[0]
		stride = offs[0]
		g.a.emN([0x49, 0xC7, 0x45, 0x00, 0, 0, 0, 0])   # mov qword [r13], 0
		g.a.emN([0x49, 0xC7, 0x45, 0x08, 0, 0, 0, 0])   # mov qword [r13+8], 0
		g.a.emN([0x49, 0xC7, 0x45, 0x10, 0, 0, 0, 0])   # mov qword [r13+16], 0
		g.a.em4(0x4C, 0x8B, 0x73, 0x08)   # mov r14, [rbx+8]  (length)
		g.a.em3(0x4D, 0x85, 0xF6)   # test r14, r14
		g.a.jccLabel(0x84, done)
		g.a.em2(0x41, 0x55)   # push r13   listCopyRaw-like growth: listGrowRaw(dst, n, stride)
		g.a.em2(0x41, 0x56)   # push r14
		g.a.movRaxImm(stride)
		g.a.pushRax()
		g.callRtNamed("listGrowExact", 24)
		g.a.em4(0x4D, 0x8B, 0x7D, 0x00)   # mov r15, [r13]  (the destination elements)
		g.a.em3(0x48, 0x8B, 0x1B)   # mov rbx, [rbx]  (the source elements)
		g.a.em3(0x4D, 0x69, 0xF6)   # imul r14, r14, stride
		g.a.emit32(stride)
		g.a.em3(0x49, 0x01, 0xDE)   # add r14, rbx    (the end of the source)
		top = g.a.asmNewLabel()
		end = g.a.asmNewLabel()
		g.placeLoopTop(top)
		g.a.em3(0x4C, 0x39, 0xF3)   # cmp rbx, r14
		g.a.jccLabel(0x83, end)
		g.a.em3(0x48, 0x89, 0xD8)   # mov rax, rbx
		g.a.em3(0x4C, 0x89, 0xF9)   # mov rcx, r15
		g.emitCopyAt(elem)
		g.a.em3(0x48, 0x81, 0xC3)   # add rbx, stride
		g.a.emit32(stride)
		g.a.em3(0x49, 0x81, 0xC7)   # add r15, stride
		g.a.emit32(stride)
		g.a.jmpLabel(top)
		g.a.asmPlace(end)
		g.a.em4(0x48, 0x8B, 0x45, 0x18)   # mov rax, [rbp+24]  (the source header)
		g.a.em4(0x48, 0x8B, 0x40, 0x08)   # mov rax, [rax+8]   (its length)
		g.a.em4(0x49, 0x89, 0x45, 0x08)   # mov [r13+8], rax
	g.a.asmPlace(done)
	g.genHelperEpilogue()

# `$dropClosure(p)`: the environment, when there is one, drops and frees itself (op 0)
fn genDropClosure(mut g Gen):
	g.a.asmPlace(fnLabel(g.fnLabels, g.a, "$dropClosure"))
	g.a.framePrologue()
	done = g.a.asmNewLabel()
	g.a.em4(0x48, 0x8B, 0x45, 0x10)   # mov rax, [rbp+16]
	g.a.em4(0x48, 0x8B, 0x48, 0x08)   # mov rcx, [rax+8]  (env)
	g.a.em3(0x48, 0x85, 0xC9)   # test rcx, rcx
	g.a.jccLabel(0x84, done)
	g.a.em1(0x51)   # push rcx   (env)
	g.a.em2(0x31, 0xC0)   # xor eax, eax
	g.a.pushRax()   # push 0     (op: drop)
	g.a.em2(0xFF, 0x11)   # call [rcx]
	g.a.addRsp(16)
	g.a.asmPlace(done)
	g.a.em1(0x5D)   # pop rbp
	g.a.em1(0xC3)   # ret

# `$copyClosure(src, dst)`: the code pointer is shared, the environment copies itself (op 1)
fn genCopyClosure(mut g Gen):
	g.a.asmPlace(fnLabel(g.fnLabels, g.a, "$copyClosure"))
	g.a.framePrologue()
	noEnv = g.a.asmNewLabel()
	done = g.a.asmNewLabel()
	g.a.em4(0x48, 0x8B, 0x45, 0x18)   # mov rax, [rbp+24]  (src)
	g.a.em4(0x48, 0x8B, 0x55, 0x10)   # mov rdx, [rbp+16]  (dst)
	g.a.em4(0x48, 0x8B, 0x48, 0x08)   # mov rcx, [rax+8]   (env)
	g.a.em3(0x48, 0x8B, 0x00)   # mov rax, [rax]     (code)
	g.a.em3(0x48, 0x89, 0x02)   # mov [rdx], rax
	g.a.em3(0x48, 0x85, 0xC9)   # test rcx, rcx
	g.a.jccLabel(0x84, noEnv)
	g.a.em1(0x51)   # push rcx   (env)
	g.a.movRaxImm(1)
	g.a.pushRax()   # push 1     (op: copy)
	g.a.em2(0xFF, 0x11)   # call [rcx]
	g.a.addRsp(16)
	g.a.em4(0x48, 0x8B, 0x55, 0x10)   # mov rdx, [rbp+16]
	g.a.em4(0x48, 0x89, 0x42, 0x08)   # mov [rdx+8], rax
	g.a.jmpLabel(done)
	g.a.asmPlace(noEnv)
	g.a.emN([0x48, 0xC7, 0x42, 0x08, 0, 0, 0, 0])   # mov qword [rdx+8], 0
	g.a.asmPlace(done)
	g.a.em1(0x5D)   # pop rbp
	g.a.em1(0xC3)   # ret

# `$env:<n>(env, op)`: env at [rbp+24] kept in rbx, op at [rbp+16]; the block is the header
# word (this function) and envSize bytes of captures at the offsets planned
fn genEnvFunction(mut g Gen, key str, envSize i64, offs i64[], types TypeId[]):
	g.genHelperPrologue(fnLabel(g.fnLabels, g.a, key))
	g.a.em4(0x48, 0x8B, 0x5D, 0x18)   # mov rbx, [rbp+24]
	copy = g.a.asmNewLabel()
	done = g.a.asmNewLabel()
	g.a.emN([0x48, 0x83, 0x7D, 0x10, 0x00])   # cmp qword [rbp+16], 0
	g.a.jccLabel(0x85, copy)
	for i, off in offs:
		g.dropAtRbx(off, types[i])
	g.rtFreeRbx()
	g.a.em2(0x31, 0xC0)   # xor eax, eax
	g.a.jmpLabel(done)
	g.a.asmPlace(copy)
	g.rtAllocImm(8 + envSize)
	g.a.em3(0x49, 0x89, 0xC5)   # mov r13, rax  (the new block)
	g.a.em3(0x48, 0x89, 0xD8)   # mov rax, rbx
	g.a.em3(0x4C, 0x89, 0xE9)   # mov rcx, r13
	g.copyBytes(8 + envSize)
	for i, off in offs:
		g.copyRbxToR13(off, types[i])
	g.a.em3(0x4C, 0x89, 0xE8)   # mov rax, r13
	g.a.asmPlace(done)
	g.genHelperEpilogue()
