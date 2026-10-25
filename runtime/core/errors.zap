# What a program says when it stops on an error, written for whoever fixes it (most often an
# agent): a stable code, the message, the place (function, file, line, column) with the line of
# source and a caret under the column, and the chain of calls that led there. With
# ZAP_RUN=errors=json the same comes as one line of JSON on standard error, for a tool to read.
#
# The places come from the table the compiler writes into the executable (debuginfo.zap,
# writeDebugTable; debugTable() reads its address): every function's first byte, and where the
# code of each statement and each check starts. The calls come from the stack, walked by the
# system's unwinder with the unwind information the compiler writes for every function
# (x64.zap, asmWriteUnwind).

extern fn AddVectoredExceptionHandler(first i64, handler fn(i64) i64) i64
extern fn SetThreadStackGuarantee(size u32[]) bool
extern fn RtlCaptureStackBackTrace(skip u32, count u32, frames i64, hash i64) u16
extern fn RtlLookupFunctionEntry(pc i64, out base i64, history i64) i64
extern fn RtlVirtualUnwind(
	kind u32,
	base i64,
	pc i64,
	entry i64,
	context i64,
	out data i64,
	out frame i64,
	pointers i64
) i64

# The failures the compiler's checks stop with, a line each by kind (failures.zap's failKind
# constants): the code, then the message
failTable = """
	division-by-zero|division by zero
	shift-out-of-range|shift out of range (the count must be 0 .. the width - 1)
	range-step|a range step must be positive
	index-out-of-bounds|index out of bounds
	old-processor|this program needs an x86-64-v3 processor (AVX2, FMA, BMI2)
	integer-overflow|integer overflow: the result does not fit its type
	integer-overflow|the value does not fit the type it is converted to
	"""

# field `column` of line `row` (both from 0) of a table written as text, '|' between the fields:
# the reports' tables, a text in the image instead of lists built at the start
fn tableField(table str, row i64, column i64) str:
	line = textLine(table, row + 1) ?? ""
	at = 0
	loop column:
		at = byteIndex(line, 124, at) + 1   # past the next '|'
	end = byteIndex(line, 124, at)
	line[at..(len if end < 0 else end)].copy()

# The errors a program stops with by the name a test gives them (`test "name" expects
# RuntimeError.IndexOutOfBounds:`), each with the code its report shows (error[code]); Failure's
# message follows its code in the report
pub fn runtimeErrors() (str, str)[]:
	[
		("IndexOutOfBounds", "index-out-of-bounds"),
		("DivisionByZero", "division-by-zero"),
		("IntegerOverflow", "integer-overflow"),
		("ShiftOutOfRange", "shift-out-of-range"),
		("RangeStep", "range-step"),
		("StackOverflow", "stack-overflow"),
		("AccessViolation", "access-violation"),
		("Crash", "crash"),
		("Failure", "failure")]

# where a Zap executable is loaded: it has no relocations, so it is never moved (0x140000000)
pub imageBase = 5_368_709_120

# A check failed: the compiler's stub called this with the kind; the stub's caller is the
# failing expression's exit, which names its place.
fn failAt(kind i64):
	stopWith(
		tableField(failTable, kind, 0),
		tableField(failTable, kind, 1),
		callsFrom(__returnAddress(), 1)
	)

# stops the program on a bug with the message, its place and the calls that led there (exit
# code 3): not an expected error, which a result gives, nor an answer to the caller (exit)
pub fn fail(msg str):
	stopWith("failure", msg, callsFrom(__returnAddress(), 0))

# the stop of an extern fn that cannot be called, its message the NUL-ended text at the address
# (the stub of arm64 calls it, compiler/targets/ccall.zap)
fn externMissing(message i64):
	fail(str(cBytes(message)))

# ZAP_RUN's errors word: a function, as a program may stop before its module variables are set
pub fn errorsWord() TraceWord:
	TraceWord("errors", "json: errors, the compiler's and a stopped program's, as JSON lines")

