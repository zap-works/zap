# A C library's function called from Linux on x64 (ccall.zap): the stub takes the Zap convention
# (the arguments' words above the frame, the result in rax) and makes the System V call: ints in
# rdi, rsi, rdx, rcx, r8, r9, floats in xmm0..xmm7, the rest on the stack, al the floats' count.
# The library keeps rbx, rbp and r12..r15 as the generated code needs, but not xmm6..xmm15, which
# the stub keeps for it; it runs with a thread block of its own in fs, the program's put back
# after. Each thread has its block (a slot of its TLS, cBlockSlot): the thread block of a thread
# glibc made and parked, taken at the thread's first call (x64LibraryBlock), so threads are in
# libraries side by side as pthreads are. The block holds the program's fs at cOwnerAt while the
# library runs, which a callback (fnValues.zap) takes to run Zap code with it.
#
# The frame, from rbp down: the program's fs, the result, the function's address, the ten xmm
# registers kept, then the stack arguments at rsp.

# the word of a library block that holds the program's fs while the library runs: glibc's unused
# vgetcpu cache in the thread control block's header
cOwnerAt = 0x38

archGetFs = 0x1003
archSetFs = 0x1002
cFrameBytes = 184

fn x64CStub(
	mut g Gen,
	label i64,
	call CCall,
	slot i64,
	library str,
	symbol str,
	missing i64
):
	g.a.asmPlace(label)
	g.a.framePrologue()
	g.subRsp((cFrameBytes + 8 * call.stackArgs(6) + 8 + 15) / 16 * 16)
	g.a.em4(0x48, 0x83, 0xE4, 0xF0)   # and rsp, -16
	g.x64FindFunction(call, slot, library, symbol, missing)
	g.a.memOp(true, 0x89, -1, 0, 5, -1, -24)   # mov [rbp-24], rax
	g.a.em5(0xBF, 0x03, 0x10, 0x00, 0x00)   # mov edi, ARCH_GET_FS
	g.a.em4(0x48, 0x8D, 0x75, 0xF8)   # lea rsi, [rbp-8]
	g.x64Syscall(syscallNumber(syscallNamed("arch_prctl")))
	for k in 6..16:
		g.a.memOp(false, 0x0F, 0x11, k, 5, -1, -cFrameBytes + 16 * (k - 6))   # movups [rbp+d], xmm
	g.x64EnterLibrary()
	g.x64CArguments(call)
	g.a.memOp(true, 0x8B, -1, 11, 5, -1, -24)   # mov r11, [rbp-24]
	g.a.em1(0xB8)   # mov eax, the floats' count
	g.a.emit32(call.args.count(it == cF64 or it == cF32).min(8))
	g.a.em3(0x41, 0xFF, 0xD3)   # call r11
	g.x64CResult(call)
	g.a.memOp(true, 0x89, -1, 0, 5, -1, -16)   # mov [rbp-16], rax
	g.a.em5(0xBF, 0x02, 0x10, 0x00, 0x00)   # mov edi, ARCH_SET_FS
	g.a.em4(0x48, 0x8B, 0x75, 0xF8)   # mov rsi, [rbp-8]
	g.x64Syscall(syscallNumber(syscallNamed("arch_prctl")))
	for k in 6..16:
		g.a.memOp(false, 0x0F, 0x10, k, 5, -1, -cFrameBytes + 16 * (k - 6))   # movups xmm, [rbp+d]
	g.a.memOp(true, 0x8B, -1, 0, 5, -1, -16)   # mov rax, [rbp-16]
	g.a.em3(0x48, 0x89, 0xEC)   # mov rsp, rbp
	g.a.em1(0x5D)   # pop rbp
	g.a.em1(0xC3)   # ret

# fs the thread's library block (made at the thread's first call), which holds the program's fs
fn x64EnterLibrary(mut g Gen):
	have = g.a.asmNewLabel()
	g.a.memOp(true, 0x8B, -1, 0, 5, -1, -8)   # mov rax, [rbp-8]: the program's fs
	g.a.memOp(true, 0x8B, -1, 0, 0, -1, 8 * cBlockSlot)   # mov rax, [rax+slot]
	g.a.em3(0x48, 0x85, 0xC0)   # test rax, rax
	g.a.jccLabel(0x85, have)   # jnz
	g.a.callLabel(fnLabel(g.fnLabels, g.a, libraryBlockKey))
	g.a.asmPlace(have)
	if not appBuild:   # (an app's, bionic's, holds ART's thread there: no callback runs in an app yet)
		g.a.memOp(true, 0x8B, -1, 2, 5, -1, -8)   # mov rdx, [rbp-8]
		g.a.memOp(true, 0x89, -1, 2, 0, -1, cOwnerAt)   # mov [rax+owner], rdx
	g.a.em3(0x48, 0x89, 0xC6)   # mov rsi, rax
	g.a.em5(0xBF, 0x02, 0x10, 0x00, 0x00)   # mov edi, ARCH_SET_FS
	g.x64Syscall(syscallNumber(syscallNamed("arch_prctl")))

