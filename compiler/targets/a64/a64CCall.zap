# A C library's function called from Linux on arm64 (ccall.zap): the stub takes the Zap
# convention (the arguments' words above the frame record, the result in x0) and makes the
# AAPCS64 call: ints in x0..x7, floats in d0..d7, the rest on the stack. The library keeps x19..x28
# and d8..d15, but not d20 and d21, which the generated code keeps: the stub keeps them. The
# library runs with a thread block of its own in tpidr_el0, the program's put back after. Each
# thread has its block (a slot of its TLS, cBlockSlot): the thread block of a thread glibc made and
# parked, taken at the thread's first call (a64LibraryBlock), so threads are in libraries side by
# side as pthreads are. A callback a library makes (a64CallbackEntry) finds the program's register
# by the block's in a table, to run Zap code with it.
#
# The frame, from sp up: the stack arguments, then the program's thread register, the function's
# address, d20 and d21.

a64CFrameBytes = 32

fn a64CStub(
	mut g Gen,
	label i64,
	call CCall,
	slot i64,
	library str,
	symbol str,
	missing i64
):
	g.a.asmPlace(label)
	g.a.a64Pair(false, a64Fp, a64Lr, a64Sp, -16, 1)   # stp x29, x30, [sp, -16]!
	g.a.a64AddImm(a64Fp, a64Sp, 0)
	out = (8 * call.stackArgs(8) + 15) / 16 * 16
	g.a.a64AddImm(a64Sp, a64Sp, -(out + a64CFrameBytes))
	g.a64FindFunction(slot, library, symbol, missing)
	g.a.a64Str(a64T0, a64Sp, out + 8)
	g.a.a64StoreF(20, a64Sp, out + 16, 8)
	g.a.a64StoreF(21, a64Sp, out + 24, 8)
	g.a.a64(0xD53B_D040 | a64T1)   # mrs x17, tpidr_el0
	g.a.a64Str(a64T1, a64Sp, out)
	g.a64EnterLibrary(out)
	g.a64CArguments(call)
	g.a.a64Ldr(a64T0, a64Sp, out + 8)
	g.a.a64Blr(a64T0)
	g.a64CResult(call)
	g.a.a64Ldr(a64T1, a64Sp, out)
	g.a.a64(0xD51B_D040 | a64T1)   # msr tpidr_el0, x17: the program's
	g.a.a64LoadF(20, a64Sp, out + 16, 8)
	g.a.a64LoadF(21, a64Sp, out + 24, 8)
	g.a.a64AddImm(a64Sp, a64Fp, 0)
	g.a.a64Pair(true, a64Fp, a64Lr, a64Sp, 16, 2)   # ldp x29, x30, [sp], 16
	g.a.a64Ret()

# tpidr_el0 the thread's library block (made at the thread's first call)
fn a64EnterLibrary(mut g Gen, out i64):
	have = g.a.asmNewLabel()
	g.a.a64Ldr(a64T1, a64Sp, out)   # the program's thread register
	g.a.a64Ldr(a64T0, a64T1, 8 * cBlockSlot)
	g.a.a64Cbz(a64T0, have, true)
	g.a.a64Bl(fnLabel(g.fnLabels, g.a, libraryBlockKey))
	g.a.a64Mov(a64T0, 0)
	g.a.asmPlace(have)
	g.a.a64(0xD51B_D040 | a64T0)   # msr tpidr_el0, x16: the library's

