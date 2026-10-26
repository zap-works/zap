# grad's backward pass (gradWrite.zap): each operation, last first, gives its arguments their
# shares of its value's gradient; loops go over their steps backward; the sums of gradients of
# structs and lists are written as helpers ($gzeroN, $gaddN).

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# the ops from `from` on, last first
fn gBackward(mut c Checker, mut w GradWriter, from i64):
	j = w.ops.len - 1
	while j >= from and not w.failed:
		op = w.ops[j].copy()
		j -= 1
		if op.kind == opLoop:
			c.gLoopBack(w, op)
			continue
		dv = c.gMaterialize(w, op.result)
		if dv.isEmpty: continue
		names = op.args.map(w.values[it].name.copy())
		if op.kind == opRule or op.kind == opPull:
			slots = op.extra.split(",").filter(not .isEmpty).map(i64.parse(it) ?? 0)
			outs = []
			for slot in slots:
				outs.push(w.gFresh("c") if w.values[op.args[slot]].active else "_")
			target = outs[0] if outs.len == 1 else "{outs.join(", ")}"
			callArgs = names.copy()
			callArgs.push(dv)
			if op.kind == opRule:
				w.gLine("{target} = {callArgs[0]}.{op.text}({callArgs[1..].join(", ")})")
			else:
				w.gLine("{target} = {op.text}({callArgs.join(", ")})")
			for k, slot in slots:
				if outs[k] != "_":
					w.values[op.args[slot]].contribs.push(outs[k].copy())
		elif op.kind == opField:
			r = op.args[0]
			if w.values[r].fieldContribs.get(op.text) == none:
				w.values[r].fieldContribs[op.text.copy()] = []
			w.values[r].fieldContribs[op.text].push(dv)
		elif op.kind == opIndex:
			list = op.args[0]
			elems = c.gElemList(w, list)
			at = names[1]
			w.gLine("{elems}[{at}] = {c.gAddText(w.values[op.result].t, "{elems}[{at}]", dv)}")
		elif op.kind == opCopy and op.text.isEmpty:
			c.gShare(w, op.args[0], dv)
		elif op.kind == opCopy:
			c.gShare(w, op.args[0], "{c.showTy(w.values[op.args[0]].t)}({dv})")
		else:
			c.gScalarBack(w, op, dv, names)

# the share `text` of value a's gradient, bound to a name
fn gShare(mut c Checker, mut w GradWriter, a i64, text str):
	if not w.values[a].active: return
	if text.startsWith("$") and " " not in text and "." not in text:
		w.values[a].contribs.push(text.copy())   # a name already
		return
	name = w.gFresh("c")
	w.gLine("{name} = {text}")
	w.values[a].contribs.push(name)

# a number's operation: its arguments' shares of dv (names: the arguments' and the value's)
fn gScalarBack(mut c Checker, mut w GradWriter, op GOp, dv str, names str[]):
	a = op.args[0]
	x = names[0]
	v = w.values[op.result].name
	m = op.text
	if m == "+" or m == "-":
		c.gShare(w, a, dv)
		c.gShare(w, op.args[1], dv if m == "+" else "-{dv}")
	elif m == "*":
		c.gShare(w, a, "{dv} * {names[1]}")
		c.gShare(w, op.args[1], "{dv} * {x}")
	elif m == "/":
		c.gShare(w, a, "{dv} / {names[1]}")
		c.gShare(w, op.args[1], "-{dv} * {x} / ({names[1]} * {names[1]})")
	elif m == "neg": c.gShare(w, a, "-{dv}")
	elif m == "exp": c.gShare(w, a, "{dv} * {v}")
	elif m == "ln": c.gShare(w, a, "{dv} / {x}")
	elif m == "sqrt": c.gShare(w, a, "{dv} * 0.5 / {v}")
	elif m == "tanh": c.gShare(w, a, "{dv} * (1.0 - {v} * {v})")
	elif m == "sin": c.gShare(w, a, "{dv} * {x}.cos()")
	elif m == "cos": c.gShare(w, a, "-{dv} * {x}.sin()")
	elif m == "abs": c.gShare(w, a, "{dv} if {x} >= 0.0 else -{dv}")
	elif m == "max" or m == "min":
		# the larger (smaller) one takes the gradient; a tie gives it to the second, as PyTorch's relu
		wins = "{x} > {names[1]}" if m == "max" else "{x} < {names[1]}"
		c.gShare(w, a, "{dv} if {wins} else 0.0")
		c.gShare(w, op.args[1], "0.0 if {wins} else {dv}")

