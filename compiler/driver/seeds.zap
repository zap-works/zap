# The seeds (spec 14.1): the compiler built for each host, the files of the one commit of the
# orphan branch `seed`, a dir a host holding its seed.exe (windows/seed.exe, linux/seed.exe, ...).
# A fresh clone builds its first compiler with its host's seed; the fixed point (checks.zap) builds
# the compiler from the sources with it; `zap build --seeds` makes them all again from the sources.

import fs

# the compiler's entry file, from the zap repository's root
compilerSource = "compiler/zap.zap"

# the dirs a build of the compiler reads its sources from
compilerSourceDirs = ["compiler", "runtime", "std"]

# a seed's file name, in its host's dir of the branch and in a build's dir: one name on every
# system (Windows runs no file without its extension, Linux runs it as named)
seedFile = "seed.exe"

# The line, run at the zap repository's root, that writes the host's seed of the branch to
# dir/seed.exe, runnable (the mode the branch keeps): the same line in every shell (spec 14.1).
fn seedLine(branch str, t Target, dir str):
	"git archive --prefix={dir}/ {branch}:{t.name} | tar -xf -"

# The compiler at root built for the target by the zap at zap (a full path), in dir (a full path,
# made when missing), which then holds it (builtCompiler, even when a test started this zap) and its
# build's caches: whether it built.
# The runtime is root's, wherever zap lies.
fn buildCompiler(root str, zap str, t Target, dir str):
	_ = fs.createDir(dir)
	option = "" if t.name == hostTarget() else " --target {t.name}"
	line = "{quoteArg(hostPath(zap))} build{option} {quoteArg("{root}/{compilerSource}")}"
	# (ZAP_RUNTIME only for a seed from before the runtime word: gone once the seeds are promoted)
	vars = [
		runAssignment("runtime={root}/runtime"),
		"ZAP_RUNTIME={root}/runtime",
		"{buildsVariable().name}={dir}/build"
	]
	Process.output(line, vars = vars, dir = dir).code == 0

# the executable buildCompiler writes in dir for the target
fn builtCompiler(dir str, t Target):
	"{dir}/build/zap{t.extensionOf()}"

# the branch of the seeds: the newest of the local seed (a promotion not pushed yet) and origin's
# (one pushed from elsewhere), by their commits' times
fn seedBranch(root str):
	times = ["seed", "origin/seed"].map(
		i64.parse(gitSays(root, "log -1 --format=%ct {it} --", "")) ?? -1
	)
	"seed" if times[0] >= times[1] else "origin/seed"

# zap build --seeds: every host's compiler built twice from the sources at the working directory,
# the zap repository's root, by this zap and then by the host's first build, each a fixed point
# (the two builds the same bytes), and the branch seed made again as one orphan commit of them
pub fn promoteSeeds():
	if not fs.exists(compilerSource):
		exit(2, "zap build --seeds: run it at the zap repository's root")
	root = fullPath(".")
	hosts = targets.filter(.isHost)
	first = hosts.all(buildCompiler(root, exePath(), it, "{root}/build/seeds/1/{.name}"))
	zap = builtCompiler("{root}/build/seeds/1/{hostTarget()}", host())
	second = first and hosts.all(buildCompiler(root, zap, it, "{root}/build/seeds/2/{.name}"))
	if not second:
		exit(1, "zap build --seeds: a host's build failed")
	rows = []
	for t in hosts:
		file = builtCompiler("{root}/build/seeds/2/{t.name}", t)
		if not sameBytes(builtCompiler("{root}/build/seeds/1/{t.name}", t), file):
			exit(1, "zap build --seeds: {t.name}'s two builds differ (the compiler does not reproduce itself)")
		mode = "100644" if t.system == systemWindows else "100755"
		blob = gitSays(root, "hash-object -w {file}", "")
		dir = gitSays(root, "mktree", "{mode} blob {blob}\t{seedFile}\n")
		rows.push("040000 tree {dir}\t{t.name}\n")
	head = gitSays(root, "rev-parse --short HEAD", "")
	commit = gitSays(
		root,
		"commit-tree {gitSays(root, "mktree", rows.join(""))} -m \"the seeds of {head}\"",
		""
	)
	if commit == "-" or gitSays(root, "update-ref refs/heads/seed {commit}", "") == "-":
		exit(1, "zap build --seeds: git could not make the commit")
	print("seed: {commit}, the seeds of {head}; push it with main: git push -f origin seed (spec 14.1)")

# what git prints for the words at root, given input, its last newline cut ("-" when it fails)
fn gitSays(root str, words str, input str):
	run = Process.output("git {words}", input = input, dir = root)
	"-" if run.code != 0 else run.out.trimmedEnd().copy()

# whether the two files hold the same bytes (a missing one none)
fn sameBytes(a str, b str):
	(fs.readFile(a) ?? "") == (fs.readFile(b) ?? "")
