# ZAP_RUN=profile: `zap run` runs the program under a sampler and prints, on stderr, where its
# time went (on Linux the processor samples every thread: compiler/linux/system.zap). The
# sampler stops the program's main thread about every millisecond to read the instruction
# pointer and walk the stack as the system's unwinder does (walkStack: the unwind
# information of the program's exception directory, and of the system's code), names each
# address by the map ZAP_RUN=map writes beside the executable, and lists the functions by the
# samples spent in their own code (self) and in what they called (total).
# `profile=name` also counts, for the samples inside that function, the function that called it
# (and for those inside one it called, the caller below it), and lists the addresses (RVAs, as
# ZAP_RUN=disasm prints them) its own samples stopped at the most.

import perf

fn profileWord():
	TraceWord(
		"profile",
		"zap run samples the program and lists its functions by time (profile=name: its hot addresses, and on Windows its callers)"
	)

extern fn CreateProcessA(
	app i64,
	cmd u8[],
	procAttrs i64,
	threadAttrs i64,
	inherit bool,
	flags i64,
	env i64,
	dir i64,
	startup u8[],
	info u8[]
) bool
extern fn SuspendThread(thread i64) u32
extern fn ResumeThread(thread i64) u32
extern fn GetThreadContext(thread i64, context u8[]) bool
extern fn ReadProcessMemory(process i64, at i64, buffer u8[], n i64, bytesRead i64) bool
extern fn WaitForSingleObject(h i64, ms i64) u32
extern fn CloseHandle(h i64) bool
extern fn RtlLookupFunctionEntry(pc i64, out base i64, history i64) i64
extern "winmm.dll" fn timeBeginPeriod(ms u32) u32

contextSize = 1232
contextFlagsAt = 48   # CONTEXT.ContextFlags
regsAt = 120   # CONTEXT.Rax, then rcx, rdx, rbx, rsp, rbp, rsi, rdi, r8..r15
ripAt = 248   # CONTEXT.Rip
deepest = 200   # frames walked per sample

# the index of the function whose code holds the address, or -1 outside the program's code
fn sampledFunction(fns perf.MapFunction[], address i64):
	rva = address - imageBase
	-1 if rva > 268_435_456 else perf.functionAtRva(fns, rva)

type Samples:
	own i64[]
	total i64[]
	count i64
	watched i64   # the function whose callers are counted (-1: none)
	callers i64[]   # per function: the samples in which it called the watched one
	hot {i64: i64}   # the watched function's RVAs and their samples

# one sample of the stopped thread: its function and every caller up the stack
fn sample(
	fns perf.MapFunction[],
	entries UnwindEntry[],
	process i64,
	thread i64,
	mut context u8[],
	mut s Samples
):
	context[contextFlagsAt] = 3   # CONTEXT_CONTROL | CONTEXT_INTEGER (0x100003)
	context[contextFlagsAt + 2] = 16
	if not GetThreadContext(thread, context): return
	seen = []
	rip = i64(context.loadWord(ripAt))
	f = sampledFunction(fns, rip)
	if f >= 0:
		s.own[f] += 1
		seen.push(f)
		if f == s.watched:
			s.hot.add(rip - imageBase, 1)
	afterWatched = f == s.watched and f >= 0
	inProgram = f >= 0
	for ret in walkStack(entries, process, context):
		caller = sampledFunction(fns, ret)
		if caller < 0:
			if inProgram: break
			continue   # the system's code the program called
		inProgram = true
		if afterWatched:
			s.callers[caller] += 1
			afterWatched = false
		if caller == s.watched and caller not in seen:
			afterWatched = true
		if caller not in seen:
			seen.push(caller)
	for g in seen:
		s.total[g] += 1
	s.count += 1

# ---------- the walk ----------

# The return addresses on the stopped thread's stack, nearest first: from the context's registers,
# each frame undone by its unwind information (the program's from its exception directory, the
# system's where the profiler has the same libraries mapped, at the same addresses), a leaf's
# return address on top, until an address no information covers.
fn walkStack(entries UnwindEntry[], process i64, context u8[]):
	regs = (0..16).map(i64(context.loadWord(regsAt + 8 * it)))
	rip = i64(context.loadWord(ripAt))
	returns = []
	loop deepest:
		sp = regs[4]
		rip = undoFrame(entries, process, rip, returns.isEmpty, regs)
		if rip == 0 or regs[4] <= sp: break
		returns.push(rip)
	returns

