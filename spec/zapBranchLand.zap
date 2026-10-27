# 13.1.5 `zap branch land`: how a land ends
# host: windows (land runs where the lint runs, and refuses elsewhere)

# The tests below land branches in a repository made as zapBranch.zap's: a branch whose suite passes or
# fails, the lint's forms, a worktree that is kept, a branch in main already, a conflict, changes not
# committed in main's checkout.

import fs
from branchRepo import branchWith, commit, git, landRepository, lintWritingCompiler, zapIn

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
