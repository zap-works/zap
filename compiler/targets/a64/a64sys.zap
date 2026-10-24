# The extern fns on Linux on arm64: a system call (syscalls.zap) made by its stub: the arguments
# in x0..x5 (a buffer as the address of its bytes), the number in x8, svc 0. A stub takes the Zap
# convention: the arguments' words above its frame record.

alias nodes = g.c.nodes

fn a64ExternStub(mut g Gen, fnd NodeId, key str):
	call = g.externSyscall(fnd)
	g.a.asmPlace(fnLabel(g.fnLabels, g.a, key))
	g.a.a64Pair(false, a64Fp, a64Lr, a64Sp, -16, 1)   # stp x29, x30, [sp, -16]!
	g.a.a64AddImm(a64Fp, a64Sp, 0)
	n = nodes[fnd].kids.len
	for i in 0..n.min(6):
		g.a.a64Ldr(i, a64Fp, 16 + 8 * (n - 1 - i))
		pt = g.c.resolveType(nodes[nodes[fnd].kids[i]].types[0])
		if g.tyK(pt) == tList or g.tyK(pt) == tStr:
			g.a64BytesAddress(i, g.tyK(pt) == tStr, a64T0)
	g.a64Syscall(call.syscallNumber())
	# (a thread clone made returns here on its own stack, whose top holds its frame record:
	# runtime/core/linux/threads.zap)
	g.a.a64Pair(true, a64Fp, a64Lr, a64Sp, 16, 2)   # ldp x29, x30, [sp], 16
	g.a.a64Ret()

# r holds the address of a list's or a str's header: the address of its bytes instead (a short
# str's, its last byte's top bit set, are in the header itself); scratch is another register
fn a64BytesAddress(mut g Gen, r i64, text bool, scratch i64):
	skip = g.a.asmNewLabel()
	if text:
		g.a.a64Load(scratch, r, 23, 1, true)
		g.a.a64(0xD340_0000 | 7 << 16 | 7 << 10 | scratch << 5 | scratch)   # ubfx scratch, 7, 1
		g.a.a64Cbz(scratch, skip, true)
	g.a.a64Ldr(r, r, 0)
	g.a.asmPlace(skip)

fn a64Syscall(mut g Gen, number i64):
	g.a.a64MovImm(8, number)
	g.a.a64Svc()

# A thread's start: the clone returns from its stub into here, sp at the word that holds the
# thread's record (+0 the closure's code, +8 its environment), x29 0 (the last frame record).
# It runs the closure, then ends the thread alone.
fn a64ThreadEntry(mut g Gen):
	g.a.a64Ldr(0, a64Sp, 0)
	g.a.a64AddImm(a64Sp, a64Sp, -16)   # the area of the call: the environment
	g.a.a64Ldr(a64T0, 0, 8)
	g.a.a64Str(a64T0, a64Sp, 0)
	g.a.a64Ldr(a64T0, 0, 0)
	g.a.a64Blr(a64T0)
	g.a.a64MovImm(0, 0)
	g.a64Syscall(syscallNumber(syscallNamed("exit")))

# `$callback:name`: the system's convention (the arguments in x0..x3) made a Zap call, the
# registers the code keeps (x19..x24) kept for the system
fn a64Callback(mut g Gen, key str, ft TypeId):
	np = g.c.types[ft].params.len
	if np > 4 or g.c.types[ft].params.any(g.tyK(it) == tFloat):
		exit(1, "zap build{targetOption()}: a callback of {np} words or floats is not made yet")
	g.a64CallbackEntry(fnLabel(g.fnLabels, g.a, key), fnLabel(g.fnLabels, g.a, "{key}$body"))
	g.a64HelperStart(fnLabel(g.fnLabels, g.a, "{key}$body"))
	name = key["$callback:".len..]
	if not g.takesRegArgs(g.c.findFunc(name), false):
		for i in 0..np:
			g.a.a64Str(i, a64Sp, 8 * (np - 1 - i))
	g.a.a64Bl(fnLabel(g.fnLabels, g.a, name))
	g.a64HelperEnd()