# Value v's gradient, its shares added (a struct's made of its fields'), bound to a name: ""
# when nothing gave it one (a zero).
fn gMaterialize(mut c Checker, mut w GradWriter, v i64) str:
	val = w.values[v].copy()
	if val.kind == gradRecord and not val.fieldContribs.isEmpty:
		st = c.derefType(val.t)
		d = declOf(tys, st)
		inits = []
		fieldTs = c.fieldTypes(d)
		for f, ft in fieldTs:
			name = c.fieldName(d, f).copy()
			part = "{val.name}.{name}"
			shares = val.fieldContribs.get(name) ?? []
			if c.gradKind(ft) == gradNone:
				inits.push("{name} = {c.gKept(ft, part)}")
			elif shares.isEmpty:
				inits.push("{name} = {c.gZeroText(ft, part)}")
			else:
				inits.push("{name} = {c.gSum(w, ft, shares)}")
		made = w.gFresh("d")
		w.gLine("{made} = {c.gTypeText(st)}({inits.join(", ")})")
		all = [made]
		all.extend(val.contribs)
		return c.gSum(w, st, all)
	shares = []
	if not val.elemList.isEmpty:
		shares.push(val.elemList.copy())
	shares.extend(val.contribs)
	if shares.isEmpty: return ""
	c.gSum(w, val.t, shares)

# the sum of the shares (names) of a gradient of type t, bound to a name when there are several
fn gSum(mut c Checker, mut w GradWriter, t TypeId, shares str[]):
	if shares.len == 1: return shares[0].copy()
	total = shares[0].copy()
	for s in shares[1..]:
		next = w.gFresh("d")
		w.gLine("{next} = {c.gAddText(t, total, s)}")
		total = next
	total

# a zero gradient of type t, shaped as the value `x`
fn gZeroText(mut c Checker, t0 TypeId, x str) str:
	t = c.derefType(t0)
	k = c.gradKind(t)
	if k == gradNum: return "{x} * 0.0"
	if k == gradTensor: return "{x}.zerosLike()"
	if k == gradRecord: return "$gzero{c.gNeedHelper(t)}({x})"
	if k == gradList: return "{x}.map({c.gZeroText(innerOf(tys, t), "it")})"
	c.gKept(t, x)

# a field without a gradient as the gradient's struct keeps it: the value's own
fn gKept(mut c Checker, t TypeId, x str):
	x.copy() if c.isPlainType(t) else "{x}.copy()"

# the sum of gradients a and b of type t
fn gAddText(mut c Checker, t0 TypeId, a str, b str) str:
	t = c.derefType(t0)
	k = c.gradKind(t)
	if k == gradNum or k == gradTensor: return "{a} + {b}"
	if k == gradRecord: return "$gadd{c.gNeedHelper(t)}({a}, {b})"
	if k == gradList: return "(0..{a}.len).map({c.gAddText(innerOf(tys, t), "{a}[it]", "{b}[it]")})"
	c.gKept(t, a)

# the derived index of struct t, its helpers asked
fn gNeedHelper(mut c Checker, t TypeId):
	i = c.noteDerive(t, 0)
	if i not in c.gradHelpers:
		c.gradHelpers.push(i)
	i

# the gradients of list `list`'s elements, a mutable list made of zeros the first time
fn gElemList(mut c Checker, mut w GradWriter, list i64):
	if not w.values[list].elemList.isEmpty: return w.values[list].elemList.copy()
	name = w.gFresh("e")
	w.gLine("{name} = {c.gZeroText(w.values[list].t, w.values[list].name)}")
	w.values[list].elemList = name.copy()
	name

# the gradient of parameter k, a zero when nothing gave it one
fn gGradientOf(mut c Checker, mut w GradWriter, k i64) str:
	d = c.gMaterialize(w, k)
	if not d.isEmpty: return d
	c.gZeroText(w.values[k].t, w.values[k].name)

# $gzeroN and $gaddN of each struct asked, written once
fn writeGradHelpers(mut c Checker, mut src str[]):
	while c.gradHelpersDone < c.gradHelpers.len:
		i = c.gradHelpers[c.gradHelpersDone]
		c.gradHelpersDone += 1
		t = c.deriveTypes[i]
		d = declOf(tys, t)
		ty = tyName(i)
		zeros = []
		sums = []
		fieldTs = c.fieldTypes(d)
		for f, ft in fieldTs:
			name = c.fieldName(d, f).copy()
			zeros.push("{name} = {c.gZeroText(ft, "a.{name}")}")
			sums.push("{name} = {c.gAddText(ft, "a.{name}", "b.{name}")}")
		src.push("fn $gzero{i}(a {ty}) {ty}:")
		src.push("\t{ty}({zeros.join(", ")})")
		src.push("fn $gadd{i}(a {ty}, b {ty}) {ty}:")
		src.push("\t{ty}({sums.join(", ")})")

