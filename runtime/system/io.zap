# Console input, files, dirs, processes, time and random for native programs. Buffers are
# u8[] values the system fills (see sys.zap); strings are built in a u8[] and
# become a str without a copy (str(move bytes)).

# ---------- stdin ----------

# The standard input, read as a stream: `stdin.line()`, `stdin.all()`, `stdin.text(n)`,
# `stdin.until(b)`.
pub type Input:
	handle i64

	# the next line of standard input without its line break; none at the end of the input. The
	# buffer is searched for the line break and the line copied a run at a time
	fn line() str?:
		if console.inEof or (console.inPos >= console.inLen and not stdinFill()): return none
		base = __ld64(__addr(console.inBuf)) + console.inPos
		first = byteIndex(__strof(base, console.inLen - console.inPos, 0), 10, 0)
		if first >= 0:
			# the whole line in the buffer (the usual case): one block, one copy
			n = first - 1 if first > 0 and __ld8(base + first - 1) == 13 else first
			out = strNew(n)
			__memcpy(sPtr(out), base, n)
			console.inPos += first + 1
			return out
		text u8[] = []
		loop:
			avail = __strof(
				__ld64(__addr(console.inBuf)) + console.inPos,
				console.inLen - console.inPos,
				0
			)
			at = byteIndex(avail, 10, 0)
			if at >= 0:
				text.reserve(text.len + at + 1)   # one block, the NUL's byte too (no growth step by step)
				text.extend(console.inBuf[console.inPos..console.inPos + at])
				console.inPos += at + 1
				break
			text.extend(console.inBuf[console.inPos..console.inLen])
			console.inPos = console.inLen
			if not stdinFill():
				break   # the input ends without a line break
		if text.len > 0 and text[len - 1] == '\r':
			_ = text.pop()
		str(move text)

	# standard input up to the byte b, left unread (the next read starts with it), or to its end;
	# none when it is already over. A FASTA record is `stdin.until('>')` after its header's line.
	# What the buffer holds is taken first; then the system reads straight into the text's room, a
	# megabyte at a time, and the bytes past b go back to the buffer.
	fn until(b u8) str?:
		if console.inEof or (console.inPos >= console.inLen and not stdinFill()): return none
		out u8[] = []
		avail = __strof(
			__ld64(__addr(console.inBuf)) + console.inPos,
			console.inLen - console.inPos,
			0
		)
		at = byteIndex(avail, i64(b), 0)
		if at >= 0:
			out.extend(console.inBuf[console.inPos..console.inPos + at])
			console.inPos += at
			return str(move out)
		out.extend(console.inBuf[console.inPos..console.inLen])
		console.inPos = console.inLen
		if console.inGiven:
			console.inEof = true   # a test's input ends where its text does
			return str(move out)
		flushStdout()   # a prompt must be visible before the wait
		loop:
			have = out.len
			chunk = 1_048_576   # (what follows b is copied back: a megabyte at most)
			out.reserve(have + chunk)
			room u8[] = []   # a window on the room past the text
			__st64(__addr(room), __ld64(__addr(out)) + have)
			__st64(__addr(room) + 8, chunk)
			got = readSome(stdinHandle, room, chunk)
			if got <= 0:
				console.inEof = true
				break
			found = byteIndex(__strof(__ld64(__addr(out)) + have, got, 0), i64(b), 0)
			if found >= 0:
				# the bytes from b on are the buffer's again
				console.inBuf = room[found..got].copy()
				console.inPos = 0
				console.inLen = got - found
				__st64(__addr(out) + 8, have + found)
				break
			__st64(__addr(out) + 8, have + got)
		str(move out)

	# n bytes of standard input as text (fewer when it ends first), or none when it is already over
	fn text(n i64) str?:
		out u8[] = []
		out.reserve(n)
		more = true
		while more and out.len < n:
			ch = stdinByte()
			if ch < 0:
				more = false
			else:
				out.push(u8(ch))
		if out.len == 0 and n > 0: return none
		str(move out)

	# The rest of standard input as one string: what the line buffer still holds, then the data.
	# When stdin is a file its size is known and the result's buffer is allocated once and read
	# into directly; a pipe is read 64 KB at a time into a growing buffer.
	fn all() str:
		if console.inGiven:
			rest = str(console.inBuf[console.inPos..console.inLen].copy())
			console.inPos = console.inLen
			console.inEof = true
			return rest
		flushStdout()
		h = handle
		held i64 = 0
		if not console.inEof and console.inPos < console.inLen:
			held = console.inLen - console.inPos
		known = fileSize(h)
		if known > 0 and held == 0:
			# a file: mapped, its pages faulted in on every processor at once (a page fault per
			# 4 KB, in parallel, costs less than the kernel's copy of the whole file); the text is
			# the view itself, never freed (a str that owns no block)
			mapping = CreateFileMappingA(h, 0, 2, 0, 0, 0)
			if mapping != 0:
				view = MapViewOfFile(mapping, 4, 0, 0, 0)
				if view != 0:
					parts = cpuCount()
					per = (known + parts - 1) / parts
					touched = (0..parts).parallel().map(k:
						lo = k * per
						hi = (lo + per).min(known)
						acc i64 = 0
						q = lo
						while q < hi:
							acc += __ld8(view + q)
							q += 4096
						acc
					)
					if touched.len > 0:
						console.inEof = true
						return __strof(view, known, 0)
		if known > 0:
			total = fileLeft(h) + held   # what the line buffer took is no longer in the file
			buf = zeroBytes(total)
			for i in 0..held:
				buf[i] = console.inBuf[console.inPos + i]
			console.inPos = console.inLen
			n = held
			if not console.inEof:
				n = readFully(h, buf, held)
				console.inEof = n < total
			buf.truncate(n)
			return str(move buf)
		buf u8[] = []
		if held > 0:
			buf.extend(console.inBuf[console.inPos..console.inLen])
			console.inPos = console.inLen
		if not console.inEof:
			readRest(h, buf)
			console.inEof = true
		str(move buf)

