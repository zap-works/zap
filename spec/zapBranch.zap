# 13.1.5 `zap branch`
# host: windows (land runs where the lint runs, and refuses elsewhere)

import fs
from branchRepo import branchWith, commit, git, landRepository, zap, zapIn

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
# repository's main one, holds changes not committed or holds ignored files outside a build/ dir (a
# project's data, which the removal would erase), and then the branch. The push stays by hand: the
# last line says where main stands.
#
# `zap branch status` lists the branches with a worktree beside main's checkout, one line each:
# whether the branch is in main already, its commits ahead of and behind main, and whether its
# worktree has changes not committed (untracked files too); then the lands running, one line each
# with its checkout and process, or that none runs.
#
# The tests of this file and of zapBranchLand.zap and zapBranchRuns.zap (split so each stays in the
# clock limit) each share one repository, made once in `testFileDir()` and reset for each, with a
# compiler whose `zap test` passes, the runtime beside it and the branch seed holding this zap
# (branchRepo).

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
