# The stack on Linux on arm64: the calls walked by their frame records (x29 points at the
# caller's x29 and the return address), from the walk's own or from a crash's context.

# RtlCaptureStackBackTrace(0, count, frames, 0): the return addresses of the calls, nearest
# first, up to count of them at frames; how many
fn rtlCaptureStackBackTrace(skip u32, count u32, frames i64, hash i64) u16:
	_ = skip
	_ = hash
	u16(frameWalk(__frameAddress(), frames, i64(count)))

# the return addresses of the frame records from record, up to room of them at frames; how many
fn frameWalk(record i64, frames i64, room i64) i64:
	n = 0
	at = record
	while at != 0 and n < room and __ld64(at + 8) != 0:
		__st64(frames + 8 * n, __ld64(at + 8))
		n += 1
		at = __ld64(at)
	n

# the ucontext's registers (its mcontext): x29, sp, pc, and the address that faulted
contextFault = 176
contextFp = 416
contextSp = 432
contextPc = 440

# the return addresses up the calls from a crash's context, up to room of them at frames
fn contextCalls(context i64, frames i64, room i64) i64:
	frameWalk(__ld64(context + contextFp), frames, room)

# a crash handler's sigaction: the handler and SA_SIGINFO | SA_ONSTACK | SA_NODEFER (a crash in
# the report itself comes back to it); the kernel returns from it by itself
fn crashAction(handler i64) u8[]:
	action = zeroBytes(32)
	action.setU64le(0, u64(handler))
	action.setU64le(8, 0x4800_0004)
	action
