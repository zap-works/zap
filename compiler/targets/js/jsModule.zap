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
# object `{$tag: "Name", ...}` of its payload (`$`: no field of Zap is named so), none `null`, an error of a result an `rt__Err`.

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
	wants JsWant[] = []
	wanted {str: bool} = {}
	prelude {str: bool} = {}   # the names runtime/js/prelude.js declares
	globals NodeId[] = []   # the module variables the code names
	globalNamed {str: bool} = {}
	b JsBody = JsBody()
	texts {str: str} = {}   # each function written, by name; a module variable's value "$value:name"
	order str[] = []   # their names, in the order written
	calls {str: str[]} = {}   # the names each one names
	refusals {str: str[]} = {}   # what each one holds that the target does not write
	tests {str: str} = {}   # a test's function: "file:line" of the test

# the module written to path from the checked program: false when what it reaches holds what this
# target does not write (each said); a test that reaches such a thing is skipped, saying why
fn genJs(mut g Gen, path str):
	js = Js()
	preludeText = fs.readFile("{runtimeDir()}js/prelude.js") ?? ""
	if preludeText == "":
		eprint("zap: no JS prelude at {runtimeDir()}js/prelude.js")
		return false
	js.prelude = preludeNames(preludeText)
	exports = g.jsExports()
	roots = []
	if g.entry != "":
		fnd = g.c.findFunc(g.entry) ?? return g.jsNoEntry()
		roots.push(jsSafe(g.entry))
		js.jsWant(jsSafe(g.entry), fnd)
	for d in exports:
		roots.push(jsSafe(nodes[d].text))
		js.jsWant(jsSafe(nodes[d].text), d)
	g.jsWriteAll(js)
	text = g.jsLinked(js, roots) ?? return false
	out = [preludeText, text]
	if g.entry != "":
		out.push("rt$run(() => \{\n\t$init();\n\t{jsSafe(g.entry)}();\n\});\n")
	else:
		out.push("$init();\n")
		named = exports.map("{jsSafe(nodes[it].text)} as {nodes[it].text}")
		out.push("export \{ {named.join(", ")} \};\n")
	match fs.writeFile(path, out.join("\n")):
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
fn jsExports(g Gen):
	if g.entry != "": return []
	g.c.decls.filter(
		nodes[it].kind == nFnDecl and nodes[it].hasFlag(flagPub) and nodes[it].mod(kidIds) == "" and
			nodes[it].names(kidIds).isEmpty
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
	"default",
	"delete",
	"do",
	"else",
	"enum",
	"eval",
	"export",
	"extends",
	"false",
	"finally",
	"for",
	"function", "if", "implements", "import", "in", "instanceof", "interface", "let", "new", "null",
	"package", "private", "protected", "public", "return", "static", "super", "switch", "this",
	"throw", "true", "try", "typeof", "undefined", "var", "void", "while", "with", "yield", "NaN",
	"Infinity", "Object", "Array", "Map", "String", "Number", "Math", "Symbol", "Error", "JSON",
	"Date", "Set", "Promise", "console", "process", "globalThis", "window", "document"
]

fn jsWantsWord():
	TraceWord("jswants", "the JS target says which function first named each one it writes")

# a function the module holds, written once
fn jsWant(
	mut js Js,
	move name str,
	fnd NodeId,
	implType TypeId? = none,
	impl NodeId? = none,
	inst i64 = -1
):
	js.jsCalled(name)
	if name in js.wanted: return
	if jsWantsWord().on() and name not in js.prelude: eprint("jswants: {name} by {js.b.name}")
	js.wanted[name.copy()] = true
	js.wants.push(JsWant(name, fnd, implType, impl, inst))

# the module variable d named: given its value by $init
fn jsWantGlobal(mut js Js, g Gen, d NodeId):
	if nodes[d].text in js.prelude: return
	js.jsCalled("$value:{nodes[d].text}")
	if nodes[d].text in js.globalNamed: return
	if jsWantsWord().on(): eprint("jswants: {nodes[d].text} by {js.b.name}")
	js.globalNamed[nodes[d].text.copy()] = true
	js.globals.push(d)

# every function wanted written, then the module variables' values, in turns until neither asks
# for more
fn jsWriteAll(mut g Gen, mut js Js):
	done = 0
	inits = 0
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
			g.jsGlobalInit(js, d)

# the line of $init that gives d its value (none for main's ordered binding, which main assigns)
fn jsGlobalInit(mut g Gen, mut js Js, d NodeId):
	name = "$value:{nodes[d].text}"
	js.b = JsBody(name = name.copy(), file = nodes[d].file(kidIds).copy())
	if nodes[d].hasFlag(flagOrdered) and g.entry == "main":
		js.jsWritten(name, "")
		return
	js.b.scopes.push(JsScope())
	g.setSubst([], [])
	value = g.jsValue(js, nodes[d].kids(kidIds)[0])
	lines = js.b.lines.copy()
	lines.push("\t{jsSafe(nodes[d].text)} = {value};")
	js.jsWritten(name, lines.join("\n"))