# `$libraryBlock`, a function of the Zap convention without arguments: a thread block for the
# calling thread, made by glibc's pthread_create, whose thread (`park`) tells its thread register
# and sleeps for good, kept in the thread's slot and in the table of blocks (a callback finds the
# program's register by it); x0 holds it. Made with the program's own block in tpidr_el0, one
# thread at a time (cLock, a spin on a word of the data). Without a thread, the program's block
# stands in.
fn a64LibraryBlock(mut g Gen, label i64):
	park = g.a.asmNewLabel()
	wait = g.a.asmNewLabel()
	done = g.a.asmNewLabel()
	full = g.a.asmNewLabel()
	asleep = g.a.asmNewLabel()
	g.a.asmPlace(label)
	g.a.a64Pair(false, a64Fp, a64Lr, a64Sp, -48, 1)   # stp x29, x30, [sp, -48]!
	g.a.a64AddImm(a64Fp, a64Sp, 0)
	g.a64CLock()
	g.a.a64(0xD53B_D040 | a64T1)   # mrs x17, tpidr_el0
	g.a.a64Str(a64T1, a64Sp, 16)   # the program's
	g.a.a64AdrData(a64T1, g.libcTls)
	g.a.a64Ldr(a64T1, a64T1, 0)
	g.a.a64(0xD51B_D040 | a64T1)   # msr tpidr_el0, x17: the program's own block
	g.a.a64Str(a64Zr, a64Sp, 24)   # the block, told by the thread
	g.a.a64AddImm(0, a64Sp, 32)   # the pthread_t
	g.a.a64MovImm(1, 0)
	g.a.a64AdrLabel(2, park)
	g.a.a64AddImm(3, a64Sp, 24)
	g.a.a64AdrData(a64T0, g.libcSlot("pthread_create"))
	g.a.a64Ldr(a64T0, a64T0, 0)
	g.a.a64Blr(a64T0)
	g.a.a64Extend(0, 0, 4, true)
	g.a.a64Cbz(0, wait, false)
	g.a.a64AdrData(a64T1, g.libcTls)
	g.a.a64Ldr(a64T1, a64T1, 0)
	g.a.a64Str(a64T1, a64Sp, 24)   # the program's block stands in
	g.a.asmPlace(wait)
	g.a.a64Ldr(0, a64Sp, 24)
	g.a.a64Cbz(0, done, true)
	g.a.a64MovImm(8, syscallNumber(syscallNamed("sched_yield")))
	g.a.a64Svc()
	g.a.a64B(wait)
	g.a.asmPlace(done)
	g.a.a64AdrData(a64T0, g.blockTable())
	g.a.a64Ldr(a64T2, a64T0, 0)   # how many blocks it holds
	g.a.a64CmpImm(a64T2, cTableBlocks)
	g.a.a64BCond(a64Hs, full)
	g.a.a64ShiftImm(0, a64T1, a64T2, 4, true)
	g.a.a64Op3(a64Add, a64T1, a64T1, a64T0)
	g.a.a64Str(0, a64T1, 8)
	g.a.a64Ldr(2, a64Sp, 16)
	g.a.a64Str(2, a64T1, 16)
	g.a.a64AddImm(a64T2, a64T2, 1)
	g.a.a64(a64DmbIsh)
	g.a.a64Str(a64T2, a64T0, 0)
	g.a.asmPlace(full)
	g.a.a64Ldr(a64T1, a64Sp, 16)
	g.a.a64(0xD51B_D040 | a64T1)   # msr tpidr_el0, x17: the thread's own
	g.a.a64Str(0, a64T1, 8 * cBlockSlot)
	g.a.a64AdrData(a64T0, g.libcTls + cLockAt)
	g.a.a64(0x889F_FC00 | a64T0 << 5 | a64Zr)   # stlr wzr, [x16]: let go
	g.a.a64AddImm(a64Sp, a64Fp, 0)
	g.a.a64Pair(true, a64Fp, a64Lr, a64Sp, 48, 2)   # ldp x29, x30, [sp], 48
	g.a.a64Ret()
	# park(x0 = the word that gets this thread's block): tells it, then sleeps in ppoll for good
	g.a.asmPlace(park)
	g.a.a64(0xD53B_D040 | 1)   # mrs x1, tpidr_el0
	g.a.a64Str(1, 0, 0)
	g.a.asmPlace(asleep)
	for r in 0..5:
		g.a.a64MovImm(r, 0)
	g.a.a64MovImm(8, syscallNumber(syscallNamed("ppoll")))
	g.a.a64Svc()
	g.a.a64B(asleep)

# the table of the library blocks: a count, then a pair for each, the block and the thread
# register of the program's thread it serves (a callback entered with a block's register sets its
# thread's)
fn blockTable(mut g Gen):
	if g.libcTable < 0: g.libcTable = g.a.asmBssZero(8 + 16 * cTableBlocks)
	g.libcTable

# `$callback:name` for a library to call: the thread register the program's for the Zap code when
# the call came from a library's block (found in the table) and the library's again after; from
# elsewhere (a signal) it runs as it is. The arguments in x0..x3 stay; the register kept is in the
# frame at +16.
fn a64CallbackEntry(mut g Gen, entry i64, body i64):
	call = g.a.asmNewLabel()
	search = g.a.asmNewLabel()
	found = g.a.asmNewLabel()
	out = g.a.asmNewLabel()
	g.a.asmPlace(entry)
	g.a.a64Pair(false, a64Fp, a64Lr, a64Sp, -32, 1)   # stp x29, x30, [sp, -32]!
	g.a.a64AddImm(a64Fp, a64Sp, 0)
	g.a.a64Str(a64Zr, a64Sp, 16)
	g.a.a64(0xD53B_D040 | a64T1)   # mrs x17, tpidr_el0
	g.a.a64AdrData(a64T0, g.blockTable())
	g.a.a64Ldr(a64T2, a64T0, 0)
	g.a.a64AddImm(a64T0, a64T0, 8)
	g.a.asmPlace(search)
	g.a.a64Cbz(a64T2, call, false)
	g.a.a64Ldr(4, a64T0, 0)
	g.a.a64Cmp(4, a64T1)
	g.a.a64BCond(a64Eq, found)
	g.a.a64AddImm(a64T0, a64T0, 16)
	g.a.a64AddImm(a64T2, a64T2, -1)
	g.a.a64B(search)
	g.a.asmPlace(found)
	g.a.a64Ldr(5, a64T0, 8)
	g.a.a64Str(a64T1, a64Sp, 16)
	g.a.a64(0xD51B_D040 | 5)   # msr tpidr_el0, x5: the program's
	g.a.asmPlace(call)
	g.a.a64Bl(body)
	g.a.a64Ldr(a64T1, a64Sp, 16)
	g.a.a64Cbz(a64T1, out, false)
	g.a.a64(0xD51B_D040 | a64T1)   # msr tpidr_el0, x17: the library's
	g.a.asmPlace(out)
	g.a.a64Pair(true, a64Fp, a64Lr, a64Sp, 32, 2)   # ldp x29, x30, [sp], 32
	g.a.a64Ret()

