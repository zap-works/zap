# 13.3 Scripts
#
# `zap run script.zap` is the quick way to a throwaway program: searches, counts, reports, file
# shuffles, what is otherwise written in Python. The script is one file; the first line that is not
# a comment is the program, so there is no `main` and no boilerplate; nothing but `import` for a
# standard module (`fs`, `json`, `csv`, `toml`, `regex`). Every idiom below names the Python form it replaces, and
# every example is a test.

import fs
import csv
import json
import regex
import toml

# The arguments, the exit code and what a script writes to stderr: `sys.argv[1:]` is `args`,
# `sys.exit(3)` is `exit(3)`, and `print(message, file=sys.stderr); sys.exit(3)` is `exit(3, message)`.
# The tests below run this very file again with arguments to see them.
if not args.isEmpty and args[0] == "report":
	print("report {args[1..].join(",")} {args.len}")   # sys.argv[1:]
	eprint("{env.get("ZAP_SPEC_SCRIPTS_NONE") ?? "no variable"}")   # os.environ.get(name, default)
	exit(3, "report: no such file")   # sys.exit(3) after a line to stderr

test "the arguments, the environment and the exit code of a script":
	p = Process.output([exePath(), "report", "a b", "c"])
	print("{p.code} {p.out.trimmedEnd()}")
	prints """
		3 report a b,c 3
		no variable
		report: no such file
		"""

# Files are read and written whole. A failure is a value (`? fs.Error`), not an exception: `?? fail`
# stops the script with the error's text (Python's traceback), `?? default` takes a default
# (`try/except` that returns it).
test "files are read and written whole":
	dir = "{testDir()}scripts-files"
	fs.createDir(dir) ?? fail   # os.makedirs(dir, exist_ok=True)
	path = "{dir}/notes.txt"
	fs.writeFile(path, "one\ntwo\n") ?? fail   # open(path, "w").write(text)
	fs.appendFile(path, "three\n") ?? fail   # open(path, "a").write(text)
	text = fs.readFile(path) ?? fail   # open(path).read()
	expect text.lines() == ["one", "two", "three"]   # text.splitlines()
	expect fs.exists(path)   # os.path.exists(path)
	missing = fs.readFile("{dir}/missing.txt") ?? "{error}"   # except FileNotFoundError
	expect missing == "NotFound"
	fs.deleteFile(path) ?? fail   # os.remove(path)
	fs.deleteTree(dir) ?? fail   # shutil.rmtree(dir)
	expect not fs.exists(dir)

# A path is taken apart and joined as `os.path` does: `fs.fileName`, `fs.stem`, `fs.extension`,
# `fs.dirOf` and `fs.join`.
test "paths are taken apart and joined":
	path = "src/lib/parser.zap"
	expect fs.fileName(path) == "parser.zap"   # os.path.basename(path)
	expect fs.dirOf(path) == "src/lib"   # os.path.dirname(path)
	expect fs.stem(path) == "parser"   # Path(path).stem
	expect fs.extension(path) == ".zap"   # Path(path).suffix
	expect fs.join("src", "main.zap") == "src/main.zap"   # os.path.join("src", "main.zap")

# A tree is walked in one call: `fs.walk(dir)` is every file under it, as its path from `dir`, depth
# first in name order; `fs.walk(dir, "*.zap")` only the files whose name matches the glob (`*` any
# run, `?` one byte).
test "a tree is walked, whole or by a glob":
	root = "{testDir()}scripts-walk"
	for dir in ["lib/deep", "docs"]:
		fs.createDir("{root}/{dir}") ?? fail
	for file in ["main.zap", "lib/util.zap", "lib/deep/core.zap", "lib/notes.txt", "docs/a.md"]:
		fs.writeFile("{root}/{file}", file) ?? fail
	all = fs.walk(root)   # [str(p) for p in Path(root).rglob("*") if p.is_file()]
	print(all.map(str(it[root.len + 1..])))
	zaps = fs.walk(root, "*.zap")   # sorted(Path(root).rglob("*.zap"))
	print(zaps.map(str(fs.fileName(it))))
	print(fs.walk(root, "?.md").len)   # fnmatch
	total = 0
	for file in zaps:
		total += (fs.readFile(file) ?? fail).len   # sum(len(open(f).read()) for f in files)
	print(total)
	fs.deleteTree(root) ?? fail
	prints """
		["docs/a.md", "lib/deep/core.zap", "lib/notes.txt", "lib/util.zap", "main.zap"]
		["core.zap", "util.zap", "main.zap"]
		1
		37
		"""

