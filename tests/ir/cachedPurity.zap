# The cache of simplified functions (build/cache/) keys a function by its whole lowered form, a
# call's purity included: a call that became impure is not given the simplification of its pure
# self, which made the two calls one.

import fs

fn buildAndRun(dir str, source str):
	_ = fs.writeFile("{dir}main.zap", source)
	Process.output("{zapPath()} run {dir}main.zap").out.trimmed().copy()

test "a call that became impure is made each time it is written":
	dir = "{testDir()}cachedPurity/"
	_ = fs.createDir(dir)
	twice = "fn twice(k i64) i64:\n\tif k == 0: return f(5) + f(5)\n\ttwice(k - 1)\n\n"
	# a body too large to inline, so the calls stay calls
	terms = (1..40).map("(n * {it} + {it}) / {it + 1}").join(" + ")
	pure = "fn f(n i64) i64:\n\t{terms}\n\n"
	print(buildAndRun(dir, "{twice}{pure}print(twice(1))\n"))
	impure = "fn f(n i64) i64:\n\tprint(\"called\")\n\t{terms}\n\n"
	print(buildAndRun(dir, "{twice}{impure}print(twice(1))\n"))
	prints """
		380
		called
		called
		380
		"""