# `$libraryBlock`, a function of the Zap convention without arguments: a thread block for the
# calling thread, made by glibc's pthread_create, whose thread (`park`) tells its fs and sleeps for
# good, kept in the thread's slot; rax holds it. Made with the program's own block in fs, one
# thread at a time (cLock, a spin on a word of the data). Without a thread, the program's block
# stands in.
fn x64LibraryBlock(mut g Gen, label i64):
	park = g.a.asmNewLabel()
	wait = g.a.asmNewLabel()
	done = g.a.asmNewLabel()
	asleep = g.a.asmNewLabel()
	g.a.asmPlace(label)
	g.a.framePrologue()
	g.a.em4(0x48, 0x83, 0xEC, 0x30)   # sub rsp, 48
	g.a.em4(0x48, 0x83, 0xE4, 0xF0)   # and rsp, -16
	g.x64CLock()
	g.a.em5(0xBF, 0x03, 0x10, 0x00, 0x00)   # mov edi, ARCH_GET_FS
	g.a.em4(0x48, 0x8D, 0x75, 0xF8)   # lea rsi, [rbp-8]
	g.x64Syscall(syscallNumber(syscallNamed("arch_prctl")))
	g.a.leaRaxData(g.libcTls)
	g.a.em3(0x48, 0x8B, 0x30)   # mov rsi, [rax]: the program's own block
	g.a.em5(0xBF, 0x02, 0x10, 0x00, 0x00)   # mov edi, ARCH_SET_FS
	g.x64Syscall(syscallNumber(syscallNamed("arch_prctl")))
	g.a.em4(0x48, 0xC7, 0x45, 0xF0)   # mov qword [rbp-16], 0: the block, told by the thread
	g.a.emit32(0)
	g.a.em4(0x48, 0x8D, 0x7D, 0xE8)   # lea rdi, [rbp-24]: the pthread_t
	g.a.em2(0x31, 0xF6)   # xor esi, esi
	g.a.em3(0x48, 0x8D, 0x15)   # lea rdx, [rip+park]
	g.a.asmRel32Label(park)
	g.a.em4(0x48, 0x8D, 0x4D, 0xF0)   # lea rcx, [rbp-16]
	g.a.leaRaxData(g.libcSlot("pthread_create"))
	g.a.em3(0x48, 0x8B, 0x00)   # mov rax, [rax]
	g.a.em2(0xFF, 0xD0)   # call rax
	g.a.em2(0x85, 0xC0)   # test eax, eax
	g.a.jccLabel(0x84, wait)   # jz: started
	g.a.leaRaxData(g.libcTls)
	g.a.em3(0x48, 0x8B, 0x00)   # mov rax, [rax]
	g.a.memOp(true, 0x89, -1, 0, 5, -1, -16)   # mov [rbp-16], rax: the program's block stands in
	g.a.asmPlace(wait)
	g.a.memOp(true, 0x8B, -1, 0, 5, -1, -16)   # mov rax, [rbp-16]
	g.a.em3(0x48, 0x85, 0xC0)   # test rax, rax
	g.a.jccLabel(0x85, done)   # jnz
	g.x64Syscall(syscallNumber(syscallNamed("sched_yield")))
	g.a.jmpLabel(wait)
	g.a.asmPlace(done)
	g.a.em5(0xBF, 0x02, 0x10, 0x00, 0x00)   # mov edi, ARCH_SET_FS
	g.a.memOp(true, 0x8B, -1, 6, 5, -1, -8)   # mov rsi, [rbp-8]: the thread's own
	g.x64Syscall(syscallNumber(syscallNamed("arch_prctl")))
	g.a.leaRaxData(g.libcTls + cLockAt)
	g.a.em2(0xC7, 0x00)   # mov dword [rax], 0: let go
	g.a.emit32(0)
	g.a.memOp(true, 0x8B, -1, 0, 5, -1, -16)   # mov rax, [rbp-16]
	g.a.memOp(true, 0x8B, -1, 2, 5, -1, -8)   # mov rdx, [rbp-8]
	g.a.memOp(true, 0x89, -1, 0, 2, -1, 8 * cBlockSlot)   # mov [rdx+slot], rax
	g.a.em3(0x48, 0x89, 0xEC)   # mov rsp, rbp
	g.a.em1(0x5D)   # pop rbp
	g.a.em1(0xC3)   # ret
	# park(rdi = the word that gets this thread's block): tells it, then sleeps in ppoll for good
	# (pause, which Android's apps may not make)
	g.a.asmPlace(park)
	g.a.em5(0x64, 0x48, 0x8B, 0x04, 0x25)   # mov rax, fs:[0]
	g.a.emit32(0)
	g.a.em3(0x48, 0x89, 0x07)   # mov [rdi], rax
	g.a.asmPlace(asleep)
	g.a.em2(0x31, 0xFF)   # xor edi, edi: ppoll(none, 0, no time, no mask, 0)
	g.a.em2(0x31, 0xF6)   # xor esi, esi
	g.a.em2(0x31, 0xD2)   # xor edx, edx
	g.a.em3(0x45, 0x31, 0xD2)   # xor r10d, r10d
	g.a.em3(0x45, 0x31, 0xC0)   # xor r8d, r8d
	g.x64Syscall(syscallNumber(syscallNamed("ppoll")))
	g.a.jmpLabel(asleep)

