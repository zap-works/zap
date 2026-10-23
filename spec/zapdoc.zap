# 13.1.4 `zap doc` and `zap lsp`

import fs

# `zap doc [module | Type | section | spec | find words]` shows what
# the runtime, std and the libraries beside std (engine, rhi: a dir holding a file of its name)
# offer and what this spec says, read from their sources: the modules, one module's public declarations with their comments, a type's fields and
# then every function taking it first by module and file, the spec's numbered sections (`spec`) or
# one with its subsections (`zap doc 6.5`), or the declarations and then the sections holding every
# word (an empty answer: the API is missing). `zap test --only doc [module]` lists the public
# declarations with no comment and fails while there is one.

# zap doc as if the compiler's repository were dir: its runtime/ (empty here) and the libraries
# beside it
fn zapIn(dir str, arguments str):
	_ = fs.createDir("{dir}runtime")
	Process.output("{zapPath()} {arguments}", vars = [runAssignment("runtime={dir}runtime")]).out
		.trimmedEnd()
		.copy()

test "a comment's first sentence ends at a period, not at a range's dots":
	dir = testDir()
	_ = fs.createDir("{dir}spans")
	_ = fs.writeFile("{dir}spans/spans.zap", "# Spans.\n\n# each of f(0) .. f(n - 1) once. Then more.\npub fn each(n i64, f fn(i64)): pass\n")
	print(zapIn(dir, "doc spans"))
	prints """
		spans.each(n i64, f fn(i64))    # each of f(0) .. f(n - 1) once
		"""

test "a type's fields, then the functions taking it first, by module and file":
	dir = testDir()
	_ = fs.createDir("{dir}orbs")
	_ = fs.writeFile("{dir}orbs/orbs.zap", "# Orbits.\n\n# A camera circling its target.\npub type Orbit:\n\tyaw f32\n\tdistance f32\n\n\t# the way it looks\n\tfn forward() f32:\n\t\tyaw\n\n# its distance grown\npub fn grown(o Orbit, by f32) f32:\n\to.distance + by\n")
	_ = fs.writeFile(
		"{dir}orbs/move.zap",
		"# turns it\npub fn steer(mut o Orbit, dt f32):\n\to.yaw += dt\n"
	)
	print(zapIn(dir, "doc Orbit").replace("\t", ">"))
	prints """
		orbs.Orbit    # A camera circling its target
		>yaw
		>distance
		orbs (move.zap):
		>orbs.steer(mut o Orbit, dt f32)    # turns it
		orbs (orbs.zap):
		>Orbit.forward() f32    # the way it looks
		>orbs.grown(o Orbit, by f32) f32    # its distance grown
		"""

# what `zap doc words` prints, run from the repository's root
fn doc(words str):
	Process.output("{zapPath()} doc {words}").out

test "a section of the spec by its number or its name, and the sections a find names":
	expect (doc("13.1").lines().first ?? "") == "# 13.1 The `zap` command"
	expect doc("loops").lines()[..3].join("|") ==
		"# 6. Control flow, optionals and errors|#|# 6.1 Conditions and loops"
	expect doc("6").lines().filter(.startsWith("# 6.")).len == 7
	print("\n  6.5 Errors: `T ? E`\n" in doc("spec"))
	prints "true"
	print("spec 13.1: The `zap` command" in doc("find language server"))
	prints "true"

# `zap doc <error>` explains a compile error, by its name (`AssignImmutable`) or its code
# (`assign-immutable`): its message, why the language refuses it and the form to write, and an
# example, the first test under `spec/`, `tests/` or `std/` that refuses it (else the example
# kept beside it in `compiler/tools/doc/errornames.zap`); `zap doc errors` lists the names with their
# codes.

fn errorDoc(words str):
	zapSays("doc {words}").trimmedEnd().copy()

test "an error by its name: its message, its explanation and its test":
	said = errorDoc("AssignImmutable").lines()
	print(said[..2].join("\n"))
	expect said.any(.startsWith("test ") and "refuses AssignImmutable:" in it)
	expect said[2] == "" and "mut" in said[3]
	prints """
		0
		error[assign-immutable]: cannot assign to immutable '$1' (declare it 'mut' to mutate)
		"""

test "an error by its code reads as by its name":
	expect errorDoc("assign-immutable") == errorDoc("AssignImmutable")

test "an unknown name is an error naming where the names are":
	print(errorDoc("NoSuchError"))
	prints """
		1
		zap doc: no module, type, error or section 'NoSuchError' (zap doc lists the modules, zap doc errors the errors, zap doc spec the sections)
		"""

test "zap doc errors lists every name with its code":
	said = errorDoc("errors")
	expect said.startsWith("0\n")
	expect "error[use-after-move]" in said and "NeedsMut" in said

test "an error no test refuses shows the example kept beside it":
	said = errorDoc("BuiltinBoundName")
	expect "\nFor example:\n\nbound Show:\n" in said

