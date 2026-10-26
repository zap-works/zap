# `zap branch land <name>...`: each branch brought into main, one after the other, once the checks
# of what its merge changes pass. Any number of lands run at once in a repository, each in a land
# checkout of its own beside main's (landCheckout); the repository's lock (lock.zap) is held only
# while a land takes its checkout and while it moves main, so no land waits for another's suite.
# Main's checkout and branch move only when the suite passed, by a fast-forward to the tested
# commit: what runs from main's checkout meanwhile sees main as it was, and a failed land has
# nothing to undo. A landed branch goes, its worktree with it. The push stays by hand. spec 13.1.5
# states it.

# the branch every land goes into
mainBranch = "main"

# zap branch land <name>...: exit code 0 when every branch is in main; the first that is not ends it
pub fn landCommand(names str[]):
	main = mainCheckout("land")
	for branch in names:
		landed = landBranch(main, branch)
		print("land: main is at {gitSays(main, "log -1 {quoteArg("--format=%h %s")} {mainBranch}", "")}{unpushed(main)}")
		if not landed: exit(1)

# the branch merged into main in the land's checkout, tested there and main moved to the merge
# when the suite passed: whether the branch is in main, each refusal or failure said
fn landBranch(main str, branch str):
	if branch == mainBranch:
		return said("land: {mainBranch} is where a branch lands, not one to land")
	if gitSays(main, "rev-parse --verify --quiet refs/heads/{branch}", "") == "-":
		return said("land: no branch {branch}")
	if hasChanges(main): return said("land: {main} has uncommitted changes; nothing landed")
	if inMain(main, branch):
		print("land: {branch} is in {mainBranch} already")
		removeLanded(main, branch)
		return true
	if lintNotRun() != "":
		return said("land: the suite would run without the lint on {hostTarget()}; land on Windows")
	lock = takeLandLock(main)
	before = gitSays(main, "rev-parse {mainBranch}", "")
	taken = landCheckout(main, before)
	releaseLandLock(main, lock)
	at = taken ?? return said("land: git could not make the land's checkout")
	landed = landedIn(main, branch, at, before)
	releaseLandCheckout(at)
	landed

# the branch merged into main in the land checkout at (made from main at before), tested there and
# main moved to the merge when the checks of what it changes passed: whether the branch is in main
fn landedIn(main str, branch str, at str, before str):
	if not mergedIn(at, branch, mainBranch): return false
	print("land: {branch} merged in {at}")
	failure = suiteFailure(at, main, before, "HEAD", "the merge changes")
	if failure != "":
		return said("land: {failure} on the merge of {branch} ({at}); {mainBranch} not moved")
	if not mainMovedToMerge(main, branch, at, before): return false
	print("land: {branch} landed")
	removeLanded(main, branch)
	true

# the merge's compiler made main's build/zap.exe when it was built from the merge's sources and
# main's was not (under the lock, so a land that moved main later never gets an older one)
fn mainTakesCompiler(main str, at str):
	if not isCompilerRepository(at) or not mergeCompilerIsNew(at, main): return
	why = copyCompiler(at, main)
	if why != "": print("land: {main}'s compiler is not the merge's: {why}")

# whether the land's checkout at holds a compiler built from the merge's sources that main's
# checkout lacks (a change that ran no suite built none, and an older land's must not be taken)
fn mergeCompilerIsNew(at str, main str):
	built = compilerBuiltFrom(at)
	built != "" and built == compilerTrees(at, "HEAD") and built != compilerBuiltFrom(main)

# main moved to the merge tested in the checkout at, which was made from main at base, under the
# lock. When main moved meanwhile (another land, or a commit by hand) and its checkout is clean,
# the lock is let go, its new commits are merged in again and tested by what they change
# (changeRun), and the move is tried again: whether main moved, each refusal said.
fn mainMovedToMerge(main str, branch str, at str, base str):
	tested = gitSays(at, "rev-parse HEAD", "")
	now = base.copy()
	while true:
		if hasChanges(main):
			return said("land: {main} has uncommitted changes; {mainBranch} not moved")
		lock = takeLandLock(main)
		current = gitSays(main, "rev-parse {mainBranch}", "")
		if current == now:
			moved = gitSays(main, "merge --ff-only -q {tested}", "") != "-"
			if moved: mainTakesCompiler(main, at)
			releaseLandLock(main, lock)
			if moved: return true
			return said(
				"land: {mainBranch} could not be moved to the merge; {mainBranch} not moved"
			)
		releaseLandLock(main, lock)
		print("land: {mainBranch} moved while the suite ran; its new commits are merged in")
		if not mergedIn(at, mainBranch, "the merge of {branch}"): return false
		now = current.copy()
		head = gitSays(at, "rev-parse HEAD", "")
		failure = suiteFailure(at, main, tested, head, "the new commits change")
		tested = gitSays(at, "rev-parse HEAD", "")   # (the lint's forms may have been committed)
		if failure != "":
			return said(
				"land: {failure} on the new commits of {mainBranch} ({at}); {mainBranch} not moved"
			)
	false