# A callback's entry on Linux, once its registers are kept: when it was called from inside a
# library (fs a thread block whose self pointer is its own address and whose owner word holds the
# program's fs), the program's fs is set for the Zap code, the library's kept in the word at rsp
# (0 when the call came from elsewhere, a signal). The argument registers stay as they were.
fn x64CallbackEnter(mut g Gen):
	skip = g.a.asmNewLabel()
	done = g.a.asmNewLabel()
	g.a.emN([0x6A, 0x00, 0x6A, 0x00])   # push 0, push 0: the kept fs, and a pad
	g.a.emN([0x49, 0x89, 0xFC, 0x49, 0x89, 0xF5, 0x49, 0x89, 0xCE])   # mov r12, rdi; r13, rsi; r14, rcx
	g.a.em5(0xBF, 0x03, 0x10, 0x00, 0x00)   # mov edi, ARCH_GET_FS
	g.a.em3(0x48, 0x89, 0xE6)   # mov rsi, rsp
	g.x64Syscall(syscallNumber(syscallNamed("arch_prctl")))
	g.a.em4(0x48, 0x8B, 0x04, 0x24)   # mov rax, [rsp]
	g.a.em4(0x48, 0x8B, 0x48, 0x10)   # mov rcx, [rax+0x10] (rdx is a callback's third argument)
	g.a.em3(0x48, 0x39, 0xC1)   # cmp rcx, rax
	g.a.jccLabel(0x85, skip)   # jne
	g.a.memOp(true, 0x8B, -1, 6, 0, -1, cOwnerAt)   # mov rsi, [rax+owner]
	g.a.em3(0x48, 0x85, 0xF6)   # test rsi, rsi
	g.a.jccLabel(0x84, skip)   # jz
	g.a.em5(0xBF, 0x02, 0x10, 0x00, 0x00)   # mov edi, ARCH_SET_FS
	g.x64Syscall(syscallNumber(syscallNamed("arch_prctl")))
	g.a.jmpLabel(done)
	g.a.asmPlace(skip)
	g.a.em4(0x48, 0xC7, 0x04, 0x24)   # mov qword [rsp], 0
	g.a.emit32(0)
	g.a.asmPlace(done)
	g.a.emN([0x4C, 0x89, 0xE7, 0x4C, 0x89, 0xEE, 0x4C, 0x89, 0xF1])   # mov rdi, r12; rsi, r13; rcx, r14

# the end of a callback after its Zap call: the library's fs back when the entry set the program's,
# the result in rax kept
fn x64CallbackLeave(mut g Gen):
	skipped = g.a.asmNewLabel()
	g.a.emN([0x49, 0x89, 0xC4])   # mov r12, rax
	g.a.em4(0x48, 0x8B, 0x34, 0x24)   # mov rsi, [rsp]
	g.a.em3(0x48, 0x85, 0xF6)   # test rsi, rsi
	g.a.jccLabel(0x84, skipped)   # jz
	g.a.em5(0xBF, 0x02, 0x10, 0x00, 0x00)   # mov edi, ARCH_SET_FS
	g.x64Syscall(syscallNumber(syscallNamed("arch_prctl")))
	g.a.asmPlace(skipped)
	g.a.emN([0x4C, 0x89, 0xE0])   # mov rax, r12
	g.a.addRsp(16)

