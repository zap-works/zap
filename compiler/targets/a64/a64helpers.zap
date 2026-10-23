# The AArch64 build's own functions (codegen.zap's, drops.zap's and fnvalues.zap's for x64): the
# start, the failure stubs, and the drops, copies and closures planned per type (typeParts says
# what each walks). They take their arguments in x0 and x1 (an environment's function: the
# environment and the op), keep what they walk in x19..x24 and have an area of four words at sp
# for the runtime's calls that take their arguments there.

alias nodes = g.c.nodes
alias tys = g.c.types

# The start: the stack's top kept in the runtime's slot (as on x64: Linux's arguments and
# environment are there), the thread's slots (the runtime's TLS) at tpidr_el0, a stack of
# Windows' size, the module variables, the entry, then the end with code 0.
fn a64Start(mut g Gen, entry str):
	g.a.a64MovImm(a64Fp, 0)   # the last frame record
	g.a.a64AdrData(a64T0, g.globalsOff)
	g.a.a64AddImm(a64T1, a64Sp, 0)
	g.a.a64Str(a64T1, a64T0, 16)
	g.libcTls = g.reserveWords(2)   # the thread block a dynamic loader left (0 of a static one), then cLock
	g.a.a64AdrData(a64T0, g.libcTls)
	g.a.a64(0xD53B_D040 | a64T1)   # mrs x17, tpidr_el0
	g.a.a64Str(a64T1, a64T0, 0)
	g.a.a64AdrData(a64T0, g.a.asmBssZero(8 * a64TlsSlots))
	g.a.a64(0xD51B_D040 | a64T0)   # msr tpidr_el0, x16
	if appBuild:
		# an app's thread is bionic's, its stack of that size (android/entry.zap): its own block is
		# its library block (ccall.zap's thread slot)
		g.a.a64Str(a64T1, a64T0, 8 * cBlockSlot)
		g.a.a64AddImm(a64Sp, a64Sp, -32)   # the area of the calls below
	else:
		g.a.a64AddImm(a64Sp, a64Sp, -32)
		g.a64CallRt("mainStack", 0)   # the stack Windows would give (runtime/system/linux/threads.zap)
		g.a.a64AddImm(a64Sp, 0, -32)   # the area of the calls below
	g.a.a64Bl(fnLabel(g.fnLabels, g.a, "$init"))
	g.a.a64Bl(fnLabel(g.fnLabels, g.a, entry))
	g.a.a64MovImm(0, 0)
	g.a64CallRt("endAfterMain", 1)
	g.a.a64Brk(0)

# the slots of the main thread's TLS (TlsAlloc gives them out in order)
a64TlsSlots = 64

# rt__name called with its n arguments in x0.., moved to the area at sp when it takes them there
fn a64CallRt(mut g Gen, name str, n i64):
	if not g.takesRegArgs(g.rtDecl(name), false):
		for i in 0..n:
			g.a.a64Str(i, a64Sp, 8 * (n - 1 - i))
	g.a.a64Bl(fnLabel(g.fnLabels, g.a, "rt__{name}"))

# a function of this file: its frame record, x19..x24 saved, the area
fn a64HelperStart(mut g Gen, label i64):
	g.a.asmPlace(label)
	g.a.a64Pair(false, a64Fp, a64Lr, a64Sp, -64, 1)   # stp x29, x30, [sp, -64]!
	g.a.a64AddImm(a64Fp, a64Sp, 0)
	for k in 0..3:
		g.a.a64Pair(false, 19 + 2 * k, 20 + 2 * k, a64Fp, 16 + 16 * k, 0)
	g.a.a64AddImm(a64Sp, a64Sp, -32)

fn a64HelperEnd(mut g Gen):
	g.a.a64AddImm(a64Sp, a64Fp, 0)
	for k in 0..3:
		g.a.a64Pair(true, 19 + 2 * k, 20 + 2 * k, a64Fp, 16 + 16 * k, 0)
	g.a.a64Pair(true, a64Fp, a64Lr, a64Sp, 64, 2)   # ldp x29, x30, [sp], 64
	g.a.a64Ret()

# a shared failure stub: rt.failAt with the kind; the return address the site's exit left tells
# it where
fn a64FailStub(mut g Gen, label i64, kind i64):
	g.a64HelperStart(label)
	g.a.a64MovImm(0, kind)
	g.a64CallRt("failAt", 1)
	g.a.a64Brk(0)

