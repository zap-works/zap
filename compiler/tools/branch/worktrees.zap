# The repository's worktrees as zap branch uses them: main's checkout, the land's own checkout beside
# it, and the compiler a checkout builds.

import fs

# a worktree, as git worktree list names it
type Worktree:
	path str
	branch str   # "" when its HEAD is detached

# every worktree of the repository holding the working dir, the main one first
fn worktrees():
	list = []
	for line in gitSays(".", "worktree list --porcelain", "").lines():
		if line.startsWith("worktree "):
			list.push(Worktree(path = line[9..].copy(), branch = ""))
		elif line.startsWith("branch refs/heads/") and not list.isEmpty:
			list[len - 1].branch = line[18..].copy()
	list

# the worktree main is checked out in, where the command (land) ends when there is none
fn mainCheckout(command str):
	w = worktrees().find(.branch == mainBranch) ?? exit(
		1,
		"{command}: no worktree of a git repository here has {mainBranch} checked out"
	)
	w.path.copy()

# The land checkouts beside main's: <main's checkout>-land, then -land-2, -land-3, ... as many as
# lands ran at once, each kept from one land to the next (its build/ caches warm). The one a
# running land uses holds that land's process id in build/land.pid.

# the nth land checkout's dir, from 1
fn landCheckoutDir(main str, n i64):
	"{main}-land" if n == 1 else "{main}-land-{n}"

# the file naming the land using the checkout at
fn landPidFile(at str):
	"{at}/build/land.pid"

# the process of the land using the checkout at, 0 when no running one does
fn landUsing(at str):
	pid = i64.parse((fs.readFile(landPidFile(at)) ?? "").trimmed()) ?? 0
	pid if pid > 0 and processRuns(pid) else 0

# the checkout this land merges and tests in: the first land checkout no running land uses, taken
# for this process (the caller holds the lock), detached at the commit with nothing else in it;
# none when git cannot make it
fn landCheckout(main str, commit str) str?:
	n = 1
	while landUsing(landCheckoutDir(main, n)) != 0: n += 1
	at = landCheckoutDir(main, n)
	if not worktrees().any(.path == at):
		_ = fs.deleteTree(at)
		gitSays(main, "worktree prune", "")
		if gitSays(main, "worktree add -q --detach {quoteArg(at)} {commit}", "") == "-": return none
	for words in ["reset -q --hard", "checkout -q --detach {commit}", "clean -fdq"]:
		if gitSays(at, words, "") == "-": return none
	_ = fs.createDir("{at}/build")
	fs.writeFile(landPidFile(at), "{processId()}\n") ?? return none
	at

# the land checkout at let go, for the next land
fn releaseLandCheckout(at str):
	_ = fs.deleteFile(landPidFile(at))

# the lands running in the repository, one line each: the checkout and the process
fn landsRunning(main str):
	lines = []
	n = 1
	while fs.exists(landCheckoutDir(main, n)):
		pid = landUsing(landCheckoutDir(main, n))
		if pid != 0: lines.push("{landCheckoutDir(main, n)}: a land runs there, process {pid}")
		n += 1
	lines

# a landed branch removed, its worktree first, unless that is the repository's main one, holds
# changes not committed (untracked files too) or holds ignored files outside build/ (a project's
# data, which the removal would erase): each removal or reason to keep said
fn removeLanded(main str, branch str):
	list = worktrees()
	if list.find(.branch == branch) is w:
		if w.path == list[0].path:
			print("land: {w.path} kept: it is the repository's main worktree")
			return
		if hasUncommitted(w.path):
			print("land: {w.path} kept: it has uncommitted changes")
			return
		if ignoredOutsideBuild(w.path) is kept:
			print("land: {w.path} kept: it holds ignored files ({kept}), which removing it would erase")
			return
		if gitSays(main, "worktree remove {quoteArg(w.path)}", "") == "-":
			print("land: {w.path} could not be removed (a program running in it?)")
			return
		print("land: removed the worktree {w.path}")
	if gitSays(main, "branch -d {branch}", "") != "-":
		print("land: removed the branch {branch}")

# whether the checkout at root has uncommitted changes, untracked files too
fn hasUncommitted(root str):
	gitSays(root, "status --porcelain", "") != ""

# the first ignored file or dir at root outside build/, none when there is none
fn ignoredOutsideBuild(root str) str?:
	said = gitSays(root, "ls-files --others --ignored --exclude-standard --directory", "")
	if said == "-": return none
	for line in said.lines():
		if not line.isEmpty and not line.startsWith("build/"): return line.copy()
	none

# A repository's own git settings (its commits' author, say) are its .gitconfig, versioned at its
# root: git's config of the repository includes it, so every worktree's commits follow them.
fn keepRepositoryConfig():
	w = worktrees().find(.branch == mainBranch) ?? return
	if not fs.exists("{w.path}/.gitconfig"): return
	if gitSays(w.path, "config --get include.path", "") != "../.gitconfig":
		gitSays(w.path, "config include.path ../.gitconfig", "")

# whether the branch is in main already
fn inMain(main str, branch str):
	gitSays(main, "merge-base --is-ancestor {branch} {mainBranch}", "") != "-"

# zap branch new <name>: the branch made from main (or the one of that name) checked out at
# <main's checkout>-wt-<name>, with its compiler (checkoutCompiler)
pub fn newCommand(name str):
	main = mainCheckout("new")
	at = "{main}-wt-{name}"
	made = gitSays(main, "rev-parse --verify --quiet refs/heads/{name}", "") == "-"
	words = "worktree add -q -b {name} {quoteArg(at)} {mainBranch}" if made
		else "worktree add -q {quoteArg(at)} {name}"
	added = Process.output("git {words}", dir = main)
	if added.code != 0: exit(1, "new: {added.out.trimmedEnd()}")
	if not isCompilerRepository(at):
		print("new: {at}, on {name}")
		return
	how = checkoutCompiler(at, main) ??
		exit(1, "new: {at}, on {name}; its compiler does not build")
	print("new: {at}, on {name}; build/zap.exe {how}")
