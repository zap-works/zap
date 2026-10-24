# An Android app's entry (appBuild): ANativeActivity_onCreate, which the app's NativeActivity calls
# on its main thread, the system's convention and thread pointer. The program cannot run there (its
# start sets the thread pointer its slots are at), so the entry starts a thread bionic makes
# (pthread_create, a stack of the runtime's main thread's size) and returns: a function of the
# system's libraries the program calls, which may enter Java's runtime, finds the thread's own
# block and stack. The thread leaves under its stack's top what the kernel gives a process's start
# (no argument, no environment, an empty auxiliary vector: an app may not read its own,
# runtime/core/linux/app/) and takes the executable's start (x64LinuxStart's, a64Start's); the
# program's end ends the process.

import fs

# the thread's stack, the start's block (argc, the arguments' end, the environment's, the vector's
# two) at its top
appThreadStack = 134_217_728
appBlockBytes = 64

# the runtime's slot that holds the place of the app's package, its logcat tags' start, and the
# one that holds the ANativeActivity the system made (its data dirs, runtime/core/linux/app/)
appTagSlot = 12
appActivitySlot = 18

# The window and the input queue the system hands the activity, and its end: its callbacks (the
# table at ANativeActivity's start, a word each: onDestroy at 40, onNativeWindowCreated at 56,
# Resized at 64, Destroyed at 80, onInputQueueCreated at 88, Destroyed at 96) keep the window and the queue in
# the runtime's slots 19 and 20 (callHand), and on their end wait while the program holds the
# window (slot 21 nonzero) or the input thread reads the queue (slot 24 nonzero), the system's
# thread then free to take them back (callTake); the activity's end marks slot 22 (callMark),
# which the program ends at, and a resize slot 23, which it sizes its picture anew at
# (runtime/core/linux/app/).
appWindowSlot = 19
appQueueSlot = 20
appHeldSlot = 21
appEndedSlot = 22
appResizedSlot = 23
appReadingSlot = 24
callHand = 0
callTake = 1
callMark = 2
appCallbacks = [
	(40, appEndedSlot, callMark, 0),
	(56, appWindowSlot, callHand, 0),
	(64, appResizedSlot, callMark, 0),
	(80, appWindowSlot, callTake, appHeldSlot),
	(88, appQueueSlot, callHand, 0),
	(96, appQueueSlot, callTake, appReadingSlot)
]

# the code at label that starts the program at start on a thread of its own and returns
fn genAppEntry(mut g Gen, label i64, start i64):
	g.a.asmPlace(label)
	if onArm():
		g.a64AppEntry(start)
	else:
		g.x64AppEntry(start)

fn a64AppEntry(mut g Gen, start i64):
	g.a.a64AdrData(1, g.globalsOff + appActivitySlot * 8)   # the activity, x0, kept
	g.a.a64Str(0, 1, 0)
	g.a64AppCallbacks()
	thread = g.a.asmNewLabel()
	g.a.a64Pair(false, a64Fp, a64Lr, a64Sp, -96, 1)   # stp x29, x30, [sp, -96]!: the attributes at +16, the thread at +80
	g.a.a64AddImm(a64Fp, a64Sp, 0)
	g.a.a64AddImm(0, a64Sp, 16)
	g.a64CallLibc("pthread_attr_init")
	g.a.a64AddImm(0, a64Sp, 16)
	g.a.a64MovImm(1, appThreadStack)
	g.a64CallLibc("pthread_attr_setstacksize")
	g.a.a64AddImm(0, a64Sp, 80)
	g.a.a64AddImm(1, a64Sp, 16)
	g.a.a64AdrLabel(2, thread)
	g.a.a64MovImm(3, 0)
	g.a64CallLibc("pthread_create")
	g.a.a64Pair(true, a64Fp, a64Lr, a64Sp, 96, 2)   # ldp x29, x30, [sp], 96
	g.a.a64Ret()
	g.a.asmPlace(thread)   # the thread's entry: the start's block, zeros
	g.a.a64AddImm(a64Sp, a64Sp, -appBlockBytes)
	for at in (0..appBlockBytes step 16):
		g.a.a64Pair(false, a64Zr, a64Zr, a64Sp, at, 0)
	g.a.a64B(start)

fn a64CallLibc(mut g Gen, name str):
	g.a.a64AdrData(a64T0, g.libcSlot(name))
	g.a.a64Ldr(a64T0, a64T0, 0)
	g.a.a64Blr(a64T0)

# the callbacks' table filled as x64AppCallbacks fills it
fn a64AppCallbacks(mut g Gen):
	labels = []
	loop appCallbacks.len:
		labels.push(g.a.asmNewLabel())
	g.a.a64Ldr(2, 0, 0)   # x2 = the callbacks' table
	for i, (at, _, _, _) in appCallbacks:
		g.a.a64AdrLabel(3, labels[i])
		g.a.a64Str(3, 2, at)
	after = g.a.asmNewLabel()
	g.a.a64B(after)
	for i, (_, slot, kind, waited) in appCallbacks:
		g.a.asmPlace(labels[i])
		g.a.a64AdrData(9, g.globalsOff + slot * 8)
		g.a.a64MovImm(10, 1)
		g.a.a64Str([1, 31, 10][kind], 9, 0)   # the handed one (x1), zero or a mark
		if kind == callTake:
			held = g.a.asmNewLabel()
			g.a.a64(0xD503_3BBF)   # dmb ish
			g.a.a64AdrData(9, g.globalsOff + waited * 8)
			g.a.asmPlace(held)
			g.a.a64Ldr(10, 9, 0)
			g.a.a64Cbz(10, held, true)
		g.a.a64Ret()
	g.a.asmPlace(after)

