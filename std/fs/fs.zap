# Files, dirs and paths: whole files read and written, dirs made and listed, a file read
# at any offset, and paths taken apart and joined (paths are str, '/' or '\' between parts).
# What fails gives an Error: `import fs`, then `text = try fs.readFile("a.txt")`,
# `fs.readFile(path) ?? ""`, fs.dirOf(path).

# why a file or a dir could not be read or written
pub type Error:
	NotFound   # nothing at the path, or a dir on the way is missing
	Denied   # the system refused: permissions, or another program holds the file
	Ended   # the file ends before the bytes asked for
	Failed(code i64)   # another reason: the system's error code

# the Error of a system error code
fn fsError(code i64) Error:
	match code:
		2, 3: .NotFound   # ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND
		5, 32, 33: .Denied   # ERROR_ACCESS_DENIED, ERROR_SHARING_VIOLATION, ERROR_LOCK_VIOLATION
		c and c == rt.endOfFileError: .Ended
		_: .Failed(code)

# ---------- whole files ----------

pub fn readFile(path str) str ? Error:
	rt.readFile(path) ?? return fsError(error)

# the whole file as bytes
pub fn readBytes(path str) u8[] ? Error:
	f = try open(path)
	f.readAt(0, f.len)

# replaces what the file held
pub fn writeFile(path str, text str) ? Error:
	if rt.writeFile(path, text) is error: return fsError(error)
	return

# creates the file if needed
pub fn appendFile(path str, text str) ? Error:
	if rt.appendFile(path, text) is error: return fsError(error)
	return

# replaces what the file held
pub fn writeBytes(path str, bytes u8[]) ? Error:
	if rt.writeBytes(path, bytes) is error: return fsError(error)
	return

# the file made one its owner may run as a program (Linux's mode 755; Windows runs any .exe):
# whether it can
pub fn canRun(path str) bool:
	_ = path
	true

# creates the file if needed
pub fn appendBytes(path str, bytes u8[]) ? Error:
	if rt.writeBytes(path, bytes, append = true) is error: return fsError(error)
	return

# when the file or dir was last written: a number that only grows as it is written again (the
# system's ticks of 100 ns), compared with an earlier one to reload what changed
pub fn modified(path str) i64 ? Error:
	rt.modifiedAt(path) ?? return fsError(rt.systemError())

# when each file and dir in a dir was last written (modified's ticks), by name: one listing,
# cheaper than modified of each when there are several
pub fn modifiedIn(dir str) {str: i64} ? Error:
	out {str: i64} = {}
	for (name, time) in rt.listDirTimes(dir) ?? return fsError(error):
		out[name.copy()] = time
	out

# a file or a dir
pub fn exists(path str) bool:
	rt.fileExists(path)

pub fn deleteFile(path str) ? Error:
	if rt.deleteFile(path) is error: return fsError(error)
	return

# moves the file to the other path, replacing what is there whole: what reads `to` meanwhile
# reads the old file or the new one, never part of one (a file written beside it, then moved)
pub fn moveFile(from str, to str) ? Error:
	if rt.moveFile(from, to) is error: return fsError(error)
	return

# Writes the bytes unless the file holds them already: whether it wrote. What a program prepares
# (generated sources, extracted assets) keeps its date when unchanged, so what reads it is not
# made again.
pub fn writeChanged(path str, bytes u8[]) bool ? Error:
	if (readBytes(path) ?? []) == bytes: return false
	try writeBytes(path, bytes)
	true

# The texts written into numbered files, `<stem>0<ext>`, `<stem>1<ext>` and on, `each` to a file
# after the header, each only where it changed; the numbered files past the last, left by more
# texts, deleted. How many files changed.
pub fn writeNumbered(stem str, ext str, header str, texts str[], each i64) i64 ? Error:
	written = 0
	file = 0
	at = 0
	while at < texts.len:
		part = "{header}{texts[at..(at + each).min(texts.len)].join("")}"
		if try writeChanged("{stem}{file}{ext}", part.bytes()): written += 1
		at += each
		file += 1
	while exists("{stem}{file}{ext}"):
		try deleteFile("{stem}{file}{ext}")
		written += 1
		file += 1
	written

