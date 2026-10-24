# The stack on Linux on x64: the calls walked by the unwind tables the ELF carries (the PE's
# exception directory, elf.zap, their place in the slots below), read as Windows' RtlVirtualUnwind
# reads them: a function's frame on rsp (the registers pushed, the bytes taken) or on rbp (the
# generated helpers'); code without an entry is a leaf, its return address on top.

# the slots that hold where the table of the code's regions is and its count of entries (each
# its start, its end and its unwind information, as RVAs of 4 bytes)
slotUnwindTable = 7
slotUnwindCount = 8

# the ucontext's registers (uc_mcontext's gregs, from byte 40): rbp, rsp, rip, and cr2 (the
# address that faulted)
contextFp = 120
contextSp = 160
contextPc = 168
contextFault = 216

# RtlCaptureStackBackTrace(0, count, frames, 0): the return addresses of the calls, nearest
# first, up to count of them at frames; how many
fn rtlCaptureStackBackTrace(skip u32, count u32, frames i64, hash i64) u16:
	_ = skip
	_ = hash
	room = i64(count)
	if room == 0: return 0
	pc = __returnAddress()
	__st64(frames, pc)
	u16(1 + unwindWalk(pc, __callerSp(), 0, false, frames + 8, room - 1))

# the return addresses up the calls from a crash's context, up to room of them at frames
fn contextCalls(context i64, frames i64, room i64) i64:
	pc = __ld64(context + contextPc)
	unwindWalk(pc, __ld64(context + contextSp), __ld64(context + contextFp), true, frames, room)

# The return addresses up the calls from the code at pc with the stack at sp and rbp at bp (0
# when not known), up to room of them at frames: how many. exact when pc is the instruction itself
# (a fault), not a return address. Code without an entry is a leaf, its caller's return address
# on top, when it is a function of the program; elsewhere (the start's code) the walk ends.
fn unwindWalk(from i64, sp0 i64, bp0 i64, exact0 bool, frames i64, room i64) i64:
	pc = from
	sp = sp0
	bp = bp0
	exact = exact0
	n = 0
	while n < room:
		last = sp
		entry = unwindEntry(pc if exact else pc - 1)
		if entry == 0 and not exact and functionAt(pc - 1) < 0: break
		if entry != 0:
			sp, bp = unwindFrame(entry, (pc if exact else pc - 1) - imageBase, sp, bp)
		if sp <= 0 or sp < last: break   # (a frame not known: the walk ends)
		next = __ld64(sp)
		if next == 0: break
		sp += 8
		__st64(frames + 8 * n, next)
		n += 1
		pc = next
		exact = false
	n

# the entry of the table whose region holds the code at pc, or 0
fn unwindEntry(pc i64) i64:
	table = gv(slotUnwindTable)
	rva = pc - imageBase
	lo = 0
	hi = gv(slotUnwindCount)
	while lo < hi:
		mid = (lo + hi) / 2
		e = table + 12 * mid
		if rva < __ld32(e):
			hi = mid
		elif rva >= __ld32(e + 4):
			lo = mid + 1
		else:
			return e
	0

# sp and rbp as they were at the call into the region of entry, from the code at rva in it (its
# codes in reverse order of the prologue: those of instructions not done yet left out)
fn unwindFrame(entry i64, rva i64, sp i64, bp i64) (i64, i64):
	info = imageBase + __ld32(entry + 8)
	offset = rva - __ld32(entry)
	count = __ld8(info + 2)
	frameOffset = __ld8(info + 3) >> 4
	s = sp
	b = bp
	k = 0
	while k < count:
		code = info + 4 + 2 * k
		done = offset >= __ld8(code)
		op = __ld8(code + 1) & 15
		arg = __ld8(code + 1) >> 4
		if op == 0:   # UWOP_PUSH_NONVOL: rbp's pushed value is the caller's rbp
			if done:
				if arg == 5: b = __ld64(s)
				s += 8
			k += 1
		elif op == 1:   # UWOP_ALLOC_LARGE: a slot's count of words, or two slots' bytes
			size = __ld16(code + 2) * 8 if arg == 0 else __ld32(code + 2)
			if done: s += size
			k += 2 if arg == 0 else 3
		elif op == 2:   # UWOP_ALLOC_SMALL
			if done: s += arg * 8 + 8
			k += 1
		elif op == 3:   # UWOP_SET_FPREG: rsp was rbp less the frame's offset
			if done: s = 0 if b == 0 else b - frameOffset * 16
			k += 1
		else:
			k += 1
	(s, b)

# a crash handler's sigaction: the handler, SA_SIGINFO | SA_ONSTACK | SA_NODEFER (a crash in the
# report itself comes back to it) | SA_RESTORER, and the return from it (x64's kernel needs one)
fn crashAction(handler i64) u8[]:
	action = zeroBytes(32)
	action.setU64le(0, u64(handler))
	action.setU64le(8, 0x4C00_0004)
	action.setU64le(16, u64(__sigreturn()))
	action
