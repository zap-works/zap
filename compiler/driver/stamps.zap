# A result kept with a stamp of what it rests on, reused while all of that stands: the compiler's
# key (compilerKey), each file's text hashed (a missing one as missing) and each of their dirs
# with its sources' names (a file added to a module's dir changes its program though no file it
# had changed).
# zap test keeps the passes of check and tests by one (spec 13.1).

import fs

# the files this process hashed: a stamp is made after what it rests on ran, and the sources do
# not change while a zap checks them
mut fileHashes {str: str} = {}

fn fileHash(path str):
	if fileHashes.get(path) is known: return known.copy()
	hash = fileHashNow(path)
	fileHashes[path.copy()] = hash.copy()
	hash

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
		lines.push("file\t{f}\t{fileHash(f)}")
		dir = fs.dirOf(f)
		if fs.isSourceFile(f) and dir not in dirs:
			dirs.push(dir.copy())
	for dir in dirs:
		lines.push("dir\t{dir}\t{dirSourcesHash(dir)}")
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
	for line in text[..at].lines():
		f = line.split("\t")
		same = match f[0]:
			"zap": true
			"file": f.len == 3 and fileHash(f[1]) == f[2]
			"dir": f.len == 3 and "{dirSourcesHash(f[1])}" == f[2]
			_: false
		if not same: return none
	text[at + 6..].copy()

fn stampedByThisZap(text str):
	text.startsWith("zap\t{compilerKey()}\n")

# the files a stamp names
pub fn stampedFiles(text str) str[]:
	head = text[..(text.indexOf("\nkept\n") ?? 0)]
	head.lines().map(.split("\t")).filter(.len == 3 and it[0] == "file").map(it[1].copy())
