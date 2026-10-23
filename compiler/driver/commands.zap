# The zap command's commands, their options and what follows them, each with a line saying what
# it does: the command line is read from these declarations, and `zap` alone, `zap doc commands`
# and the errors for an unknown command or option print from them (spec 13.1).

import fs

type CommandOption:
	name str   # as written, dashes and all: --check
	value str   # what a valued option takes (`N`, `kinds`); "" for a switch
	about str

type Command:
	name str
	operands str   # what follows the options, as the usage writes it
	about str
	options CommandOption[]
	least i64 = 0   # the operands it needs at least
	rest bool = false   # the words after the first operand are the program's, options or not

# the options of an app's build (--target android), run's and build's alike
fn assetsOption():
	CommandOption(
		"--assets",
		"dir",
		"an app's assets: the files of dir in its APK, copied into the app's files dir at its first start"
	)

fn iconOption():
	CommandOption("--icon", "file.png", "an app's icon, the picture its launcher shows")

fn labelOption():
	CommandOption(
		"--label",
		"name",
		"an app's name, shown under its icon (the file's stem by default)"
	)

commands = [
	Command(
		name = "run",
		operands = "<file.zap> [args...]",
		about = "compile and run, the words after the file going to the program",
		options = [
			CommandOption(
				"--live",
				"",
				"rebuild when a source is saved and swap the changed functions into the running program"
			),
			assetsOption(),
			iconOption(),
			labelOption(),
			CommandOption(
				"--target",
				"name",
				"built for that target and run where it runs (zap build's); android and android-x64 run it as an app, its output read from logcat"
			)
		],
		least = 1,
		rest = true
	),
	Command(
		name = "build",
		operands = "<file.zap>",
		about = "compile to a native executable, build/<file>.exe",
		options = [
			assetsOption(),
			iconOption(),
			labelOption(),
			CommandOption(
				"--target",
				"name",
				"windows (the default: x64, build/<file>.exe), linux (x64) or linux-arm64 (one static ELF build/<file>), android or android-x64 (the program as an app, build/<file>.apk)"
			),
			CommandOption(
				"--seeds",
				"",
				"no file: the compiler built twice for every host, the branch seed made again (spec 14.1)"
			)
		]
	),
	Command(
		name = "test",
		operands = "[paths...] [name text]",
		about = "every check, or the kinds --only names (spec 13.1)",
		options = [
			CommandOption("--only", "kinds", "only these kinds of check, a comma list"),
			CommandOption(
				"--update",
				"[why]",
				"keeps what the checks found: the prints texts that differ, the baselines' gains; a why, a word that is no path, accepts a slower measure for that reason"
			),
			CommandOption(
				"--full",
				"",
				"the full run: fmt too, the compiler built a third time and compared with the second, and the benchmarks at their real sizes, five runs each"
			),
			CommandOption("--jobs", "N", "N files at once (default: by the processors and free memory)"),
			CommandOption(
				"--target",
				"name",
				"linux, linux-arm64, android or android-x64: run where it runs"
			)
		]
	),
	Command(
		name = "fmt",
		operands = "<file | dir>...",
		about = "lays out the sources",
		options = [],
		least = 1
	),
	Command(
		name = "doc",
		operands = "[module | Type | section | spec | find words | Error | errors | table]",
		about = "the runtime, std, the dependencies, the spec and the compiler's tables",
		options = []
	),
	Command(
		name = "branch",
		operands = "new <name> | land <name>... | status",
		about = "new: the branch made from main, checked out beside main's checkout with a compiler; land: each branch merged into main once the whole suite passes on the merge; status: the branches beside main's checkout (spec 13.1.5)",
		options = [],
		least = 1
	),
	Command(
		name = "lsp",
		operands = "",
		about = "the language server for editors, on stdin and stdout",
		options = []
	)
]

# a command line read by its command's declaration: the options given, by name (a switch's
# value ""), and the other words in order
type CommandLine:
	command str
	operands str[]
	given {str: str}

	# whether the option was given
	fn hasFlag(name str):
		given.get(name) != none

	# the value given to the option, none when it was not given
	fn option(name str) str?:
		if given.get(name) is value: value.copy() else: none