# ---------- dirs ----------

# removes a dir with what it holds, or a file (one that is not there counts as removed)
pub fn deleteTree(path str) ? Error:
	if rt.deleteTree(path) is error: return fsError(error)
	return

# makes the missing dirs above it too; an existing dir counts as made
pub fn createDir(path str) ? Error:
	if rt.createDir(path) is error: return fsError(error)
	return

# the names in a dir (no "." and "..")
pub fn list(path str) str[] ? Error:
	rt.listDir(path) ?? return fsError(error)

# Every file under the dir, at any depth, depth first in name order, as its path from the dir joined
# with '/' (Python's `os.walk` and `Path.rglob`); with a `pattern`, only those whose name matches it
# (globMatches). A dir that cannot be read counts as empty. `.` names its files as they are.
# With `sources`, the Zap sources (.zap and .zapx) under a dir, or the one source file a path
# names: a dir named build, node_modules or top is skipped, and so is a dir under it that a
# `.gitignore` names, there or above it up to the repository's root (a line ending in `/`: the dir
# by its path from the file's dir, or any dir of that name when it has no other `/`): what a tool
# made is not the repository's source. With `programs` too, a dir holding a main.zap counts as
# that one file.
pub fn walk(dir str, pattern str = "", sources bool = false, programs bool = false) str[]:
	if sources and isSourceFile(dir): return [dir.copy()]
	out = []
	walkInto(dir, pattern, sources, programs, out)
	if not sources: return out
	start = normalize(join(rt.currentDir(), dir))
	ignored = ignoredDirs(start)
	if ignored.isEmpty: return out
	out.filter(f: not ignored.any(isUnder(normalize(join(rt.currentDir(), f)), it, start)))

fn walkInto(dir str, pattern str, sources bool, programs bool, mut out str[]):
	for name in (rt.listDir(dir) ?? []).sorted():
		full = name if dir == "." else join(dir, name)
		if sources:
			# a name without a dot is taken for a dir, not looked at: a look costs more than the walk
			if isSourceFile(name):
				if pattern == "" or globMatches(name, pattern): out.push(full)
			elif programs and rt.fileExists("{full}/main.zap"):
				out.push("{full}/main.zap")
			elif "." not in name and name != "build" and name != "node_modules" and
				name != "top":
				walkInto(full, pattern, sources, programs, out)
		elif rt.isDir(full):
			walkInto(full, pattern, sources, programs, out)
		elif pattern == "" or globMatches(name, pattern):
			out.push(full)

# whether the name matches the glob pattern: `*` stands for any run of bytes (none too), `?` for one
# byte, any other byte for itself (Python's `fnmatch`, without classes)
pub fn globMatches(name str, pattern str) bool:
	n = 0
	p = 0
	star = -1   # where the last `*` is in the pattern, and the name's place its run reaches
	mark = 0
	while n < name.len:
		if p < pattern.len and pattern[p] == '*':
			star = p
			mark = n
			p += 1
		elif p < pattern.len and (pattern[p] == '?' or pattern[p] == name[n]):
			p += 1
			n += 1
		elif star >= 0:
			mark += 1
			p = star + 1
			n = mark
		else:
			return false
	while p < pattern.len and pattern[p] == '*':
		p += 1
	p == pattern.len

# whether the path names a Zap source: a .zap file, or a .zapx one (Zap with markup in it)
pub fn isSourceFile(path str) bool:
	path.endsWith(".zap") or path.endsWith(".zapx")

# A stamp of the .zap files under the paths (walk of each, as sources): their names, lengths and hashes,
# changed when any of them changes: the key of a cache of what they compute
pub fn zapStamp(paths str[]) str:
	parts = []
	for path in paths:
		for file in walk(path, sources = true):
			text = readFile(file) ?? ""
			parts.push("{file} {text.len}:{text.hash():x}")
	joined = parts.join("\n")
	"{joined.len}:{joined.hash():x}"

