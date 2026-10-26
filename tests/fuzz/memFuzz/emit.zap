# The program text of a statement list: statements, operands, and generic calls.

fn emit(sts St[], depth i64, loops i64, flat Use[], first i64, mut out str[]) i64:
	pad = "\t".repeat(depth + 1)
	at = first
	for st in sts:
		i = at
		at += 1
		k = st.kind
		c = st.c
		if k == 24:
			out.push("{pad}for i{depth} in 0..{c}:")
			out.push("{pad}\t_ = i{depth}")
			at = emit(st.body, depth + 1, loops + 1, flat, at, out)
		elif k == 25:
			out.push("{pad}if i{depth - 1} % 2 == 0:")
			at = emit(st.body, depth + 1, loops, flat, at, out)
			if not st.alt.isEmpty:
				out.push("{pad}else:")
				at = emit(st.alt, depth + 1, loops, flat, at, out)
		else:
			st.emitStmt(pad, flat, i, loops, out)
	at

fn emitStmt(st St, pad str, flat Use[], i i64, loops i64, mut out str[]):
	k = st.kind
	b = st.b
	c = st.c
	gb = give(flat, i, loops, sv(b))
	gc = give(flat, i, loops, sv(c))
	# a statement that reads the same variable twice gives the first a copy
	gbc = "{sv(b)}.copy()" if b == c else gb.copy()
	if k <= 18:
		st.emitStmtBasic(pad, gb, flat, i, loops, out)
	elif k <= 34:
		st.emitStmtCall(pad, gb, gc, gbc, out)
	elif k == 45:
		st.emitStmtGlobal(pad, gb, out)
	elif k == 46:
		st.emitStmtEat(pad, gb, out)
	else:
		st.emitTemps(pad, out)

fn emitStmtBasic(st St, pad str, gb str, flat Use[], i i64, loops i64, mut out str[]):
	k = st.kind
	a = st.a
	b = st.b
	c = st.c
	q = "\""
	if k == 0:
		out.push("{pad}{sv(a)} = {q}{st.lit}{q}")
	elif k == 1:
		out.push("{pad}{sv(a)} = {gb}")
	elif k == 2:
		out.push("{pad}{sv(a)} = cut({sv(b)} + {sv(c)})")
	elif k == 3:
		out.push("{pad}if {lv(a)}.len < 20:")
		out.push("{pad}\t{lv(a)}.push({gb})")
	elif k == 4:
		out.push("{pad}{lv(a)} = {give(flat, i, loops, lv(b))}")
	elif k == 5:
		out.push("{pad}{sv(a)} = move {sv(b)}")
	elif k == 6:
		out.push("{pad}if {lv(b)}.len > 0:")
		last = "{lv(b)}[{lv(b)}.len - 1]"
		# the element moves out of a list nothing reads again
		out.push("{pad}\t{sv(c)} = {last.copy() if give(flat, i, loops, lv(b)) == lv(b) else "{last}.copy()"}")
	elif k == 7:
		out.push("{pad}{lv(a)} = {lv(b)}.map(x: cut({q}\{x}{st.lit}{q}))")
	elif k == 8:
		out.push("{pad}{lv(a)} = {lv(b)}.filter(x: x.len > {st.lit.len})")
	elif k == 9:
		out.push("{pad}r.name = {gb}")
	elif k == 10:
		out.push("{pad}if r.items.len < 20:")
		out.push("{pad}\tr.items.push({gb})")
	elif k == 11:
		out.push("{pad}{sv(a)} = r.name.copy()")
	elif k == 12:
		out.push("{pad}{lv(a)} = r.items.copy()")
	elif k == 13:
		out.push("{pad}r.items = {give(flat, i, loops, lv(b))}")
	elif k == 14:
		out.push("{pad}{sv(a)} = join2({sv(b)}, {sv(c)})")
	elif k == 15:
		out.push("{pad}addTo({lv(a)}, {gb})")
	elif k == 16:
		out.push("{pad}{sv(c)} = lastOr({lv(b)}, {q}{st.lit}{q})")
	elif k == 17:
		out.push("{pad}{lv(a)} = keep({give(flat, i, loops, lv(b))})")
	elif k == 18:
		if a != b:
			out.push("{pad}{sv(a)}, {sv(b)} = {sv(b)}, {sv(a)}")

