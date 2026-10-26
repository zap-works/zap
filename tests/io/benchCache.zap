# std/compare's cache of measured runs: a tiny bench suite (a Zap program against a Python one)
# run again reuses both results, a changed source is measured again, and --fresh measures all.

import fs

# the suite's source, over the programs the test writes
suiteSource = """
	import compare

	fn inputFor(mode str) str: ""

	compare.suite(
		[compare.Problem(
			name = "benchcacheprog",
			zap = "DIRbenchcacheprog.zap",
			others = ["DIRbenchcacheprog.py"],
			arg = "1",
			quickArg = "1",
			smallArg = "1",
			stdin = false,
			flags = ""
		)],
		inputFor,
		args
	)
	"""

# the cache line of the suite run with the options
fn cacheLine(suite str, options str):
	for line in Process.output("{zapPath()} run {suite} {options}").out.lines():
		if line.startsWith("cache:"): return line.copy()
	"no cache line"

# writes the two programs, each with a comment of its own text
fn writePrograms(zapNote str, pythonNote str):
	dir = testDir()
	_ = fs.writeFile("{dir}benchcacheprog.zap", "# {zapNote}\nprint(\"hi\")\n")
	body = "import sys\nsys.stdout.buffer.write(bytes([104, 105, 10]))\n"
	_ = fs.writeFile("{dir}benchcacheprog.py", "# {pythonNote}\n{body}")

test "a bench suite reuses the cached runs, measures a changed source again, --fresh Zap's, --fresh all every one":
	dir = testDir()
	suite = "{dir}benchcachesuite.zap"
	_ = fs.writeFile(suite, suiteSource.replace("DIR", dir))
	stamp = "{clockSeconds()}"
	writePrograms(stamp, stamp)
	print(cacheLine(suite, ""))
	print(cacheLine(suite, ""))
	writePrograms("{stamp} changed", stamp)
	print(cacheLine(suite, ""))
	print(cacheLine(suite, "--fresh"))
	print(cacheLine(suite, "--fresh all"))
	prints """
		cache: 0 of 2 results reused
		cache: 2 of 2 results reused
		cache: 1 of 2 results reused
		cache: 1 of 2 results reused
		cache: 0 of 2 results reused
		"""