# the dirs the .gitignore files at dir and above it (to the repository's root) name: a full path,
# or "*/name" for any dir of that name under the .gitignore's dir ("base/*/name")
fn ignoredDirs(dir str):
	out = []
	at = dir.copy()
	loop 64:
		for line in (rt.readFile("{at}/.gitignore") ?? "").lines():
			rule = line.trimmed()
			if not rule.endsWith("/") or "*" in rule or rule.startsWith("#") or
				rule.startsWith("!"):
				continue
			name = rule[..len - 1]
			inner = name[1..] if name.startsWith("/") else name
			out.push("{at}/{inner}" if "/" in name else "{at}/*/{inner}")
		if rt.fileExists("{at}/.git"): break
		up = dirOf(at)
		if up == "" or up == at: break
		at = up.copy()
	out

# whether the file's full path lies in the ignored dir (ignoredDirs) below the dir the walk
# started from (one asked for by its path is walked)
fn isUnder(file str, dir str, start str):
	match dir.indexOf("/*/"):
		star:
			base = start if start.len > star else dir[..star]
			file.startsWith("{base}/") and "/{dir[star + 3..]}/" in file[base.len..]
		none: dir.startsWith("{start}/") and file.startsWith("{dir}/")

# ---------- a file read at any offset ----------

# n bytes from byte `at` of the open file `handle` (Windows; linux/fs.zap's on Linux)
fn bytesAt(handle i64, at i64, n i64) u8[] ? Error:
	if not rt.SetFilePointerEx(handle, at, out moved, 0) or moved != at:
		return fsError(rt.systemError())
	buf = rt.zeroBytes(n)
	if rt.readFully(handle, buf, 0) < n: return Error.Ended
	buf

# A file open for reading: closed when it goes, or earlier by close().
pub type File:
	handle i64

	# n bytes from byte `at`
	fn readAt(at i64, n i64):
		bytesAt(handle, at, n)

	# the file's size in bytes
	fn len():
		rt.fileSize(handle)

	# closes the file now instead of when it goes
	fn close():
		if handle != 0:
			rt.CloseHandle(handle)
		handle = 0

	mut fn drop():
		close()

# opened for reading, shared with other readers
pub fn open(path str) File ? Error:
	h = rt.openForRead(path)
	if h == -1: return fsError(rt.systemError())
	File(handle = h)

# ---------- paths ----------

fn isSlash(b u8):
	b == '/' or b == '\\'

# the index of the last slash, or -1
fn lastSlash(path str):
	i = path.len - 1
	while i >= 0 and not isSlash(path[i]):
		i -= 1
	i

# the dir the user's application of this name keeps what it fetches or makes for every project in:
# %LOCALAPPDATA%/<app> on Windows, ~/.cache/<app> elsewhere
pub fn cacheDir(app str) str:
	if env.get("LOCALAPPDATA") is local: return "{local.replace("\\", "/")}/{app}"
	"{env.get("HOME") ?? "."}/.cache/{app}"

# the user's folder (USERPROFILE on Windows, HOME elsewhere); "" when the system names none
pub fn userDir() str:
	home = env.get("USERPROFILE") if onWindows() else env.get("HOME")
	(home ?? "").replace("\\", "/")

# "a/b/c.txt" -> "a/b"; "" when the path has no dir
pub fn dirOf(path str) ref str:
	path[..lastSlash(path).max(0)]

# "a/b/c.txt" -> "c.txt"
pub fn fileName(path str) ref str:
	path[lastSlash(path) + 1..]

# "a/b/c.txt" -> "c"
pub fn stem(path str) ref str:
	name = fileName(path)
	dot = name.lastIndexOf(".") ?? name.len
	name[..dot]

# "a/b/c.txt" -> ".txt"; "" when the name has none
pub fn extension(path str) ref str:
	name = fileName(path)
	dot = name.lastIndexOf(".") ?? name.len
	name[dot..]

# the parts joined by one '/' ("a/" and "b" -> "a/b"); an absolute part starts over
pub fn join(base str, part str) str:
	if base == "" or part.startsWith("/") or ":" in part: return part.copy()
	base + part if isSlash(base[len - 1]) else "{base}/{part}"