fn emitStmtCall(st St, pad str, gb str, gc str, gbc str, mut out str[]):
	k = st.kind
	a = st.a
	b = st.b
	c = st.c
	if k == 19:
		# the closure owns what it keeps: the variable itself when nothing reads it again
		f = "f{out.len}"
		kept = sv(b)
		if b == c or gb != sv(b):
			kept = "k{out.len}"
			out.push("{pad}{kept} = {sv(b)}.copy()")
		out.push("{pad}{f} = (x str): cut(x + {kept})")
		out.push("{pad}{sv(a)} = {f}({sv(c)})")
	elif k == 20:
		out.push("{pad}{sv(a)} = str(r.items.reduce(0, (n, x): n + x.len))")
	elif k == 21:
		out.push("{pad}{lv(a)} = [{gbc}, {gc}]")
	elif k == 22:
		out.push("{pad}t{out.len} = Rec(name = {gbc}, items = [{gc}])")
		out.push("{pad}r = t{out.len - 1}")
	elif k == 23:
		out.push(
			"{pad}{lv(a)} = {lv(a)}.flatMap(x: [x.copy(), x.copy()]).filter(x: x.len > 1)"
		)
		out.push("{pad}if {lv(a)}.len > 20:")
		out.push("{pad}\t{lv(a)} = []")
	elif k == 26:
		out.push("{pad}m[{gbc}] = {gc}")
	elif k == 27:
		out.push("{pad}{sv(a)} = (m.get({sv(b)}) ?? \"q\").copy()")
	elif k == 28:
		out.push("{pad}_ = m.remove({sv(b)})")
	elif k == 29:
		out.push("{pad}if {sv(b)}.len > 2:")
		out.push("{pad}\to = {gb}")
		out.push("{pad}else:")
		out.push("{pad}\to = none")
	elif k == 30:
		out.push("{pad}{sv(a)} = match o:")
		out.push("{pad}\tv: v.copy()")
		out.push("{pad}\tnone: \"n\"")
	elif k == 31:
		w = "w{out.len}"
		out.push("{pad}{w} = 0")
		out.push("{pad}loop:")
		out.push("{pad}\t{w} += 1")
		out.push("{pad}\tif {w} > {c}:")
		out.push("{pad}\t\tbreak")
		out.push("{pad}\tif {lv(a)}.len < 20:")
		out.push("{pad}\t\t{lv(a)}.push({sv(b)}.copy())")
	elif k == 32:
		out.push("{pad}{sv(a)} = firstLong({lv(b)}, {c})")
	elif k == 33:
		out.push("{pad}r.add({gb})")
	elif k == 34:
		out.push("{pad}{sv(a)} = r.label()")

# the module variables
fn emitStmtGlobal(st St, pad str, gb str, mut out str[]):
	a = st.a
	b = st.b
	q = "\""
	x = st.x
	if x == 0:
		out.push("{pad}gs = {gb}")
	elif x == 1:
		out.push("{pad}{sv(a)} = cut({q}\{gs}{st.lit}{q})")
	elif x == 2:
		out.push("{pad}addTo(gl, {gb})")
	elif x == 3:
		out.push("{pad}{sv(a)} = lastOr(gl, gs)")
	else:
		out.push("{pad}gs = lastOr(gl, {sv(b)})")