fn x64AppEntry(mut g Gen, start i64):
	g.a.leaRaxData(g.globalsOff + appActivitySlot * 8)   # the activity, rdi, kept
	g.a.em3(0x48, 0x89, 0x38)   # mov [rax], rdi
	g.x64AppCallbacks()
	thread = g.a.asmNewLabel()
	g.a.em1(0x55)   # push rbp
	g.a.em3(0x48, 0x89, 0xE5)   # mov rbp, rsp
	g.a.emN([0x48, 0x81, 0xEC, 128, 0, 0, 0])   # sub rsp, 128: the attributes at rsp, the thread at +64
	g.a.em3(0x48, 0x89, 0xE7)   # mov rdi, rsp
	g.x64CallLibc("pthread_attr_init")
	g.a.em3(0x48, 0x89, 0xE7)   # mov rdi, rsp
	g.a.em1(0xBE)   # mov esi, the stack's size
	g.a.emit32(appThreadStack)
	g.x64CallLibc("pthread_attr_setstacksize")
	g.a.emN([0x48, 0x8D, 0x7C, 0x24, 64])   # lea rdi, [rsp+64]
	g.a.em3(0x48, 0x89, 0xE6)   # mov rsi, rsp
	g.a.em3(0x48, 0x8D, 0x15)   # lea rdx, [rip + the thread's entry]
	g.a.asmRel32Label(thread)
	g.a.em2(0x31, 0xC9)   # xor ecx, ecx
	g.x64CallLibc("pthread_create")
	g.a.em3(0x48, 0x89, 0xEC)   # mov rsp, rbp
	g.a.em1(0x5D)   # pop rbp
	g.a.em1(0xC3)   # ret
	g.a.asmPlace(thread)   # the thread's entry: rsp is 8 past 16's multiple
	g.a.emN([0x48, 0x83, 0xEC, appBlockBytes + 8])   # sub rsp, 72: the start's block, zeros
	g.a.em2(0x31, 0xC0)   # xor eax, eax
	for at in (0..appBlockBytes + 8 step 8):
		g.a.emN([0x48, 0x89, 0x44, 0x24, at])   # mov [rsp+at], rax
	g.a.jmpLabel(start)

# call the C library's function (its address the loader put in its data word, ccall.zap)
fn x64CallLibc(mut g Gen, name str):
	g.a.leaRaxData(g.libcSlot(name))
	g.a.em3(0x48, 0x8B, 0x00)   # mov rax, [rax]
	g.a.em2(0xFF, 0xD0)   # call rax

# the callbacks' table filled with the activity's end's, the window's and the input queue's
# (appCallbacks), each placed after a jump over them
fn x64AppCallbacks(mut g Gen):
	labels = []
	loop appCallbacks.len:
		labels.push(g.a.asmNewLabel())
	g.a.em3(0x48, 0x8B, 0x07)   # mov rax, [rdi]: the callbacks' table
	for i, (at, _, _, _) in appCallbacks:
		g.a.em3(0x48, 0x8D, 0x0D)   # lea rcx, [rip + the callback]
		g.a.asmRel32Label(labels[i])
		g.a.em3(0x48, 0x89, 0x48)   # mov [rax + at], rcx
		g.a.em1(at)
	after = g.a.asmNewLabel()
	g.a.jmpLabel(after)
	for i, (_, slot, kind, waited) in appCallbacks:
		g.a.asmPlace(labels[i])
		g.a.leaRaxData(g.globalsOff + slot * 8)
		if kind == callMark:
			g.a.emN([0x48, 0xC7, 0x00, 1, 0, 0, 0])   # mov qword [rax], 1
		elif kind == callTake:
			held = g.a.asmNewLabel()
			g.a.emN([0x48, 0xC7, 0x00, 0, 0, 0, 0])   # mov qword [rax], 0
			g.a.em3(0x0F, 0xAE, 0xF0)   # mfence
			g.a.leaRaxData(g.globalsOff + waited * 8)
			g.a.asmPlace(held)
			g.a.em2(0xF3, 0x90)   # pause
			g.a.em4(0x48, 0x83, 0x38, 0x00)   # cmp qword [rax], 0
			g.a.jccLabel(0x85, held)   # jnz
		else:
			g.a.em3(0x48, 0x89, 0x30)   # mov [rax], rsi: the handed one
		g.a.em1(0xC3)   # ret
	g.a.asmPlace(after)

# the app's package (apk.zap), its logcat tags' start, in the data, its place in the runtime's slot
fn writeAppTag(mut g Gen, exePath str):
	at = g.a.data.len
	bytesPutStr(g.a.data, appPackage(fs.stem(exePath)))
	g.a.data.push(0)
	g.a.patchAddress(g.globalsOff + appTagSlot * 8, dataRvaOf(g.a.code.len) + at)
