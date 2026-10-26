# The JS target (`--target js`): one ES module written from the checked tree, after the program's
# ownership was checked on the lowered form (genX64 lowers it as Windows' x64 would, then hands
# the tree here instead of writing an image). A Zap function is a JS function of its global name,
# a method `Type__name`, a generic's instance `name__mangle`; only what the entry reaches is
# written. What the runtime does over raw memory or the system is runtime/js/prelude.js's: a
# function the prelude declares takes the place of the runtime's of that name, the others are
# written from their Zap like the program's.
#
# Values: numbers are JS numbers (jsNumbers.zap), a str a JS string, a struct an object of its
# fields, a list an array, a map a Map, a plain enum the number of its variant, a carrying one an
# object `{tag: "Name", ...}` of its payload, none `null`, an error of a result an `rt__Err`.

import fs

alias nodes = g.c.nodes
alias kidIds = g.c.kidIds
alias tys = g.c.types

# a function of the module: a declaration, a method of a type, or a generic's instance
type JsWant:
	name str
	fnd NodeId
	implType TypeId? = none
	impl NodeId? = none   # a generic impl, its substitution in force while it is written
	inst i64 = -1   # the instance of g.c.instances, or -1

# the names a block binds, Zap's to the JS text that reads each
type JsScope:
	names {str: str} = {}

# the function being written
type JsBody:
	lines str[] = []
	depth i64 = 1
	scopes JsScope[] = []
	temps i64 = 0
	declared {str: bool} = {}   # the JS names it declares
	boxed {str: bool} = {}   # its parameters passed boxed (`{v}`: changed for the caller)
	writeBacks str[] = []   # the boxed arguments of the calls being written, each `place = box.v`
	selfType TypeId? = none   # in a method: its type (a bare name may be a field)
	ret TypeId = tyUnit
	name str = ""   # its name in the module, and its source file (for what is refused)
	file str = ""

type Js:
	out str[] = []
	wants JsWant[] = []
	wanted {str: bool} = {}
	prelude {str: bool} = {}   # the names runtime/js/prelude.js declares
	globals NodeId[] = []   # the module variables the code names
	globalNamed {str: bool} = {}
	b JsBody = JsBody()
	errors str[] = []

# the module written to path from the checked program: false when the tree holds what this target
# does not write (each said)
fn genJs(mut g Gen, path str) bool:
	js = Js()
	preludeText = fs.readFile("{runtimeDir()}js/prelude.js") ?? ""
	if preludeText == "":
		eprint("zap: no JS prelude at {runtimeDir()}js/prelude.js")
		return false
	js.prelude = preludeNames(preludeText)
	js.out.push(preludeText)
	exports = g.jsExports()
	if g.entry != "":
		js.jsWant(g.jsFnName(g.entry) ?? return g.jsNoEntry(), g.c.findFunc(g.entry) ?? return g.jsNoEntry())
	for d in exports:
		js.jsWant(jsSafe(nodes[d].text), d)
	g.jsWriteAll(js)
	if not js.errors.isEmpty:
		for e in js.errors:
			eprint(e)
		return false
	if g.entry != "":
		js.out.push("rt$run(() => \{\n\t$init();\n\t{jsSafe(g.entry)}();\n\});\n")
	else:
		js.out.push("$init();\n")
		named = exports.map("{jsSafe(nodes[it].text)} as {nodes[it].text}")
		js.out.push("export \{ {named.join(", ")} \};\n")
	match fs.writeFile(path, js.out.join("\n")):
		error: false
		_: true

fn jsNoEntry(g Gen):
	eprint("zap: no function {g.entry} to start the module")
	false

# the names the prelude declares (`function name(` at a line's start, `const name =`, `class name`)
fn preludeNames(text str):
	out {str: bool} = {}
	for line in text.lines():
		for lead in ["function ", "const ", "class ", "let "]:
			if line.startsWith(lead):
				rest = line[lead.len..]
				end = 0
				while end < rest.len and (rest[end].isWordByte() or rest[end] == '$'):
					end += 1
				if end > 0: out[rest[..end].copy()] = true
	out

# a module with no entry: the public functions of the entry file, each exported by its own name
fn jsExports(g Gen) NodeId[]:
	if g.entry != "": return []
	g.c.decls.filter(
		nodes[it].kind == nFnDecl and nodes[it].hasFlag(flagPub) and nodes[it].mod() == "" and
			nodes[it].names().isEmpty
	)

# the JS name of the function of that global name
fn jsFnName(g Gen, name str) str?:
	if g.c.findFunc(name) == none: return none
	jsSafe(name)