# The report, then the end (exit code 3). `stack` is the failing place, then the calls that led
# there (callsFrom, crashStack).
fn stopWith(code str, message str, stack i64[]):
	flushStdout()
	json = (errorsWord().value() ?? "") == "json"
	report u8[] = []
	places = placesOf(stack)
	if json:
		jsonReport(report, code, message, places)
	else:
		humanReport(report, code, message, places)
	writeRaw(stderrHandle, report)
	ExitProcess(3)

# ---------- the stack ----------

# a CONTEXT (the registers of a thread): its size and where it keeps rsp and rip
contextSize = 1232
contextRsp = 152
contextRip = 248

# room for the registers of a thread: pages of its own (16-byte aligned), not the heap a crash
# may have broken
fn newContext() i64:
	allocPages(4096)

# The return addresses on the stack after `ret` (one of them: a function's __returnAddress()),
# `up` of them skipped first, into frames (room for `room`): their count. It allocates
# nothing, for the leak notes' walk inside the allocator.
fn returnsAfter(ret i64, up i64, frames i64, room i64) i64:
	n = i64(RtlCaptureStackBackTrace(0, u32(room), frames, 0))
	i = 0
	while i < n and __ld64(frames + i * 8) != ret:
		i += 1
	from = (i + up).min(n)
	__memcpy(frames, frames + from * 8, (n - from) * 8)
	n - from

# the calls on the stack, nearest first, from the one returning to `ret`, `up` calls further
fn callsFrom(ret i64, up i64) i64[]:
	room = 128
	frames = allocPages(room * 8)
	n = returnsAfter(ret, up, frames, room)
	places = (0..n).map(__ld64(frames + it * 8) - 1)
	if places.first is at and functionAt(at) < 0:
		return [at]   # a call from the start's code (the program's top level): no function's
	programCalls(places)

# the places on the stack of a crash, from its context (which the walk changes): the
# instruction at fault, then the calls that led there
fn crashStack(context i64) i64[]:
	at i64[] = [__ld64(context + contextRip)]
	exact = true
	while at.len < 128 and unwind(context, exact):
		at.push(__ld64(context + contextRip) - 1)
		exact = false
	programCalls(at)

# the program's own places among addresses on the stack, up to 48: the system's before the
# program's left out (a crash inside an extern fn), the walk ending at the first after them
fn programCalls(at i64[]) i64[]:
	stack i64[] = []
	for a in at:
		if stack.len == 48: break
		if functionAt(a) >= 0:
			stack.push(a)
		elif not stack.isEmpty:
			break
	stack

# The context one call up, its function's unwind information read by the system: false when
# its code has none (the start's) or the stack ends there. `exact` when the context's rip is the
# instruction itself (a fault), not a return address (which may be the next function's start).
fn unwind(context i64, exact bool) bool:
	pc = __ld64(context + contextRip)
	sp = __ld64(context + contextRsp)
	base i64 = 0
	entry = RtlLookupFunctionEntry(pc if exact else pc - 1, out base, 0)
	if entry == 0:
		if not exact: return false
		# a function of the system that keeps no frame: its return address on top
		__st64(context + contextRip, __ld64(sp))
		__st64(context + contextRsp, sp + 8)
	else:
		_ = RtlVirtualUnwind(0, base, pc, entry, context, out _, out _, 0)
	__ld64(context + contextRip) != 0 and __ld64(context + contextRsp) > sp

# ---------- the table ----------

fn word(at i64) i64:
	__ld32(at)

# the index of the function whose code holds the address, or -1 (outside the program's code)
fn functionAt(addr i64) i64:
	t = debugTable()
	if t == 0 or word(t) != 1_195_525_210: return -1
	rva = addr - imageBase
	if rva >= word(t + 16): return -1
	lastStartAtOrBefore(word(t + 4), rva, functionStart)