# the program's standard input
pub stdin = Input(handle = stdinHandle)

fn stdinFill() bool:
	if console.inGiven:
		console.inEof = true   # a test's input ends where its text does
		return false
	flushStdout()   # a prompt must be visible before the wait
	if console.inBuf.len == 0:
		console.inBuf = zeroBytes(stdinBufSize)
	got = readSome(stdinHandle, console.inBuf, stdinBufSize)
	if got <= 0:
		console.inEof = true
		return false
	console.inLen = got
	console.inPos = 0
	true

fn stdinByte() i64:
	if console.inEof: return -1
	if console.inPos >= console.inLen:
		if not stdinFill(): return -1
	b = console.inBuf[console.inPos]
	console.inPos += 1
	i64(b)

# ---------- process ----------

# the program's arguments, what a program reads as `args`: the command line's, or those a test
# gives the rest of itself (args.set)
pub mut programArgs = commandLine()

# the command line the program was started with, split, without the program name
fn commandLine() str[]:
	words = commandWords(cBytes(GetCommandLineA()))
	words[1..].copy()

# A command line split into its words by Windows' rules, which a Process's line follows on
# every system: spaces part them, double quotes group, backslashes escape a quote
fn commandWords(cmd u8[]) str[]:
	r str[] = []
	n = cmd.len
	i i64 = 0
	arg u8[] = []
	while i < n:
		while i < n and (cmd[i] == ' ' or cmd[i] == '\t'):
			i += 1
		if i >= n: return r
		inQuote = false
		going = true
		while going and i < n:
			ch = cmd[i]
			if ch == '\\':
				k i64 = 0
				while i < n and cmd[i] == '\\':
					k += 1
					i += 1
				if i < n and cmd[i] == '"':
					h = k / 2
					while h > 0:
						arg.push('\\')
						h -= 1
					if k % 2 == 1:
						arg.push('"')
						i += 1
				else:
					while k > 0:
						arg.push('\\')
						k -= 1
			elif ch == '"':
				inQuote = not inQuote
				i += 1
			elif not inQuote and (ch == ' ' or ch == '\t'):
				going = false
			else:
				arg.push(ch)
				i += 1
		r.push(str(move arg))   # leaves arg empty for the next argument
	r

