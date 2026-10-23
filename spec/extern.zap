# 10. Foreign functions: `extern`
#
# Operating-system calls, graphics APIs and foreign libraries are declared, not wrapped. An `extern`
# signature is the only thing the compiler takes on trust; there is no `unsafe` keyword and no raw
# pointer type, so a reviewer greps `extern` and reads the signatures as C. A function is
# kernel32's unless a DLL is named. Calls use the system's convention, and a `bool` result is
# normalised.

extern fn MulDiv(number i64, numerator i64, denominator i64) i32
extern fn GetStdHandle(which i64) i64
extern fn SetEnvironmentVariableA(name i64, value i64) bool
extern "ws2_32.dll" fn htonl(host u32) u32
extern "ucrtbase.dll" fn powf(x f32, y f32) f32
extern "ucrtbase.dll" fn fmaf(a f32, b f32, c f32) f32
extern fn LoadLibraryA(name str) i64
extern fn GetProcAddress(module i64, name str) i64
extern fn GetTickCount() i64

test "integers, bools, f32 and f64 cross by value":
	print(MulDiv(6, 7, 2))
	print(MulDiv(-10, 3, 4))
	print(GetStdHandle(-11) != 0)
	print(SetEnvironmentVariableA(0, 0))
	print(htonl(1))
	a f32 = 2.0
	print(powf(a, 10.0))
	print(fmaf(1.5, 2.0, 0.25))
	prints """
		21
		-8
		true
		false
		16777216
		1024
		3.25
		"""

test "an extern parameter crosses as a word, a buffer or a struct's address" refuses ExternParameter:
	extern fn Foo(counts {str: i64}) i64

	m {str: i64} = {}
	print(Foo(m))

# A `str` or a list crosses as the address of its bytes (a `u8[]` parameter accepts any list of
# plain values: `Vertex[]`, `f32[]`, pixels); a list of an extern type is a C array. A struct
# crosses as its address (`mut` when the system writes into it), and only an `extern type`, laid
# out as C lays it out: a plain struct's fields may be reordered (spec 14.2), so neither it nor a
# list of it is a parameter's type.

extern "kernel32.dll" fn RtlMoveMemory(dst u8[], src u8[], n i64)

type Corner:
	x f32
	y f32
	kind i64

test "a plain struct crosses into no extern" refuses ExternPlainStruct:
	type Span:
		low u8
		high i64

	extern fn Measure(spans Span[]) i64

	print(Measure([Span(low = 1, high = 2)]))

test "an extern's u8[] takes the bytes of any list of plain values":
	src = [Corner(x = 1.5, y = 2.5, kind = 7), Corner(x = 3.0, y = 4.0, kind = 9)]
	dst = [Corner(x = 0.0, y = 0.0, kind = 0), Corner(x = 0.0, y = 0.0, kind = 0)]
	RtlMoveMemory(dst, src, 32)
	floats f32[] = [1.0, 2.0]
	bytes u8[] = zeros(8)
	RtlMoveMemory(bytes, floats, 8)
	expect dst[1].kind == 9
	expect dst[0].y == 2.5
	expect bytes[7] == 64

# An `out` parameter (`out id u32`) is the address of the caller's local, passed as `out name`,
# which declares `name` there with the parameter's type; `out _` drops the value, and an existing
# local may be written (it is then mutable, spec 2.4). Only an extern has one.

extern fn QueryPerformanceFrequency(out freq i64) bool
extern fn QueryPerformanceCounter(out now i64) bool
extern fn GetSystemTimeAdjustment(out adjustment u32, out increment u32, out disabled i32) bool

test "out declares a new local, writes a mut one, or drops the value":
	QueryPerformanceFrequency(out freq)
	print(freq > 1000)
	last = 0
	loop 3:
		QueryPerformanceCounter(out last)
	QueryPerformanceCounter(out _)
	print(last > 0)
	ok = GetSystemTimeAdjustment(out adjustment, out increment, out _)
	print(ok and increment > 0 and adjustment < 4_294_967_295)
	prints """
		true
		true
		true
		"""

test "out is an extern's" refuses OutParameterOutsideExtern:
	fn count(out n i64):
		pass

	count(out k)
	print(k)

test "out writes no parameter" refuses OutTargetImmutable:
	extern fn QueryPerformanceCounter(out now i64) bool

	fn read(t i64) i64:
		_ = QueryPerformanceCounter(out t)
		t
	print(read(0))

# A callback type (`fn(i64, i64) i64`: plain words in, a plain word or nothing out) is given as the
# name of a top-level function, reached through an entry with the system's convention. A lambda is
# refused: the system keeps a code address, not an environment.