# n bytes of the stopped program's memory at `at`, as numbers, or none
fn readAt(process i64, at i64, n i64) i64[]?:
	b = fill(n, u8(0))
	if not ReadProcessMemory(process, at, b, n, 0): return none
	b.map(i64(it))

# the little-endian 16 or 32 bits at b[at], and the 32 as a signed number
fn bits16(b i64[], at i64):
	b[at] | b[at + 1] << 8

fn bits32(b i64[], at i64):
	bits16(b, at) | bits16(b, at + 2) << 16

fn signed32(b i64[], at i64):
	bits32(b, at) - (1 << 32 if b[at + 3] >= 128 else 0)

fn signed8(b i64[], at i64):
	b[at] - (256 if b[at] >= 128 else 0)

# the word on top of the stack, popped: 0 when it cannot be read
fn popWord(process i64, mut regs i64[]):
	w = readAt(process, regs[4], 8) ?? return 0
	regs[4] += 8
	bits32(w, 0) | bits32(w, 4) << 32

# The frame of the code at rip undone: regs as its caller left them, its return address (0 when
# no unwind information covers rip). The program's code without an entry is a leaf's, and so is
# the system's where the thread stopped (exact: rip is no return address; a call into the kernel).
fn undoFrame(entries UnwindEntry[], process i64, rip i64, exact bool, mut regs i64[]) i64:
	base = imageBase
	entry = UnwindEntry(start = 0, end = 0, info = -1)
	rva = rip - imageBase
	if rva >= 0 and rva < 268_435_456:
		k = unwindEntryOf(entries, rva)
		if k >= 0:
			entry = entries[k]
	else:
		b = 0
		at = RtlLookupFunctionEntry(rip, out b, 0)
		if at == 0 and not exact: return 0
		if at != 0:
			e = readAt(process, at, 12) ?? return 0
			base = b
			entry = UnwindEntry(start = bits32(e, 0), end = bits32(e, 4), info = bits32(e, 8))
	if entry.info >= 0:
		head = readAt(process, base + entry.info, 4) ?? return 0
		offset = rip - base - entry.start
		if not (
			offset >= head[1] and
				epilogueUndone(process, rip, base + entry.start, base + entry.end, regs)
		) and
			not codesUndone(process, base, entry.info, offset, regs):
			return 0
	popWord(process, regs)

# Whether rip is in an epilogue (add rsp or lea rsp, pops, then ret or a jump out of the function
# [start, end)), which is then run on regs up to the return address: the unwind codes describe
# only the prologue.
fn epilogueUndone(process i64, rip i64, start i64, end i64, mut regs i64[]):
	c = readAt(process, rip, 32) ?? return false
	i = 0
	sp = regs[4]
	if c[0] == 0x48 and c[1] == 0x83 and c[2] == 0xC4:
		sp += signed8(c, 3)   # add rsp, imm8
		i = 4
	elif c[0] == 0x48 and c[1] == 0x81 and c[2] == 0xC4:
		sp += signed32(c, 3)   # add rsp, imm32
		i = 7
	elif (c[0] & 0xF8) == 0x48 and c[1] == 0x8D and ((c[2] >> 3) & 7) == 4 and (c[2] & 7) != 4 and
		(c[2] >> 6) in [1, 2]:
		r = (c[2] & 7) + (c[0] & 1) * 8   # lea rsp, [r + disp]
		sp = regs[r] + (signed8(c, 3) if (c[2] >> 6) == 1 else signed32(c, 3))
		i = 4 if (c[2] >> 6) == 1 else 7
	pops = []
	while i < 28:
		rex = c[i] if (c[i] & 0xF0) == 0x40 else 0
		at = i + 1 if rex != 0 else i
		if (c[at] & 0xF8) == 0x58:
			pops.push((rex & 1) * 8 + (c[at] & 7))   # pop r
			i = at + 1
			continue
		if c[at] == 0xE9:
			target = rip + at + 5 + signed32(c, at + 1)
			if target >= start and target < end: return false   # a jump inside: not an epilogue
		elif not (
			c[at] == 0xC3 or c[at] == 0xC2 or (c[at] == 0xFF and ((c[at + 1] >> 3) & 7) == 4)
		):
			return false
		regs[4] = sp
		for r in pops:
			regs[r] = popWord(process, regs)
		return true
	false

# whether unwind code k (its 2-byte slots in codes) was run at offset into a prologue of size
# prolog
fn codeRan(codes i64[], k i64, offset i64, prolog i64):
	offset >= prolog or codes[2 * k] <= offset