# the path of the running executable
pub fn exePath() str:
	buf = zeroBytes(4096)
	n = GetModuleFileNameA(0, buf, 4095)
	buf.truncate(i64(n))
	str(move buf)

# the ending of an executable's file name where the program runs: ".exe" on Windows, "" on Linux
# (`"build/game{exeSuffix()}"`)
pub fn exeSuffix() str:
	".exe"

# what parts the dirs of a list of paths (PATH's) where the program runs: ";" on Windows, ":" on
# Linux
pub fn pathListSeparator() str:
	";"

# the working directory, as the system writes it (C:\dir\sub)
pub fn currentDir() str:
	buf = zeroBytes(4096)
	n = GetCurrentDirectoryA(4095, buf)
	buf.truncate(i64(n))
	str(move buf)

# The environment variables of the process, read and written as a map: `env["PATH"]` (stops when
# it is not set), `env.get("HOME")` (none when it is not set), `env["X"] = v` (for this program
# and the ones it starts).
pub type Environment:
	block i64 = 0   # the system holds the variables: the value names nothing of its own

	# the value of an environment variable; none when it is not set
	fn get(name str) str?:
		key = cstr(name)
		room = 256
		buf = zeroBytes(room)
		n = i64(GetEnvironmentVariableA(key, buf, room))
		if n >= room:   # too small: n is the room the value and its NUL need
			room = n
			buf = zeroBytes(room)
			n = i64(GetEnvironmentVariableA(key, buf, room))
		if n == 0 or n >= room: return none
		buf.truncate(n)
		str(move buf)

	# env[name]: the value of an environment variable; the program stops when it is not set
	fn index(name str) str:
		get(name) ?? fail("the environment variable {name} is not set")

	# env[name] = value: sets it for this program and the ones it starts
	fn set(name str, value str):
		if not SetEnvironmentVariableA(cstr(name), cstr(value)):
			fail("the environment variable {name} cannot be set")
		if name == runVariable().name and gv(slotTrace) != 0:
			freePages(gv(slotTrace))
			gset(slotTrace, 0)   # read again when next asked

# the environment variables of this process
pub env = Environment()

# An environment variable a program reads, declared once with what it does, as what a function
# gives (`fn runVariable() EnvVariable: EnvVariable("ZAP_RUN", "...")`), which may be read before
# the module variables are set: `zap doc environment` lists the declarations of the runtime, std,
# the compiler and the dependencies.
pub type EnvVariable:
	name str
	about str   # one line: what setting it does

	# its value; none when it is not set
	fn value() str?:
		env.get(name)

# A word of ZAP_RUN naming a diagnostic asked for (`profile`, `disasm=main`), declared as an
# EnvVariable is: a build refuses a word no declaration of the program or the compiler names.
pub type TraceWord:
	name str
	about str   # one line: what the word makes the program or the compiler say

	# whether ZAP_RUN holds the word, alone or as `word=value`
	fn on() bool:
		value() != none

	# the value ZAP_RUN gives the word: `profile=main` gives "main", `profile` alone "", none without it
	fn value() str?:
		wordIn(runText(), name)

# A word of ZAP_RUN naming how a program runs (`headless`, `gpu=d3d12`, `audio=off`), declared and
# read as a TraceWord is.
pub type RunWord:
	name str
	about str   # one line: what the word makes the program do

	# whether ZAP_RUN holds the word, alone or as `word=value`
	fn on() bool:
		value() != none

	# the value ZAP_RUN gives the word, none without it
	fn value() str?:
		wordIn(runText(), name)