# The source tree of a program is one flag away: `fs.walk(dir, sources = true)` is its .zap files
# only, leaving out the dirs `build`, `node_modules` and `top`, those with a dot in the name and
# those a `.gitignore` names; with `programs = true` a dir holding a `main.zap` is that one file.
test "a tree is walked for its sources":
	root = "{testDir()}scripts-sources"
	for dir in ["lib", "app/inner", "build", ".hidden"]:
		fs.createDir("{root}/{dir}") ?? fail
	for file in [
		"a.zap",
		"lib/b.zap",
		"lib/c.txt",
		"app/main.zap",
		"app/inner/d.zap",
		"build/e.zap",
		".hidden/f.zap"]:
		fs.writeFile("{root}/{file}", file) ?? fail
	print(fs.walk(root, sources = true).map(str(it[root.len + 1..])))
	print(fs.walk(root, sources = true, programs = true).map(str(it[root.len + 1..])))
	print(fs.walk("{root}/lib/b.zap", sources = true).len)
	fs.deleteTree(root) ?? fail
	prints """
		["a.zap", "app/inner/d.zap", "app/main.zap", "lib/b.zap"]
		["a.zap", "app/main.zap", "lib/b.zap"]
		1
		"""

# Lines and words are cut with `lines()`, `split(sep)` and `words()`; a column is parsed with
# `T.parse(text)`, which gives a `T?`; `trimmed(chars)`, `trimmedStart(chars)` and
# `trimmedEnd(chars)` strip the white space or the bytes of `chars`. Padding is in the format: `{n:>5}`, `{name:<8}`,
# `{v:>10.2}`.
test "a table of text is cut, summed and printed in columns":
	table = "ana\t3\t1.5\nbo\t10\t2.25\n\ncy\tx\t4\n"
	rows = table.lines().filter(not .isEmpty)   # [l for l in f if l.strip()]
	total = 0.0
	for row in rows:
		cols = row.split("\t")   # row.split("\t")
		total += f64.parse(cols[2]) ?? 0.0   # float(cols[2])
	print(total)
	for row in rows:
		cols = row.split("\t")
		print("{cols[0]:<5}{(i64.parse(cols[1]) ?? -1):>4}")   # f"{name:<5}{n:>4}"
	print("::ab::".trimmed(":"))   # "::ab::".strip(":")
	print("[{total:>8.2}]")   # f"[{total:8.2f}]"
	prints """
		7.75
		ana     3
		bo     10
		cy     -1
		ab
		[    7.75]
		"""

# Counting is `counts.add(key, 1)` (a `collections.Counter`); a float sum per key is
# `sums[key] = (sums.get(key) ?? 0.0) + v`; the top n by value are the keys sorted by it.
test "words are counted and the most frequent listed":
	text = "the cat and the dog and the bird"
	counts {str: i64} = {}
	for word in text.words():
		counts.add(word, 1)   # counts[word] += 1, with Counter
	top = counts.keys().sortedBy(-counts[it])[..2]   # [w for w, n in counts.most_common(2)]
	print(top)
	for (word, n) in counts.entries().sorted():   # sorted(counts.items())
		print("{word}={n}")
	sums {str: f64} = {}
	for (key, v) in [("a", 0.5), ("b", 2.0), ("a", 0.25)]:
		sums[key.copy()] = (sums.get(key) ?? 0.0) + v   # sums[key] += v, with defaultdict(float)
	print(sums)
	prints r"""
		["the", "and"]
		and=2
		bird=1
		cat=1
		dog=1
		the=3
		{"a": 0.75, "b": 2}
		"""

# A regular expression is compiled once and matched without backtracking: `re.isMatch(line)`
# (`re.search(pattern, line)`), `re.find(text)` (`.span()` of the first match), `re.findAll(text)`,
# `re.count(text)` and `re.replace(text, by)` (`re.sub`). Flags lead the pattern as in Python:
# `(?m)` makes `^` and `$` match at each line, `(?i)` ignores ASCII case, `(?s)` lets `.` match a
# newline.
test "a regex is matched over lines, counted and replaced":
	source = "fn one(): 1\n  fn two(): 2\nfn Three(): 3\n"
	functions = regex.compile(r"(?m)^fn \w+") ?? fail   # re.compile(r"^fn \w+", re.M)
	expect functions.count(source) == 2   # len(re.findall(...))
	print(source.lines().count(functions.isMatch(it)))   # sum(1 for l in lines if functions.search(l))
	first = functions.find(source) ?? fail("none")   # functions.search(source).span()
	print("{first.start}-{first.end} {source[first.start..first.end]}")
	loose = regex.compile(r"(?mi)^\s*fn (\w+)") ?? fail
	print(loose.count(source))
	print(functions.replace(source, "def").trimmedEnd())   # functions.sub("def", source)
	spans = regex.compile(r"(?s)\(.*\)") ?? fail
	print(spans.count("(a\nb)"))
	prints """
		2
		0-6 fn one
		3
		def(): 1
		  fn two(): 2
		def(): 3
		1
		"""