# Whether the unwind codes of the UNWIND_INFO at base + info (and those it chains to) were undone
# on regs, those of the prologue's instructions not yet run at offset left out.
fn codesUndone(process i64, base i64, info i64, offset i64, mut regs i64[]):
	at = base + info
	off = offset
	loop 32:
		head = readAt(process, at, 4) ?? return false
		prolog = head[1]
		count = head[2]
		frameReg = head[3] & 15
		slots = count + count % 2
		codes = readAt(process, at + 4, 2 * slots + 12) ?? return false
		frame = regs[4]
		if frameReg != 0 and
			(0..count).any((codes[2 * it + 1] & 15) == 3 and codeRan(codes, it, off, prolog)):
			frame = regs[frameReg] - 16 * (head[3] >> 4)
		k = 0
		while k < count:
			op = codes[2 * k + 1] & 15
			arg = codes[2 * k + 1] >> 4
			if codeRan(codes, k, off, prolog):
				if op == 0:
					regs[arg] = popWord(process, regs)   # UWOP_PUSH_NONVOL
				elif op == 1:
					regs[4] += 8 * bits16(codes, 2 * k + 2) if arg == 0
						else bits32(codes, 2 * k + 2)
				elif op == 2:
					regs[4] += 8 * arg + 8   # UWOP_ALLOC_SMALL
				elif op == 3:
					regs[4] = frame   # UWOP_SET_FPREG
				elif op == 4 or op == 5:
					saved = frame +
						(8 * bits16(codes, 2 * k + 2) if op == 4 else bits32(codes, 2 * k + 2))
					w = readAt(process, saved, 8) ?? return false
					regs[arg] = bits32(w, 0) | bits32(w, 4) << 32   # UWOP_SAVE_NONVOL
				elif op == 10:
					return false   # a machine frame (an interrupt's): not walked
			k += (2 if arg == 0 else 3) if op == 1
				else 2 if op in [4, 6, 8]
				else 3 if op in [5, 9]
				else 1
		if ((head[0] >> 3) & 4) == 0: return true
		at = base + bits32(codes, 2 * slots + 8)   # the chained entry's unwind information
		off = 1 << 30   # whose prologue has run
	false

fn reportSamples(fns perf.MapFunction[], s Samples, title str, counts i64[]):
	eprint("{title} ({s.count} samples)")
	order = (0..fns.len).filter(counts[it] > 0).sortedBy(-counts[it])
	for i in order[..len.min(30)]:
		share = counts[i] * 100.0 / s.count
		eprint("  {share:>5.1}%  {counts[i]:>6}  {fns[i].name}")

# the watched function's addresses (RVAs) its samples stopped at the most
fn reportHot(s Samples, watchedName str):
	eprint("")
	eprint("hot addresses of {watchedName}")
	for rva in s.hot.keys().sortedBy(-s.hot[it])[..s.hot.len.min(25)]:
		eprint("  {rva:08x}  {s.hot[rva]:>6}")

# Runs the executable (its command line) under the sampler, then prints where its time went;
# its exit code
fn profileRun(exe str, line str, watchedName str):
	fns = functionsOf(exe)
	entries = unwindEntries(exe)
	startup = fill(104, u8(0))
	startup[0] = 104
	info = fill(24, u8(0))   # PROCESS_INFORMATION: hProcess, hThread
	cmd = []
	cmd.extend(line.bytes())
	cmd.push(0)
	if not CreateProcessA(0, cmd, 0, 0, true, 0, 0, 0, startup, info): return -1
	process = i64(info.loadWord(0))
	thread = i64(info.loadWord(8))
	timeBeginPeriod(1)
	s = Samples(
		own = zeros(fns.len),
		total = zeros(fns.len),
		count = 0,
		watched = fns.findIndex(.name == watchedName) ?? -1,
		callers = zeros(fns.len),
		hot = {}
	)
	context = fill(contextSize, u8(0))
	while WaitForSingleObject(process, 1) != 0:
		if SuspendThread(thread) != 4_294_967_295:
			sample(fns, entries, process, thread, context, s)
			ResumeThread(thread)
	CloseHandle(thread)
	p = Process(handle = process)
	code = p.wait()
	reportSamples(fns, s, "self", s.own)
	eprint("")
	reportSamples(fns, s, "total", s.total)
	if s.watched >= 0:
		eprint("")
		reportSamples(fns, s, "callers of {watchedName}", s.callers)
		s.reportHot(watchedName)
	code