# A word of ZAP_SETUP, the comma-separated list of what is set once on a machine (`arm64=host`,
# `memory=2048`), declared and read as a TraceWord is.
pub type SetupWord:
	name str
	about str   # one line: what the word tells about the machine

	# whether ZAP_SETUP holds the word, alone or as `word=value`
	fn on() bool:
		value() != none

	# the value ZAP_SETUP gives the word, none without it
	fn value() str?:
		wordIn(setupVariable().value() ?? "", name)

# A variable zap sets for the programs it starts, which no one sets: read as an EnvVariable is,
# but left out of `zap doc environment`.
pub type InternalVariable:
	name str

	# its value; none when it is not set
	fn value() str?:
		env.get(name)

# the value a comma-separated list of words gives one: `profile=main` gives "main", `profile`
# alone "", none without it
pub fn wordIn(words str, name str) str?:
	at = 0
	while at < words.len:
		end = byteIndex(words, 44, at)   # the next ','
		if end < 0: end = words.len
		item = words[at..end]
		if item == name: return ""
		if item.len > name.len and item[name.len] == '=' and item[..name.len] == name:
			return item[name.len + 1..].copy()
		at = end + 1
	none

pub fn runVariable() EnvVariable:
	EnvVariable("ZAP_RUN", "what one run asks for: words, word=value (gpu=d3d12, profile=main)")

pub fn setupVariable() EnvVariable:
	EnvVariable(
		"ZAP_SETUP",
		"what a machine sets once: words, word=value (arm64=host, memory=2048)"
	)

# an engine program with no one at the screen (no window, drawn offscreen, no real input), as a
# scripted run is; zap test sets it for everything it starts
pub fn headlessWord() RunWord:
	RunWord("headless", "no window, drawn offscreen, no real input, as a scripted run does")

# ZAP_RUN's text with the words first, so they are the ones read: what a test or a script gives
# the programs it starts, the user's words kept
pub fn runWith(words str) str:
	given = runVariable().value() ?? ""
	words.copy() if given == "" else "{words},{given}"

# the assignment ("ZAP_RUN=words") of runWith, for the variables a program is started with
pub fn runAssignment(words str) str:
	"{runVariable().name}={runWith(words)}"

# ZAP_RUN's text, read once into pages of its own, read again after env sets it
fn runText() str:
	if gv(slotTrace) == 0:
		gset(slotTrace, textPages(runVariable().value() ?? ""))
	pagesText(gv(slotTrace))

# a text copied into pages of its own ([length][bytes]: not the heap's, so no leak report lists
# it), which may be read before the module variables are set
fn textPages(text str) i64:
	p = allocPages(8 + text.len)
	__st64(p, text.len)
	__memcpy(p + 8, sPtr(text), text.len)
	p

fn pagesText(p i64) str:
	__strof(p + 8, __ld64(p), 0)

# appends to buf what h gives until it ends (a pipe's end: when every writer has closed it)
fn readRest(h i64, mut buf u8[]):
	chunk = zeroBytes(stdinBufSize)
	loop:
		got = readSome(h, chunk, stdinBufSize)
		if got <= 0: return
		buf.extend(chunk[..got])

# The variables ("NAME=value") with each name kept once, its latest value (a later one
# overrides); Windows' own "=C:=C:\dir" keep the "=" their name starts with
fn latestVariables(all str[]) str[]:
	kept str[] = []
	for i, v in all:
		name = v[..(v.indexOf("=", 1) ?? len)]
		if not all[i + 1..].any(it.startsWith("{name}=")):
			kept.push(v.copy())
	kept

# reads from h into buf from index `start` until buf is full or the data ends; how many bytes
# of buf hold data then
fn readFully(h i64, buf u8[], start i64) i64:
	total = buf.len
	n = start
	while n < total:
		got = readSome(h, buf[n..total], total - n)
		if got <= 0: return n
		n += got
	n

