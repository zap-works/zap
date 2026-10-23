# 13.2 Environment variables
#
# The repository reads two environment variables, each a comma-separated list of words (`word` or
# `word=value`, `disasm=main`), each word declared once with a line saying what it does:
# `ZAP_SETUP` holds what is set once on a machine, as `SetupWord("arm64", "...")` (`arm64=<ssh
# name>`, `memory=MB`, `android=<adb serial>`, `dxc=<path>`); `ZAP_RUN` holds what one run asks for,
# the behaviours as `RunWord("gpu", "...")` (`headless`, `gpu=d3d12`, `audio=off`, `hostcopy=off`,
# `pipelinecache=off`, `runtime=<dir>`) and the diagnostics as `TraceWord("profile", "...")`. A word
# is read by its `on()` and `value()`, and its name is declared in one group only. Where zap sets
# words for the programs it starts (zap test sets `headless`) it adds them to the list the user
# gave. The variables zap sets for the programs it starts are `InternalVariable("ZAP_TEST_RUN")`:
# read as an `EnvVariable("NAME", "...")` is, left out of the table. A new setting is a word of
# one of the two lists, or a program's option, never a new variable. `zap doc environment` prints
# the declarations of the working dir's repository, its dependencies, std, the runtime and the
# compiler after this section, and `zap run`, `zap build` and `zap test` refuse a word of
# `ZAP_SETUP` or `ZAP_RUN` that nothing declares, listing the words.

import fs

fn profileWord():
	TraceWord("profile", "zap run samples the program")

fn mapWord():
	TraceWord("map", "writes the map of the functions")

test "a trace word may carry a value":
	before = env.get("ZAP_RUN") ?? ""
	env["ZAP_RUN"] = "map,profile=main"
	print("{profileWord().on()} {profileWord().value()} {mapWord().value()}")
	print(TraceWord("prof", "a word not given").value())
	env["ZAP_RUN"] = before
	prints """
		true some("main") some("")
		none
		"""

test "a variable is read through its declaration":
	before = env.get("ZAP_TEST_ENV") ?? ""
	declared = EnvVariable("ZAP_TEST_ENV", "a variable of this test")
	env[declared.name] = "set"
	print(declared.value())
	env[declared.name] = before
	prints "some(\"set\")"

# The compiler's words explain a pass on stderr; `profile` makes `zap run` sample the program's
# main thread about every millisecond and list its functions by self and total time (`profile=name`
# also counts that function's callers and the addresses its samples stopped at). `map` writes
# `build/x.exe.map` beside the executable, its functions' addresses after the executable's hash:
# what reads it (`profile`, `disasm`, `zap test --only size`) refuses a map of another build.

# what running `command` with ZAP_RUN set to `words` writes, both streams, in the test's dir
fn traced(words str, command str):
	Process.output(command, vars = ["ZAP_RUN={words}"]).out.replace("\r\n", "\n")

fn program():
	file = "{testDir()}traced.zap"
	_ = fs.writeFile(file, "xs = [1, 2]\nprint(xs.len)\n")
	file

test "tokens lists the entry file's tokens":
	said = traced("tokens", "{zapPath()} build {program()}")
	expect "1:1   identifier       xs" in said and "1:7   int literal      1" in said

test "a word no declaration names is refused, the words listed":
	said = traced("map,nocahe", "{zapPath()} build {program()}")
	expect said.startsWith("zap: ZAP_RUN names no word 'nocahe': ") and ", nocache, " in said

test "a program's own word is known to its build":
	file = "{testDir()}own.zap"
	_ = fs.writeFile(file, "fn drawWord() TraceWord:\n\tTraceWord(\"draws\", \"each draw\")\n\nprint(drawWord().on())\n")
	print(traced("draws", "{zapPath()} run {file}").trimmed())
	prints "true"

test "zap doc environment lists the declarations":
	said = traced("", "{zapPath()} doc environment")
	expect "  ZAP_SETUP " in said and "  ZAP_RUN " in said and "  memstats " in said and
		"  tokens " in said
	expect "words of ZAP_SETUP" in said and "  arm64 " in said and "  headless " in said and
		"  gpu " in said
	table = said[(said.lastIndexOf("environment variables:") ?? 0)..]
	expect "  ZAP_TEST_RUN " not in table and "  ZAP_READS " not in table

test "a word is declared in one group only":
	said = traced("", "{zapPath()} doc environment")
	names = said
		.lines()
		.filter(.startsWith("  ") and not .startsWith("  ZAP_"))
		.map(.trimmed().split(" ")[0])
	repeated = []
	for i, name in names:
		if name in names[i + 1..]: repeated.push(name)
	print(repeated)
	prints "[]"

test "a run word may carry a value":
	before = env.get("ZAP_RUN") ?? ""
	env["ZAP_RUN"] = "headless,gpu=d3d12"
	print("{headlessWord().on()} {RunWord("gpu", "the backend").value()} {RunWord("audio", "no sound").value()}")
	env["ZAP_RUN"] = before
	prints """
		true some("d3d12") none
		"""

# The runtime's words are a program's: `memstats`, `memcheck` (a use after free or a second free
# stops the program at once) and `leaks` (each block never freed listed by the calls that
# allocated it, each call by its function and line).

test "memstats counts the allocations and frees at exit":
	Process.output("{zapPath()} build {program()}")
	said = traced("memstats", builtExe("traced"))
	print(said.lines()[0])
	expect "zap memstats: allocations=" in said and " peak=" in said
	prints "2"

# `ZAP_RUN=errors=json` writes errors as JSON lines (see *Runtime errors*).
