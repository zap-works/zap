# Extern functions: stubs that call the system's (or a loaded library's) functions.

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

# An extern function is a stub in the Zap convention (arguments on the stack, the last one
# nearest the return address, the result in rax) that performs the Win64 call: the first four
# arguments in rcx, rdx, r8, r9 (an f64 in xmm0..xmm3 too), the rest above the shadow space,
# the stack aligned to 16. The system preserves rbx, r12..r15 and xmm6..xmm15, so a caller's
# cached locals survive the call.
fn genExternFunction(mut g Gen, fnd NodeId, key str):
	if nodes[fnd].names2()[0] == jsLibrary:
		# a JS function (`extern "js" fn`): only the JS target has it, a native call stops
		label = fnLabel(g.fnLabels, g.a, key)
		g.cMessageStub(
			label,
			"extern fn {nodes[fnd].text2()} is a JS function: it runs under --target js"
		)
		return
	if onLinux() and not nodes[fnd].names2()[0].startsWith(syscallLibrary):
		g.genLibraryStub(fnd, key)
		return
	if onArm():
		g.a64ExternStub(fnd, key)
		return
	if onLinux():
		g.x64SyscallStub(fnd, key)
		return
	g.a.asmPlace(fnLabel(g.fnLabels, g.a, key))
	# the parameters are read through g at each step: resolveType changes g.c
	n = nodes[fnd].kids(kidIds).len
	g.a.framePrologue()
	g.a.em4(0x48, 0x83, 0xE4, 0xF0)   # and rsp, -16
	extra = 0
	if n > 4:
		extra = n - 4
	g.subRsp((32 + 8 * extra + 15) / 16 * 16)
	argRegs = [1, 2, 8, 9]   # rcx, rdx, r8, r9
	for i in 0..n:
		disp = 16 + 8 * (n - 1 - i)
		pt = g.c.resolveType(nodes[nodes[fnd].kids(kidIds)[i]].types()[0])
		if i < 4:
			g.a.memOp(true, 0x8B, -1, argRegs[i], 5, -1, disp)   # mov reg, [rbp+disp]
			if g.tyK(pt) == tList or g.tyK(pt) == tStr:
				g.loadBytesAddress(argRegs[i], g.tyK(pt) == tStr)
			if g.tyK(pt) == tFloat:
				# an f64 whole (movq), an f32 in the low half (movd): the slot holds its bits
				wide = tys[pt].bits == 64
				g.a.em1(0x66)
				if i < 2 and wide:
					g.a.em1(0x48)
				elif i >= 2:
					g.a.em1(0x49 if wide else 0x41)
				g.a.em2(0x0F, 0x6E)
				g.a.em1(0xC0 | i << 3 | (argRegs[i] & 7))   # movq / movd xmm_i, reg
		else:
			g.a.memOp(true, 0x8B, -1, 0, 5, -1, disp)   # mov rax, [rbp+disp]
			if g.tyK(pt) == tList or g.tyK(pt) == tStr:
				g.loadBytesAddress(0, g.tyK(pt) == tStr)
			g.a.memOp(true, 0x89, -1, 0, 4, -1, 32 + 8 * (i - 4))   # mov [rsp+32+8(i-4)], rax
	notLoaded = -1
	if nodes[fnd].names2()[0] == "":
		# an extern loaded fn: the address bindExtern wrote, or a stop with a message
		notLoaded = g.a.asmNewLabel()
		g.a.leaRaxData(g.loadedSlot(fnd))
		g.a.em3(0x48, 0x8B, 0x00)   # mov rax, [rax]
		g.a.em3(0x48, 0x85, 0xC0)   # test rax, rax
		g.a.jccLabel(0x84, notLoaded)
		g.a.em2(0xFF, 0xD0)   # call rax
	else:
		slot = g.a.asmImport(nodes[fnd].names2()[0], nodes[fnd].text2())   # the name as written, before the module prefix
		g.a.em2(0xFF, 0x15)   # call [rip+import]
		g.a.asmDisp32Import(slot)
	ret = g.c.fnRetType(fnd)
	if g.tyK(ret) == tFloat and tys[ret].bits == 32:
		g.a.em4(0xF3, 0x0F, 0x5A, 0xC0)   # cvtss2sd xmm0, xmm0: an f32 travels as its f64
		g.a.movqRaxXmm0()
	elif g.tyK(ret) == tFloat:
		g.a.movqRaxXmm0()
	elif g.tyK(ret) == tBool:
		g.a.em2(0x85, 0xC0)   # test eax, eax
		g.a.em3(0x0F, 0x95, 0xC0)   # setne al
		g.a.em3(0x0F, 0xB6, 0xC0)   # movzx eax, al
	elif g.tyK(ret) == tInt:
		g.truncTo(ret)   # the system defines only the low 32 bits of an int
	g.a.em3(0x48, 0x89, 0xEC)   # mov rsp, rbp
	g.a.em1(0x5D)   # pop rbp
	g.a.em1(0xC3)   # ret
	if notLoaded >= 0:
		g.genMessageStub(notLoaded, loadedMissingText(nodes[fnd].text2()))

# what the program stops with when it calls an extern loaded fn that was not given an address
fn loadedMissingText(name str):
	"extern fn {name} has no address: bindExtern or bindExterns did not give it one"

# reg holds the address of a list's or a str's header: the address of its bytes instead (a short
# str's, its last byte's top bit set, are in the header itself)
fn loadBytesAddress(mut g Gen, reg i64, text bool):
	skip = g.a.asmNewLabel()
	if text:
		if reg >= 8:
			g.a.em1(0x41)
		g.a.em4(0xF6, 0x40 | (reg & 7), 23, 0x80)   # test byte [reg+23], 128
		g.a.jccLabel(0x85, skip)   # jnz: short
	g.a.memOp(true, 0x8B, -1, reg, reg, -1, 0)   # mov reg, [reg]: the buffer
	g.a.asmPlace(skip)

# the data word holding the address of extern loaded fn fnd (zero until bindExtern)
fn loadedSlot(mut g Gen, fnd NodeId):
	match g.loadedSlots.get(fnd):
		off: return off
		none:
			off = g.reserveWords(1)
			g.loadedSlots[fnd] = off
			return off