# an existing file opened for reading (GENERIC_READ, OPEN_EXISTING), or -1, shared for reading and
# writing: a file another process is writing is read as far as it is written; its path added to
# the file of the paths read
fn openForRead(path str) i64:
	to = readsFile()
	if to != "":
		_ = appendFile(to, "{path}\n")
	CreateFileA(cstr(path), -2_147_483_648, 3, 0, 3, 128, 0)

# a file every Zap program adds each path it reads to, a line each (zap test's: what a pass rests on)
pub fn pathsReadVariable() InternalVariable:
	InternalVariable("ZAP_READS")

# the file the paths read are added to, "" for none: ZAP_READS's, read once into pages of its own
# (slotReads, as traceText)
fn readsFile() str:
	if gv(slotReads) == 0:
		gset(slotReads, textPages(pathsReadVariable().value() ?? ""))
	pagesText(gv(slotReads))

# The paths read from now on added to the file, a line each ("" for none): a program that does
# several jobs in turn tells each one's reads apart (zap test's checks).
pub fn noteReadsTo(file str):
	if gv(slotReads) != 0:
		freePages(gv(slotReads))
	gset(slotReads, textPages(file))

# The file functions fail with the system's error code (GetLastError), which std's fs names.

# the code of the system's last failed call
fn systemError() i64:
	GetLastError()

# the system's code for a file that ends before the bytes asked for (ERROR_HANDLE_EOF)
endOfFileError = 38

# the whole text of a file
fn readFile(path str) str ? i64:
	h = openForRead(path)
	if h == -1: return systemError()
	size = fileSize(h)
	buf = zeroBytes(size)
	n = readFully(h, buf, 0)
	if size == 0:
		readRest(h, buf)   # a file the system tells no size of (Linux's /proc) read to its end
	CloseHandle(h)
	if n < size: return endOfFileError
	str(move buf)

# writes the bytes to a file, replacing what it held, or adds them at its end (append), creating
# it if needed
fn writeBytes(path str, bytes u8[], append bool = false) ? i64:
	# FILE_APPEND_DATA and OPEN_ALWAYS, or GENERIC_WRITE and CREATE_ALWAYS
	access i64 = 4 if append else 1_073_741_824
	disp i64 = 4 if append else 2
	h = CreateFileA(cstr(path), access, 1, 0, disp, 128, 0)
	if h == -1: return systemError()
	writeRaw(h, bytes)
	_ = CloseHandle(h)

# writes the text to a file, replacing what it held
fn writeFile(path str, text str) ? i64:
	try writeBytes(path, text.bytes())

# adds the text at the end of a file, creating it if needed
fn appendFile(path str, text str) ? i64:
	try writeBytes(path, text.bytes(), append = true)

# when the file or dir was last written, in the system's ticks (100 ns since 1601); none when
# it cannot be read (systemError() says why)
fn modifiedAt(path str) i64?:
	info = zeroBytes(36)   # WIN32_FILE_ATTRIBUTE_DATA
	if not GetFileAttributesExA(cstr(path), 0, info): return none
	i64(info.u64le(20))   # ftLastWriteTime

# whether a file or dir exists at the path
fn fileExists(path str) bool:
	GetFileAttributesA(cstr(path)) != -1   # INVALID_FILE_ATTRIBUTES when there is none

# removes the file
fn deleteFile(path str) ? i64:
	if DeleteFileA(cstr(path)): return
	return systemError()

# moves the file to the other path, replacing what is there whole: a program reading `to`
# meanwhile reads the old file or the new one, never part of one
fn moveFile(from str, to str) ? i64:
	if MoveFileExA(cstr(from), cstr(to), 1): return   # MOVEFILE_REPLACE_EXISTING
	return systemError()

# removes a dir with what it holds, or a file (one that is not there counts as removed); the
# error is the first part that could not be removed
fn deleteTree(path str) ? i64:
	at = path[..len - 1].copy() if path.endsWith("/") else path.copy()
	attributes = GetFileAttributesA(cstr(at))
	if attributes == -1: return
	if attributes & 16 == 0: return deleteFile(at)   # FILE_ATTRIBUTE_DIRECTORY
	for name in listDir(at) ?? []:
		try deleteTree("{at}/{name}")
	if not RemoveDirectoryA(cstr(at)): return systemError()