# x0 = the address of a value of type t: dropped (what it owns freed)
fn a64DropAt(mut g Gen, t TypeId):
	if not g.isOwningType(t): return
	k = g.tyK(t)
	if k == tStr or (isListKind(k) and g.c.isPlainType(g.listElem(t))):
		# one buffer, owned when the capacity is above 0 (a short str's is negative)
		skip = g.a.asmNewLabel()
		g.a.a64Ldr(1, 0, 16)
		g.a.a64CmpImm(1, 0)
		g.a.a64BCond(a64Le, skip)
		g.a.a64Ldr(0, 0, 0)
		g.a.a64Cbz(0, skip, false)
		g.a64CallRt("rtFree", 1)
		g.a.asmPlace(skip)
		return
	g.a.a64Bl(g.closureStubLabel("$dropClosure") if k == tFn else g.typeFnLabel(t, true))

# x0 = the source's address, x1 = the destination's, both of type t: a deep copy
fn a64CopyAt(mut g Gen, t TypeId):
	if not g.isOwningType(t):
		g.a.a64Mov(5, 0)
		g.a.a64Mov(4, 1)
		g.a.a64CopyBytes(g.sizeOf(t))
		return
	k = g.tyK(t)
	if k == tStr:
		g.a64CallRt("strCopyRaw", 2)
	elif isListKind(k) and g.c.isPlainType(g.listElem(t)):
		g.a.a64MovImm(2, g.c.elemStride(g.listElem(t)))
		g.a64CallRt("listCopyRaw", 3)
	else:
		g.a.a64Bl(g.closureStubLabel("$copyClosure") if k == tFn else g.typeFnLabel(t, false))

# x0 = x19 + off, then its drop (x19 the value being dropped)
fn a64DropPart(mut g Gen, off i64, t TypeId):
	g.a.a64AddImm(0, 19, off)
	g.a64DropAt(t)

# the part at off of x19 deep-copied to the same offset of x20 (the source and the destination)
fn a64CopyPart(mut g Gen, off i64, t TypeId):
	g.a.a64AddImm(0, 19, off)
	g.a.a64AddImm(1, 20, off)
	g.a64CopyAt(t)

# on to label when the word at x19 is (or, equal false, is not) v
fn a64TagIs(mut g Gen, spot TagSpot, v i64, equal bool, label i64):
	g.a.a64Load(6, 19, spot.off, spot.size, true)
	g.a.a64CmpValue(6, spotBits(v, spot.size), 7)
	g.a.a64BCond(a64Eq if equal else a64Ne, label)

# the planned function next (drops.zap's genDropFunctions), written for AArch64
fn a64GenPlanned(mut g Gen, next Planned):
	key = next.key
	t = next.t ?? tyError
	if key == "$dropClosure":
		g.a64DropClosure()
	elif key == "$copyClosure":
		g.a64CopyClosure()
	elif key.startsWith("$env:"):
		g.a64EnvFunction(key, next.envSize, next.offs, next.types)
	elif key.startsWith("$fnval:"):
		# called as a closure: the words below its environment are the function's own
		g.a.asmPlace(fnLabel(g.fnLabels, g.a, key))
		g.a.a64B(fnLabel(g.fnLabels, g.a, key[7..]))
	elif key.startsWith("$callback:"):
		g.a64Callback(key, t)
	elif key.startsWith("$drop:"):
		g.a64DropFunction(t, next.offs, next.types, next.tags)
	else:
		g.a64CopyFunction(t, next.offs, next.types, next.tags)

# `$drop:T(p)`: p kept in x19
fn a64DropFunction(mut g Gen, t TypeId, offs i64[], types TypeId[], tags i64[]):
	g.a64HelperStart(fnLabel(g.fnLabels, g.a, "$drop:{g.descriptor(t)}"))
	g.a.a64Mov(19, 0)
	k = g.tyK(t)
	done = g.a.asmNewLabel()
	if k == tStruct and nodes[declOf(tys, t)].hasFlag(flagDrop):
		# the type's drop, when the value is live: the empty value `move` leaves owns nothing
		g.a.a64Ldr(6, 19, g.c.dropLiveOffset(declOf(tys, t)))
		g.a.a64Cbz(6, done, false)
		g.a.a64Str(19, a64Sp, 0)
		g.a.a64Bl(fnLabel(g.fnLabels, g.a, "{tys[t].name}_drop"))
	if k == tStruct or k == tArray:
		for i, off in offs:
			g.a64DropPart(off, types[i])
	elif k == tOption:
		g.a64TagIs(g.c.optionTag(t), g.c.optionTag(t).absent, true, done)
		g.a64DropPart(offs[0], types[0])
	elif k == tResult:
		isErr = g.a.asmNewLabel()
		g.a64TagIs(resultTag(), 1, false, isErr)
		g.a64DropPart(offs[0], types[0])
		g.a.a64B(done)
		g.a.asmPlace(isErr)
		g.a64DropPart(offs[1], types[1])
	elif k == tEnum:
		i = 0
		while i < offs.len:
			tag = tags[i]
			next = g.a.asmNewLabel()
			g.a64TagIs(g.c.enumTag(declOf(tys, t)), tag, false, next)
			while i < offs.len and tags[i] == tag:
				g.a64DropPart(offs[i], types[i])
				i += 1
			g.a.a64B(done)
			g.a.asmPlace(next)
	elif k == tBox or k == tMap:
		g.a.a64Ldr(19, 19, 0)
		g.a.a64Cbz(19, done, false)
		if k == tBox and tys[t].counted:
			g.a.a64AddImm(4, 19, -8)
			g.a64Count(-1)
			g.a.a64Cbz(6, done, true)   # other owners remain
		g.a64DropPart(0, types[0] if k == tBox else g.mapTableType(t))
		g.a.a64AddImm(0, 19, -8 if k == tBox and tys[t].counted else 0)
		g.a64CallRt("rtFree", 1)
	else:
		g.a64DropList(types[0], offs[0], done)
	g.a.asmPlace(done)
	g.a64HelperEnd()

