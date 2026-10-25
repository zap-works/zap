# Linux on x64 (target.zap): the start, the system calls' stubs, a thread's entry and the return
# from a signal's handler; the code between them is Windows' own, but for the thread's slots (fs
# for gs, x64TlsAccess) and the callbacks' convention (System V's, callbackRegs).

alias nodes = g.c.nodes

# the slots of the main thread's TLS, as on arm64 (TlsAlloc gives them out in order)
x64TlsSlots = 64

# The start: the stack's top kept in the runtime's slot (Linux's arguments and environment are
# there) and the processor checked (genX64CpuCheck), the thread's slots at fs, a stack of
# Windows' size, then as on Windows: the module variables, the entry, the end with code 0. The
# return from a signal's handler after it (`$sigreturn`, the sigaction's restorer).
fn x64LinuxStart(mut g Gen, entry str):
	g.genX64CpuCheck()
	g.libcTls = g.reserveWords(2)   # the thread block a dynamic loader left in fs (0 of a static one), then cLock
	g.a.leaRaxData(g.libcTls)
	g.a.em3(0x48, 0x89, 0xC6)   # mov rsi, rax
	g.a.em5(0xBF, 0x03, 0x10, 0x00, 0x00)   # mov edi, ARCH_GET_FS
	g.x64Syscall(syscallNumber(syscallNamed("arch_prctl")))
	g.a.leaRaxData(g.a.asmBssZero(8 * x64TlsSlots))
	g.a.em3(0x48, 0x89, 0xC6)   # mov rsi, rax
	g.a.em5(0xBF, 0x02, 0x10, 0x00, 0x00)   # mov edi, ARCH_SET_FS
	g.x64Syscall(syscallNumber(syscallNamed("arch_prctl")))
	if appBuild:
		# an app's thread is bionic's, its stack of that size (android/entry.zap): its own block is
		# its library block (ccall.zap's thread slot)
		g.a.leaRaxData(g.libcTls)
		g.a.em3(0x48, 0x8B, 0x00)   # mov rax, [rax]
		g.a.emN([0x64, 0x48, 0x89, 0x04, 0x25])   # mov fs:[slot], rax
		g.a.emit32(8 * cBlockSlot)
	else:
		g.callRtNamed("mainStack", 0)   # the stack Windows would give (runtime/core/linux/threads.zap)
		g.a.em3(0x48, 0x89, 0xC4)   # mov rsp, rax
	g.a.em4(0x48, 0x83, 0xEC, 0x08)   # sub rsp, 8: as a call's entry has it
	g.genX64Run(entry)
	g.a.asmPlace(fnLabel(g.fnLabels, g.a, "$sigreturn"))
	g.x64Syscall(syscallNumber(syscallNamed("rt_sigreturn")))

fn x64Syscall(mut g Gen, number i64):
	g.a.em1(0xB8)   # mov eax, number
	g.a.emit32(number)
	g.a.em2(0x0F, 0x05)   # syscall

# An extern fn on Linux: its system call (syscalls.zap) made from the Zap convention (the
# arguments' words above the frame) with the arguments in rdi, rsi, rdx, r10, r8, r9 (a buffer
# as the address of its bytes), the answer in rax. A thread clone made returns from here on its
# own stack, whose top holds the frame's rbp and the return into the thread's entry.
fn x64SyscallStub(mut g Gen, fnd NodeId, key str):
	call = g.externSyscall(fnd)
	g.a.asmPlace(fnLabel(g.fnLabels, g.a, key))
	g.a.framePrologue()
	n = nodes[fnd].kids.len
	regs = [7, 6, 2, 10, 8, 9]
	for i in 0..n.min(6):
		from = (7 - i if i >= 3 and i <= 4 else i) if call.swapsLast and n >= 5 else i
		g.a.memOp(true, 0x8B, -1, regs[i], 5, -1, 16 + 8 * (n - 1 - from))   # mov reg, [rbp+disp]
		pt = g.c.resolveType(nodes[nodes[fnd].kids[from]].types()[0])
		if g.tyK(pt) == tList or g.tyK(pt) == tStr:
			g.loadBytesAddress(regs[i], g.tyK(pt) == tStr)
	g.x64Syscall(call.syscallNumber())
	g.a.em1(0x5D)   # pop rbp
	g.a.em1(0xC3)   # ret

# A thread's start: the clone returns from its stub into here, rsp at the word that holds the
# thread's record. It runs the closure as Windows' entry does, then ends the thread alone.
fn x64LinuxThreadEntry(mut g Gen):
	g.a.em4(0x48, 0x8B, 0x0C, 0x24)   # mov rcx, [rsp]
	g.a.em4(0x48, 0x83, 0xEC, 0x08)   # sub rsp, 8: as a call's entry has it
	g.genThreadRun()
	g.a.em2(0x31, 0xFF)   # xor edi, edi
	g.x64Syscall(syscallNumber(syscallNamed("exit")))

# the instruction's prefix and displacement that reach the thread's slot rcx (mov rax, seg:[rcx *
# 8 + disp]): gs:0x1480 on Windows (the TEB's TLS slots), fs:0 on Linux (the slots the start and
# a clone give)
fn x64TlsAccess(store bool):
	if onLinux(): return [0x64, 0x48, 0x89 if store else 0x8B, 0x04, 0xCD, 0x00, 0x00, 0x00, 0x00]
	[0x65, 0x48, 0x89 if store else 0x8B, 0x04, 0xCD, 0x80, 0x14, 0x00, 0x00]

# the registers a callback's arguments come in, and where its stack arguments start above rbp:
# Windows' rcx, rdx, r8, r9 above the shadow space; System V's rdi, rsi, rdx, rcx, r8, r9
fn callbackRegs():
	if onLinux(): return ([7, 6, 2, 1, 8, 9], 16)
	([1, 2, 8, 9], 48)