# the index of the last of n ascending starts at or before x (start(k) is the k-th), or -1 before
# the first: the function, line or block that holds an address
pub fn lastStartAtOrBefore(n i64, x i64, start fn(i64) i64) i64:
	if n == 0 or x < start(0): return -1
	lo = 0
	hi = n
	while hi - lo > 1:
		mid = (lo + hi) / 2
		if start(mid) <= x:
			lo = mid
		else:
			hi = mid
	lo

# where the f-th function's entry is: its first byte's rva, its name's offset
fn functionEntry(f i64) i64:
	debugTable() + 20 + f * 8

# where the l-th line entry is, after the functions': its first byte's rva, line, column, file
# (the entry past the last is the table of files)
fn lineEntry(l i64) i64:
	functionEntry(word(debugTable() + 4)) + l * 16

fn functionName(f i64) str:
	cString(debugTable() + word(functionEntry(f) + 4))

fn functionStart(f i64) i64:
	word(functionEntry(f))

# the line entry (index) that holds the address, or -1
fn lineAt(addr i64) i64:
	lastStartAtOrBefore(word(debugTable() + 8), addr - imageBase, lineStart)

fn lineStart(l i64) i64:
	word(lineEntry(l))

fn cString(p i64) str:
	bytes = cBytes(p)
	str(move bytes)

# A place in the source: the function, the file, the line and column (0 when unknown).
type Place:
	function str
	file str
	line i64
	col i64
	times i64   # the same place this many times in a row (a recursion)

fn placeOf(addr i64) Place:
	f = functionAt(addr)
	if f < 0: return Place(function = "?", file = "", line = 0, col = 0, times = 1)
	p = Place(function = functionName(f), file = "", line = 0, col = 0, times = 1)
	l = lineAt(addr)
	# a line note before the function's first byte belongs to another function
	if l >= 0 and word(lineEntry(l)) >= functionStart(f):
		e = lineEntry(l)
		p.line = word(e + 4)
		p.col = word(e + 8)
		t = debugTable()
		files = lineEntry(word(t + 8))
		p.file = cString(t + word(files + word(e + 12) * 4))
	p

# the places of the stack, the program's own: the runtime's report and the start code left out
fn placesOf(stack i64[]) Place[]:
	out Place[] = []
	for addr in stack:
		p = placeOf(addr)
		if p.function.startsWith("$"): break
		n = out.len
		if n > 1 and out[n - 1].function == p.function and out[n - 1].line == p.line and
			out[n - 1].col == p.col and out[n - 1].file == p.file:
			out[n - 1].times += 1
			continue
		out.push(p)
	out

# ---------- the reports ----------

fn humanReport(mut out u8[], code str, message str, places Place[]):
	outStr(out, "zap: error[{code}]: {message}\n")
	for i, p in places:
		outStr(out, "  at " if i == 0 else "  called from ")
		outStr(out, p.function)
		if p.file != "":
			outStr(out, " ({p.file}:{p.line}:{p.col})")
		if p.times > 1:
			outStr(out, " [{p.times} times in a row]")
		out.push('\n')
		if i == 0 and p.line > 0:
			outStr(out, caretLines(sourceLine(p), p.line, p.col))
	if places.isEmpty:
		outStr(out, "  (no place known: the program was built without its table)\n")

# Line `line` of a source shown as the reports show it (the compiler's too): its number and
# text, then a caret under column col (the line's tabs kept, so that the caret lines up);
# nothing for a line that cannot be read
pub fn caretLines(source str, line i64, col i64) str:
	if source == "": return ""
	number = str(line)
	out u8[] = []
	outStr(out, "   {number} | {source}\n   ")
	loop number.len:
		out.push(' ')
	outStr(out, " | ")
	for k in 0..col - 1:
		out.push('\t' if k < source.len and source[k] == '\t' else ' ')
	outStr(out, "^\n")
	str(move out)

# line `line` (from 1) of a text without its line break, or none past its end
pub fn textLine(text str, line i64) str?:
	n = 1
	for l in text.lines():
		if n == line: return l.copy()
		n += 1
	none

