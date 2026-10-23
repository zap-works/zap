# The process the program runs in: its arguments, executable and working dir, the environment
# and the words of ZAP_RUN and ZAP_SETUP, the files it reads noted, and its clock.

# the program's arguments, what a program reads as `args`: the command line's, or those a test
# gives the rest of itself (args.set)
pub mut programArgs = commandLine()

# An option a program accepts: its name (`--iso`), whether a value follows it, and a line of help.
pub type ArgOption:
	name str
	takesValue bool
	help str

# the options the program declared (args.options, cli.zap), in the order given: the args' state
# a test starts again
mut declaredOptions ArgOption[] = []

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
		end = byteIndex(words, 44, at)   # the next ','\'
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