fn emitStmtEat(st St, pad str, gb str, mut out str[]):
	a = st.a
	b = st.b
	q = "\""
	x = st.x
	# the statement reads a too: a value given away from it is a copy
	gn = "{sv(b)}.copy()" if a == b and x != 2 and x != 4 else gb.copy()
	if x == 0:
		out.push("{pad}loop eatLen({gn}) % 3:")
		out.push("{pad}\t{sv(a)} = cut({q}\{{sv(a)}}{st.lit}{q})")
	elif x == 1:
		out.push("{pad}{sv(a)} = cut({q}\{{sv(a)}}\{eatLen({gn})}{q})")
	elif x == 2:
		out.push("{pad}{lv(a)} = [{gb}, {q}{st.lit}{q}]")
	elif x == 3:
		out.push(
			"{pad}{sv(a)} = join2({sv(a)}, opt(join2({gn}, {q}{st.lit}{q})) ?? {q}{st.lit}{q})"
		)
	else:
		out.push("{pad}{lv(a)} = (0..eatLen({gb}) % 3).map(_: {q}{st.lit}{q})")

# ---------- statements over temporaries ----------

# an operand of ?: or ?? over the variable v (isPlaceForm and the others say which kind of value)
fn operand(form i64, v i64, lit str):
	s = sv(v)
	forms = [
		s.copy(),
		"r.name",
		"\" \{({s})} \".trimmed()",
		"\"\{({s})}xyz\"[0..3]",
		"{s}.upper()",
		"make({s}).name", "make(\"\{({s})}yy\").items[0]", "\"<\{{s}}>\"", "\"{lit}\"", "opt({s}) ?? \"{lit}\""]
	forms[form]

# the left side of ??: an owned temporary, a reference into a temporary, a reference into a
# place, a place, a reference into the map
fn optional(form i64, v i64):
	s = sv(v)
	forms = ["opt({s})", "make({s}).items.first", "{lv(v % nList)}.first", "o", "m.get({s})"]
	forms[form]

# what reads the value of ?: or ??: a copy, an interpolation, a read parameter
fn consume(form i64, e str):
	forms = ["cut({e})", "cut(\"[\{{e}}]\")", "join2({e}, \"z\")"]
	forms[form]

fn leave(z i64):
	["", "continue", "break"][z]

fn pushLeave(pad str, cond str, z i64, mut out str[]):
	if z > 0:
		out.push("{pad}if {cond}:")
		out.push("{pad}\t{leave(z)}")

# a value of the generic's type t made from variable v: a number, a str, a list, a struct, an
# optional (a reference goes through a (ref str)[], the last form only a stand-in)
fn genericArg(t i64, v i64):
	forms = [
		"{sv(v)}.len",
		"{sv(v)}.copy()",
		"{lv(v % nList)}.copy()",
		"make({sv(v)})",
		"opt({sv(v)})",
		sv(v)
	]
	forms[t]

# the call of generic g for type t, and what makes its result (an optional, a value, a reference)
# a value of the program's variables
fn genericCall(st St, h str):
	t = st.y
	ab = h.copy() if t == 5 else "[{genericArg(t, st.b)}, {genericArg(t, st.c)}]"
	q = "\""
	lit = "{q}{st.lit}{q}"
	call = [
		"wrapIf({sv(st.b)}.len > 1, {genericArg(t, st.c)})",
		"same({genericArg(t, st.c)})",
		"lastOf({ab})",
		"pairOf({genericArg(t, st.b)}, {genericArg(t, st.c)})[1]",
		"pickAt({ab}, 1)",
		"firstOr([{genericArg(t, st.c)}], {genericArg(t, st.b)})",
		"boxed({genericArg(t, st.c)})[1]",
		"keepOpt({genericArg(t, st.c)})",
	][st.x]
	if st.x == 3 or st.x == 5:
		return ["str({call})", call.copy(), call.copy(), "{call}.name", "{call} ?? {lit}"][t]
	if st.x == 4:
		return [
			"str({call})",
			"{call}.copy()",
			"{call}.copy()",
			"{call}.name.copy()",
			"({call} ?? {lit}).copy()",
			"{call}.copy()"
		][t]
	[
		"str({call} ?? 0)",
		"{call} ?? {lit}",
		"{call} ?? []",
		"({call} ?? make({lit})).name",
		"{call} ?? none ?? {lit}",
		"({call} ?? {lit}).copy()"
	][t]