# creates a dir and the dirs above it that are missing (an existing dir counts as
# created)
fn createDir(path str) ? i64:
	if CreateDirectoryA(cstr(path), 0) or fileExists(path): return
	# a missing dir above it is made first
	cut = path.lastIndexOf("/") ?? (path.lastIndexOf("\\") ?? 0)
	if cut <= 0: return systemError()
	try createDir(path[..cut])
	if CreateDirectoryA(cstr(path), 0) or fileExists(path): return
	return systemError()

# whether the path names a Zap source: a .zap file, or a .zapx one (Zap with markup in it)
pub fn isSourceFile(path str) bool:
	path.endsWith(".zap") or path.endsWith(".zapx")

# The Zap sources under a dir (or the one file a path naming a source names), in order, its
# dirs walked; a dir named build, node_modules or top is skipped (output, packages, other
# languages' sources). With `programs`, a dir holding a main.zap counts as that one file: a
# program of several files.
fn zapFiles(path str, programs bool) str[]:
	out str[] = []
	if isSourceFile(path):
		out.push(path.copy())
		return out
	for name in (listDir(path) ?? []).sorted():
		full = name.copy() if path == "." else path + "/" + name   # "." names its files as they are
		if isSourceFile(name):
			out.push(full)
		elif programs and fileExists(full + "/main.zap"):
			out.push(full + "/main.zap")
		elif not name.contains(".") and name != "build" and name != "node_modules" and
			name != "top":
			out.extend(zapFiles(full, programs))
	out

# names in a dir (no "." and "..")
fn listDir(path str) str[] ? i64:
	r str[] = []
	info = zeroBytes(600)   # a WIN32_FIND_DATAA: the name at byte 44
	h = FindFirstFileA(cstr(path + "/*"), info)
	if h == -1: return systemError()
	going = true
	while going:
		n i64 = 0
		while info[44 + n] != 0:
			n += 1
		if not (n == 1 and info[44] == '.') and
			not (n == 2 and info[44] == '.' and info[45] == '.'):
			r.push(str(info[44..44 + n]))
		if not FindNextFileA(h, info):
			going = false
	FindClose(h)
	r

# A process started from a command line: `p = Process.start("git status")`, then `p.isDone`
# (whether it ended) and `p.wait()` (its exit code, kept in `p.code`); `Process.run(cmd)` starts
# one and waits for it; `Process.output(cmd)` runs one to its end and keeps what it wrote in `out`.
pub type Process:
	handle i64   # -1: it could not start
	code i64 = -1   # the exit code, once waited for; -1 before, or when it never started
	out str = ""   # Process.output's: what it wrote to stdout and stderr, in the order written

	# whether the process has ended (wait then gives its exit code at once)
	fn isDone() bool:
		processDone(self)

	# waits for the process to end; its exit code (kept in code), -1 when it never started
	mut fn wait() i64:
		processWait(self)

	# waits for the process to end, ms milliseconds at most: its exit code, or none while it still
	# runs (a wait that may never end, for a peer that never came, has a limit)
	mut fn waitWithin(ms i64) i64?:
		since = clockMs()
		while not self.isDone:
			if clockMs() - since >= ms: return none
			sleepMs(1)
		wait()

# Process's isDone and wait on Windows, functions a system's files replace (linux/process.zap)
fn processDone(p Process) bool:
	p.handle == -1 or p.code != -1 or WaitForSingleObject(p.handle, 0) == 0

fn processWait(mut p Process) i64:
	if p.handle == -1 or p.code != -1: return p.code
	WaitForSingleObject(p.handle, -1)
	p.code = exitCodeOf(p.handle)
	CloseHandle(p.handle)
	p.code