# a list's elements dropped (x19 its header), then its buffer; a window owns nothing
fn a64DropList(mut g Gen, elem TypeId, stride i64, done i64):
	g.a.a64Ldr(6, 19, 16)
	g.a.a64Cbz(6, done, false)
	g.a.a64Ldr(20, 19, 0)   # the first element
	g.a.a64Ldr(21, 19, 8)
	g.a.a64MovImm(6, stride)
	g.a.a64Op3(a64Mul, 21, 21, 6)
	g.a.a64Op3(a64Add, 21, 21, 20)   # the end of the elements
	top = g.a.asmNewLabel()
	end = g.a.asmNewLabel()
	g.a.asmPlace(top)
	g.a.a64Cmp(20, 21)
	g.a.a64BCond(a64Hs, end)
	g.a.a64Mov(0, 20)
	g.a64DropAt(elem)
	g.a.a64AddImm(20, 20, stride)
	g.a.a64B(top)
	g.a.asmPlace(end)
	g.a.a64Ldr(0, 19, 0)
	g.a.a64Cbz(0, done, false)
	g.a64CallRt("rtFree", 1)

# the count at the address in x4 changed by by, atomically: x6 the count after
fn a64Count(mut g Gen, by i64):
	if armAtomics():
		g.a.a64MovImm(5, by)
		g.a.a64Op3(a64LdaddAl, 6, 4, 5)
		g.a.a64AddImm(6, 6, by)
		return
	again = g.a.asmNewLabel()
	g.a.asmPlace(again)
	g.a.a64(0xC85F_FC00 | 4 << 5 | 6)   # ldaxr x6, [x4]
	g.a.a64AddImm(6, 6, by)
	g.a.a64(0xC800_FC00 | 8 << 16 | 4 << 5 | 6)   # stlxr w8, x6, [x4]
	g.a.a64Fixed(fxA64Cond, again, 0x3500_0000 | 8)   # cbnz w8, again
	g.a.a64(a64DmbIsh)   # a full barrier, as x64's lock prefix is

# `$copy:T(src, dst)`: src kept in x19, dst in x20
fn a64CopyFunction(mut g Gen, t TypeId, offs i64[], types TypeId[], tags i64[]):
	g.a64HelperStart(fnLabel(g.fnLabels, g.a, "$copy:{g.descriptor(t)}"))
	g.a.a64Mov(19, 0)
	g.a.a64Mov(20, 1)
	k = g.tyK(t)
	done = g.a.asmNewLabel()
	if k in [tStruct, tArray, tOption, tResult, tEnum]:
		# the whole value bitwise, then the owning parts replaced by deep copies
		g.a.a64Mov(5, 19)
		g.a.a64Mov(4, 20)
		g.a.a64CopyBytes(g.sizeOf(t))
		if k == tOption:
			g.a64TagIs(g.c.optionTag(t), g.c.optionTag(t).absent, true, done)
		guarded = k == tEnum or k == tResult
		i = 0
		while i < offs.len:
			tag = tags[i]
			next = g.a.asmNewLabel()
			if guarded:
				spot = resultTag() if k == tResult else g.c.enumTag(declOf(tys, t))
				g.a64TagIs(spot, 1 if k == tResult else tag, k == tResult and tag == 0, next)
			while i < offs.len and (tags[i] == tag or not guarded):
				g.a64CopyPart(offs[i], types[i])
				i += 1
			if guarded:
				g.a.a64B(done)
				g.a.asmPlace(next)
	elif k == tBox and tys[t].counted:
		# another owner of the same value: the pointer, one more in the count
		g.a.a64Ldr(19, 19, 0)
		g.a.a64Str(19, 20, 0)
		g.a.a64Cbz(19, done, false)
		g.a.a64AddImm(4, 19, -8)
		g.a64Count(1)
	elif k == tBox or k == tMap:
		g.a.a64Ldr(19, 19, 0)
		g.a.a64Str(a64Zr, 20, 0)
		g.a.a64Cbz(19, done, false)
		inner = types[0] if k == tBox else g.mapTableType(t)
		g.a.a64MovImm(0, g.sizeOf(inner))
		g.a64CallRt("rtAlloc", 1)
		g.a.a64Str(0, 20, 0)
		g.a.a64Mov(1, 0)
		g.a.a64Mov(0, 19)
		g.a64CopyAt(inner)
	else:
		g.a64CopyList(types[0], offs[0], done)
	g.a.asmPlace(done)
	g.a64HelperEnd()

