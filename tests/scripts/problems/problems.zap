# The script problems: what an agent writes to look at a repository or a file once, in Zap and in
# Python (others/<name>.py), each pair printing the same bytes. `zap test --only bench
# tests/scripts` races them (tests/scripts/bench.zap, std/compare's script race); the test in
# agree.zap checks the outputs. The inputs are fixed: data/ holds small files, and repo.fi a
# git fast-import stream of a repository of sources and of 300 commits, made once into
# build/scripts/repo, so outputs and times stay comparable whatever this repository holds.
import compare
import fs

repoDir = "build/scripts/repo"

# the fixed repository, made once from data/repo.fi (no autocrlf: the bytes are the stream's)
pub fn prepare():
	if fs.exists("{repoDir}/.git"): return
	_ = fs.createDir("build/scripts")
	made = [
		"git init -q -b main {repoDir}",
		"git -C {repoDir} config core.autocrlf false",
		"git -C {repoDir} fast-import --quiet < tests/scripts/data/repo.fi",
		"git -C {repoDir} reset -q --hard"
	]
	for line in made:
		if Process.run(shellLine(line)) != 0:
			_ = fs.deleteTree(repoDir)
			exit(1, "cannot make the fixed repository of tests/scripts: {line}")

pub fn problems() compare.Problem[]:
	pattern = quoteArg(r"^pub\sfn\s\w+\(.*\)\sstr:$")
	[
		# the functions per file under a dir (a regex per line), the ten most and a JSON line
		script("count", "{repoDir}/compiler"),
		# the last 200 commits' subjects by their first word
		script("gitlog", repoDir),
		# a column of a TSV summed by name
		script("table", "tests/scripts/data/t.tsv"),
		# a regex over every line of the files under a dir, found lines printed with their place
		script("grep", "{repoDir}/std {pattern}"),
		# the files of git ls-files by extension: lines, blank and comment lines
		script("loc", repoDir),
		# a JSON file filtered, grouped and written back as JSON
		script("jsonq", "tests/scripts/data/commits.json"),
		# a quoted CSV read and summed by a column
		script("csvsum", "tests/scripts/data/commits.csv"),
		# a tree copied and a regex replaced in every file of it
		script("replace", "{repoDir}/std build/scripts/replaced"),
		# the TODO and FIXME lines of git ls-files, by dir
		script("todo", repoDir),
		# the longest common subsequence of two files' lines, as a diff
		script("diff", "tests/scripts/data/old.txt tests/scripts/data/new.txt"),
		# the files most often changed in all of git log --numstat
		script("gitstat", repoDir)
	]

# a script problem: Zap's script and its Python one, run with the arguments
fn script(name str, arg str):
	compare.Problem(
		name = "script-{name}",
		zap = "tests/scripts/{name}.zap",
		others = ["tests/scripts/others/{name}.py"],
		arg = arg.copy(),
		quickArg = arg.copy(),
		smallArg = arg.copy(),
		stdin = false,
		flags = "",
		script = true
	)

# whether the problem's Zap and Python scripts print the same bytes
pub fn agree(name str) bool:
	prepare()
	all = problems()
	i = all.findIndex(.name == "script-{name}") ?? return false
	all[i].agree("")