# JSON whose shape the script knows is read into its own types: `Reading.fromJson(text)`
# (`Reading(**json.loads(text))`, checked once) is a `Reading?`, `Reading[].fromJson(text)` a list
# of them, and a missing or wrongly typed field makes it none. A value is written by `v.toJson()`
# (`json.dumps(asdict(v))`, compact) or `v.toJson(2)` (`json.dumps(asdict(v), indent=2)`). The
# fields are then read as fields (`r.values`), with no lookup by name.
type Reading:
	label str
	values f64[]

test "JSON is read into the script's own types and written back":
	text = "[\{\"label\": \"tab\there\", \"values\": [1, 0.5]}, \{\"label\": \"b\", \"values\": []}]"
	readings = Reading[].fromJson(text) ?? fail("not readings")   # [Reading(**d) for d in json.loads(text)]
	print(readings[0].values)   # r.values
	print(readings[0].toJson())   # json.dumps(asdict(r), separators=(",", ":"))
	print(readings[1].toJson(indent = 2))   # json.dumps(asdict(r), indent=2)
	print(Reading.fromJson("\{\"label\": 1}") == none)   # a wrong shape: none
	print(readings.toJson(2).lines().len)
	prints r"""
		[1, 0.5]
		{"label":"tab\there","values":[1,0.5]}
		{
		  "label": "b",
		  "values": []
		}
		true
		13
		"""

# For a shape the script does not know, `json.parse(text)` (`json.loads`) reads a `Doc` whose
# values are read by their keys (`doc.textOf(node, key)`, `doc.number(node, key)`,
# `doc.get(node, key)`) and walked by `count` and `at`; a bad text is an error value. It is written
# with `doc.text()` (compact) and `doc.text(indent = 2)` (`json.dumps(value, indent=2)`), the same
# text `toJson` writes.
test "JSON of an unknown shape is read as a document and rewritten":
	doc = json.parse("\{\"name\": \"Ana \\\"B\\\"\", \"n\": [1, 2.5], \"ok\": true}") ?? fail   # json.loads(text)
	print(doc.textOf(doc.root, "name"))   # data["name"]
	print(doc.numbers(doc.root, "n") ?? [])   # data["n"]
	print(doc.text())   # json.dumps(data, separators=(",", ":"))
	print(doc.text(indent = 2))   # json.dumps(data, indent=2)
	if json.parse("[1,") is error: print(error)   # except json.JSONDecodeError as error: print(error)
	prints r"""
		Ana "B"
		[1, 2.5]
		{"name":"Ana \"B\"","n":[1,2.5],"ok":true}
		{
		  "name": "Ana \"B\"",
		  "n": [
		    1,
		    2.5
		  ],
		  "ok": true
		}
		JSON: the text ends where a value was expected
		"""

# CSV whose columns the script knows is read into its own type the same way: `Row[].fromCsv(text)`
# (`csv.DictReader`, each row checked once) is a `Row[] ? str`, the header's names matched to the
# fields and the rest of the columns left out. A `str` field is its cell, an optional field is none
# for an empty cell (or a missing column), any other field reads its cell as the JSON of its type
# (`12`, `2.5`, `true`). Quotes follow RFC 4180 (a quoted field holds commas, line breaks and
# doubled quotes); a second argument is the separator (`'\t'` for a TSV, `delimiter="\t"`). An error
# names the line and the column. `rows.toCsv()` writes the rows back (`csv.DictWriter`), quoting
# where a cell needs it, a line to each row.
type Entry:
	name str
	count i64
	price f64
	note str?