# the thread block's creation taken: a spin on cLock, the thread yielding while another is in it
fn a64CLock(mut g Gen):
	spin = g.a.asmNewLabel()
	busy = g.a.asmNewLabel()
	held = g.a.asmNewLabel()
	g.a.a64AdrData(a64T0, g.libcTls + cLockAt)
	g.a.asmPlace(spin)
	g.a.a64(0x885F_FC00 | a64T0 << 5 | a64T1)   # ldaxr w17, [x16]
	g.a.a64Cbz(a64T1, busy, true)
	g.a.a64MovImm(a64T1, 1)
	g.a.a64(0x8800_7C00 | a64T2 << 16 | a64T0 << 5 | a64T1)   # stxr w15, w17, [x16]
	g.a.a64Cbz(a64T2, held, false)
	g.a.a64B(spin)
	g.a.asmPlace(busy)
	g.a.a64MovImm(8, syscallNumber(syscallNamed("sched_yield")))
	g.a.a64Svc()
	g.a.a64B(spin)
	g.a.asmPlace(held)

# x16 the function's address: the slot's word, found by dlopen and dlsym at the first call when
# the function is a library's (library set); the stub goes to missing when there is none (a
# helper's, with no missing, is the dynamic linker's)
fn a64FindFunction(mut g Gen, slot i64, library str, symbol str, missing i64):
	g.a.a64AdrData(a64T0, slot)
	g.a.a64Ldr(a64T0, a64T0, 0)
	if library == "":
		if missing >= 0: g.a.a64Cbz(a64T0, missing, false)
		return
	found = g.a.asmNewLabel()
	opened = g.a.asmNewLabel()
	g.a.a64Cbz(a64T0, found, true)
	g.a.a64AdrData(0, g.strLit(library))
	g.a.a64MovImm(1, dlopenNow)
	g.a64CallZap(dlopenKey)
	g.a.a64Cbz(0, opened, false)
	g.a.a64AdrData(1, g.strLit(symbol))
	g.a64CallZap(dlsymKey)
	g.a.a64AdrData(a64T0, slot)
	g.a.a64Str(0, a64T0, 0)
	g.a.asmPlace(opened)
	g.a.a64Mov(a64T0, 0)
	g.a.asmPlace(found)
	g.a.a64Cbz(a64T0, missing, false)

# the function key called with its two words in x0 and x1, the Zap convention's stack
fn a64CallZap(mut g Gen, key str):
	g.a.a64AddImm(a64Sp, a64Sp, -16)
	g.a.a64Str(0, a64Sp, 8)
	g.a.a64Str(1, a64Sp, 0)
	g.a.a64Bl(fnLabel(g.fnLabels, g.a, key))
	g.a.a64AddImm(a64Sp, a64Sp, 16)

# the arguments from the Zap convention's words above the frame record to AAPCS64's places
fn a64CArguments(mut g Gen, call CCall):
	n = call.args.len
	nInt = 0
	nFloat = 0
	stack = 0
	for i, kind in call.args:
		at = 16 + 8 * (n - 1 - i)
		float = kind == cF64 or kind == cF32
		inReg = nFloat < 8 if float else nInt < 8
		if not float and inReg:
			g.a.a64Ldr(nInt, a64Fp, at)
			if kind == cBytes or kind == cText: g.a64BytesAddress(nInt, kind == cText, a64T0)
			nInt += 1
			continue
		g.a.a64Ldr(a64T1, a64Fp, at)
		if kind == cBytes or kind == cText: g.a64BytesAddress(a64T1, kind == cText, a64T0)
		if float and inReg:
			g.a.a64Op2(a64FmovDX if kind == cF64 else a64FmovSW, nFloat, a64T1)
			nFloat += 1
		else:
			g.a.a64Str(a64T1, a64Sp, 8 * stack)
			stack += 1

# x0 the result as the Zap convention has it
fn a64CResult(mut g Gen, call CCall):
	if call.ret == cF32:
		g.a.a64Op2(a64FcvtSD, 0, 0)   # fcvt d0, s0: an f32 travels as its f64
	if call.ret == cF32 or call.ret == cF64:
		g.a.a64Op2(a64FmovXD, 0, 0)
	elif call.ret == cBool:
		g.a.a64Extend(0, 0, 4, true)
		g.a.a64CmpImm(0, 0)
		g.a.a64Cset(0, a64Ne)
	else:
		g.a.a64Extend(0, 0, call.bits / 8, not call.signed)
