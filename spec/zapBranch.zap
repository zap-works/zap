# 13.1.5 `zap branch`
# host: windows (land runs where the lint runs, and refuses elsewhere)

import fs

# `zap branch` manages a repository's branches, each with its worktree beside main's checkout, run
# from any worktree of the repository. Its first word names what it does; a missing or unknown one,
# or the wrong number of names, is refused with the command's usage, exit code 2. A repository's
# .gitconfig at its root (its commits' author, say) is made part of its git config by each
# `zap branch` command, so every worktree's commits follow it.
#
# `zap branch new <name>` makes the branch from main (or takes the one of that name) and checks it
# out beside main's checkout, at `<main's checkout>-wt-<name>`, with its compiler: main's
# build/zap.exe when it was built from the same sources (the git trees of compiler/, runtime/ and
# std/, which build/zap.trees names beside it with the executable's hash and the seed's commit), else one the host's
# seed builds.
#
# `zap branch land <name>...` brings each branch into main, one after the other, the first that
# does not land ending the run. It refuses when main's checkout has uncommitted changes. Any number
# of lands run at once in a repository, each in a land checkout of its own beside main's:
# `<main's checkout>-land`, `-land-2`, `-land-3`, ... as many as run at once, each kept between
# lands so its build/ caches stay warm, the one a running land uses named by that land's process
# id in its build/land.pid. The repository's lock (a ref of the common git dir naming the process
# that holds it) is held only while a land takes its checkout and while it moves main, never
# through a suite: a second land waits those moments, and the lock of a process that ended is taken
# over. In its checkout the merge is made, the compiler is made when the repository holds one
# (compiler/zap.zap, as `zap branch new` makes it) and `zap test` runs on what the merge changes,
# which on a host that does not note the lint (any but Windows) would run without it: land
# refuses there, before it merges. A conflict aborts the merge and lists the files; a failing
# suite leaves main where it was. The suite is asked for the lint's forms (`fixlint`, 13.1): the
# merge's files may gain forms the branch's alone lacked (main's changes), which it writes instead
# of failing; the land commits them and runs the suite again on the commit, up to three times. Only when the suite passed is main fast-forwarded to the merge,
# so main's checkout never holds an untested merge, and the merge's compiler becomes main's
# build/zap.exe.
#
# What the merge changes (`git diff --name-only` from main's commit before the merge to the merge)
# decides what runs, in one `zap test --only <kinds> <paths>` whose line is printed first. The
# language's core is compiler/, runtime/, std/, spec/ and tests/: a file under one of them adds
# that directory alone, and any file outside them, engine/, rhi/ and projects/<name>/ that is not
# a .md file or the LICENSE adds all five; either way the kinds are build,dups,limits,check,tests.
# What a change in one of the core's directories breaks in another is left to a full `zap test`.
# A file under engine/ or rhi/ adds that directory, and one under projects/<name>/ adds
# projects/<name>, as a path. When the core did not change, the kinds are check,tests. .md files and the LICENSE (the README's
# numbers are only written, by the bench) add nothing, and a merge that changes only them moves
# main without a suite.
#
# When main moved meanwhile (another land, or a commit by hand) and its checkout has no
# uncommitted changes, the new main is merged into the land's merge again and the same rule
# applies to what the new commits change (its kept passes skip what stands) before main moves.
# Once the branch is in main (landed, or there already), its worktree is removed, unless it is the
# repository's main one, holds changes not committed or holds ignored files outside build/ (a
# project's data, which the removal would erase), and then the branch. The push stays by hand: the
# last line says where main stands.
#
# `zap branch status` lists the branches with a worktree beside main's checkout, one line each:
# whether the branch is in main already, its commits ahead of and behind main, and whether its
# worktree has changes not committed (untracked files too); then the lands running, one line each
# with its checkout and process, or that none runs.
#
# The tests below share one repository, made once in `testFileDir()` and reset for each, with a
# compiler whose `zap test` passes, the runtime beside it and the branch seed holding this zap.

# the compiler of a test's repository: `zap test` passes
passingCompiler = "print(\"the suite passes\")\n"

# a compiler whose first suite moves a file of main's checkout to another name and commits it
# there meanwhile (the test's repository is beside the land's checkout), and says so; a second
# suite says it ran again
fn compilerMovingMain(from str, to str):
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
lintWritingCompiler = """
asked = (env.get("ZAP_RUN") ?? "").indexOf("fixlint") != none
if asked and Process.output("git ls-files c.txt").out.trimmedEnd() == "":
	_ = Process.output("git mv a.txt c.txt")
	print("the suite writes a form")
else:
	print("the suite passes")
"""

