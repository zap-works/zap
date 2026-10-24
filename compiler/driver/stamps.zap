# A result kept with a stamp of what it rests on, reused while all of that stands: the compiler's
# key (compilerKey), each file's text hashed (a missing one as missing) with the time it was last
# written when it was read, and each of their dirs with its sources' names (a file added to a
# module's dir changes its program though no file it had changed). A file whose time is still
# the stamp's is not read again: its text is the one hashed.
# zap test keeps the passes of check and tests by one (spec 13.1).

import fs

# the files this process hashed: a stamp is made after what it rests on ran, and the sources do
# not change while a zap checks them
mut fileHashes {str: str} = {}

# when each file this process read was last written, taken before it was read (0: not known)
mut fileTimes {str: i64} = {}

fn fileHash(path str):
	if fileHashes.get(path) is known: return known.copy()
	noteFileTime(path)
	hash = fileHashNow(path)
	fileHashes[path.copy()] = hash.copy()
	hash

# the time the file at path was last written noted, before it is read
fn noteFileTime(path str):
	if path not in fileTimes: fileTimes[path.copy()] = fs.modified(path) ?? 0

# the file's text hashed as it is now, read again each time ("missing" when there is none)
fn fileHashNow(path str):
	"{(fs.readFile(path) ?? "").hash()}" if fs.exists(path) else "missing"

# the names of a dir's source files, hashed
fn dirSourcesHash(dir str):
	(fs.list(dir) ?? [])
		.filter(fs.isSourceFile(it))
		.sorted()
		.join("\n")
		.hash()

# the text that keeps `kept` while the files are as they are now, and this compiler the one
pub fn stamped(files str[], kept str) str:
	lines = ["zap\t{compilerKey()}"]
	dirs str[] = []
	for f in files:
		lines.push("file\t{f}\t{fileHash(f)}\t{fileTimes.get(f) ?? 0}")
		dir = fs.dirOf(f)
		if fs.isSourceFile(f) and dir not in dirs:
			dirs.push(dir.copy())
	for dir in dirs:
		time = fs.modified(dir) ?? 0   # (before the listing: a file added after it changes it)
		lines.push("dir\t{dir}\t{dirSourcesHash(dir)}\t{time}")
	lines.push("kept")
	"{lines.join("\n")}\n{kept}"

# what a stamped text keeps, while everything its stamp names is as it was; none when it is not
pub fn keptWhileSame(text str) str?:
	if not stampedByThisZap(text): return none
	keptWhileFilesSame(text)

# what a stamped text keeps while the files and dirs its stamp names are as they were, whatever
# compiler stamped it; none when one is not
pub fn keptWhileFilesSame(text str) str?:
	at = try text.indexOf("\nkept\n")
	rows = text[..at].lines().map(.split("\t"))
	times = stampTimesOf(rows)
	for f in rows:
		same = match f[0]:
			"zap": true
			"file": f.len == 4 and
				(unchangedSince(f[1], f[2], f[3], times) or fileHash(f[1]) == f[2])
			"dir": f.len == 4 and
				(
					f[3] != "0" and "{times.timeOf(f[1])}" == f[3] or
						"{dirSourcesHash(f[1])}" == f[2]
				)
			_: false
		if not same: return none
	text[at + 6..].copy()

# When the files and dirs a stamp names were last written: a dir that holds several of them
# listed once (fs.modifiedIn), when the first is asked for, in place of a look at each.
type StampTimes:
	counts {str: i64}   # by dir, the paths below it the stamp names
	listed {str: {str: i64}} = {}

fn stampTimesOf(rows str[,]):
	counts {str: i64} = {}
	for f in rows:
		if f.len == 4 and (f[0] == "file" or f[0] == "dir"):
			dir = fs.dirOf(f[1])
			counts[dir.copy()] = (counts.get(dir) ?? 0) + 1
	StampTimes(counts)

fn timeOf(mut t StampTimes, path str) i64:
	dir = fs.dirOf(path)
	if (t.counts.get(dir) ?? 0) >= 3:
		if dir not in t.listed: t.listed[dir.copy()] = fs.modifiedIn(dir) ?? {}
		if t.listed[dir].get(fs.fileName(path)) is time: return time
	fs.modified(path) ?? 0

# whether the file at path was last written at the time a stamp holds: its text is the one it
# hashed, which this process then knows
fn unchangedSince(path str, hash str, time str, mut times StampTimes):
	if time == "0" or "{times.timeOf(path)}" != time: return false
	if path not in fileHashes:
		fileHashes[path.copy()] = hash.copy()
		fileTimes[path.copy()] = i64.parse(time) ?? 0
	true

fn stampedByThisZap(text str):
	text.startsWith("zap\t{compilerKey()}\n")

# the files a stamp names
pub fn stampedFiles(text str) str[]:
	head = text[..(text.indexOf("\nkept\n") ?? 0)]
	head.lines().map(.split("\t")).filter(.len == 4 and it[0] == "file").map(it[1].copy())
