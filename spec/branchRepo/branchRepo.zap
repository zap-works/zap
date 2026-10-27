# a repository of its own for `zap branch`'s tests: made once in the test file's dir, reset for each test

import fs

# the compiler of a test's repository: `zap test` passes
passingCompiler = "print(\"the suite passes\")\n"

# a compiler whose first suite moves a file of main's checkout to another name and commits it
# there meanwhile (the test's repository is beside the land's checkout), and says so; a second
# suite says it ran again
pub fn compilerMovingMain(from str, to str) str:
	"""
	if Process.output("git log -1 --format=%s", dir = "../repo").out.trimmedEnd() == "moved":
		print("the suite passes again")
	else:
		_ = Process.output("git mv FROM TO", dir = "../repo")
		_ = Process.output("git commit -q -m moved", dir = "../repo")
		print("the suite passes, main moves")
	""".replace("FROM", from).replace("TO", to)

# a compiler whose suite, asked for the lint's forms (fixlint in ZAP_RUN), writes one (a.txt
# renamed) the first time, as a merge whose files gained a form the branch's alone lacked
pub lintWritingCompiler = """
asked = (env.get("ZAP_RUN") ?? "").indexOf("fixlint") != none
if asked and Process.output("git ls-files c.txt").out.trimmedEnd() == "":
	_ = Process.output("git mv a.txt c.txt")
	print("the suite writes a form")
else:
	print("the suite passes")
"""

# what git prints in dir, given input
pub fn git(dir str, words str, input str = "") str:
	Process.output("git {words}", input = input, dir = dir).out.trimmedEnd().copy()

# the file written in dir and committed there
pub fn commit(dir str, file str, text str):
	_ = fs.createDir(fs.dirOf("{dir}/{file}"))
	_ = fs.writeFile("{dir}/{file}", text)
	git(dir, "add -A")
	_ = git(dir, "commit -q -m {file}")

# this zap, named from any dir
pub fn zap() str:
	fs.join(currentDir(), zapPath())

# the repository the tests share, "" until the first makes it
mut sharedRepository = ""

# A repository on main: a.txt, a compiler (by default one whose suite passes, any other committed
# on top), the runtime it is built with and a std; the branch seed holding this zap as the host's
# seed. The first test makes it in the dir the tests share; each after resets it (resetRepository),
# its land checkouts kept warm as zap branch keeps them. Its dir.
pub fn landRepository(compiler str = passingCompiler) str:
	if sharedRepository == "":
		sharedRepository = madeRepository()
	else:
		resetRepository(sharedRepository)
	dir = sharedRepository.copy()
	if compiler != passingCompiler: commit(dir, "compiler/zap.zap", compiler)
	dir

# the repository landRepository starts from, made in the dir the tests share: its dir
fn madeRepository():
	dir = "{testFileDir()}repo"
	_ = fs.createDir("{dir}/compiler")
	git(dir, "init -q -b main")
	if fs.normalize(git(dir, "rev-parse --show-toplevel")) != fs.normalize(dir):
		exit(1, "no repository made in {dir}")
	git(dir, "config user.name land")
	git(dir, "config user.email land@example.com")
	git(dir, "config maintenance.auto false")   # no git maintenance after each commit
	git(dir, "config core.looseCompression 0")   # the seed written and read back at once
	_ = fs.writeFile("{dir}/.gitignore", "build/\n")
	_ = fs.writeFile("{dir}/compiler/zap.zap", passingCompiler)
	_ = fs.createDir("{dir}/std")
	_ = fs.writeFile("{dir}/std/std.txt", "std\n")
	Process.output("git archive -o {dir}/runtime.tar HEAD runtime")
	Process.output("tar -xf runtime.tar", dir = dir)
	_ = fs.deleteFile("{dir}/runtime.tar")
	commit(dir, "a.txt", "a\n")
	seed = git(dir, "hash-object -w {quoteArg(zap())}")
	host = git(dir, "mktree", "100755 blob {seed}\tseed.exe\n")
	hosts = ["windows", "linux", "linux-arm64"]
	seeds = git(dir, "mktree", hosts.map("040000 tree {host}\t{it}\n").join(""))
	git(dir, "update-ref refs/heads/seed {git(dir, "commit-tree {seeds} -m seeds")}")
	git(dir, "tag start")   # where resetRepository puts main back
	dir

# the repository at dir as madeRepository left it: main at its first commit (the tag start) with
# nothing else in its checkout, no branch but main and the seed, no worktree beside it but the
# land checkouts (their caches kept), none of them used by a land, and no lock
fn resetRepository(dir str):
	beside = fs.dirOf(dir)
	for name in fs.list(beside) ?? []:
		if name.startsWith("repo-wt-"): _ = fs.deleteTree("{beside}/{name}")
		if name.startsWith("repo-land"): _ = fs.deleteFile("{beside}/{name}/build/land.pid")
	git(dir, "worktree prune")
	git(dir, "reset -q --hard start")
	git(dir, "clean -fdxq")
	refs = git(dir, "for-each-ref --format=%(refname) refs/heads").lines()
	gone = refs.filter(it != "refs/heads/main" and it != "refs/heads/seed")
	git(dir, "update-ref --stdin", "{gone.map("delete {it}\n").join("")}delete refs/zap/land\n")

# the branch made from main in a worktree beside dir, with the file committed there: the
# worktree's dir
pub fn branchWith(dir str, branch str, file str, text str) str:
	at = "{dir}-wt-{branch}"
	git(dir, "worktree add -q -b {branch} {quoteArg(at)} main")
	commit(at, file, text)
	at

# what a zap command line run in dir says, its exit code first: dir written <repo>, and the
# commit cut from the line saying where main is
pub fn zapIn(dir str, words str) str:
	said = Process.output("{quoteArg(zap())} {words}", dir = dir)
	lines = ["{said.code}"]
	for line in said.out.replace("\r\n", "\n").replace(dir, "<repo>").lines():
		if line.startsWith("land: main is at "):
			rest = line[17..]
			lines.push("land: main is at{rest[(rest.indexOf(" ") ?? 0)..]}")
		else:
			lines.push(line.copy())
	lines.join("\n")

# `zap branch land feature` while the suite moves a file of main's checkout to `to` and commits
# it: what it says between the first suite and the land, the lines before and after checked here
pub fn landWhileMainMoves(dir str, to str) str:
	branchWith(dir, "feature", "b.txt", "b\n")
	said = zapIn(dir, "branch land feature").lines()
	expect fs.exists("{dir}/b.txt") and fs.exists("{dir}/{to}")
	expect said[..5] == [
		"0",
		"land: feature merged in <repo>-land",
		"land: the merge changes b.txt; zap test --only build,dups,limits,check,tests compiler runtime std spec tests",
		"the suite passes, main moves",
		"land: main moved while the suite ran; its new commits are merged in"
	]
	expect said[len - 4..] == [
		"land: feature landed",
		"land: removed the worktree <repo>-wt-feature",
		"land: removed the branch feature",
		"land: main is at Merge branch 'main'"
	]
	said[5..said.len - 4].join("\n")