# the thread block's creation taken: a spin on cLock, the thread yielding while another is in it
fn x64CLock(mut g Gen):
	spin = g.a.asmNewLabel()
	held = g.a.asmNewLabel()
	g.a.leaRaxData(g.libcTls + cLockAt)
	g.a.em3(0x49, 0x89, 0xC2)   # mov r10, rax
	g.a.asmPlace(spin)
	g.a.em2(0x31, 0xC0)   # xor eax, eax
	g.a.em5(0xBA, 0x01, 0x00, 0x00, 0x00)   # mov edx, 1
	g.a.em5(0xF0, 0x41, 0x0F, 0xB1, 0x12)   # lock cmpxchg [r10], edx
	g.a.jccLabel(0x84, held)   # jz
	g.x64Syscall(syscallNumber(syscallNamed("sched_yield")))
	g.a.jmpLabel(spin)
	g.a.asmPlace(held)

# rax the function's address: the slot's word, found by dlopen and dlsym at the first call when
# the function is a library's (library set); the stub goes to missing when there is none (a
# helper's, with no missing, is the dynamic linker's)
fn x64FindFunction(mut g Gen, call CCall, slot i64, library str, symbol str, missing i64):
	g.a.leaRaxData(slot)
	g.a.em3(0x48, 0x8B, 0x00)   # mov rax, [rax]
	g.a.em3(0x48, 0x85, 0xC0)   # test rax, rax
	if library == "":
		if missing >= 0: g.a.jccLabel(0x84, missing)   # jz
		return
	found = g.a.asmNewLabel()
	opened = g.a.asmNewLabel()
	g.a.jccLabel(0x85, found)   # jnz
	g.a.leaRaxData(g.strLit(library))
	g.a.pushRax()
	g.a.em2(0x6A, dlopenNow)   # push RTLD_NOW
	g.a.callLabel(fnLabel(g.fnLabels, g.a, dlopenKey))
	g.a.em4(0x48, 0x83, 0xC4, 0x10)   # add rsp, 16
	g.a.em3(0x48, 0x85, 0xC0)   # test rax, rax
	g.a.jccLabel(0x84, opened)   # jz: no library, and no function
	g.a.pushRax()
	g.a.leaRaxData(g.strLit(symbol))
	g.a.pushRax()
	g.a.callLabel(fnLabel(g.fnLabels, g.a, dlsymKey))
	g.a.em4(0x48, 0x83, 0xC4, 0x10)   # add rsp, 16
	g.a.em3(0x48, 0x89, 0xC1)   # mov rcx, rax
	g.a.leaRaxData(slot)
	g.a.em3(0x48, 0x89, 0x08)   # mov [rax], rcx
	g.a.em3(0x48, 0x89, 0xC8)   # mov rax, rcx
	g.a.asmPlace(opened)
	g.a.asmPlace(found)
	g.a.em3(0x48, 0x85, 0xC0)   # test rax, rax
	g.a.jccLabel(0x84, missing)   # jz

# the arguments from the Zap convention's words above the frame to System V's places
fn x64CArguments(mut g Gen, call CCall):
	regs = [7, 6, 2, 1, 8, 9]
	n = call.args.len
	nInt = 0
	nFloat = 0
	stack = 0
	for i, kind in call.args:
		disp = 16 + 8 * (n - 1 - i)
		float = kind == cF64 or kind == cF32
		inReg = nFloat < 8 if float else nInt < 6
		reg = 0
		if not float and inReg: reg = regs[nInt]
		g.a.memOp(true, 0x8B, -1, reg, 5, -1, disp)   # mov reg, [rbp+disp]
		if kind == cBytes or kind == cText:
			g.loadBytesAddress(reg, kind == cText)
		if float and inReg:
			g.a.em1(0x66)
			if kind == cF64: g.a.em1(0x48)
			g.a.em3(0x0F, 0x6E, 0xC0 | nFloat << 3)   # movq / movd xmm, rax
			nFloat += 1
		elif inReg:
			nInt += 1
		else:
			g.a.memOp(true, 0x89, -1, 0, 4, -1, 8 * stack)   # mov [rsp+8k], rax
			stack += 1

# rax the result as the Zap convention has it
fn x64CResult(mut g Gen, call CCall):
	if call.ret == cF32:
		g.a.em4(0xF3, 0x0F, 0x5A, 0xC0)   # cvtss2sd xmm0, xmm0: an f32 travels as its f64
	if call.ret == cF32 or call.ret == cF64:
		g.a.em5(0x66, 0x48, 0x0F, 0x7E, 0xC0)   # movq rax, xmm0
	elif call.ret == cBool:
		g.a.em2(0x85, 0xC0)   # test eax, eax
		g.a.em3(0x0F, 0x95, 0xC0)   # setne al
		g.a.em3(0x0F, 0xB6, 0xC0)   # movzx eax, al
	else:
		g.truncBits(call.bits, call.signed)