# ---------- loops ----------

# the names a loop's body assigns that the function had before it
fn gCarried(c Checker, w GradWriter, body NodeId):
	out str[] = []
	for s in nodes[body].kids(kidIds):
		# `h = v` of a name bound before the loop: a let the checker read as an assignment
		name = ""
		if nodes[s].kind == nAssign and nodes[nodes[s].kids(kidIds)[0]].kind == nIdent:
			name = nodes[nodes[s].kids(kidIds)[0]].text.copy()
		elif nodes[s].kind == nLet and nodes[s].names().isEmpty:
			name = nodes[s].text.copy()
		if not name.isEmpty and w.names.get(name) != none and name not in out:
			out.push(name)
	out

# `for x in xs:` or `for i in a..b:` over values the loop changes. Forward, each step keeps what its
# backward pass reads: the values the loop changes at its start, and every value its operations
# make or read (moved into a list a value at the end of the step); the op the backward pass walks.
fn gFor(mut c Checker, mut w GradWriter, s NodeId):
	if nodes[s].text.startsWith("$") or nodes[s].kids(kidIds).len != 1 or nodes[s].sub().len != 1:
		return c.gradUnsupported(w, s, "this loop's form")
	if w.inLoop: return c.gradUnsupported(w, s, "a loop in a loop")
	body = nodes[s].sub()[0]
	elementT = tyInt(64, true)
	over, rangeText, elemT = c.gLoopOver(w, nodes[s].kids(kidIds)[0], elementT)
	if w.failed: return
	carried = c.gCarried(w, body)
	tag = w.gFresh("loop")
	before = carried.map(w.names[it])
	after, tapes = c.gLoopTapes(w, before, tag)
	steps = "{tag}n"
	index = "{tag}i"
	element = nodes[s].text.copy()
	outer = w.values.len
	inner = w.copy()
	starts = []
	elementValue = -1
	ends = []
	# a value the loop changes made active by the body makes each step's start active: read again
	allActive = false
	loop 2:
		inner = w.stepWriter()
		starts = []
		for k, name in carried:
			inner.gLine("{tapes[k]}.push({w.values[after[k]].name}{"" if c.isPlainType(w.values[after[k]].t) else ".copy()"})")
			start = inner.gAdd(
				inner.gFresh("v"),
				w.values[after[k]].t,
				w.values[after[k]].kind,
				w.values[after[k]].active or allActive
			)
			inner.values[start].lent = true
			inner.values[start].text = "{tapes[k]}[{index}]"
			inner.gLine("{inner.values[start].name} = {inner.values[start].text}")
			inner.names[name.copy()] = start
			starts.push(start)
		elementValue = -1
		if over >= 0:
			elementValue = inner.gAdd(
				"{w.values[over].name}[{index}]",
				elemT,
				c.gradKind(elemT),
				w.values[over].active
			)
			inner.values[elementValue].lent = true
			inner.names[element.copy()] = elementValue
		else:
			inner.names[element.copy()] = inner.gAdd(index, elementT, gradNone, false)
		for st in nodes[body].kids(kidIds).copy():
			c.gStmt(inner, st)
		ends = carried.map(inner.names[it])
		if allActive or not ends.any(inner.values[it].active) or
			starts.all(inner.values[it].active):
			break
		allActive = true
	kept = c.gKeepSteps(w, inner, StepValues(outer, starts.copy(), elementValue, ends.copy()), tag)
	activeAfter = false
	for k in 0..carried.len:
		inner.gLine("{w.values[after[k]].name} = {inner.values[ends[k]].name}")
		activeAfter = activeAfter or inner.values[ends[k]].active
	w.gLine("{steps} = {"{w.values[over].name}.len" if over >= 0 else "({rangeText}).count()"}")
	w.gLine("for {index} in {"0..{steps}" if over >= 0 else rangeText}:")
	w.lines.extend(inner.lines)
	w.counter = inner.counter
	w.failed = w.failed or inner.failed
	for k, name in carried:
		w.values[after[k]].active = w.values[after[k]].active or activeAfter
		w.names[name.copy()] = after[k]
	if after.any(w.values[it].active):
		at = w.loops.len
		w.ops.push(
			GOp(kind = opLoop, result = after[0], args = before.copy(), node = s, extra = str(at))
		)
		w.loops.push(
			GLoop(
				carried,
				before,
				after,
				tapes,
				over,
				rangeText,
				element,
				elementT = elemT,
				body,
				steps,
				index,
				outer,
				starts,
				ends,
				kept,
				elementValue,
				values = inner.values.copy(),
				ops = inner.ops.copy()
			)
		)

