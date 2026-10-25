# The rules of names the checker can tell (spec 2.1), once every body is checked: a public type's
# name does not repeat its module's, as it is read `m.T` (a name the same as its module's,
# `image.Image`, stays); a public function giving a bool that only reads says what holds (`is`,
# `has` or `can` and a word, or a verb of the third person: `isDone`, `hasAlpha`, `contains`); a
# method that only reads a field of its value is that field; and the words refused (`folder`,
# `size` for what `len` says).

alias nodes = c.nodes
alias tys = c.types

# what a function that changes something, or acts outside the program, does: its bool may say
# how that went
doesAction = doesAct | doesChange | doesWait | doesPrint

pub fn checkNameRules(mut c Checker):
	for d in c.decls.copy():
		k = nodes[d].kind
		if nodes[d].origin() != none or nodes[d].hasFlag(flagExtern) or nodes[d].mod() == "derive" or
			nodes[d].text2().startsWith("$"):
			continue
		if isTypeDeclKind(k):
			c.checkRefusedWords(d, false)
			if nodes[d].hasFlag(flagPub): c.typeRepeatsModule(d)
		elif k == nFnDecl and not nodes[d].sub().isEmpty:
			c.functionNames(d, none)
		elif k == nImplDecl:
			for m in nodes[d].kids.copy():
				if nodes[m].kind == nFnDecl and not nodes[m].sub().isEmpty: c.functionNames(m, d)

# the rules of a function's name: of a method when impl (its type's declaration) is given, whose
# parameters leave out its value
fn functionNames(mut c Checker, d NodeId, impl NodeId?):
	c.checkRefusedWords(d, impl != none)
	generic = not nodes[d].names().isEmpty
	if impl is impl: generic = generic or not nodes[impl].names().isEmpty
	if nodes[d].hasFlag(flagPub) and not generic: c.boolName(d)
	if impl is impl: c.getterMethod(d, impl)

# the module's last segment ("b" for a.b), "" for the main module's
fn moduleWord(id str) ref str:
	at = id.lastIndexOf(".") ?? -1
	id[at + 1..]

fn typeRepeatsModule(mut c Checker, d NodeId):
	name = nodes[d].text2().copy()
	m = moduleWord(nodes[d].mod()).copy()
	if m == "" or name.len <= m.len or not name.lower().startsWith(m.lower()) or
		not name[m.len].isUpper():
		return
	c.enterModuleOf(d)
	c.errorAt(
		nodes[d].line,
		nodes[d].col,
		compileError("TypeRepeatsModule", ["{name}", "{m}", "{name[m.len..]}"])
	)

# the words of a camelCase name, lower case
fn camelWords(name str):
	out = []
	start = 0
	for i in 1..name.len:
		if name[i].isUpper() and not name[i - 1].isUpper():
			out.push(name[start..i].lower())
			start = i
	out.push(name[start..].lower())
	out

# a verb of the third person: contains, starts, exists (not "class")
fn thirdPerson(word str):
	word.len > 2 and word.endsWith("s") and not word.endsWith("ss")

# whether a bool's name says what holds: is, has or can and a word anywhere (`typeIsNumeric`), or
# a verb of the third person first or after the type a runtime function is named for
# (`contains`, `strStartsWith`)
fn saysWhatHolds(name str):
	words = camelWords(name)
	for i, w in words:
		if (w == "is" or w == "has" or w == "can") and i + 1 < words.len: return true
	thirdPerson(words[0]) or words.len > 1 and thirdPerson(words[1])

fn boolName(mut c Checker, d NodeId):
	c.enterModuleOf(d)
	if c.tKind(c.fnRetType(d)) != tBool or saysWhatHolds(c.writtenName(d)): return
	if nodes[d].hasFlag(flagMut) or nodes[d].kids.any(nodes[it].ival == modeMut) or
		(c.fnDoes(d) & doesAction) != 0:
		return
	c.errorAt(nodes[d].line, nodes[d].col, compileError("BoolNameSpelling", ["{c.writtenName(d)}"]))

# a method taking nothing but its value whose body reads one of the value's fields: that field
# (unless a bound asks for a function of its name, which a field does not meet)
fn getterMethod(mut c Checker, d NodeId, impl NodeId):
	if not nodes[d].kids.isEmpty or c.boundAsks(c.writtenName(d)): return
	body = nodes[d].sub()[0]
	if nodes[body].kind != nBlock or nodes[body].kids.len != 1: return
	e = nodes[body].kids[0]
	if nodes[e].kind == nExprStmt or nodes[e].kind == nReturn:
		if nodes[e].kids.len != 1: return
		e = nodes[e].kids[0]
	field = ""
	if nodes[e].kind == nIdent:
		field = nodes[e].text.copy()
	elif nodes[e].kind == nField and nodes[nodes[e].kids[0]].kind == nIdent and
		nodes[nodes[e].kids[0]].text == "self":
		field = nodes[e].text.copy()
	if field == "": return
	sd = c.findDeclInModule(nodes[impl].mod(), nStructDecl, c.programName(impl)) ?? return
	if not nodes[sd].kids.any(nodes[it].text == field): return
	c.enterModuleOf(d)
	c.errorAt(
		nodes[d].line,
		nodes[d].col,
		compileError("GetterMethod", ["{c.writtenName(d)}", field])
	)

# `folder` (a dir), and `size` for a function of a value alone (a method taking nothing more),
# which `len` says
fn checkRefusedWords(mut c Checker, d NodeId, method bool):
	name = c.writtenName(d).copy()
	word = ""
	if "folder" in name.lower():
		word = "folder: a dir"
	elif name == "size" and nodes[d].kind == nFnDecl and
		nodes[d].kids.len == (0 if method else 1):
		word = "size: len for a count, or a word for what it measures"
	if word == "": return
	c.enterModuleOf(d)
	c.errorAt(nodes[d].line, nodes[d].col, compileError("RefusedWord", ["{name}", word]))

# whether a bound of the program declares a function of that name
fn boundAsks(c Checker, name str):
	c.decls.any(nodes[it].kind == nBoundDecl and nodes[it].kids.any(nodes[it].text == name))