# a function written: its parameters, then its body
fn jsWriteFunction(mut g Gen, mut js Js, w JsWant):
	if nodes[w.fnd].hasFlag(flagExtern):
		g.jsExtern(js, w)
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
		file = nodes[w.fnd].file(kidIds).copy()
	)
	if g.jsCuttable(w.name):
		js.tests[w.name.copy()] = "{nodes[w.fnd].file(kidIds)}:{nodes[w.fnd].line}"
	js.b.scopes.push(JsScope())
	params = []
	if w.implType != none:
		params.push("self")
		js.jsBind("self", "self.v" if g.jsBoxedSelf(w.fnd) else "self")
	for p in nodes[w.fnd].kids(kidIds).copy():
		name = js.jsDeclare(g, nodes[p].text)
		params.push(name.copy())
		if g.jsBoxedParam(w.fnd, p):
			js.b.boxed[name.copy()] = true
			js.jsBind(nodes[p].text, "{name}.v")
	if nodes[w.fnd].sub(kidIds).isEmpty:
		js.jsRefuse(g, w.fnd, "a function without a body ({nodes[w.fnd].text})")
		return
	g.jsBodyOf(js, nodes[w.fnd].sub(kidIds)[0], js.b.ret)
	star = "*" if g.tyK(js.b.ret) == tSeq else ""
	text = "function{star} {w.name}({params.join(", ")}) \{\n{js.b.lines.join("\n")}\n\}\n"
	js.jsWritten(w.name, text)
	g.setSubst([], [])

# the library of `extern "js" fn`: a function of the JS the module runs in (the DOM, fetch, timers)
jsLibrary = "js"

# An extern fn: one of JS's (`extern "js" fn name(...)`, or `extern "js" "console.log" fn log(...)`
# naming what it calls) a function of the module calling it with the same arguments; another
# system's is refused.
fn jsExtern(mut g Gen, mut js Js, w JsWant):
	js.b = JsBody(name = w.name.copy(), file = nodes[w.fnd].file(kidIds).copy())
	named = nodes[w.fnd].names2(kidIds)
	if named.isEmpty or named[0] != jsLibrary:
		js.jsRefuse(g, w.fnd, "the system's function {nodes[w.fnd].text} (an extern fn)")
		return
	callee = named[1].copy() if named.len > 1 else "globalThis.{nodes[w.fnd].text2(kidIds)}"
	params = nodes[w.fnd].kids(kidIds).map(jsSafe(nodes[it].text)).join(", ")
	js.jsWritten(w.name, "function {w.name}({params}) \{\n\treturn {callee}({params});\n\}\n")

# whether the function runs a test of its own (a test's body, a test source's main, the program's
# main a test starts again): one the target cannot write is skipped, not the build failed
fn jsCuttable(g Gen, name str):
	if name.startsWith("$test") and name != "$testMain": return true
	isUnitMain(g.c.modules, name) or name == "main" and g.entry == "$testMain"

# a body's statements, its last expression the function's result when it gives one
fn jsBodyOf(mut g Gen, mut js Js, body NodeId, ret TypeId):
	kids = nodes[body].kids(kidIds).copy()
	for i, s in kids:
		if i == kids.len - 1 and nodes[s].kind == nExprStmt and g.tyK(ret) != tUnit and
			g.tyK(g.ty(nodes[s].kids(kidIds)[0])) != tUnit:
			js.jsLine("return {g.jsReturned(js, nodes[s].kids(kidIds)[0], ret)};")
		else:
			g.jsStmt(js, s)

# whether parameter p of fnd is passed in a box: a mut one whose value is no JS object (a number,
# a str, an optional), or one the body assigns whole, so the caller's place sees the change
fn jsBoxedParam(mut g Gen, fnd NodeId, p NodeId):
	te = nodes[p].types(kidIds)[0]
	if nodes[te].kind == nTyRef and nodes[te].ival == 1:   # `mut ref T`: as a mut T
		return not g.jsIsObject(g.c.resolveType(nodes[te].types(kidIds)[0]))
	if nodes[p].ival != modeMut: return false
	t = g.c.resolveType(nodes[p].types(kidIds)[0])
	not g.jsIsObject(t) or g.jsAssignsWhole(nodes[fnd].sub(kidIds)[0], nodes[p].text)

# whether a method's receiver is passed in a box: one the body assigns whole (`self = next()` of an
# enum, `self += 1` of a number type), which the caller's place then holds
fn jsBoxedSelf(g Gen, md NodeId):
	not nodes[md].sub(kidIds).isEmpty and g.jsAssignsWhole(nodes[md].sub(kidIds)[0], "self")

# whether values of type t are JS objects, changed in place through any name of them
fn jsIsObject(mut g Gen, t TypeId):
	k = g.tyK(t)
	if k in [tStruct, tList, tMap, tArray, tBox]: return true
	k == tEnum and not g.jsPlainEnum(t)

# whether the tree e assigns the name whole (`name = v`, not a part of it)
fn jsAssignsWhole(g Gen, e NodeId, name str) bool:
	k = nodes[e].kind
	if k == nLet and nodes[e].text == name and nodes[e].canAssign(kidIds): return true
	if k == nAssign and nodes[nodes[e].kids(kidIds)[0]].kind == nIdent and
		nodes[nodes[e].kids(kidIds)[0]].text == name:
		return true
	if k == nUnary and nodes[e].ival == unMove and g.jsNamesWhole(nodes[e].kids(kidIds)[0], name):
		return true   # `move name`: the caller's place is left empty
	if k == nCall and nodes[nodes[e].kids(kidIds)[0]].kind == nField and
		nodes[nodes[e].kids(kidIds)[0]].text == "take" and
		g.jsNamesWhole(nodes[nodes[e].kids(kidIds)[0]].kids(kidIds)[0], name):
		return true   # (the checker's `name.take()` for a move of it)
	if nodes[e].kids(kidIds).any(g.jsAssignsWhole(it, name)): return true
	nodes[e].sub(kidIds).any(g.jsAssignsWhole(it, name))

# whether e is the name itself (through the dereferences the checker wrote)
fn jsNamesWhole(g Gen, e NodeId, name str) bool:
	if nodes[e].kind == nDeref: return g.jsNamesWhole(nodes[e].kids(kidIds)[0], name)
	nodes[e].kind == nIdent and nodes[e].text == name