# what git prints in dir, given input
fn git(dir str, words str, input str = ""):
	Process.output("git {words}", input = input, dir = dir).out.trimmedEnd().copy()

# the file written in dir and committed there
fn commit(dir str, file str, text str):
	_ = fs.createDir(fs.dirOf("{dir}/{file}"))
	_ = fs.writeFile("{dir}/{file}", text)
	git(dir, "add -A")
	_ = git(dir, "commit -q -m {file}")

# this zap, named from any dir
fn zap():
	fs.join(currentDir(), zapPath())

# the repository the tests share, "" until the first makes it
mut sharedRepository = ""

# A repository on main: a.txt, a compiler (by default one whose suite passes, any other committed
# on top), the runtime it is built with and a std; the branch seed holding this zap as the host's
# seed. The first test makes it in the dir the tests share; each after resets it (resetRepository),
# its land checkouts kept warm as zap branch keeps them. Its dir.
fn landRepository(compiler str = passingCompiler):
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
fn branchWith(dir str, branch str, file str, text str):
	at = "{dir}-wt-{branch}"
	git(dir, "worktree add -q -b {branch} {quoteArg(at)} main")
	commit(at, file, text)
	at

# what a zap command line run in dir says, its exit code first: dir written <repo>, and the
# commit cut from the line saying where main is
fn zapIn(dir str, words str):
	said = Process.output("{quoteArg(zap())} {words}", dir = dir)
	lines = ["{said.code}"]
	for line in said.out.replace("\r\n", "\n").replace(dir, "<repo>").lines():
		if line.startsWith("land: main is at "):
			rest = line[17..]
			lines.push("land: main is at{rest[(rest.indexOf(" ") ?? 0)..]}")
		else:
			lines.push(line.copy())
	lines.join("\n")

test "branches land one after the other: one whose suite passes moves main to it, one whose suite fails leaves main where it was and ends the run":
	dir = landRepository()
	branchWith(dir, "first", "b.txt", "b\n")
	branchWith(dir, "broken", "compiler/zap.zap", "exit(1, \"the suite fails\")\n")
	branchWith(dir, "last", "c.txt", "c\n")
	print(zapIn(dir, "branch land first broken last"))
	expect fs.exists("{dir}/b.txt") and not fs.exists("{dir}/c.txt") and
		not fs.exists("{dir}-wt-first")
	prints """
		1
		land: first merged in <repo>-land
		land: the merge changes b.txt; zap test --only build,dups,limits,check,tests compiler runtime std spec tests
		the suite passes
		land: first landed
		land: removed the worktree <repo>-wt-first
		land: removed the branch first
		land: main is at b.txt
		land: broken merged in <repo>-land
		land: the merge changes compiler/; zap test --only build,dups,limits,check,tests compiler
		the suite fails
		land: the suite failed on the merge of broken (<repo>-land); main not moved
		land: main is at b.txt
		"""

test "forms the lint finds in the merge are written and committed by the land, and the suite runs again on them":
	dir = landRepository(lintWritingCompiler)
	branchWith(dir, "first", "b.txt", "b")
	print(zapIn(dir, "branch land first"))
	print(git(dir, "ls-tree --name-only main"))
	prints """
		0
		land: first merged in <repo>-land
		land: the merge changes b.txt; zap test --only build,dups,limits,check,tests compiler runtime std spec tests
		the suite writes a form
		land: the lint's forms of the merge written and committed; the suite runs again
		the suite passes
		land: first landed
		land: removed the worktree <repo>-wt-first
		land: removed the branch first
		land: main is at The lint's forms of the merge
		.gitignore
		b.txt
		c.txt
		compiler
		runtime
		std
		"""

# whether a line of a land says how it ended, not what it merged or ran
fn landOutcome(line str):
	line.startsWith("land: ") and line.indexOf("merged in") == none and
		line.indexOf("; zap test") == none

test "a landed branch's worktree with changes not committed, or holding ignored files outside build/ (removing it would erase them), is kept, and so is the branch":
	dir = landRepository()
	notes = branchWith(dir, "notes", "b.txt", "b\n")
	_ = fs.writeFile("{notes}/notes.txt", "not committed\n")
	rom = branchWith(dir, "rom", ".gitignore", "build/\nrom/\n")
	_ = fs.createDir("{rom}/rom")
	_ = fs.writeFile("{rom}/rom/game.bin", "the game\n")
	_ = fs.createDir("{rom}/build")
	_ = fs.writeFile("{rom}/build/a.exe", "built\n")
	said = zapIn(dir, "branch land notes rom").lines()
	print(said[1..].filter(landOutcome(it)).join("\n"))
	print(fs.exists("{rom}/rom/game.bin"))
	prints """
		land: notes landed
		land: <repo>-wt-notes kept: it has uncommitted changes
		land: main is at b.txt
		land: rom landed
		land: <repo>-wt-rom kept: it holds ignored files (rom/), which removing it would erase
		land: main is at Merge branch 'rom'
		true
		"""