# a list's copy (x19 the source's header, x20 the destination's): grown to the length, each
# element copied deep
fn a64CopyList(mut g Gen, elem TypeId, stride i64, done i64):
	for off in [0, 8, 16]:
		g.a.a64Str(a64Zr, 20, off)
	g.a.a64Ldr(21, 19, 8)
	g.a.a64Cbz(21, done, false)
	g.a.a64Mov(0, 20)
	g.a.a64Mov(1, 21)
	g.a.a64MovImm(2, stride)
	g.a64CallRt("listGrowExact", 3)
	g.a.a64MovImm(6, stride)
	g.a.a64Op3(a64Mul, 23, 21, 6)
	g.a.a64Ldr(21, 19, 0)   # the source's elements
	g.a.a64Ldr(22, 20, 0)   # the destination's
	g.a.a64Op3(a64Add, 23, 23, 21)   # the end of the source's
	top = g.a.asmNewLabel()
	end = g.a.asmNewLabel()
	g.a.asmPlace(top)
	g.a.a64Cmp(21, 23)
	g.a.a64BCond(a64Hs, end)
	g.a.a64Mov(0, 21)
	g.a.a64Mov(1, 22)
	g.a64CopyAt(elem)
	g.a.a64AddImm(21, 21, stride)
	g.a.a64AddImm(22, 22, stride)
	g.a.a64B(top)
	g.a.asmPlace(end)
	g.a.a64Ldr(6, 19, 8)
	g.a.a64Str(6, 20, 8)

# `$dropClosure(p)`: the environment, when there is one, drops and frees itself (op 0)
fn a64DropClosure(mut g Gen):
	g.a64HelperStart(fnLabel(g.fnLabels, g.a, "$dropClosure"))
	done = g.a.asmNewLabel()
	g.a.a64Ldr(0, 0, 8)
	g.a.a64Cbz(0, done, false)
	g.a.a64MovImm(1, 0)
	g.a.a64Ldr(6, 0, 0)
	g.a.a64Blr(6)
	g.a.asmPlace(done)
	g.a64HelperEnd()

# `$copyClosure(src, dst)`: the code pointer is shared, the environment copies itself (op 1)
fn a64CopyClosure(mut g Gen):
	g.a64HelperStart(fnLabel(g.fnLabels, g.a, "$copyClosure"))
	g.a.a64Mov(19, 1)
	g.a.a64Ldr(6, 0, 0)
	g.a.a64Str(6, 19, 0)
	g.a.a64Ldr(0, 0, 8)
	noEnv = g.a.asmNewLabel()
	g.a.a64Cbz(0, noEnv, false)
	g.a.a64MovImm(1, 1)
	g.a.a64Ldr(6, 0, 0)
	g.a.a64Blr(6)
	g.a.asmPlace(noEnv)
	g.a.a64Str(0, 19, 8)   # (0 when there is none)
	g.a64HelperEnd()

# `$env:<n>(env, op)`: env kept in x19; op 0 drops the captures and frees the block, 1 returns
# a copy of it (the header word, this function, then envSize bytes of captures)
fn a64EnvFunction(mut g Gen, key str, envSize i64, offs i64[], types TypeId[]):
	g.a64HelperStart(fnLabel(g.fnLabels, g.a, key))
	g.a.a64Mov(19, 0)
	copy = g.a.asmNewLabel()
	done = g.a.asmNewLabel()
	g.a.a64Cbz(1, copy, true)
	for i, off in offs:
		g.a64DropPart(off, types[i])
	g.a.a64Mov(0, 19)
	g.a64CallRt("rtFree", 1)
	g.a.a64MovImm(0, 0)
	g.a.a64B(done)
	g.a.asmPlace(copy)
	g.a.a64MovImm(0, 8 + envSize)
	g.a64CallRt("rtAlloc", 1)
	g.a.a64Mov(20, 0)
	g.a.a64Mov(5, 19)
	g.a.a64Mov(4, 20)
	g.a.a64CopyBytes(8 + envSize)
	for i, off in offs:
		g.a64CopyPart(off, types[i])
	g.a.a64Mov(0, 20)
	g.a.asmPlace(done)
	g.a64HelperEnd()
