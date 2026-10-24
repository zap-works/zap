# The README's numbers (spec 13.1): `zap test --only bench --full` writes them to the repository's
# numbers.json, the one place they are kept (the site reads it), and rewrites the blocks of its
# README.md between `<!-- numbers:NAME -->` and `<!-- /numbers -->` from it: the tokens of the
# benchmark programs, their time and memory against C, C++, Rust and Python, what is built with Zap and
# the compiler itself. The suite's `measured` lines are the source of the first two.

import fs

# a program of a problem in a language: its time (ms), peak memory (bytes) and tokens; time and
# memory are 0 for a program not raced or over its memory (oom)
type Measured:
	problem str
	language str
	ms i64
	bytes i64
	tokens i64
	oom bool = false

# a project in projects/ (its dir) and the name the README gives it
projectNames = [
	("mario", "Mario 64"),
	("skyrim", "Skyrim"),
	("firered", "FireRed"),
	("minecraft", "Minecraft"),
	("ragnarok", "Ragnarok"),
	("excel1", "Excel 1.00"),
	("skate3", "Skate 3"),
	("dkc", "Donkey Kong Country"),
	("lemmings", "Lemmings"),
	("pop", "Prince of Persia")
]

# the site's own project, shown last, after the engine
siteProject = "site", "ZapX"

# one block of numbers: its name (the README's mark), its header and its rows of cells as the
# README shows them (a link written `[text](url)`)
type NumbersTable:
	name str
	header str[]
	rows (str[])[]

# numbers.json
type NumbersFile:
	tables NumbersTable[]
# the tab-separated `measured` line of a suite, none for any other line
fn parseMeasured(line str) Measured?:
	f = line.split("\t")
	if f.len < 6 or f[0] != "measured": return none
	Measured(
		problem = f[1].copy(),
		language = f[2].copy(),
		ms = i64.parse(f[3]) ?? 0,
		oom = f[3] == "out of memory",
		bytes = i64.parse(f[4]) ?? 0,
		tokens = i64.parse(f[5].trimmed()) ?? 0
	)

# Rewrites the README at the repository's root with the suite's numbers; only a README that has
# the marks, and only when a block changes.
fn rewriteReadme(root str, measured Measured[]):
	numbers = NumbersFile(
		tables = [
			tokensTable(measured),
			speedTable(measured),
			builtTable(root),
			compilerTable(root)
		]
	)
	jsonPath = "{root}/baselines/numbers.json"
	_ = fs.createDir(fs.dirOf(jsonPath))
	fs.writeFile(jsonPath, numbers.toJson()) ?? return print("  {jsonPath}: cannot write: {error}")
	path = "{root}/README.md"
	text = fs.readFile(path) ?? return
	if "<!-- numbers:" not in text: return
	out = text.copy()
	for t in numbers.tables:
		out = withBlock(out, t.name, t.markdown())
	if out != text:
		fs.writeFile(path, out) ?? return print("  {path}: cannot write: {error}")
		print("  {path}: numbers rewritten")

# the text with the body between the marks of a block (the text unchanged without them)
fn withBlock(text str, name str, body str):
	open = "<!-- numbers:{name} -->"
	close = "<!-- /numbers -->"
	at = text.indexOf(open) ?? return text.copy()
	from = at + open.len
	end = text.indexOf(close, from) ?? return text.copy()
	"{text[..from]}\n{body}\n{text[i64(end)..]}"

# ---------- markdown ----------

fn tableRow(cells str[]):
	"| {cells.join(" | ")} |"

# a table as markdown: the header cells, the first column left and the others right, the rows
fn markdown(t NumbersTable):
	rule = [":---"]
	for _ in 1..t.header.len:
		rule.push("---:")
	lines = [tableRow(t.header), tableRow(rule)]
	for row in t.rows:
		lines.push(tableRow(row))
	lines.join("\n")

fn table(name str, header str[], rows (str[])[]):
	NumbersTable(name = name.copy(), header = header.copy(), rows = rows.copy())

fn ratioText(ratio f64):
	"{ratio:.2}x"

fn thousands(n i64):
	text = str(n)
	out = ""
	for i, c in text.chars():
		if i > 0 and (text.len - i) % 3 == 0:
			out += ","
		out += c
	out

# ---------- tokens ----------

# Zap's time or memory over the best of C, C++ and Rust is above 1.00x as the tables print it
fn behindBest(measured Measured[], problem str):
	zap = runOf(measured, problem, "zap") ?? return false
	for language in ["c", "c++", "rust"]:
		rival = runOf(measured, problem, language) ?? continue
		if zap.ms * 1000 > rival.ms * 1005 or zap.bytes * 1000 > rival.bytes * 1005: return true
	false

# The problems the numbers show, in the order they were measured: those where Zap is not behind
# the best of C, C++ and Rust, in time nor in memory. The tokens and the speed tables, so the README and the site,
# all take their rows from here.
fn problemNames(measured Measured[]):
	names str[] = []
	for m in measured:
		if m.problem not in names and not behindBest(measured, m.problem):
			names.push(m.problem.copy())
	names

fn tokensOf(measured Measured[], problem str, language str) i64?:
	i = try measured.findIndex(.problem == problem and .language == language)
	measured[i].tokens