extern "user32.dll" fn CallWindowProcA(
	proc fn(i64, i64, i64, i64) i64,
	window i64,
	message i64,
	wparam i64,
	lparam i64
) i64

fn windowProc(window i64, message i64, wparam i64, lparam i64):
	window * 1000 + message * 100 + wparam * 10 + lparam

fn negate(window i64, message i64, wparam i64, lparam i64):
	-(window + message + wparam + lparam)

test "the system calls a function back":
	expect CallWindowProcA(windowProc, 1, 2, 3, 4) == 1234
	expect CallWindowProcA(negate, 10, 20, 30, 40) == -100
	expect CallWindowProcA(windowProc, 9, 8, 7, 6) == 9876

test "a lambda is no callback" refuses CallbackNotFunction:
	extern "user32.dll" fn CallWindowProcA(proc fn(i64, i64, i64, i64) i64, window i64, message i64, wparam i64, lparam i64) i64

	k = 3
	print(CallWindowProcA((a, b, c, d): a + k, 1, 2, 3, 4))

# Extern types: a structure the system reads or writes is an `extern type`, in C layout, holding
# integers, floats, bools, other extern types and fixed arrays of those, with C pointers written
# as references: `ref T` (an extern value or a number), `ref str` (the bytes; end with `\0` where C
# wants a C string), `ref T[]` (the address of the elements; the count is a field of its own) and
# `ref T?` (NULL for none). The bytes are read here through RtlMoveMemory, and each pointer
# followed (a float shown as its bits: 20.0 and 1.5).

extern loaded "RtlMoveMemory" fn bytesOfInfo(dst u8[], src Info, n i64)
extern loaded "RtlMoveMemory" fn bytesAt(dst u8[], src i64, n i64)
extern loaded "RtlMoveMemory" fn bytesOfChoice(dst u8[], src Choice, n i64)

extern type Choice:
	first ref Pair?
	second ref Pair?

extern type Pair:
	a u32
	b f32

extern type Stage:
	stage u32
	name ref str

extern type Stages:
	count u32
	stages ref Stage[]

extern type Info:
	kind u32 = 7
	next ref Pair?
	name ref str
	items ref Pair[]
	count u32
	one ref Pair
	pad u8[3]

fn word(b u8[], at i64, size i64):
	v = 0
	for k in 0..size:
		v |= i64(b[at + k]) << (k * 8)
	v

fn followed(at i64, n i64):
	out = fill(n, u8(0))
	bytesAt(out, at, n)
	out

test "an extern type's pointers point at what it was made from":
	k = LoadLibraryA("kernel32.dll\0")
	mover = GetProcAddress(k, "RtlMoveMemory\0")
	bindExtern(bytesOfInfo, mover)
	bindExtern(bytesAt, mover)
	items = [Pair(a = 1, b = 0.5), Pair(a = 2, b = 20.0)]
	single = Pair(a = 5, b = 1.5)
	info = Info(next = none, name = "zap\0", items, count = 2, one = single, pad = [0, 0, 0])
	b = fill(56, u8(0))
	bytesOfInfo(b, info, 56)
	print("{word(b, 0, 4)} {word(b, 8, 8)} {word(b, 32, 4) + 1}")
	name = followed(word(b, 16, 8), 3)
	print(str(move name))
	second = followed(word(b, 24, 8) + 8, 8)
	print("{word(second, 0, 4)} {word(second, 4, 4)}")
	one = followed(word(b, 40, 8), 8)
	print("{word(one, 0, 4)} {word(one, 4, 4)}")
	# the addresses were followed by hand: what they point into lives until here
	print(items.len + single.a)
	prints """
		7 0 3
		zap
		2 1101004800
		5 1069547520
		7
		"""

# An array field given no value, in the type or in the literal, starts empty as a `mut` array local
# does: each element `0`, `0.0` or `false` (a name the system fills in, a C struct's padding).

extern type Named:
	name u8[8]
	size u32[2, 2]
	kind u32 = 1

test "an extern type's array field left out starts empty":
	n = Named()
	print("{n.name} {n.size} {n.kind}")
	prints "[0, 0, 0, 0, 0, 0, 0, 0] [[0, 0], [0, 0]] 1"

test "a list of extern types is a C array of their structures":
	entry = "main\0"
	stages = [Stage(stage = 1, name = entry), Stage(stage = 16, name = "frag\0")]
	info = Stages(count = u32(stages.len), stages)
	_ = info
	expect info.count == 2
	expect stages[1].stage == 16