# what a loop walks: the list's value (-1 for a range) and its elements' type, or the range's
# text (`lo..hi`, its bounds' values) and indexT
fn gLoopOver(mut c Checker, mut w GradWriter, iterable NodeId, indexT TypeId):
	if nodes[iterable].kind == nRange and nodes[iterable].kids(kidIds).len == 2:
		lo = c.gExpr(w, nodes[iterable].kids(kidIds)[0])
		hi = c.gExpr(w, nodes[iterable].kids(kidIds)[1])
		return (-1, "{w.values[lo].name}..{w.values[hi].name}", indexT)
	over = c.gExpr(w, iterable)
	(over, "", innerOf(tys, c.derefType(w.values[over].t)))

# each value the loop changes copied before it (tag m k) and its tape, the list of its value at
# each step's start (tag t k): the copies' values and the tapes' names
fn gLoopTapes(mut c Checker, mut w GradWriter, before i64[], tag str):
	after = []
	tapes = []
	for k, b in before:
		m = "{tag}m{k}"
		tape = "{tag}t{k}"
		plain = c.isPlainType(w.values[b].t)
		w.gLine("{m} = {w.values[b].name}{"" if plain else ".copy()"}")
		w.gLine("{tape} {c.gTypeText(w.values[b].t)}[] = []")
		tapes.push(tape)
		after.push(w.gAdd(m, w.values[b].t, w.values[b].kind, w.values[b].active))
	(after, tapes)

# a writer of one step of a loop: w's values and names, its own lines and ops, one level in
fn stepWriter(w GradWriter):
	inner = w.copy()
	inner.lines = []
	inner.indent += 1
	inner.ops = []
	inner.inLoop = true
	inner

# a step's values: those from outer on are its own; its starts, its element's and its ends
type StepValues:
	outer i64
	starts i64[]
	element i64
	ends i64[]

# The values the backward pass reads that are the step's own: kept, a list each declared before
# the loop (tag k v) and pushed at the step's end
fn gKeepSteps(mut c Checker, mut w GradWriter, mut inner GradWriter, sv StepValues, tag str):
	kept = []
	for v in sv.outer..inner.values.len:
		if v in sv.starts or v == sv.element or inner.values[v].lent or
			not inner.values[v].name.startsWith("$v"):
			continue
		if inner.ops.any(v in .args or .kind == opScalar and .result == v):
			kept.push(v)
	for v in kept:
		list = "{tag}k{v}"
		w.gLine("{list} {c.gTypeText(inner.values[v].t)}[] = []")
		plain = c.isPlainType(inner.values[v].t)
		moved = "" if plain else "move " if v not in sv.ends else ""
		copied = ".copy()" if not plain and v in sv.ends else ""
		inner.lines.push(
			"{"\t".repeat(inner.indent)}{list}.push({moved}{inner.values[v].name}{copied})"
		)
	kept

