# A checkout's compiler, build/zap.exe: a clean checkout takes main's when main's was built from the
# same sources, else builds its own with the host's seed. What a compiler was built from is the git
# trees of its sources' dirs (compilerSourceDirs, what the build kind of zap test hashes), kept in a
# stamp beside it with its bytes' hash, so a compiler built again by hand is never taken for the
# stamped one.

import fs

# the file beside a checkout's build/zap.exe naming the trees it was built from and its hash
fn compilerStamp(root str):
	"{root}/build/zap.trees"

# the trees of the compiler's sources at the commit, one text ("-" for a dir it lacks), asked of
# git at once
fn compilerTrees(root str, commit str):
	listed = gitSays(root, "ls-tree {commit} {compilerSourceDirs.join(" ")}", "").lines()
	compilerSourceDirs.map(listedObject(listed, it)).join(" ")

# the object a line of git ls-tree names for the path ("<mode> <type> <object>\t<path>"), "-"
# when none does
fn listedObject(listed str[], path str):
	line = listed.find(.endsWith("\t{path}")) ?? return "-"
	line.split("\t")[0].split(" ")[2].copy()

# the stamp's lines (the trees, the executable's hash, the commit of the seed that built it), none
# when no stamp names them or the executable changed since
fn compilerStampLines(root str):
	lines = (fs.readFile(compilerStamp(root)) ?? "").lines()
	if lines.len != 3 or lines[1] != fileHashNow(builtCompiler(root, host())): return []
	lines

# the trees root's build/zap.exe was built from, "" when it has no valid stamp
fn compilerBuiltFrom(root str):
	lines = compilerStampLines(root)
	"" if lines.isEmpty else lines[0].copy()

# whether root's build/zap.exe is the host's seed's build (the newest commit of the branch) of the
# sources as they are now: the first build of the fixed point already made
fn seedBuiltFromCurrentSources(root str, branch str):
	lines = compilerStampLines(root)
	dirs = compilerSourceDirs.join(" ")
	not lines.isEmpty and lines[0] == compilerTrees(root, "HEAD") and
		lines[2] == gitSays(root, "rev-parse {branch}", "") and
		gitSays(root, "status --porcelain -- {dirs}", "") == ""

# the compiler of the clean checkout at root, in its build/: the one there or main's when built
# from the same trees, else one built by the host's seed and stamped. How it came, none when it
# did not build.
fn checkoutCompiler(root str, main str) str?:
	trees = compilerTrees(root, "HEAD")
	if compilerBuiltFrom(root) == trees: return "built already"
	taking = ""
	if root != main and compilerBuiltFrom(main) == trees:
		taking = copyCompiler(main, root)
		if taking == "": return "taken from main's checkout"
	_ = fs.createDir("{root}/build")
	extract = seedLine(seedBranch(root), host(), "build")
	if Process.run(shellLine(inDir(root, extract))) != 0: return none
	if not buildCompiler(root, "{root}/build/{seedFile}", host(), root): return none
	seed = gitSays(root, "rev-parse {seedBranch(root)}", "")
	stamp = "{trees}\n{fileHashNow(builtCompiler(root, host()))}\n{seed}"
	fs.writeFile(compilerStamp(root), stamp) ?? return none
	"built by the host's seed" if taking == ""
		else "built by the host's seed (taking main's failed: {taking})"

# from's build/zap.exe, its stamp and its key (compilerKey) copied into to's build/: why it could
# not, "" when it did
fn copyCompiler(from str, to str):
	bytes = fs.readBytes(builtCompiler(from, host())) ??
		return "{from}'s build/zap.exe cannot be read"
	stamp = fs.readFile(compilerStamp(from)) ?? return "{from}'s build/zap.trees cannot be read"
	exe = builtCompiler(to, host())
	_ = fs.createDir("{to}/build")
	why = moveAside(exe)
	if why != "": return why
	if fs.writeBytes(exe, bytes) is error: return "{exe} cannot be written ({error})"
	if not fs.canRun(exe): return "{exe} cannot run"
	if fs.writeFile(compilerStamp(to), stamp) is error:
		return "{compilerStamp(to)} cannot be written ({error})"
	if fs.readFile(sourcesKeyFile(builtCompiler(from, host()))) is key:
		_ = fs.writeFile(sourcesKeyFile(exe), key)
	""

# The executable moved to a name of this process (<exe>.<pid>.old), so what runs it keeps
# running (Windows renames a running executable, but never replaces it): why it could not be,
# "" when it was or none was there. The names of earlier processes are deleted when they can be;
# one still running stays.
fn moveAside(exe str):
	for name in fs.list(fs.dirOf(exe)) ?? []:
		if name.startsWith("{fs.fileName(exe)}.") and name.endsWith(".old"):
			_ = fs.deleteFile("{fs.dirOf(exe)}/{name}")
	if not fs.exists(exe): return ""
	if fs.moveFile(exe, "{exe}.{processId()}.old") is error:
		return "{exe} cannot be moved aside ({error})"
	""
