# zap run's executable kept from one run to the next (spec 13.1): a stamp beside it names what
# it was built from (stamps.zap: the compiler's key, each source the build parsed or embedded,
# their dirs), the entry, the words of ZAP_RUN and ZAP_SETUP and the executable's own write, so a
# run that changed none of them starts it without loading the program. A file outside a checkout
# (no build/zap.exe at its dir or above it) is built in the user's cache, keyed by its full path,
# its caches beside the others of the kind: the working dir is left as it was.

import fs

# where this run's executable goes ("": buildsDir) and the build's caches
mut runExeDir = ""
mut cachesDir = "build/cache"

# the run of the entry placed: in the user's cache when the file lies outside a checkout
fn placeRun(file str):
	if insideCheckout(file): return
	zap = fs.cacheDir("zap")
	runExeDir = "{zap}/run/{testSlug(fullPath(file))}/"
	cachesDir = "{zap}/cache"

# whether a dir at the file's or above it holds a zap built for this host
fn insideCheckout(file str):
	dir = fs.dirOf(fullPath(file)).copy()
	loop 64:
		if fs.exists(builtCompiler(dir, host())): return true
		up = fs.dirOf(dir)
		if up == "" or up == dir: return false
		dir = up.copy()
	false

fn runStampOf(exe str):
	"{exe}.stamp"

# what a kept executable was built for besides its sources: the entry, the environment's words
fn runFor(file str):
	run = runVariable().value() ?? ""
	setup = setupVariable().value() ?? ""
	"entry\t{fullPath(file)}\nrun\t{run}\nsetup\t{setup}\nexe\t"

# whether the executable at exe is the one a build of file would write now
fn runKept(file str, exe str):
	text = fs.readFile(runStampOf(exe)) ?? return false
	kept = keptWhileSame(text) ?? return false
	written = fs.modified(exe) ?? return false
	kept == "{runFor(file)}{written}"

# the stamp of the executable just built from file, the sources this process parsed its files,
# the entry first: an edited entry, the usual change, is told before the runtime's are hashed
fn keepRun(file str, exe str):
	files = [fullPath(file)]
	for i, at in sourcesParsed:
		full = fullPath(at)
		fileHashes[full.copy()] = "{sourceHashes[i]}"
		time = fileTimes.get(at) ?? 0
		if time != 0: fileTimes[full.copy()] = time
		if full not in files: files.push(full)
	written = fs.modified(exe) ?? return
	_ = fs.writeFile(runStampOf(exe), stamped(files, "{runFor(file)}{written}"))