# a name JS takes as it is: one of its words gets a `$` after it
fn jsSafe(name str):
	name.copy() if name not in jsWords else "{name}$"

jsWords = [
	"arguments", "await", "break", "case", "catch", "class", "const", "continue", "debugger",
	"default", "delete", "do", "else", "enum", "eval", "export", "extends", "false", "finally", "for",
	"function", "if", "implements", "import", "in", "instanceof", "interface", "let", "new", "null",
	"package", "private", "protected", "public", "return", "static", "super", "switch", "this",
	"throw", "true", "try", "typeof", "undefined", "var", "void", "while", "with", "yield", "NaN",
	"Infinity", "Object", "Array", "Map", "String", "Number", "Math", "Symbol", "Error", "JSON",
	"Date", "Set", "Promise", "console", "process", "globalThis", "window", "document"
]

fn jsWantsWord():
	TraceWord("jswants", "the JS target says which function first named each one it writes")

# a function the module holds, written once
fn jsWant(mut js Js, move name str, fnd NodeId, implType TypeId? = none, impl NodeId? = none, inst i64 = -1):
	if name in js.wanted: return
	if jsWantsWord().on() and name not in js.prelude: eprint("jswants: {name} by {js.b.name}")
	js.wanted[name.copy()] = true
	js.wants.push(JsWant(name, fnd, implType, impl, inst))

# the module variable d named: given its value by $init
fn jsWantGlobal(mut js Js, g Gen, d NodeId):
	if nodes[d].text in js.globalNamed or nodes[d].text in js.prelude: return
	if jsWantsWord().on(): eprint("jswants: {nodes[d].text} by {js.b.name}")
	js.globalNamed[nodes[d].text.copy()] = true
	js.globals.push(d)

# every function wanted written, then the module variables' initializers, in turns until neither
# asks for more; then $init, giving them their values in the order their initializers read them
fn jsWriteAll(mut g Gen, mut js Js):
	done = 0
	inits = 0
	initLines = []
	loop:
		while done < js.wants.len:
			w = js.wants[done].copy()
			done += 1
			if js.prelude.get(w.name) != none: continue
			g.jsWriteFunction(js, w)
		if inits == js.globals.len: break
		while inits < js.globals.len:
			d = js.globals[inits]
			inits += 1
			initLines.push(g.jsGlobalInit(js, d))
	ordered, _ = g.c.initOrder(js.globals.copy())
	byDecl {NodeId: str} = {}
	for i, d in js.globals:
		byDecl[d] = initLines[i].copy()
	js.out.push(js.globals.map("let {jsSafe(nodes[it].text)};").join("\n"))
	lines str[] = []
	for d in ordered:
		if byDecl.get(d) is text and text != "": lines.push(text.copy())
	body = lines.join("\n")
	js.out.push("function $init() \{\n{body}\n\}\n")

# the line of $init that gives d its value (none for main's ordered binding, which main assigns)
fn jsGlobalInit(mut g Gen, mut js Js, d NodeId):
	if nodes[d].hasFlag(flagOrdered) and g.entry == "main": return ""
	js.b = JsBody(name = "the value of {nodes[d].text}", file = nodes[d].file().copy())
	js.b.scopes.push(JsScope())
	g.setSubst([], [])
	value = g.jsValue(js, nodes[d].kids(kidIds)[0])
	lines = js.b.lines.copy()
	lines.push("\t{jsSafe(nodes[d].text)} = {value};")
	lines.join("\n")

# a function written: its parameters, then its body
fn jsWriteFunction(mut g Gen, mut js Js, w JsWant):
	if nodes[w.fnd].hasFlag(flagExtern):
		js.jsRefuse(g, w.fnd, "the system's function {nodes[w.fnd].text} (an extern fn)")
		return
	if w.inst >= 0:
		gi = g.c.instances[w.inst].copy()
		g.setSubst(gi.sub.names, gi.sub.types)
		g.c.checkInstance(w.inst)
	elif w.impl is impl:
		g.setSubstOf(impl)
	else:
		g.setSubst([], [])
	g.c.readBody(w.fnd)
	js.b = JsBody(
		selfType = w.implType,
		ret = g.c.fnRetType(w.fnd),
		name = w.name.copy(),
		file = nodes[w.fnd].file().copy()
	)
	js.b.scopes.push(JsScope())
	params = []
	if w.implType != none:
		params.push("self")
		js.jsBind("self", "self")
	for p in nodes[w.fnd].kids(kidIds).copy():
		name = js.jsDeclare(g, nodes[p].text)
		params.push(name.copy())
		if g.jsBoxedParam(w.fnd, p):
			js.b.boxed[name.copy()] = true
			js.jsBind(nodes[p].text, "{name}.v")
	if nodes[w.fnd].sub().isEmpty:
		js.jsRefuse(g, w.fnd, "a function without a body ({nodes[w.fnd].text})")
		return
	g.jsBodyOf(js, nodes[w.fnd].sub()[0], js.b.ret)
	js.out.push("function {w.name}({params.join(", ")}) \{\n{js.b.lines.join("\n")}\n\}\n")
	g.setSubst([], [])