test "an optional C pointer given a value points at it":
	k = LoadLibraryA("kernel32.dll\0")
	bindExtern(bytesAt, GetProcAddress(k, "RtlMoveMemory\0"))
	bindExtern(bytesOfChoice, GetProcAddress(k, "RtlMoveMemory\0"))
	seven = Pair(a = 7, b = 0.0)
	nine = Pair(a = 9, b = 0.0)
	some = GetTickCount() > 0
	for c in [
		Choice(first = seven, second = nine if not some else none),
		Choice(first = nine, second = seven if some else none)
	]:
		b = fill(16, u8(0))
		bytesOfChoice(b, c, 16)
		second = word(b, 8, 8)
		print("{word(followed(word(b, 0, 8), 4), 0, 4)} {0 if second == 0 else word(followed(second, 4), 0, 4)}")
	prints """
		7 0
		9 7
		"""

test "an extern type holds only what C holds" refuses ExternFieldType:
	extern type Bad:
		names str[]

	b = Bad(names = [])
	print(1)
	_ = b

# The value borrows what its pointers point to, as a view does, so they stay alive and unchanged
# while it is used. A pointer field is given at construction and is not read or changed after.

test "a list of extern types borrows what their pointers point to" refuses ChangeWhileBorrowed:
	extern type Stage:
		name ref str

	extern type Stages:
		stages ref Stage[]

	mut entry = "main\0"
	stages = [Stage(name = entry)]
	info = Stages(stages = stages)
	entry = "other\0"
	_ = info
	print(1)

test "a C pointer field is not read" refuses CPointerField:
	extern type Note:
		name ref str

	n = Note(name = "a\0")
	print(n.name)

# Functions found at run time: `extern loaded fn` declares a function whose address is known only
# while the program runs (a Vulkan extension's, a plugin's). `bindExtern(f, address)` gives one its
# address; `bindExterns(find)` gives every `extern loaded fn` of the calling module its address,
# calling `find(name)` (a `fn(str) i64`) with each name as written. `extern loaded "RtlMoveMemory"
# fn copyWordsIn(...)` names the symbol when the declared name differs, as `extern "libc.so"
# "__system_property_get" fn systemProperty(...)` does for a library's. Calling one without an
# address stops the program with its name. The runtime's own externs are in `runtime/system/sys.zap`.
# Memory the system hands out (a mapped buffer, a string it allocated) is read and written
# through `win.memoryAt(address, len)`, whose copies are checked against `len`, rather than an
# extern copy given a length of its own (*Modules*, `win`).

extern loaded fn sqrtLoaded(x f32) f32
extern loaded fn GetTickCount64() i64
extern loaded fn GetCurrentProcessId() u32
extern loaded "GetCurrentProcessId" fn processId() u32

fn kernel(name str):
	GetProcAddress(LoadLibraryA("kernel32.dll\0"), "{name}\0")

test "an extern loaded fn calls the address bindExtern gave it":
	bindExtern(sqrtLoaded, GetProcAddress(LoadLibraryA("ucrtbase.dll\0"), "sqrtf\0"))
	expect sqrtLoaded(9.0) == 3

test "bindExterns finds each loaded function by its own name, or the symbol written":
	bindExterns(kernel)
	expect GetTickCount64() > 0
	expect GetCurrentProcessId() > 0
	expect processId() == GetCurrentProcessId()

test "a loaded function called before its address" stops Failure:
	extern loaded fn neverBound() i64
	print(neverBound())

# Address space at a fixed address: `vmem.reserve(base, size)` reserves a window (*Modules*,
# `vmem`), `commit` makes its pages memory, and its loads and stores of 1 to 16 bytes are each one
# host access at an address taken modulo the window's length, so none reaches outside it: an
# emulator's guest memory, kept at the guest's own addresses.

import vmem

test "a window's committed pages are read and written at their addresses, modulo its length":
	w = vmem.reserve(0x20_0000_0000, 1 << 30) ?? fail("the window's address space is taken")
	at = w.base + 0x1_0000
	expect w.commit(at, 0x100)
	w.store32(at + 4, 0xDEAD_BEEF)
	w.store8(at, 7)
	w.store128(at + 16, 1, 2)
	print("{w.load8(at)} {w.load32(at + 4):x} {w.load16(at + 6):x} {w.load128(at + 16)}")
	print("{w.load32(0x1_0004):x} {w.load64(at + 0x4000_0010)}")
	w.write(at + 32, [u16(5), 6])
	back u16[] = [0, 0]
	w.read(at + 32, back)
	print("{back} {w.holds(at, 8)} {w.holds(w.end() - 4, 8)} {vmem.reserve(w.base, 1 << 30)}")
	prints """
		7 deadbeef dead (1, 2)
		deadbeef 1
		[5, 6] true false none
		"""

test "a copy past the window stops the program" stops IndexOutOfBounds:
	import vmem
	w = vmem.reserve(0x21_0000_0000, 1 << 20) ?? fail("taken")
	w.write(w.end() - 2, [u32(1)])
