# The extern fns of a Linux build that are not system calls: functions of a C library, called by
# the System V convention (x64) or AAPCS64 (arm64) from the stub of the Zap convention, the way
# Windows' stubs call kernel32's. A library is loaded when the program runs, so a machine
# without it builds the program and stops it at the call that needs it:
#   - `extern loaded fn`: the address bindExtern gave it;
#   - `extern "libvulkan.so.1" fn` (or "vulkan-1.dll", which Windows names it, and an Android
#     app's libvulkan.so): found at its first call by the C library's dlopen and dlsym;
#   - a function of another Windows library (kernel32.dll): no address, the stop names it.
# The program is then a dynamic executable that needs the C library (elf.zap); the processor's
# thread register holds a thread block of the library's while it runs, one for each thread.

alias nodes = g.c.nodes
alias tys = g.c.types

# the kinds of a parameter or a result
cWord = 0
cBytes = 1
cText = 2
cF64 = 3
cF32 = 4
cBool = 5

# the Linux library a Windows library's functions are found in, and Android's
linuxLibraries = [("vulkan-1.dll", "libvulkan.so.1", "libvulkan.so")]

# RTLD_NOW
dlopenNow = 2

# where the lock that serializes the making of thread blocks is, from the word that keeps the
# program's own block
cLockAt = 8

# the thread slot (runtime/core/linux/threads.zap's, past those tlsAlloc gives out) that holds
# the thread's library block
cBlockSlot = 62

# how many library blocks the arm64 table holds (a thread past them has the program's block)
cTableBlocks = 256

type CCall:
	args i64[]
	ret i64
	bits i64 = 64
	signed bool = true

# the Linux library the extern fn's library names, "" when Linux has none
fn linuxLibraryOf(library str):
	if library.indexOf(".so") != none: return library.copy()
	for (windows, linux, android) in linuxLibraries:
		if windows == library: return (android if appBuild else linux).copy()
	""

# the extern fn's parameters and result as a C call has them
fn cCallOf(mut g Gen, fnd NodeId):
	call = CCall(args = [], ret = cWord)
	for i in 0..nodes[fnd].kids.len:
		pt = g.c.resolveType(nodes[nodes[fnd].kids[i]].types[0])
		k = g.tyK(pt)
		if k == tList:
			call.args.push(cBytes)
		elif k == tStr:
			call.args.push(cText)
		elif k == tFloat:
			call.args.push(cF64 if tys[pt].bits == 64 else cF32)
		else:
			call.args.push(cWord)
	ret = g.c.fnRetType(fnd)
	k = g.tyK(ret)
	if k == tFloat:
		call.ret = cF64 if tys[ret].bits == 64 else cF32
	elif k == tBool:
		call.ret = cBool
	elif k == tInt:
		call.bits = tys[ret].bits
		call.signed = tys[ret].isSigned
	call

# how many of the call's arguments the stack carries, the registers taking ints ints and 8 floats
fn stackArgs(call CCall, ints i64):
	nInt = 0
	nFloat = 0
	stack = 0
	for kind in call.args:
		if kind == cF64 or kind == cF32:
			nFloat += 1
			if nFloat > 8: stack += 1
		else:
			nInt += 1
			if nInt > ints: stack += 1
	stack

# The data word the dynamic linker fills with the C library's function `name` (a symbol the
# program needs of it: dlopen and dlsym load the others)
fn libcSlot(mut g Gen, name str):
	if g.a.libcNames.indexOf(name) is at: return g.a.libcAt[at]
	off = g.reserveWords(1)
	g.a.libcNames.push(name.copy())
	g.a.libcAt.push(off)
	off

# the stub of an extern fn on Linux that is not a system call (externs.zap)
fn genLibraryStub(mut g Gen, fnd NodeId, key str):
	library = nodes[fnd].names2()[0].copy()
	named = nodes[fnd].names2()
	name = nodes[fnd].text2.copy()
	symbol = named[1].copy() if named.len > 1 else name
	label = fnLabel(g.fnLabels, g.a, key)
	linux = linuxLibraryOf(library)
	if library != "" and linux == "":
		g.cMessageStub(
			label,
			"extern fn {name} is a function of {library}, which Linux does not have"
		)
		return
	call = g.cCallOf(fnd)
	missing = g.a.asmNewLabel()
	slot = g.loadedSlot(fnd)
	if onArm():
		g.a64CStub(label, call, slot, linux, symbol, missing)
	else:
		g.x64CStub(label, call, slot, linux, symbol, missing)
	if library == "":
		g.cMessageStub(missing, loadedMissingText(name))
	else:
		g.cMessageStub(
			missing,
			"extern fn {name} is a function of {linux}, which this machine does not have"
		)
	if library != "":
		g.cHelpers()

# the labels of dlopen and dlsym as the stubs that find their function call them
dlopenKey = "$dlopen"
dlsymKey = "$dlsym"
libraryBlockKey = "$libraryBlock"

# dlopen and dlsym, called by the stubs that find their function when first called: stubs of the
# Zap convention over the C library's own, whose addresses the dynamic linker gave, taking
# addresses of NUL-ended names
fn cHelpers(mut g Gen):
	if g.hasCHelpers: return
	g.hasCHelpers = true
	for (name, key) in [("dlopen", dlopenKey), ("dlsym", dlsymKey)]:
		label = fnLabel(g.fnLabels, g.a, key)
		call = CCall(args = [cWord, cWord], ret = cWord)
		slot = g.libcSlot(name)
		if onArm():
			g.a64CStub(label, call, slot, "", name, -1)
		else:
			g.x64CStub(label, call, slot, "", name, -1)
	blockLabel = fnLabel(g.fnLabels, g.a, libraryBlockKey)
	if onArm():
		g.a64LibraryBlock(blockLabel)
	else:
		g.x64LibraryBlock(blockLabel)

# a stub that stops the program with the message (the function itself, or the way out of one)
fn cMessageStub(mut g Gen, label i64, msg str):
	if onArm():
		g.a64HelperStart(label)
		g.a.a64AdrData(0, g.strLit(msg))
		g.a64CallRt("externMissing", 1)
		g.a.a64Brk(0)
		return
	g.genMessageStub(label, msg)