# cmd with its program's path written with backslashes: Windows finds no program named with `/`
# (`build/game.exe`); the arguments stay as written
fn windowsProgram(cmd str) str:
	quoted = cmd.startsWith("\"")
	end = (cmd.indexOf("\"", 1) ?? cmd.len) if quoted else cmd.indexOf(" ") ?? cmd.len
	"{cmd[..end].replace("/", "\\")}{cmd[end..]}"

# Process.start(cmd): the command line started, not waited for (handle -1 when it cannot start)
pub fn processStart(cmd str) Process:
	flushStdout()   # our output stays ahead of the child's
	si = zeroBytes(104)   # a STARTUPINFOA: cb = 104
	si[0] = 104
	procInfo = zeroBytes(24)   # a PROCESS_INFORMATION: hProcess, hThread
	started = CreateProcessA(0, cstr(windowsProgram(cmd)), 0, 0, true, 0, 0, 0, si, procInfo)
	if not started: return Process(handle = -1)
	CloseHandle(i64(procInfo.loadWord(8)))
	Process(handle = i64(procInfo.loadWord(0)))

# Process.run(cmd): the command line run and waited for; its exit code, -1 when it cannot start
pub fn processRun(cmd str) i64:
	p = processStart(cmd)
	p.wait()

# The command line that runs line in the shell of the system the program runs on, for what only
# a shell does (redirections, pipelines, a variable set for one line): Windows' cmd, or Linux's sh,
# which Process.start starts there
pub fn shellLine(line str) str:
	"cmd /c \"{line}\""

# an argument of a command line in double quotes, which group it in cmd's lines and sh's
pub fn quoteArg(s str) str:
	"\"{s.replace("\"", "\\\"")}\""

# a shell line (shellLine's) with a variable set for it alone
pub fn withVariable(name str, value str, line str) str:
	"set {name}={value}&& {line}" if onWindows() else "{name}={quoteArg(value)} {line}"

# a shell line with the variables ("NAME=value") set for it alone
pub fn withVariables(vars str[], line str) str:
	out = line.copy()
	for v in vars:
		at = v.indexOf("=") ?? v.len
		out = withVariable(v[..at], v[(at + 1).min(len)..], out)
	out

# Process.output(cmd): the program run to its end with no shell between, the line split into its
# words (commandWords) and the program found on the PATH (or named from here); its stdin is
# `input`, `vars` ("NAME=value") are set for it alone, it runs in `dir` ("": here), and what it
# writes to stdout and stderr, one stream in the order written, is kept in `out` (`p.code` its
# exit code, -1 when it cannot start)
pub fn processOutput(cmd str, input str = "", vars str[] = [], dir str = "") Process:
	flushStdout()
	inOurs, inTheirs = childPipe(false, input.len + 1)
	writeRaw(inOurs, input.bytes())   # the pipe holds it all: written before the program starts
	CloseHandle(inOurs)
	outOurs, outTheirs = childPipe(true, 65_536)
	si = zeroBytes(104)   # a STARTUPINFOA: cb = 104, STARTF_USESTDHANDLES, the three handles
	si[0] = 104
	si.setU32le(60, 256)
	si.setU64le(80, u64(inTheirs))
	si.setU64le(88, u64(outTheirs))
	si.setU64le(96, u64(outTheirs))
	all = processVariables() if not vars.isEmpty else []
	all.extend(vars)
	block = "" if vars.isEmpty else "{latestVariables(all).join("\0")}\0\0"
	envBlock = 0 if vars.isEmpty else sPtr(block)   # 0: the program gets this one's
	there = "{dir}\0"
	procInfo = zeroBytes(24)
	started = CreateProcessA(
		0,
		cstr(windowsProgram(cmd)),
		0,
		0,
		true,
		0,
		envBlock,
		0 if dir == "" else sPtr(there),
		si,
		procInfo
	)
	CloseHandle(inTheirs)
	CloseHandle(outTheirs)   # the pipe ends when the program and its children close theirs
	p = Process(handle = -1)
	if started:
		CloseHandle(i64(procInfo.loadWord(8)))
		p.handle = i64(procInfo.loadWord(0))
	text u8[] = []
	readRest(outOurs, text)
	CloseHandle(outOurs)
	p.out = str(move text)
	_ = p.wait()
	p