# a body's statements, its last expression the function's result when it gives one
fn jsBodyOf(mut g Gen, mut js Js, body NodeId, ret TypeId):
	kids = nodes[body].kids(kidIds).copy()
	for i, s in kids:
		if i == kids.len - 1 and nodes[s].kind == nExprStmt and g.tyK(ret) != tUnit and
			g.tyK(g.ty(nodes[s].kids(kidIds)[0])) != tUnit:
			js.jsLine("return {g.jsValue(js, nodes[s].kids(kidIds)[0])};")
		else:
			g.jsStmt(js, s)

# whether parameter p of fnd is passed in a box: a mut one whose value is no JS object (a number,
# a str, an optional), or one the body assigns whole, so the caller's place sees the change
fn jsBoxedParam(mut g Gen, fnd NodeId, p NodeId):
	if nodes[p].ival != modeMut: return false
	t = g.c.resolveType(nodes[p].types()[0])
	not g.jsIsObject(t) or g.jsAssignsWhole(nodes[fnd].sub()[0], nodes[p].text)

# whether values of type t are JS objects, changed in place through any name of them
fn jsIsObject(mut g Gen, t TypeId):
	k = g.tyK(t)
	if k == tStruct or k == tList or k == tMap or k == tArray or k == tBox: return true
	k == tEnum and not g.jsPlainEnum(t)

# whether the tree e assigns the name whole (`name = v`, not a part of it)
fn jsAssignsWhole(g Gen, e NodeId, name str) bool:
	k = nodes[e].kind
	if k == nLet and nodes[e].text == name and canAssign(nodes[e]): return true
	if k == nAssign and nodes[nodes[e].kids(kidIds)[0]].kind == nIdent and
		nodes[nodes[e].kids(kidIds)[0]].text == name:
		return true
	if nodes[e].kids(kidIds).any(g.jsAssignsWhole(it, name)): return true
	nodes[e].sub().any(g.jsAssignsWhole(it, name))

# a form this target does not write: the build fails naming it and where it is
fn jsRefuse(mut js Js, g Gen, e NodeId, what str):
	js.errors.push("{js.b.file}:{nodes[e].line}: the JS target does not write {what} (in {js.b.name})")

# ---------- the body being written ----------

fn jsLine(mut js Js, text str):
	js.b.lines.push("{"\t".repeat(js.b.depth)}{text}")

fn jsOpen(mut js Js, text str):
	js.jsLine("{text} \{")
	js.b.depth += 1
	js.b.scopes.push(JsScope())

fn jsClose(mut js Js, text str = "}"):
	js.b.depth -= 1
	js.b.scopes.truncate(js.b.scopes.len - 1)
	js.jsLine(text)

# a fresh name for a value the code keeps a moment
fn jsTemp(mut js Js):
	js.b.temps += 1
	"$t{js.b.temps}"

# the JS text a Zap name reads, innermost scope first
fn jsLookup(js Js, name str) str?:
	i = js.b.scopes.len - 1
	while i >= 0:
		if js.b.scopes[i].names.get(name) is v: return v.copy()
		i -= 1
	none

fn jsBind(mut js Js, name str, text str):
	js.b.scopes[js.b.scopes.len - 1].names[name.copy()] = text.copy()

# a new JS name for the Zap name in the innermost scope: the name itself, or numbered when the
# function already declares it (JS refuses a second `let` in a block, and a shadowed name is
# another variable) or a function of the module has it
fn jsDeclare(mut js Js, g Gen, name str):
	out = js.jsFresh(g, name)
	js.jsBind(name, out)
	out

# a JS name for the Zap name no other variable of the function has, not bound yet
fn jsFresh(mut js Js, g Gen, name str):
	base = jsSafe(name)
	out = base.copy()
	n = 1
	while out in js.b.declared or g.c.findFunc(out) != none:
		n += 1
		out = "{base}${n}"
	js.b.declared[out.copy()] = true
	out