fn jsonReport(mut out u8[], code str, message str, places Place[]):
	outStr(out, "\{\"error\":")
	outQuoted(out, code)
	outStr(out, ",\"message\":")
	outQuoted(out, message)
	if places.first is p:
		outStr(out, ",")
		jsonPlace(out, p)
		outStr(out, ",\"function\":")
		outQuoted(out, p.function)
		line = sourceLine(p)
		if line != "":
			outStr(out, ",\"source\":")
			outQuoted(out, line)
	outStr(out, ",\"stack\":[")
	for i, p in places:
		outStr(out, ",\{\"function\":" if i > 0 else "\{\"function\":")
		outQuoted(out, p.function)
		outStr(out, ",")
		jsonPlace(out, p)
		outStr(out, ",\"times\":{p.times}}")
	outStr(out, "]}\n")

# a place's "file", "line" and "col" members
fn jsonPlace(mut out u8[], p Place):
	outStr(out, "\"file\":")
	outQuoted(out, p.file)
	outStr(out, ",\"line\":{p.line},\"col\":{p.col}")

# the line of the source a place names, "" when its file cannot be read
fn sourceLine(p Place) str:
	if p.line <= 0: return ""
	textLine(readFile(p.file) ?? "", p.line) ?? ""

fn hex(v i64) str:
	"0x{u64(v):x}"

# ---------- crashes ----------

# The program's crashes (a bad memory access, a stack overflow) reported like its errors. The
# system calls this handler for every exception first, before any handler found by unwinding
# the stack; it takes only the fatal ones raised by the program's own code, and lets the rest go
# on (a driver that raises and handles its own). Set up when the runtime starts
# (crashFilterSet), with room kept on the stack for the report when the stack itself overflowed.
# An access to a page a touch commits (sys.zap, touchPages) is no crash: the page is committed
# and the access runs again (EXCEPTION_CONTINUE_EXECUTION).
fn crashFilter(info i64) i64:
	record = __ld64(info)
	code = __ld32(record)
	kind = crashRow(code)
	if kind == 0 and touchCommit(__ld64(record + 40)): return -1
	if kind < 0:
		return 0   # not fatal: EXCEPTION_CONTINUE_SEARCH
	# a copy: the walk changes it, and the system keeps the original when the program goes on
	context = newContext()
	__memcpy(context, __ld64(info + 8), contextSize)
	# in a function of the system (an extern fn), the place is the program's call into it
	inside = " inside a function of the system the program called" if functionAt(
		__ld64(context + contextRip)
	) <
		0
		else ""
	stack = crashStack(context)
	if stack.isEmpty:
		return 0   # not the program's: let the system handle it
	name = tableField(crashTable, kind, 0)
	detail = ""
	if name == "access-violation":
		access = "writing" if __ld64(record + 32) == 1 else "reading"
		detail = " ({access} address {hex(__ld64(record + 40))})"
	elif name == "crash":
		detail = " (exception {hex(code)})"
	what = tableField(crashTable, kind, 1)
	why = tableField(crashTable, kind, 2)
	stopWith(name, "{what}{detail}{inside}{why}", stack)
	0

# the line of crashTable of the system's code, or -1 (the filter sees every exception, a
# driver's own included: it allocates nothing)
fn crashRow(code i64) i64:
	match code:
		3_221_225_477: 0
		3_221_225_725: 1
		3_221_225_620: 2
		3_221_225_501: 3
		_: -1

# The fatal exceptions, a line each: the report's code, what stopped, what most often causes it.
# An access's message names it, a crash's the exception.
crashTable = """
	access-violation|invalid memory access|: an extern fn given a bad pointer or size, or a bug of the compiler
	stack-overflow|stack overflow|: a recursion without end, or one too deep
	division-by-zero|integer division by zero|
	crash|the processor stopped the program|
	"""

fn setCrashFilter() bool:
	_ = AddVectoredExceptionHandler(1, crashFilter)
	room u32[] = [65_536]
	SetThreadStackGuarantee(room)

mut crashFilterSet = setCrashFilter()
