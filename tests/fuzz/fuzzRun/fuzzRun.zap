# What the fuzzers share: a generated program is a test file whose one test holds the program's
# statements and checks that it prints what the fuzzer worked out, and `zap test` runs it, which
# also poisons freed memory and fails when a block is left allocated. A failing program is kept
# beside it.

import fs

# the first line of the test that stands for the program's main
pub fn testHeader() str:
	"test \"the program prints what the fuzzer worked out\":"

# the test's last lines: the check that the program printed `want` (lines, each ending in \n)
pub fn testCheck(want str) str:
	text = want.replace("\\", "\\\\").replace(r"{", r"\{").replace("\n", "\n\t\t")
	"\tprints \"\"\"\n\t\t{text}\"\"\""

# whether a line from `from` on moves the variable name whole (`move name`), which leaves it usable and
# empty where a later line changes it
pub fn movesWhole(lines str[], from i64, name str) bool:
	for j in from..lines.len:
		at = 0
		loop:
			found = lines[j].indexOf("move {name}", at) ?? break
			end = found + 5 + name.len
			if end >= lines[j].len or
				not (lines[j][end].isWordByte() or lines[j][end] == '.' or lines[j][end] == '['):
				return true
			at = found + 1
	false

# runs the test file (written by the caller in its test's dir) of the program made from seed;
# whether it passed. A failure is kept (keptFailure: the test's dir goes when it ends), and what
# zap test said goes to stderr.
pub fn passes(file str, seed i64) bool:
	tested = Process.output("{zapPath()} test --only tests {file}")
	if tested.code == 0: return true
	keep = keptFailure(file, seed)
	_ = fs.writeFile(keep, fs.readFile(file) ?? "")
	eprint("FAIL seed {seed} ({keep}):\n{tested.out.trimmed()}")
	false

# where the program of file made from seed is kept when it failed: build/fuzz/<stem>-fail<seed>.zap
pub fn keptFailure(file str, seed i64) str:
	_ = fs.createDir("build/fuzz")
	"build/fuzz/{fs.stem(file)}-fail{seed}.zap"