# what the files a change touches run
type ChangeRun:
	core bool
	areas str[]   # what changed, as the line says it
	paths str[]   # the engine, rhi and projects that changed

# the dirs of the language's core, which a change runs every kind of check for
coreDirs = ["compiler", "runtime", "std", "spec", "tests"]
coreKinds = "build,dups,limits,check,tests"
ownKinds = "check,tests"

# the path file belongs to when it is in engine/, rhi/ or projects/<name>/, else ""
fn ownPath(file str):
	for dir in ["engine", "rhi"]:
		if file.startsWith("{dir}/"): return dir
	if file.startsWith("projects/") and file[9..].indexOf("/") is end: return file[..9 + end].copy()
	""

# what the files (as git names them) run: the core for any file outside engine/, rhi/ and
# projects/<name>/ that is not documentation (.md: the README's numbers are only written, by the
# bench) or the LICENSE, those directories for their own files
fn changeRun(files str[]):
	run = ChangeRun(core = false, areas = [], paths = [])
	for file in files:
		if file.endsWith(".md") or file == "LICENSE": continue
		own = ownPath(file)
		area = file.copy()
		if own != "":
			area = own.copy() if "/" in own else "{own}/"
			if own not in run.paths: run.paths.push(own.copy())
		else:
			run.core = true
			if file.indexOf("/") is end: area = file[..end + 1].copy()
		if area not in run.areas: run.areas.push(area)
	run

# why the checks of what changed in the checkout at from from to to failed ("" when they pass, or
# when no file a check reads changed: main then moves without a suite); the line printed names
# what changed and the one `zap test` that runs. Forms the lint finds in the merge (the branch's
# alone lacked main's changes) are written by the suite (fixlint) and committed, and the suite runs
# again on the commit.
fn suiteFailure(at str, main str, from str, to str, what str):
	files = gitSays(at, "diff --name-only {from} {to}", "")
	if files == "-": return "git could not list the changes"
	run = changeRun(files.lines())
	if run.areas.isEmpty:
		print("land: the change touches no file a check reads; no suite")
		return ""
	paths = coreDirs.copy() if run.core else run.paths.copy()
	if run.core:
		for path in run.paths: paths.push(path)
	words = "test --only {coreKinds if run.core else ownKinds} {paths.join(" ")}"
	print("land: {what} {run.areas.join(" and ")}; zap {words}")
	zap = landCompiler(at, main) ?? return "the compiler does not build"
	line = inDir(at, "{quoteArg(hostPath(zap))} {words}")
	asking = withVariable(runVariable().name, runWith(fixLintWord().name), line)
	loop lintRounds:
		if Process.run(shellLine(asking)) != 0: return "the suite failed"
		if not hasChanges(at): return ""
		if gitSays(at, "commit -a -q -m {quoteArg("The lint's forms of the merge")}", "") == "-":
			return "git could not commit the lint's forms"
		print("land: the lint's forms of the merge written and committed; the suite runs again")
	"the lint's forms do not settle"

# how many times a land's suite runs again for the lint's forms the merge's files gained
lintRounds = 3

# the branch name merged into the checkout at: whether it merged; a conflict with against lists
# its files and leaves the checkout as it was
fn mergedIn(at str, name str, against str):
	message = quoteArg("Merge branch '{name}'")
	if gitSays(at, "merge -q -m {message} {name}", "") != "-": return true
	files = gitSays(at, "diff --name-only --diff-filter=U", "")
	gitSays(at, "merge --abort", "")
	if files == "" or files == "-": return said("land: git could not merge {name}")
	said("land: {name} conflicts with {against}; nothing landed. The files:\n  {files.lines().join("\n  ")}")

# the zap the land's checkout tests with: the merge's compiler when the repository holds one (it
# goes to main's checkout once the merge lands), else this zap; none when it does not build
fn landCompiler(at str, main str) str?:
	if not isCompilerRepository(at): return exePath()
	_ = try checkoutCompiler(at, main)
	builtCompiler(at, host())

# whether the checkout at root has changes to its tracked files not committed
fn hasChanges(root str):
	gitSays(root, "status --porcelain --untracked-files=no", "") != ""

# how many of main's commits origin's main lacks, as the line says it ("" without an origin)
fn unpushed(main str):
	count = gitSays(main, "rev-list --count origin/{mainBranch}..{mainBranch}", "")
	if count == "-": return ""
	", {count} commits ahead of origin/{mainBranch} (the push is by hand)"

# the line printed, false: a refusal said
fn said(line str):
	print(line)
	false