# `zap` with the words after it: the command they name, run
pub fn runZap(words str[]):
	if words.isEmpty:
		eprint(zapUsage())
		exit(2)
	c = commands.find(.name == words[0]) ?? exit(2, "zap: no command '{words[0]}'\n{zapUsage()}")
	line = c.readCommandLine(words[1..])
	file = "" if line.operands.isEmpty else line.operands[0]
	match c.name:
		"run":
			line.chooseBuild()
			placeRun(file)
			if line.hasFlag("--live"):
				liveRun(file, line.operands[1..])
			else:
				buildFile(file, true, line.operands[1..], false)
		"build":
			if line.hasFlag("--seeds"):
				promoteSeeds()
				return
			if file == "":
				exit(2, c.missingOperands())
			line.chooseBuild()
			buildFile(file, false, [], liveBuildVariable().value() != none)
		"test": line.testCommand()
		"fmt": line.formatCommand()
		"doc": line.docCommand()
		"branch": line.branchCommand()
		_: lspServe()

# the build's target, as --target says: an app for an Android one
fn chooseBuild(line CommandLine):
	if line.option("--target") is name:
		chooseTarget(name)
		if runner() == runnerAdb:
			appBuild = true
	if line.option("--assets") is dir: appAssetsDir = dir.copy()
	if line.option("--icon") is path: appIconFile = path.copy()
	if line.option("--label") is name: appLabel = name.copy()

# the words after the command read: an option it does not declare, a valued option without its
# value or too few operands print the command's usage and end the run
fn readCommandLine(c Command, words str[]):
	line = CommandLine(command = c.name.copy(), operands = [], given = {})
	i = 0
	while i < words.len:
		w = words[i]
		if c.rest and not line.operands.isEmpty:
			line.operands.push(w.copy())
		elif w.startsWith("--"):
			o = c.options.find(.name == w) ?? exit(2, c.refused("no option {w}"))
			if o.value == "":
				line.given[w.copy()] = ""
			elif o.value.startsWith("["):   # an optional value ("[why]"): taken when the next word is no option and no path
				taken = i + 1 < words.len and not words[i + 1].startsWith("--") and
					not fs.exists(words[i + 1])
				line.given[w.copy()] = words[i + 1].copy() if taken else ""
				if taken: i += 1
			elif i + 1 < words.len:
				i += 1
				line.given[w.copy()] = words[i].copy()
			else:
				exit(2, c.refused("{w} takes {o.value}"))
		else:
			line.operands.push(w.copy())
		i += 1
	if line.operands.len < c.least:
		exit(2, c.missingOperands())
	line

# what a command line without the operands the command needs is told
fn missingOperands(c Command):
	c.refused("{c.operands} missing")

# what a refused command line is told: why, then the command's usage
fn refused(c Command, why str):
	"zap {c.name}: {why}\n{c.commandDoc()}"

# `zap run [--live] <file.zap> [args...]`
fn commandUsage(c Command):
	parts = ["zap", c.name.copy()]
	for o in c.options:
		parts.push("[{o.name}]" if o.value == "" else "[{o.name} {o.value}]")
	if c.operands != "":
		parts.push(c.operands.copy())
	parts.join(" ")

# the command's usage, what it does and each option's line
fn commandDoc(c Command):
	lines = [c.commandUsage(), "    {c.about}"]
	heads = c.options.map(.name.copy() if .value == "" else "{.name} {.value}")
	width = heads.map(.len).max() ?? 0
	for i, o in c.options:
		lines.push("    {heads[i]}{" ".repeat(width - heads[i].len)}   {o.about}")
	lines.join("\n")

# every command's doc: `zap` alone, `zap doc commands`
fn zapUsage():
	commands.map(.commandDoc()).join("\n")

# zap fmt <file | dir>...
fn formatCommand(line CommandLine):
	for path in line.operands:
		formatPath(path, false)