# '/' between parts, "." and "x/.." taken out, no '/' at the end ("a\\b/../c/" -> "a/c")
pub fn normalize(path str) str:
	parts str[] = []
	for part in path.replace("\\", "/").split("/"):
		if part == ".." and not parts.isEmpty and parts[len - 1] != ".." and parts[len - 1] != "":
			parts.pop()
		elif part != "." and not (part == "" and not parts.isEmpty):
			parts.push(part.copy())
	parts.join("/")

# ---------- this machine's copies ----------
# What zap fetches once a machine (a tool, a library) is kept in a dir of the machine's, one for
# every checkout and worktree: a fetch unpacks an archive there, then notes it was whole.

# whether a fetch into dir (fetchUnpacked) ended whole
pub fn isFetched(dir str) bool:
	exists("{dir}/fetched.txt")

# the text at url, "" when it cannot be fetched
pub fn fetchText(url str) str:
	got = Process.output("{fetchTool("curl")} -sfL {url}")
	"" if got.code != 0 else got.out

# The archive at url (a zip, or a tar however packed) fetched and its dir `inner` (a path in the
# archive) unpacked into dir, then noted whole (isFetched); whether it was.
pub fn fetchUnpacked(url str, inner str, dir str) bool:
	_ = createDir(dir)
	archive = "{dir}/fetching{clockMs()}"
	parts = inner.split("/").filter(it != "").len
	if Process.output("{fetchTool("curl")} -sfL -o \"{archive}\" {url}").code == 0 and
		Process.output(
			"{fetchTool("tar")} -xf \"{archive}\" -C \"{dir}\" --strip-components {parts} {inner}"
		).code == 0:
		_ = writeFile("{dir}/fetched.txt", "{url}\n")
	_ = deleteFile(archive)
	isFetched(dir)

# curl or tar: Windows' own (System32's: another tar on the PATH may not read a zip), the PATH's
# elsewhere
fn fetchTool(name str):
	if not onWindows(): return name.copy()
	"{(env.get("SystemRoot") ?? "C:/Windows").replace("\\", "/")}/System32/{name}.exe"

test "paths taken apart":
	p = "a/b/c.txt"
	expect dirOf(p) == "a/b"
	expect fileName(p) == "c.txt"
	expect stem(p) == "c"
	expect extension(p) == ".txt"
	print("{dirOf("x")} {fileName("x")} {stem("x")}{extension("x")}")
	expect join ==
		{("a/b", "c"): "a/b/c", ("a/b/", "c"): "a/b/c", ("a", "/c"): "/c", ("a", "C:/c"): "C:/c"}
	expect normalize == {"a\\b/../c/": "a/c", "../a": "../a", "/a": "/a"}
	prints """
		 x x
		"""

test "walking the sources leaves out the dirs a .gitignore names":
	base = "{testDir()}fs-ignore"
	for dir in ["a/made", "a/b/out", "a/keep"]:
		createDir("{base}/{dir}") ?? fail("{error}")
	for file in ["a/one.zap", "a/made/two.zap", "a/b/out/three.zap", "a/keep/four.zap"]:
		writeFile("{base}/{file}", "print(1)\n") ?? fail("{error}")
	writeFile("{base}/.gitignore", "# made by a tool\na/made/\nout/\n*.exe\n") ?? fail("{error}")
	print(walk(base, sources = true).map(str(it[base.len + 1..])))
	print(walk("{base}/a/b", sources = true).len)
	prints r"""
		["a/keep/four.zap", "a/one.zap"]
		0
		"""

test "a file read at an offset":
	writeFile("{testDir()}fs-test.txt", "abcde") ?? fail("{error}")
	f = open("{testDir()}fs-test.txt") ?? fail("{error}")
	print(f.readAt(2, 2) ?? [])
	if f.readAt(4, 2) is error: print(error)
	print(f.len)
	f.close()
	print(readBytes("{testDir()}fs-test.txt") ?? [])
	deleteFile("{testDir()}fs-test.txt") ?? fail("{error}")
	prints """
		[99, 100]
		Ended
		5
		[97, 98, 99, 100, 101]
		"""

