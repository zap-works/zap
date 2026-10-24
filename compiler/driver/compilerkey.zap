# The key every cache of the compiler's results is kept under (the parse and IR caches, zap fmt's
# files laid out, the passes of zap test): what can change the compiler's behaviour, the sources
# its build read (compiler/ and the runtime and std files it imports), not its bytes. A build of
# the compiler writes the key beside its executable with the executable's hash; same sources give
# the same key wherever they were built (the fixed point, spec 14.1, gives the same behaviour).

import fs

# the key once known (0 before)
mut compilerKeyKnown = 0

# each source file this process parsed and its text hashed, as read
mut sourcesParsed str[] = []
mut sourceHashes i64[] = []

fn noteSourceParsed(at str, text str):
	noteSourceRead(at, text.hash())

# a source the build read (a kept stage's are read for its key, not parsed), once
fn noteSourceRead(at str, hash i64):
	if at in sourcesParsed: return
	sourcesParsed.push(at.copy())
	sourceHashes.push(hash)

# where the key of the executable at exe is kept: beside it (build/zap.sources)
fn sourcesKeyFile(exe str):
	"{fs.dirOf(exe)}/{fs.stem(exe)}.sources"

# This compiler's key: its sources' (sourcesKeyFile) while the file is its executable's (the
# executable's write as kept, else its hash), else the hash of its executable (a compiler copied
# without it, or built by one before the key)
pub fn compilerKey() i64:
	if compilerKeyKnown != 0: return compilerKeyKnown
	exe = exePath()
	kept = (fs.readFile(sourcesKeyFile(exe)) ?? "").lines()
	if kept.len == 3 and kept[2] == "{fs.modified(exe) ?? 0}" and i64.parse(kept[1]) is key:
		compilerKeyKnown = key
		return key
	bytes = (fs.readFile(exe) ?? "").hash()
	compilerKeyKnown = bytes
	if kept.len >= 2 and kept[0] == "{bytes}":
		compilerKeyKnown = i64.parse(kept[1]) ?? bytes
	compilerKeyKnown

# the key of the sources this process parsed for the target: each file's name as a build anywhere
# names it (portablePath) with its text's hash
fn sourcesKey():
	lines = (0..sourcesParsed.len).map("{portablePath(sourcesParsed[it])}\t{sourceHashes[it]}")
	"{targets[buildTarget].name}\n{lines.sorted().join("\n")}".hash()

# after a build of the compiler from entry to exe, the key of its sources kept beside it
fn keepCompilerKey(entry str, exe str):
	if portablePath(entry) != compilerSource: return
	bytes = (fs.readFile(exe) ?? "").hash()
	_ = fs.writeFile(sourcesKeyFile(exe), "{bytes}\n{sourcesKey()}\n{fs.modified(exe) ?? 0}")
