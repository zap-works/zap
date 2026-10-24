# The optional arguments of the built-in encoders of formats (`v.toJson(2)`, `rows.toCsv(sep)`,
# `Row[].fromCsv(text, sep)`), and the checks of the CSV reader and writer; the functions that do
# the work are written per type by derive.zap (derivecsv.zap).

alias nodes = c.nodes
alias tys = c.types

# argument i of call e, which `name = value` may give, checked as an integer of type t
fn checkOptionalInt(mut c Checker, e NodeId, method str, i i64, name str, t TypeId):
	a = c.argAt(e, i)
	if nodes[a].kind == nNamedArg:
		if nodes[a].text != name:
			c.errorAt(
				nodes[a].line,
				nodes[a].col,
				compileError("NoParameter", [method.copy(), nodes[a].text.copy()])
			)
		c.setArg(e, i, nodes[a].kids[0])
	at = c.checkExpr(c.argAt(e, i), t)
	if c.tKind(at) != tInt and c.tKind(at) != tError:
		c.errorAt(
			nodes[e].line,
			nodes[e].col,
			compileError("IntegerArgument", ["{name} is an integer", c.showTy(at)])
		)

# toJson's indent
fn checkIndentArg(mut c Checker, e NodeId):
	c.checkOptionalInt(e, "toJson", 0, "indent", tyInt(64, true))

# the separator at argument i of call e: the one given, else a comma
fn checkSeparatorArg(mut c Checker, e NodeId, method str, i i64):
	if c.argCount(e) <= i:
		nodes[e].kids.push(newNode(nodes, nInt, nodes[e].line, nodes[e].col, text = "44"))
	c.checkOptionalInt(e, method, i, "sep", tyInt(8, false))

# whether t is a list of structs a CSV holds as rows, else the error is reported
fn checkCsvRows(mut c Checker, e NodeId, t TypeId):
	elem = innerOf(tys, t)
	if c.tKind(t) == tList and c.tKind(elem) == tStruct and c.isSerializable(elem): return true
	c.errorAt(nodes[e].line, nodes[e].col, compileError("CsvRowType", [c.showTy(t)]))
	false

# Row[].fromCsv(text, sep = ','): Row[] ? str
fn checkCsvRead(mut c Checker, e NodeId, t TypeId) TypeId:
	if c.argCount(e) < 1 or c.argCount(e) > 2:
		c.errorAt(
			nodes[e].line,
			nodes[e].col,
			compileError("ArgumentCount", ["fromCsv", "1 or 2", "{c.argCount(e)}"])
		)
		return tyError
	if not c.checkCsvRows(e, t): return tyError
	c.checkStrArg(e, 0, "fromCsv expects a str")
	c.checkSeparatorArg(e, "fromCsv", 1)
	c.noteDerive(t, deriveFromCsv)
	c.typed(e, tyResult(tys, t, tyStr))

# rows.toCsv(sep = ','): str
fn checkCsvWrite(mut c Checker, e NodeId, t TypeId) TypeId:
	if c.argCount(e) > 1:
		c.errorAt(
			nodes[e].line,
			nodes[e].col,
			compileError("ArgumentCount", ["toCsv", "0 or 1", "{c.argCount(e)}"])
		)
		return tyError
	if not c.checkCsvRows(e, t): return tyError
	c.checkSeparatorArg(e, "toCsv", 0)
	c.noteDerive(t, deriveToCsv)
	c.typed(e, tyStr)
