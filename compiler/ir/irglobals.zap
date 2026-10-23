# The module variables' functions, lowered through the intermediate form as plain functions with
# an empty frame: `$init` gives the module variables their initial values (the runtime's first, in
# the order declared), `$fini` drops them at exit, the last declared first. A program's ordered
# binding (flagOrdered) is main's to assign, where it stands; when the entry is not main (the
# tests', which call no statement of main unless they call main), `$init` gives it its value, but
# for a test's source's (a unit, whose main the tests' program runs alone).
#
# Only the variables the generated code names (irGlobal notes them) and those whose initializer
# does something besides its value (initializerActs) are given one, each by a function of its own
# (`$init:name`) that `$init` calls: the functions an initializer calls may name more variables, so
# the functions and the initializers are generated in turns until neither asks for more.

alias nodes = g.c.nodes

# the program's functions, every module variable's initializer they or an effect need, `$init`
# and `$fini`
fn genFunctionsAndGlobals(mut g Gen, pending PendingFn[]):
	waiting = []   # the variables not given a value yet
	acts = []   # whether each one's initializer acts
	for d in g.c.decls:
		if g.initialized(d) and not g.startsZero(d):
			waiting.push(d)
			acts.push(g.initializerActs(d))
	given {NodeId: bool} = {}
	grew = true
	while grew:
		g.genCalledFunctions(pending)
		grew = false
		for i, d in waiting.copy():
			if d not in given and (acts[i] or nodes[d].text in g.globalsNamed):
				g.irGlobalInit(d)
				given[d] = true
				grew = true
	lw = irPlainLower()
	ordered, _ = g.c.initOrder(waiting)   # each after the variables its initializer reads
	for d in ordered:
		if d in given:
			lw.irPut(IrInst(op = irCall, key = g.initKey(d)))
	g.irEmitPlain("$init", lw)
	g.irGlobalsFini(given)
	g.genCalledFunctions(pending)   # the drops $fini asks for

# whether $init gives d its value: a module variable or a constant list, not main's ordered binding
# (a test's source's, unit, is always its main's: the tests' program runs that main alone)
fn initialized(mut g Gen, d NodeId):
	g.hasStorage(d) and
		(
			not nodes[d].hasFlag(flagOrdered) or
				g.entry != "main" and not isUnitMain(g.c.modules, g.entry) and
				not g.c.modules[moduleIndex(g.c.modules, nodes[d].mod())].unit
		)

# whether d's initial value is zero bytes (`0`, `zeros(n)`): its storage starts so
fn startsZero(mut g Gen, d NodeId):
	g.irIsZeroLiteral(nodes[d].kids[0]) and g.irZeroIsEmpty(g.c.constTypeOf(d))

fn initKey(g Gen, d NodeId):
	"$init:{nodes[d].text}"

# whether d's initializer changes something outside its value: it runs even when no code names d
fn initializerActs(mut g Gen, d NodeId):
	g.c.initializerDoes(d) & (doesAct | doesChange | doesCallValue | doesRaw | doesWait) != 0

fn irGlobalInit(mut g Gen, d NodeId):
	lw = irPlainLower()
	g.setSubst([], [])
	at = lw.irDef(irInt, IrInst(op = irDataAddr, imm = g.globalOf(nodes[d].text)))
	mark = lw.owned.len
	value = g.irValue(lw, nodes[d].kids[0])
	if lw.ok:
		g.irPutValue(lw, at, g.c.constTypeOf(d), value)
		g.irDropTemporaries(lw, mark)
	g.irEmitPlain(g.initKey(d), lw)

# the variables given a value, and those main assigns, dropped
fn irGlobalsFini(mut g Gen, given {NodeId: bool}):
	lw = irPlainLower()
	i = g.c.decls.len - 1
	while i >= 0:
		d = g.c.decls[i]
		if g.hasStorage(d) and (d in given or nodes[d].text in g.globalsNamed):
			at = lw.irDef(irInt, IrInst(op = irDataAddr, imm = g.globalOf(nodes[d].text)))
			lw.irPut(IrInst(op = irDrop, a = at, ty = g.c.constTypeOf(d)))
		i -= 1
	g.irEmitPlain("$fini", lw)

# a lowering of generated statements: no function node, no parameters, no result
fn irPlainLower():
	IrLower(f = newIrFn(), fnd = none, names = [], vals = [], breaks = [], conts = [])

# the lowered statements as the function key: entered like any function, left through the
# epilogue; the form must take them all
fn irEmitPlain(mut g Gen, key str, mut lw IrLower):
	if not lw.ok:
		die("x64: {key}: the intermediate form cannot take it: {lw.why}")
	g.irLeave(lw, -1)
	g.irOwnProgram(lw.f, key, g.irFileNow)
	g.irOwnSettle()
	g.made.push(IrMade(key = key.copy(), node = none, ret = tyUnit, f = move lw.f))
	g.irMadeLambdas()
	g.irMakeAll()
