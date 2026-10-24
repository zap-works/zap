# The script race (a Problem with script = true; spec 13.1): a throwaway script's time end to end,
# as an agent meets it. Zap's side is `zap run script.zap args` after an edit of the script (the
# build's caches warm, a trailing comment's text rewritten before each run, so the script is
# compiled again) and, apart, the same run unchanged; the rival is `python script.py args`. The
# three are run in turns, rounds times, and the median of each is kept; the ratio raced is Zap
# edited over Python, in wall time (Zap's run starts the compiled script as a child, so no one
# process's cycles hold it). A script's arguments are the problem's arg; the scripts' output is
# compared with the line endings read as LF (Python's text streams write CRLF on Windows).

import fs

# the rounds of a script race: the least, so that a median is not one run's noise
scriptRounds = 5

# the limit of one script run, in seconds
scriptSeconds = 120.0

# the command that runs Zap's script at src: the compiler of the PATH, compiling it again
fn zapScriptLine(src str, arg str):
	"{quoteArg(zapExePath())} run {src} {arg}"

# the command that runs the Python script at src
fn pythonScriptLine(src str, arg str):
	"{python()} -I {src} {arg}"

# a script's output with its line endings as LF
fn scriptLineEndings(text str):
	text.replace("\r\n", "\n")

fn scriptOutput(path str):
	scriptLineEndings(fs.readFile(path) ?? "")

# A script problem raced: the medians of Zap's run after an edit, of its unchanged run and of
# Python's, and whether all printed the same bytes.
type ScriptRace:
	edited Run
	same Run
	python Run
	output bool

# Races the problem's two scripts rounds times, in turns; the first turn only warms the caches
# (std's modules, the interpreter's files). None when a run failed.
fn raceScript(p Problem, rounds i64) ScriptRace?:
	source = fs.readFile(p.zap) ?? return none
	pyPath = try p.others.find(extensionOf(it) == "py")
	dir = "{benchDir}/scripts"
	_ = fs.createDir(dir)
	work = "{dir}/{fs.fileName(p.zap)}"
	zapLine = zapScriptLine(work, p.arg)
	pyLine = pythonScriptLine(pyPath, p.arg)
	zapOut = "{dir}/{p.name}.zap.out"
	sameOut = "{dir}/{p.name}.same.out"
	pyOut = "{dir}/{p.name}.py.out"
	edited = []
	same = []
	python = []
	stamp = i64(clockSeconds() * 1000.0)
	for round in 0..=rounds:
		_ = fs.writeFile(work, "{source}\n# edit {stamp + round}\n")
		e = runMeasured(zapLine, "", zapOut, 0, scriptSeconds)
		s = runMeasured(zapLine, "", sameOut, 0, scriptSeconds)
		y = runMeasured(pyLine, "", pyOut, 0, scriptSeconds)
		if e.code != 0 or s.code != 0 or y.code != 0:
			eprint(
				"{p.name}: a run failed (zap edited {e.code}, unchanged {s.code}, python {y.code})"
			)
			return none
		if round > 0:
			edited.push(e)
			same.push(s)
			python.push(y)
	expected = scriptOutput(pyOut)
	ScriptRace(
		edited = medianRun(edited),
		same = medianRun(same),
		python = medianRun(python),
		output = scriptOutput(zapOut) == expected and scriptOutput(sameOut) == expected
	)

fn milliseconds(run Run):
	run.seconds * 1000.0

# A script suite (suite's, when the problems are scripts): the table, and for zap test the
# `bench` line of each problem, time: Zap edited over Python, in nanoseconds of wall time. Ends
# with 1 when a script failed or printed something else. Nothing is built in advance and nothing
# kept: an edited run is never one that was measured before.
fn scriptSuite(problems Problem[], request SuiteRequest):
	if request.ab != "": return   # (a race of two zaps: scripts are raced against Python's alone)
	if request.tokens:
		tokensLines(problems, request.name)
		return
	rounds = request.runs.max(scriptRounds)
	print("script           zap edited    zap same      python   edited / python   same / python  output")
	failed = false
	for p in problems:
		if request.name not in p.name: continue
		match p.raceScript(rounds):
			race:
				ratio = race.edited.seconds / race.python.seconds
				again = race.same.seconds / race.python.seconds
				check = "ok" if race.output else "DIFFERS"
				failed = failed or not race.output
				print(
					"{p.name:<14}{race.edited.milliseconds():>10.0} ms{race.same.milliseconds():>9.0} ms{race.python.milliseconds():>9.0} ms{ratioCell(ratio):>16}{ratioCell(again):>16}  {check}"
				)
				benchLine(
					p.name,
					"time",
					i64((race.edited.seconds * 1.0e9).round()),
					i64((race.python.seconds * 1.0e9).round()),
					"python",
					p.zap,
					p.arg,
					""
				)
			none: failed = true
	if failed:
		exit(1)

# whether the script problem's two scripts print the same bytes (the check of its test): each
# run as the race runs them, a difference named on stderr
fn scriptAgree(p Problem):
	pyPath = p.others.find(extensionOf(it) == "py") ?? return false
	lines = [zapScriptLine(p.zap, p.arg), pythonScriptLine(pyPath, p.arg)]
	outDir = "{benchDir}/scripts/{p.name}"
	_ = fs.createDir(outDir)
	sameOutput(lines, "", outDir, true)