test "a CSV is read into the script's own type and written back":
	text = "id,name,count,price,note\n1,axe,3,2.5,\"sharp, old\"\n2,\"bow \"\"long\"\"\",4,10,\n"
	entries = Entry[].fromCsv(text) ?? fail   # list(csv.DictReader(io.StringIO(text)))
	print(entries.sum(it.count))   # sum(int(r["count"]) for r in rows)
	print("{entries[0].note} {entries[1].note} {entries[1].name}")
	print(entries.toCsv().trimmedEnd())   # csv.DictWriter(out, fieldnames).writerows(rows)
	print((Entry[].fromCsv(entries.toCsv()) ?? fail) == entries)
	tsv = entries.toCsv(sep = '\t')   # delimiter="\t"
	print(tsv.lines()[0])
	print((Entry[].fromCsv(tsv, '\t') ?? fail).len)
	prints r"""
		7
		some("sharp, old") none bow "long"
		name,count,price,note
		axe,3,2.5,"sharp, old"
		"bow ""long""",4,10,
		true
		name	count	price	note
		2
		"""

test "a CSV that does not fit the type says the line and the column":
	for text in [
		"name,count,price\naxe,3,x",
		"name,count,price\naxe,3,1\nbow,4",
		"name,count\naxe,3",
		"name,count,price\n\"axe,3,1",
		"name,count,price\n\"axe\"x,3,1",
		""
	]:
		if Entry[].fromCsv(text) is error: print(error)
	prints r"""
		CSV line 2, column 3 ("price"): "x" is not a valid f64
		CSV line 3: 2 columns where the header has 3
		CSV line 1: no column "price"
		CSV line 2, column 1: a quoted field is never closed
		CSV line 2, column 1: text after a closing quote
		CSV: the text has no header line
		"""

# For a CSV of any shape, `csv.parse(text)` (`csv.reader`) is a `Csv` of text cells: its `header`,
# its `rows` (each as long as the header) and `col(name)`, the header's index of a name. The same
# quoting, separator and errors; `csv.text(rows)` and `table.text()` write cells as CSV text.
test "a CSV of unknown columns is read as text cells":
	table = csv.parse("a,b\n1,\"x,\ny\"\r\n2,z\n") ?? fail   # rows = list(csv.reader(io.StringIO(text)))
	print(table.header)
	print(table.rows)
	print(table.rows[0][table.col("b") ?? fail("no b")].lines().len)
	print(table.col("c") == none)
	print(table.text().trimmedEnd())
	print((csv.parse("a;b\n1;2", ';') ?? fail).rows)
	if csv.parse("a,b\n1") is error: print(error)
	prints r"""
		["a", "b"]
		[["1", "x,\ny"], ["2", "z"]]
		2
		true
		a,b
		1,"x,
		y"
		2,z
		[["1", "2"]]
		CSV line 2: 1 columns where the header has 2
		"""

# TOML is read, never written (`tomllib.loads`), for config files such as pyproject.toml and
# Cargo.toml. `toml.json(text)` is the document as JSON text, so a known shape is read as JSON is,
# into the script's own types, and `toml.parse(text)` a `json.Doc` for an unknown one. A table is an
# object, `[[name]]` a list of tables, a date its text; an error says the line.
type Package:
	name str
	version str
	keywords str[]
	edition i64?

type Project:
	package Package
	bin Package[]
	level f64

test "a TOML config is read into the script's own types":
	text = """
		# a manifest
		level = 1.5e1
		[package]
		name = "zap"
		version = 'one \\ two'
		keywords = [
			"a",   # why
			"b\\u00e9",
		]
		[[bin]]
		name = "x"
		version = '''
		multi
		line'''
		keywords = []
		edition = 0x7E8
		[[bin]]
		name = "y"
		version = "2"
		keywords = ["k"]
		"""
	project = Project.fromJson(toml.json(text) ?? fail) ?? fail("shape")   # tomllib.loads(text)
	print("{project.package.name} {project.package.version} {project.package.keywords}")
	print("{project.bin.len} {project.bin[0].edition} {project.bin[1].edition} {project.level} {project.bin[0].version.lines()}")
	doc = toml.parse(text) ?? fail
	print(doc.textOf(doc.get(doc.root, "package") ?? fail("none"), "name"))
	print(toml.json("a.b = 1\n[c]\nd = \{ e = [1, 2.5], f = 1979-05-27 }") ?? fail)
	if toml.json("a = 1\na = 2") is error: print("{error.line} {error.message}")
	if toml.json("a = 1\nb = \n") is error: print("{error.line} {error.message}")
	prints r"""
		zap one \ two ["a", "bé"]
		2 some(2024) none 15 ["multi", "line"]
		zap
		{"a":{"b":1},"c":{"d":{"e":[1,2.5],"f":"1979-05-27"}}}
		2 a is given twice
		2 expected a value
		"""

# A process runs to its end with `Process.output([program, arg, ...])` (`subprocess.run(args,
# capture_output=True, text=True)`): each word is one argument, quoted for the system, so a path
# with spaces needs no care; `Process.output(line)` takes one command line to be split. `p.out` is
# what it wrote (both streams in order), `p.code` its exit code, -1 when it did not start. `dir =`
# is `cwd=`, `input =` is `input=` and `vars = ["NAME=value"]` is `env=`.
test "a process is run with its arguments as a list":
	p = Process.output(["git", "--version"])   # subprocess.run(["git", "--version"], ...)
	expect p.code == 0   # p.returncode
	expect p.out.startsWith("git version")   # p.stdout
	print(Process.output(["zap-spec-scripts-no-such-program"]).code)   # FileNotFoundError
	print(Process.output("git --version").code)   # shell=False with a split line
	prints """
		-1
		0
		"""