test "a branch in main already is not merged again, only removed":
	dir = landRepository()
	branchWith(dir, "feature", "b.txt", "b\n")
	git(dir, "merge -q feature")
	print(zapIn(dir, "branch land feature"))
	prints """
		0
		land: feature is in main already
		land: removed the worktree <repo>-wt-feature
		land: removed the branch feature
		land: main is at b.txt
		"""

# `zap branch land feature` while the suite moves a file of main's checkout to `to` and commits
# it: what it says between the first suite and the land, the lines before and after checked here
fn landWhileMainMoves(dir str, to str):
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

test "main moved by a commit that changes only .md files during the suite: no second suite":
	dir = landRepository(compilerMovingMain("old.md", "notes.md"))
	commit(dir, "old.md", "doc\n")
	print(dir.landWhileMainMoves("notes.md"))
	prints "land: the change touches no file a check reads; no suite"

test "main moved by a code commit during the suite: the suite runs again, then main moves":
	print(landRepository(compilerMovingMain("a.txt", "c.txt")).landWhileMainMoves("c.txt"))
	prints """
		land: the new commits change c.txt; zap test --only build,dups,limits,check,tests compiler runtime std spec tests
		the suite passes again
		"""

test "what a merge changes decides the run: a project's own checks, no suite for documentation":
	dir = landRepository()
	branchWith(dir, "game", "projects/skyrim/main.zap", "x\n")
	branchWith(dir, "engine", "engine/e.zap", "e\n")
	branchWith(dir, "docs", "notes.md", "n\n")
	branchWith(dir, "lib", "std/s.zap", "s\n")
	branchWith(dir, "tool", "tools/t.zap", "t\n")
	said = zapIn(dir, "branch land game engine docs lib tool").lines()
	print(said.filter(.startsWith("land: the ")).join("\n"))
	prints """
		land: the merge changes projects/skyrim; zap test --only check,tests projects/skyrim
		land: the merge changes engine/; zap test --only check,tests engine
		land: the change touches no file a check reads; no suite
		land: the merge changes std/; zap test --only build,dups,limits,check,tests std
		land: the merge changes tools/; zap test --only build,dups,limits,check,tests compiler runtime std spec tests
		"""

test "a merge that conflicts is aborted, its files listed":
	dir = landRepository()
	branchWith(dir, "clash", "a.txt", "clash\n")
	commit(dir, "a.txt", "main\n")
	print(zapIn(dir, "branch land clash"))
	expect git("{dir}-land", "status --porcelain") == ""
	prints """
		1
		land: clash conflicts with main; nothing landed. The files:
		  a.txt
		land: main is at a.txt
		"""

test "uncommitted changes in main's checkout refuse the land":
	dir = landRepository()
	branchWith(dir, "feature", "b.txt", "b\n")
	_ = fs.writeFile("{dir}/a.txt", "changed\n")
	print(zapIn(dir, "branch land feature"))
	prints """
		1
		land: <repo> has uncommitted changes; nothing landed
		land: main is at a.txt
		"""

test "a land waits while a running process holds the lock, and takes over one whose ended":
	dir = landRepository()
	branchWith(dir, "first", "b.txt", "b\n")
	branchWith(dir, "second", "c.txt", "c\n")
	ended = git(dir, "hash-object -w --stdin", "999999999\n")
	git(dir, "update-ref refs/zap/land {ended}")
	print(zapIn(dir, "branch land first").lines()[..2].join("\n"))
	git(dir, "update-ref refs/zap/land {git(dir, "hash-object -w --stdin", "{processId()}\n")}")
	out = "{testDir()}second.txt"
	enter = "cd /d" if onWindows() else "cd"
	p = Process.start(
		shellLine(
			"{enter} {quoteArg(dir)} && {quoteArg(zap())} branch land second > {quoteArg(out)} 2>&1"
		)
	)
	# the lock goes once the land says it waits (a loaded machine may take long to start it)
	loop 600:
		if "waiting" in (fs.readFile(out) ?? "") or p.isDone: break
		sleepMs(100)
	expect not p.isDone
	git(dir, "update-ref -d refs/zap/land")
	print(p.wait())
	print((fs.readFile(out) ?? "").lines()[0].replace("{processId()}", "<this>"))
	expect git(dir, "rev-parse --verify --quiet refs/zap/land") == ""
	prints """
		0
		land: took over the lock of process 999999999, which ended
		0
		land: waiting for the land of process <this>
		"""