# A pipe whose one end a started process inherits: (ours, its), its end the write end when the
# process writes into it; size the bytes it holds before a write waits
fn childPipe(childWrites bool, size i64) (i64, i64):
	_ = CreatePipe(out readEnd, out writeEnd, 0, size)
	ours = writeEnd if not childWrites else readEnd
	theirs = writeEnd if childWrites else readEnd
	_ = SetHandleInformation(theirs, 1, 1)   # HANDLE_FLAG_INHERIT
	(ours, theirs)

# the environment variables of this process, "NAME=value" each
fn processVariables() str[]:
	all str[] = []
	block = GetEnvironmentStringsA()
	at = block
	while __ld8(at) != 0:
		v = str(cBytes(at))
		at += v.len + 1
		all.push(v)
	_ = FreeEnvironmentStringsA(block)
	all

# ---------- time and random ----------

# milliseconds from a fixed point (the processor's counter): the difference of two readings is
# the time between them, which changes to the clock do not move
pub fn clockMs() i64:
	counterNow() * 1000 / counterFrequency()

# seconds from the same fixed point as clockMs, to the counter's precision (well under a
# microsecond): the clock of frame times and measurements
pub fn clockSeconds() f64:
	f64(counterNow()) / f64(counterFrequency())

# waits that many milliseconds, the processor given to the other threads
pub fn sleepMs(ms i64):
	if ms > 0:
		Sleep(ms)

# A sequence of random numbers that repeats for its seed (xorshift64*): `rng = Random(seed)`,
# then `rng.next(0..10)`, `rng.next(1..=6)`, `rng.next(0.0..1.0)`. `random(range)` draws from
# the program's own sequence.
pub type Random:
	state i64

	# the next 64 random bits
	mut fn nextBits() u64:
		x = u64(randomStart if state == 0 else state)
		x ^= x >> 12
		x ^= x << 25
		x ^= x >> 27
		state = i64(x)
		x * 2_685_821_657_736_338_717

	# rng.next(lo..hi) of integers: one of [lo, hi); the program stops when the range is empty
	mut fn nextInt(lo i64, hi i64) i64:
		if hi <= lo:
			fail("random from an empty range {lo}..{hi}")
		lo + i64((nextBits() >> 1) % u64(hi - lo))

	# rng.next(lo..hi) of floats: one of [lo, hi)
	mut fn nextFloat(lo f64, hi f64) f64:
		lo + (hi - lo) * (f64(i64(nextBits() >> 11)) / 9007199254740992.0)

# the state a seed of 0 starts from (xorshift never leaves 0)
randomStart i64 = -7_046_029_254_386_353_131

mut programRandom = Random(state = randomStart)

# random(lo..hi) of integers, from the program's sequence
fn randomIn(lo i64, hi i64) i64:
	programRandom.nextInt(lo, hi)

# random(lo..hi) of floats, from the program's sequence
fn randomFloatIn(lo f64, hi f64) f64:
	programRandom.nextFloat(lo, hi)

# ---------- streams ----------
# A Stream writes bytes somewhere: the console for now, files and sockets later. `write` and
# `writeBytes` add nothing; `print(value)`, the one way to write a line, formats any value and
# adds a newline (the compiler writes the formatting, like for `print`).

# the console's standard output or error
pub type Stream:
	handle i64

	# writes the text as it is, with no line break
	fn write(text str):
		writeToHandle(handle, text.bytes())

	# writes the bytes as they are
	fn writeBytes(b u8[]):
		writeToHandle(handle, b)

# the standard output as a stream (stdout.write(text), .print(value), .writeBytes)
pub stdout = Stream(handle = stdoutHandle)

# the standard error as a stream
pub stderr = Stream(handle = stderrHandle)

# stream.print(value): the formatted value and a newline
fn streamPrint(s Stream, text str):
	writeLineToHandle(s.handle, text)
