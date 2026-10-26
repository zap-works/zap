# A type as a source file of the module being checked writes it (zap fmt writes a `pub`
# function's result so, results.zap): a struct's, an enum's or a defined type's name, with the
# alias of its module's import where another module declares it (`esm.Esm`), the rest as
# typeWritten gives them; none where the file cannot name it (a generic's instance or a type of a
# module it does not import, a tuple, a function, a reference).

alias nodes = c.nodes
alias tys = c.types

fn sourceType(mut c Checker, t TypeId) str?:
	k = c.tKind(t)
	if tys[t].defined != none or k == tStruct or k == tEnum: return c.sourceNamed(t)
	if k == tOption:
		inner = try c.sourceType(try tys[t].inner)
		return "({inner})?" if c.tKind(tys[t].inner) == tResult else "{inner}?"
	if k == tResult:
		value = try c.sourceType(try tys[t].inner)
		err = try c.sourceType(try tys[t].err)
		return "({value}) ? {err}" if c.tKind(tys[t].inner) == tOption else "{value} ? {err}"
	if k == tList:
		inner = try c.sourceType(try tys[t].inner)
		return "({inner})[]" if c.tKind(tys[t].inner) == tResult else "{inner}[]"
	if k == tMap:
		key = try c.sourceType(try tys[t].inner)
		value = try c.sourceType(try tys[t].val)
		return "\{{key}: {value}}"
	if k in [tInt, tFloat, tBool, tStr]: return typeWritten(tys, t, 0)
	none

# a named type: its name, with its module's alias when another module declares it
fn sourceNamed(mut c Checker, t TypeId) str?:
	decl = tys[t].defined ?? declOf(tys, t)
	name = tys[t].display
	if name.startsWith("(") or name == "": return none   # a tuple
	mod = nodes[decl].mod()
	if mod in c.ownModules() or mod == "rt": return name.copy()
	if "<" in name or c.curMod < 0: return none
	imp = try c.modules[c.curMod].imports.find(nodes[it].text == mod)
	"{nodes[imp].text2()}.{name}"
