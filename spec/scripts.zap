# 13.3 Scripts
#
# `zap run script.zap` is the quick way to a throwaway program: searches, counts, reports, file
# shuffles, what is otherwise written in Python. The script is one file; the first line that is not
# a comment is the program, so there is no `main` and no boilerplate; nothing but `import` for a
# standard module (`fs`, `json`, `regex`). Every idiom below names the Python form it replaces, and
# every example is a test.

import fs
import json
import regex

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
# `T.parse(text)`, which gives a `T?`; `trimmed()`, `trimmedStart(chars)` and `trimmedEnd(chars)`
# strip the white space or the bytes of `chars`. Padding is in the format: `{n:>5}`, `{name:<8}`,
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
	print("::ab::".trimmedStart(":").trimmedEnd(":"))   # "::ab::".strip(":")
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

# JSON is read with `json.parse(text)` (`json.loads`), a `Doc` whose values are read by their keys
# (`doc.textOf(node, key)`, `doc.number(node, key)`, `doc.get(node, key)`) and walked by `count` and
# `at`; a bad text is an error value. It is written with `doc.text()` (compact) and
# `doc.text(indent = 2)` (`json.dumps(value, indent=2)`); a program's own value is written by its
# `toJson()`, with the same escapes and number forms.
type Reading:
	label str
	values f64[]

test "JSON is read, rewritten and written from a program's own values":
	doc = json.parse("\{\"name\": \"Ana \\\"B\\\"\", \"n\": [1, 2.5], \"ok\": true}") ?? fail   # json.loads(text)
	print(doc.textOf(doc.root, "name"))   # data["name"]
	print(doc.numbers(doc.root, "n") ?? [])   # data["n"]
	print(doc.text())   # json.dumps(data, separators=(",", ":"))
	print(doc.text(indent = 2))   # json.dumps(data, indent=2)
	print(Reading(label = "tab\there", values = [1.0, 0.5]).toJson())   # json.dumps(asdict(r))
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
		{"label":"tab\there","values":[1,0.5]}
		JSON: the text ends where a value was expected
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
