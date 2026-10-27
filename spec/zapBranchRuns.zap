# 13.1.5 `zap branch land`: what runs after main moves or the merge changes
# host: windows (land runs where the lint runs, and refuses elsewhere)

# The tests below land a branch while main moves under the suite, and branches whose merges change
# different directories, in a repository made as zapBranch.zap's.

from branchRepo import branchWith, commit, compilerMovingMain, landRepository, landWhileMainMoves, zapIn

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
