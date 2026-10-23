# A program's command line, as methods of `args` (any str[]): `--name value` options, `--name`
# switches given or not, numbers after an option, and the positional arguments (the words that
# are neither): args.option("--iso"), args.hasFlag("--uncapped"),
# `i64.parse(args.option("--frames") ?? "") ?? 60`. A program declares its options once with
# args.options, and args.positional reads them.

# the argument after `name` (`--port 7000`), none when `name` is not given or ends the line
pub fn listOption(words str[], name str) str?:
	if words.indexOf(name) is i and i + 1 < words.len: return words[i + 1].copy()
	none

# whether the switch `name` is given (`--uncapped`)
pub fn listHasFlag(words str[], name str) bool:
	name in words

# the numbers after `name`, separated by commas (`--at 1.5,0,-2`); a part that is not a number
# counts as 0; empty when `name` is not given
pub fn listOptionNumbers(words str[], name str) f64[]:
	match words.option(name):
		text: text.split(",").map(f64.parse(it) ?? 0.0)
		none: []

# An option a program accepts: its name (`--iso`), whether a value follows it, and a line of help.
pub type ArgOption:
	name str
	takesValue bool
	help str

# the options the program declared (args.options), in the order given
mut declaredOptions ArgOption[] = []

# declares the program's options once: `positional` skips the value after each one that takes
# one, and `usage` lists them
pub fn listOptions(words str[], declared ArgOption[]):
	declaredOptions = declared.copy()

# one line a declared option: its name, `value` when it takes one, and its help
pub fn listUsage(words str[]) str:
	lines = []
	for o in declaredOptions:
		value = " value" if o.takesValue else ""
		lines.push("  {o.name}{value}  {o.help}")
	lines.join("\n")

# the arguments that are not options: every word that does not start with "--", except the
# value after a declared option that takes one
pub fn listPositional(words str[]) str[]:
	out = []
	i = 0
	while i < words.len:
		if declaredTakesValue(words[i]):
			i += 2
		else:
			if not words[i].startsWith("--"):
				out.push(words[i].copy())
			i += 1
	out

fn declaredTakesValue(name str) bool:
	declaredOptions.any(it.name == name and it.takesValue)

# ---------- arg(i, default) ----------
# The checker writes arg(i, d) as argParsed(i, T.parse(argOrEmpty(i)), d) for a number type T,
# and as argTextOr(i, d) for text.

# the i-th argument, "" when there is none
fn argOrEmpty(i i64) str:
	programArgs[i].copy() if i >= 0 and i < programArgs.len else ""

# the i-th argument as it parsed (none for a missing one or a malformed one); a given argument
# that does not parse stops the program, so a typo never runs with the default
fn argParsed<T>(i i64, parsed T?, d T) T:
	if parsed is value: return value
	if i >= 0 and i < programArgs.len:
		fail("argument {i} is not a number: {programArgs[i]}")
	d

# the i-th argument, d when there is none
fn argTextOr(i i64, d str) str:
	programArgs[i].copy() if i >= 0 and i < programArgs.len else d.copy()