test "numbered files written where they changed, those past the last deleted":
	stem = "{testDir()}fs-numbered"
	print(writeNumbered(stem, ".txt", "#", ["a", "b", "c"], 2) ?? -1)
	print(writeNumbered(stem, ".txt", "#", ["a", "b", "c"], 2) ?? -1)
	print(writeNumbered(stem, ".txt", "#", ["a", "x"], 2) ?? -1)
	print("{readFile("{stem}0.txt") ?? ""} {exists("{stem}1.txt")}")
	deleteFile("{stem}0.txt") ?? fail("{error}")
	prints """
		2
		0
		2
		#ax false
		"""

test "why a file could not be read":
	print(readFile("build/fs-test-missing.txt") ?? "{error}")
	print(readFile("build/no-such-dir/a.txt") ?? "{error}")
	print(list("build/no-such-dir") ?? ["{error}"])
	createDir("{testDir()}fs-test-dir/a") ?? print("{error}")
	print(exists("{testDir()}fs-test-dir/a"))
	prints """
		NotFound
		NotFound
		["NotFound"]
		true
		"""

test "bytes written, appended and when":
	writeBytes("{testDir()}fs-bytes.bin", [0, 1, 255]) ?? fail("{error}")
	appendBytes("{testDir()}fs-bytes.bin", [7]) ?? fail("{error}")
	print(readBytes("{testDir()}fs-bytes.bin") ?? [])
	first = modified("{testDir()}fs-bytes.bin") ?? 0
	_ = writeBytes("{testDir()}fs-bytes.bin", [])
	print("{first > 0} {(modified("{testDir()}fs-bytes.bin") ?? 0) >= first} {modified("build/fs-none.bin") ?? -1}")
	deleteFile("{testDir()}fs-bytes.bin") ?? fail("{error}")
	prints """
		[0, 1, 255, 7]
		true true -1
		"""

test "a dir's times listed as each file's":
	writeFile("{testDir()}fs-timed.txt", "t") ?? fail("{error}")
	times = modifiedIn(testDir()[..testDir().len - 1]) ?? fail("{error}")
	at = modified("{testDir()}fs-timed.txt") ?? 0
	print("{(times.get("fs-timed.txt") ?? -1) == at} {at > 0}")
	deleteFile("{testDir()}fs-timed.txt") ?? fail("{error}")
	prints "true true"

test "a file moved over another":
	writeFile("{testDir()}fs-moved.txt", "new") ?? fail("{error}")
	writeFile("{testDir()}fs-kept.txt", "old") ?? fail("{error}")
	moveFile("{testDir()}fs-moved.txt", "{testDir()}fs-kept.txt") ?? fail("{error}")
	print("{readFile("{testDir()}fs-kept.txt") ?? ""} {exists("{testDir()}fs-moved.txt")}")
	moveFile("{testDir()}fs-moved.txt", "{testDir()}fs-kept.txt") ?? print("{error}")
	deleteFile("{testDir()}fs-kept.txt") ?? fail("{error}")
	prints """
		new false
		NotFound
		"""

test "a tree walked, all of it or the names a glob matches":
	base = "{testDir()}fs-walk"
	for dir in ["b/deep", "a", "empty"]:
		createDir("{base}/{dir}") ?? fail
	for file in ["top.zap", "b/two.txt", "b/deep/three.zap", "a/one.zap", "a/.hidden"]:
		writeFile("{base}/{file}", "x") ?? fail
	print(walk(base).map(str(it[base.len + 1..])))
	print(walk(base, "*.zap").map(str(fileName(it))))
	print(walk("{base}/none"))
	print(globMatches("one.zap", "*.zap"))
	print(globMatches("one.zap", "o?e.*"))
	print(globMatches("one.zap", "*zap*x"))
	print(globMatches("", "*"))
	deleteTree(base) ?? fail
	prints r"""
		["a/.hidden", "a/one.zap", "b/deep/three.zap", "b/two.txt", "top.zap"]
		["one.zap", "three.zap", "top.zap"]
		[]
		true
		true
		false
		true
		"""