# A loop's backward pass: its steps last first, each step's values read back from what the
# forward pass kept, their gradients given to the values it started with, to what the body read
# from before the loop, and to the list's elements.
fn gLoopBack(mut c Checker, mut w GradWriter, op GOp):
	gl = w.loops[i64.parse(op.extra) ?? 0].copy()
	seeds = []
	for k, a in gl.after:
		seeds.push(c.gMaterialize(w, a))
	if seeds.all(.isEmpty): return
	tag = w.gFresh("back")
	grads = (0..gl.carried.len).map("{tag}g{it}")
	for k, a in gl.after:
		w.gLine("{grads[k]} = {seeds[k] if not seeds[k].isEmpty else c.gZeroText(w.values[a].t, w.values[a].name)}")
	if gl.over >= 0 and w.values[gl.over].active:
		c.gElemList(w, gl.over)
	outer = gl.outer
	inner = w.copy()
	inner.lines = []
	inner.indent += 1
	inner.values = gl.values.copy()
	for v in 0..outer:
		inner.values[v] = w.values[v].copy()
	for mut value in inner.values:
		value.contribs = []
		value.fieldContribs = {}
	inner.ops = gl.ops.copy()
	inner.gLine("{gl.index} = {gl.steps} - 1 - {tag}j")
	if gl.elementValue >= 0 and w.values[gl.over].active:
		idx = inner.gAdd(gl.index, tyInt(64, true), gradNone, false)
		inner.ops.insert(
			0,
			GOp(kind = opIndex, result = gl.elementValue, args = [gl.over, idx], node = op.node)
		)
	# the step's values as the forward pass kept them, in the order they were made, each a name of
	# its own here (so a value no derivative reads is seen and not kept)
	renames {str: str} = {}
	for v in outer..gl.values.len:
		old = inner.values[v].name.copy()
		if not old.startsWith("$v") or v == gl.elementValue: continue
		fresh = inner.gFresh("v")
		renames[old] = fresh.copy()
		inner.values[v].name = fresh.copy()
		if v in gl.kept:
			inner.gLine("{fresh} = {gl.keptList(v)}[{gl.index}]")
		elif inner.values[v].lent:
			inner.gLine("{fresh} = {renamed(inner.values[v].text, renames)}")
	for k in 0..gl.carried.len:
		if inner.values[gl.ends[k]].active:
			inner.values[gl.ends[k]].contribs.push(grads[k].copy())
	c.gBackward(inner, 0)
	for k, start in gl.starts:
		d = c.gMaterialize(inner, start)
		inner.gLine("{grads[k]} = {d if not d.isEmpty else c.gZeroText(inner.values[start].t, inner.values[start].name)}")
	# what the body gave the values from before the loop: summed over the steps
	sums = []
	for v in 0..outer:
		if v == gl.over: continue
		fieldShares = inner.values[v].fieldContribs.copy()
		for field, shares in fieldShares:
			acc = "{tag}f{v}{field}"
			ft = c.gFieldType(w.values[v].t, field)
			w.gLine("{acc} = {c.gZeroText(ft, "{w.values[v].name}.{field}")}")
			inner.gLine("{acc} = {c.gAddText(ft, acc, c.gSum(inner, ft, shares))}")
			sums.push((v, field.copy(), acc))
		if not inner.values[v].contribs.isEmpty:
			acc = "{tag}w{v}"
			w.gLine("{acc} = {c.gZeroText(w.values[v].t, w.values[v].name)}")
			inner.gLine("{acc} = {c.gAddText(w.values[v].t, acc, c.gSum(inner, w.values[v].t, inner.values[v].contribs))}")
			sums.push((v, "", acc))
		if not inner.values[v].elemList.isEmpty and w.values[v].elemList.isEmpty:
			w.values[v].elemList = inner.values[v].elemList.copy()
	# a value kept that no derivative reads is not kept
	for v in gl.kept:
		name = inner.values[v].name
		if not inner.lines.any(
			valueNames(it).count(it == name) > 0 and not .trimmedStart().startsWith("{name} = ")
		):
			list = gl.keptList(v)
			w.lines = w.lines.filter(
				not .trimmedStart().startsWith("{list}.push(") and
					not (.trimmedStart().startsWith("{list} ") and .endsWith("[] = []"))
			)
	w.gLine("for {tag}j in 0..{gl.steps}:")
	w.lines.extend(inner.lines)
	w.counter = inner.counter
	w.failed = w.failed or inner.failed
	for (v, field, acc) in sums:
		if field.isEmpty:
			w.values[v].contribs.push(acc.copy())
		else:
			if w.values[v].fieldContribs.get(field) == none:
				w.values[v].fieldContribs[field.copy()] = []
			w.values[v].fieldContribs[field].push(acc.copy())
	for k, b in gl.before:
		if w.values[b].active:
			w.values[b].contribs.push(grads[k].copy())

# the list that keeps value v of a loop's steps
fn keptList(gl GLoop, v i64):
	"{gl.steps[..gl.steps.len - 1]}k{v}"

# the type of field `field` of struct type t
fn gFieldType(mut c Checker, t TypeId, field str):
	st = c.derefType(t)
	d = declOf(tys, st)
	fieldTs = c.fieldTypes(d)
	for f, ft in fieldTs:
		if c.fieldName(d, f) == field: return ft
	tyError

# text with the value names that renames maps written as their new ones
fn renamed(text str, renames {str: str}) str:
	out = []
	i = 0
	while i < text.len:
		if text[i] == '$' and i + 1 < text.len and text[i + 1] == 'v':
			j = i + 2
			while j < text.len and text[j] >= '0' and text[j] <= '9':
				j += 1
			word = text[i..j]
			out.extend((renames.get(word) ?? word).bytes())
			i = j
		else:
			out.push(text[i])
			i += 1
	str(move out)