test "a new branch takes main's compiler when the sources are main's, else the seed builds one":
	dir = landRepository()
	print(zapIn(dir, "branch new one"))
	commit("{dir}-wt-one", "b.txt", "b\n")
	expect zapIn(dir, "branch land one").startsWith("0\n")
	print(zapIn(dir, "branch new two"))
	print(Process.output(quoteArg("{dir}-wt-two/build/zap{exeSuffix()}")).out.trimmedEnd())
	commit(dir, "compiler/zap.zap", "print(\"changed\")\n")
	print(zapIn(dir, "branch new three"))
	prints """
		0
		new: <repo>-wt-one, on one; build/zap.exe built by the host's seed
		0
		new: <repo>-wt-two, on two; build/zap.exe taken from main's checkout
		the suite passes
		0
		new: <repo>-wt-three, on three; build/zap.exe built by the host's seed
		"""

test "status lists each branch beside main with its state, and whether a land holds the lock":
	dir = landRepository()
	branchWith(dir, "ahead", "b.txt", "b\n")
	branchWith(dir, "merged", "c.txt", "c\n")
	at = branchWith(dir, "dirty", "d.txt", "d\n")
	git(dir, "merge -q merged")
	_ = fs.writeFile("{at}/notes.txt", "not committed\n")
	print(zapIn(dir, "branch status"))
	_ = fs.createDir("{dir}-land-2/build")
	_ = fs.writeFile("{dir}-land-2/build/land.pid", "999999999\n")
	_ = fs.createDir("{dir}-land/build")
	_ = fs.writeFile("{dir}-land/build/land.pid", "{processId()}\n")
	held = zapIn(dir, "branch status").lines()
	print(held[4..].join("\n").replace("{processId()}", "<this>"))
	prints """
		0
		ahead: not in main, 1 ahead, 1 behind, clean
		dirty: not in main, 1 ahead, 1 behind, uncommitted changes
		merged: in main, 0 ahead, 0 behind, clean
		no land runs
		<repo>-land: a land runs there, process <this>
		"""

# a compiler whose suite waits (30 s at most) until a second land holds a land checkout of its own,
# so two lands overlap
meetingCompiler = """
	loop 600:
		if Process.output("git hash-object ../repo-land-2/build/land.pid").code == 0: break
		sleepMs(50)
	print("the suite passes")
	"""

test "two lands at once each run in a land checkout of their own, and both land":
	dir = landRepository(meetingCompiler)
	branchWith(dir, "first", "b.txt", "b\n")
	branchWith(dir, "second", "c.txt", "c\n")
	enter = "cd /d" if onWindows() else "cd"
	outs = ["first", "second"].map("{testDir()}{it}.txt")
	lands = ["first", "second"].map(name:
		out = outs[0 if name == "first" else 1]
		Process.start(
			shellLine(
				"{enter} {quoteArg(dir)} && {quoteArg(zap())} branch land {name} > {quoteArg(out)} 2>&1"
			)
		)
	)
	codes = []
	for mut p in lands:
		codes.push(p.wait())
	said = outs.map((fs.readFile(it) ?? "").replace(dir, "<repo>").lines())
	print(codes)
	# which land takes which checkout is whichever comes first
	print(said.map(.filter(.indexOf("merged in") != none)[0].split(" merged in ")[1]).sorted())
	expect fs.exists("{dir}/b.txt") and fs.exists("{dir}/c.txt")
	expect not fs.exists("{dir}-land/build/land.pid") and
		not fs.exists("{dir}-land-2/build/land.pid")
	expect git(dir, "rev-parse --verify --quiet refs/zap/land") == ""
	prints """
		[0, 0]
		["<repo>-land", "<repo>-land-2"]
		"""

test "a branch line without its subcommand, or with the wrong names, is refused with the usage":
	dir = landRepository()
	print(zapIn(dir, "branch new").lines()[..2].join("\n"))
	print(zapIn(dir, "branch frob").lines()[..2].join("\n"))
	print(zapIn(dir, "branch status now").lines()[..2].join("\n"))
	prints """
		2
		zap branch: new takes one name
		2
		zap branch: no subcommand frob
		2
		zap branch: status takes no name
		"""