# `zap lsp` offers the outline of a file, the project's declarations by name, go to definition (a
# method of a list, string or map reaches its runtime function), references, formatting, what
# follows `orbit.` (the fields of its type, then the functions taking it first that the file sees),
# the checker's errors on save (`zap test --only check` on the file), and hover: the declaration
# and the comment above it, or, for an operation the compiler writes in line or a runtime function
# without a comment, what the spec says of the name. It reads declarations from the text, so it
# answers while a file is half written. It also gives the words their colours as semantic tokens
# (keywords, types, functions and methods, fields, modules, variants, the circle's constants), read
# from the compiler's own lists of words, options and built-in types. `tools/vscode-zap/` is the VS
# Code extension (a grammar that colours the keywords, types, calls and fields, a diff's too, and a client that runs
# `zap lsp` from a copy of `build/zap.exe` and restarts it when the compiler is rebuilt); `npx @vscode/vsce package --allow-missing-repository --skip-license -o
# build/zap-lang.vsix` packages it and `code --install-extension build/zap-lang.vsix` installs it.

# a message of the protocol with its header
fn framed(body str):
	"Content-Length: {body.len}\r\n\r\n{body}"

# what zap lsp answers to the messages (framed), between an initialize with those params and
# an exit
fn lspSays(params str, messages str):
	input = framed(
		"\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":\{{params}}}"
	)
	input += messages
	input += framed("\{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}")
	Process.output("{zapPath()} lsp", input = input).out

# the semantic tokens zap lsp gives the source: a token a line, `line:column word type`
fn colours(source str):
	uri = "file:///{testDir()}x.zap"
	said = lspSays(
		"",
		framed(
			"\{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didChange\",\"params\":\{\"textDocument\":\{\"uri\":\"{uri}\"},\"contentChanges\":[\{\"text\":{jsonQuote(source)}}]}}"
		) +
			framed(
				"\{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/semanticTokens/full\",\"params\":\{\"textDocument\":\{\"uri\":\"{uri}\"}}}"
			)
	)
	types = [
		"keyword",
		"type",
		"function",
		"method",
		"property",
		"namespace",
		"enumMember",
		"number"
	]
	at = (said.indexOf("\"data\":[") ?? 0) + 8
	numbers = said[at..said.indexOf("]", at) ?? at].split(",").map(i64.parse(it) ?? 0)
	lines = source.lines()
	out = []
	line = 0
	col = 0
	for k in 0..numbers.len / 5:
		line += numbers[5 * k]
		col = col + numbers[5 * k + 1] if numbers[5 * k] == 0 else numbers[5 * k + 1]
		word = lines[line][col..col + numbers[5 * k + 2]]
		out.push("{line + 1}:{col} {word} {types[numbers[5 * k + 3]]}")
	out.join("\n")

test "zap lsp colours the words":
	print(colours("import fs\n\ntype Kind:\n\tInt\n\nfn twice(x i64): x * 2\n\nk = Kind.Int\nprint(\"\{[1].map(twice).len} \{pi}\")\n"))
	prints """
		1:0 import keyword
		1:7 fs namespace
		3:0 type keyword
		3:5 Kind type
		4:1 Int type
		6:0 fn keyword
		6:3 twice function
		6:11 i64 type
		8:4 Kind type
		8:9 Int enumMember
		9:0 print function
		9:12 map method
		9:23 len property
		9:29 pi number
		"""

# where zap lsp says the word at a place of a file is declared: `file:line` (the file below the
# repository's root), one a line
fn definitionOf(path str, line i64, col i64):
	root = currentDir().replace("\\", "/")
	uri = "file:///{root}/{path}"
	said = lspSays(
		"\"rootUri\":\"file:///{root}\"",
		framed(
			"\{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/definition\",\"params\":\{\"textDocument\":\{\"uri\":\"{uri}\"},\"position\":\{\"line\":{line},\"character\":{col}}}}"
		)
	)
	head = "\"uri\":\"file:///{root}/"
	out = []
	at = said.indexOf(head) ?? -1
	while at >= 0:
		start = at + head.len
		file = said[start..said.indexOf("\"", start) ?? start]
		l = said.indexOf("\"line\":", start) ?? start
		out.push("{file}:{(i64.parse(said[l + 7..said.indexOf(",", l) ?? l]) ?? -1) + 1}")
		at = said.indexOf(head, start) ?? -1
	out.join("\n")

# A part's names are found where its module's are: a part sees the module's other files, and the
# file that names the parts sees theirs, before any other file of the project.
test "zap lsp finds a name in the module's parts":
	expect definitionOf("tests/programs/parts/shapes/more/area.zap", 0, 11) ==
		"tests/programs/parts/shapes/square.zap:1"
	expect definitionOf("tests/programs/parts/main.zap", 12, 8) == "tests/programs/parts/sums.zap:1"

# what a zap command line writes, both streams, and its exit code
fn zapSays(words str):
	said = Process.output("{zapPath()} {words}")
	"{said.code}\n{said.out.replace("\r\n", "\n")}"

test "zap doc prints the compiler's tables after their sections":
	expect "\n==  !=  in  not in\n" in zapSays("doc operators")
	expect "\ngrid-cell-spelling: " in zapSays("doc refused")
	expect "\nreserved: fn type mut " in zapSays("doc keywords")