# The tokens of each program: a row per problem, the total of each language over the problems it
# has and its ratio to Zap's over the same problems.
fn tokensTable(measured Measured[]):
	languages = ["zap", "c", "c++", "rust", "py"]
	rows = []
	totals = [0, 0, 0, 0, 0]
	zapTotals = [0, 0, 0, 0, 0]
	for problem in problemNames(measured):
		zapTokens = tokensOf(measured, problem, "zap") ?? 0
		row = [problem.copy()]
		for k, language in languages:
			match tokensOf(measured, problem, language):
				n:
					row.push(thousands(n))
					totals[k] += n
					zapTotals[k] += zapTokens
				none: row.push("-")
		rows.push(row)
	total = ["total"]
	ratio = ["vs Zap"]
	for k in 0..languages.len:
		total.push(thousands(totals[k]))
		ratio.push(ratioText(f64(totals[k]) / f64(zapTotals[k].max(1))))
	rows.push(total)
	rows.push(ratio)
	table("tokens", ["tokens", "Zap", "C", "C++", "Rust", "Python"], rows)

# ---------- time and memory ----------

fn runOf(measured Measured[], problem str, language str) Measured?:
	i = try measured.findIndex(.problem == problem and .language == language and .ms > 0)
	measured[i].copy()

fn overMemory(measured Measured[], problem str, language str):
	measured.any(.problem == problem and .language == language and .oom)

# The Zap programs' time and memory, and their ratio to C, C++, Rust and Python (below 1.00 is Zap
# ahead); the worst ratio and the geometric mean close each column.
fn speedTable(measured Measured[]):
	rivals = ["c", "c++", "rust", "py"]
	rows = []
	ratios = []
	for problem in problemNames(measured):
		zap = runOf(measured, problem, "zap") ?? continue
		row = [problem.copy(), "{zap.ms}", "{zap.bytes / 1048576.0:.1}"]
		times = []
		memories = []
		for k, language in rivals:
			match runOf(measured, problem, language):
				r:
					times.push(ratioText(f64(zap.ms) / f64(r.ms)))
					memories.push(ratioText(f64(zap.bytes) / f64(r.bytes.max(1))))
					ratios.push(
						Ratio(
							rival = k,
							time = f64(zap.ms) / f64(r.ms),
							memory = f64(zap.bytes) / f64(r.bytes.max(1))
						)
					)
				none:
					cell = "OOM" if overMemory(measured, problem, language) else "-"
					times.push(cell.copy())
					memories.push(cell)
		row.extend(times)
		row.extend(memories)
		rows.push(row)
	rows.push(summaryRow("worst", ratios, .max() ?? 0.0))
	rows.push(summaryRow("geomean", ratios, geometricMean))
	table(
		"speed",
		["Zap against", "ms", "MB", "time C", "C++", "Rust", "Python", "memory C", "C++", "Rust", "Python"],
		rows
	)

# one problem's Zap program against a rival (0 C, 1 C++, 2 Rust, 3 Python)
type Ratio:
	rival i64
	time f64
	memory f64

fn geometricMean(ratios f64[]):
	if ratios.isEmpty: return 0.0
	logs = 0.0
	for r in ratios:
		logs += r.ln()
	(logs / ratios.len).exp()

fn summaryRow(label str, ratios Ratio[], pick fn(f64[]) f64):
	row = [label.copy(), "", ""]
	for k in 0..4:
		row.push(ratioText(pick(ratios.filter(.rival == k).map(.time))))
	for k in 0..4:
		row.push(ratioText(pick(ratios.filter(.rival == k).map(.memory))))
	row

# ---------- what is built with Zap, the compiler ----------

# the non-blank lines of the .zap files under a folder
fn zapLines(dir str):
	lines = 0
	for file in fs.walk(dir, sources = true):
		for line in (fs.readFile(file) ?? "").lines():
			if line.trimmed() != "":
				lines += 1
	lines

# The engine (engine/ and rhi/) and the programs of projects/, each with its lines of Zap and a
# link to its dir; those not there are left out.
fn builtTable(root str):
	rows = []
	for (dir, name) in projectNames:
		root.projectRow(dir, name, rows)
	rows.push(["[Engine](engine)", thousands(zapLines("{root}/engine") + zapLines("{root}/rhi"))])
	dir, name = siteProject
	root.projectRow(dir, name, rows)
	table("built", ["Built with Zap", "lines of Zap"], rows)

# the row of the project in projects/dir, when it has lines of Zap
fn projectRow(root str, dir str, name str, mut rows (str[])[]):
	lines = zapLines("{root}/projects/{dir}")
	if lines > 0: rows.push(["[{name}](projects/{dir})", thousands(lines)])

# The compiler: its lines of Zap (compiler/ and runtime/, which build/zap.exe is made of) and
# the time this compiler takes to build itself.
fn compilerTable(root str):
	lines = zapLines("{root}/compiler") + zapLines("{root}/runtime")
	t0 = clockSeconds()
	done = buildCompiler(root, exePath(), host(), "{root}/build/self")
	seconds = clockSeconds() - t0
	built = "{seconds:.1} s" if done else "-"
	table(
		"compiler",
		["The compiler", ""],
		[["lines of Zap", thousands(lines)], ["builds itself in", built]]
	)
