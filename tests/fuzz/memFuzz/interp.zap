# The reference interpreter: runs the statements on plain values to know what the program prints.

# the values the program's variables hold, as the program must see them
type Env:
	s str[]
	l str[,]
	rn str
	ri str[]
	loops i64[]
	mk str[]   # the map: its keys and values
	mv str[]
	has bool   # the optional
	ov str
	gs str   # the module variables
	gl str[]

# runs the statements; how they were left: 0 at their end, 1 by continue, 2 by break
fn run(sts St[], mut env Env) i64:
	for st in sts:
		k = st.kind
		c = st.c
		if k == 24:
			for i in 0..c:
				env.loops.push(i)
				left = run(st.body, env)
				env.loops.pop()
				if left == 2: break
		elif k == 25:
			left = run(st.body if env.loops[len - 1] % 2 == 0 else st.alt, env)
			if left > 0: return left
		elif k == 45:
			st.runGlobal(env)
		elif k == 46:
			st.runEat(env)
		elif k >= 35:
			left = st.runTemps(env)
			if left > 0: return left
		elif k <= 23:
			st.runStmtLow(env)
		else:
			st.runStmtMap(env)
	0

fn runStmtLow(st St, mut env Env):
	k = st.kind
	a = st.a
	b = st.b
	c = st.c
	if k == 0:
		env.s[a] = st.lit.copy()
	elif k == 1:
		env.s[a] = env.s[b].copy()
	elif k == 2:
		env.s[a] = cut(env.s[b] + env.s[c])
	elif k == 3:
		if env.l[a].len < 20:
			env.l[a].push(env.s[b].copy())
	elif k == 4:
		env.l[a] = env.l[b].copy()
	elif k == 5:
		v = env.s[b].copy()
		env.s[b] = ""
		env.s[a] = v
	elif k == 6:
		if not env.l[b].isEmpty:
			env.s[c] = env.l[b][env.l[b].len - 1].copy()
	elif k == 7:
		lit = st.lit
		env.l[a] = env.l[b].map(cut(it + lit))
	elif k == 8:
		n = st.lit.len
		env.l[a] = env.l[b].filter(.len > n)
	elif k == 9:
		env.rn = env.s[b].copy()
	elif k == 10:
		if env.ri.len < 20:
			env.ri.push(env.s[b].copy())
	elif k == 11:
		env.s[a] = env.rn.copy()
	elif k == 12:
		env.l[a] = env.ri.copy()
	elif k == 13:
		env.ri = env.l[b].copy()
	elif k == 14:
		env.s[a] = cut(env.s[b] + env.s[c])
	elif k == 15:
		if env.l[a].len < 20:
			env.l[a].push(env.s[b].copy())
	elif k == 16:
		if env.l[b].isEmpty:
			env.s[c] = st.lit.copy()
		else:
			env.s[c] = env.l[b][env.l[b].len - 1].copy()
	elif k == 17:
		env.l[a] = env.l[b].copy()
	elif k == 18:
		if a != b:
			t = env.s[a].copy()
			env.s[a] = env.s[b].copy()
			env.s[b] = t
	elif k == 19:
		env.s[a] = cut(env.s[c] + env.s[b])
	elif k == 20:
		env.s[a] = str(env.ri.reduce(0, (n, x): n + x.len))
	elif k == 21:
		env.l[a] = [env.s[b].copy(), env.s[c].copy()]
	elif k == 22:
		env.rn = env.s[b].copy()
		env.ri = [env.s[c].copy()]
	elif k == 23:
		doubled = env.l[a].flatMap([.copy(), .copy()]).filter(.len > 1)
		env.l[a] = [] if doubled.len > 20 else doubled

fn runStmtMap(st St, mut env Env):
	k = st.kind
	a = st.a
	b = st.b
	c = st.c
	if k == 26:
		i = env.mk.indexOf(env.s[b]) ?? -1
		if i >= 0:
			env.mv[i] = env.s[c].copy()
		else:
			env.mk.push(env.s[b].copy())
			env.mv.push(env.s[c].copy())
	elif k == 27:
		i = env.mk.indexOf(env.s[b]) ?? -1
		env.s[a] = env.mv[i].copy() if i >= 0 else "q"
	elif k == 28:
		i = env.mk.indexOf(env.s[b]) ?? -1
		if i >= 0:
			env.mk.remove(i)
			env.mv.remove(i)
	elif k == 29:
		env.has = env.s[b].len > 2
		env.ov = env.s[b].copy() if env.has else ""
	elif k == 30:
		env.s[a] = env.ov.copy() if env.has else "n"
	elif k == 31:
		loop c:
			if env.l[a].len < 20:
				env.l[a].push(env.s[b].copy())
	elif k == 32:
		found = "none"
		for x in env.l[b]:
			if found == "none" and x.len > c:
				found = x.copy()
		env.s[a] = found
	elif k == 33:
		if env.ri.len < 20:
			env.ri.push(env.s[b].copy())
		env.rn = env.s[b].copy()
	elif k == 34:
		env.s[a] = cut("{env.rn}!")

fn runGlobal(st St, mut env Env):
	a = st.a
	b = st.b
	x = st.x
	if x == 0:
		env.gs = env.s[b].copy()
	elif x == 1:
		env.s[a] = cut(env.gs + st.lit)
	elif x == 2:
		if env.gl.len < 20:
			env.gl.push(env.s[b].copy())
	elif x == 3:
		env.s[a] = env.gs.copy() if env.gl.isEmpty else env.gl[len - 1].copy()
	else:
		env.gs = env.s[b].copy() if env.gl.isEmpty else env.gl[len - 1].copy()

fn runEat(st St, mut env Env):
	a = st.a
	b = st.b
	x = st.x
	n = env.s[b].len
	if x == 0:
		loop n % 3:
			env.s[a] = cut(env.s[a] + st.lit)
	elif x == 1:
		env.s[a] = cut("{env.s[a]}{n}")
	elif x == 2:
		env.l[a] = [env.s[b].copy(), st.lit.copy()]
	elif x == 4:
		env.l[a] = (0..n % 3).map(_: st.lit.copy())
	else:
		j = cut(env.s[b] + st.lit)
		env.s[a] = cut(env.s[a] + (cut("{j}?") if j.len > 1 else st.lit.copy()))

# make's name and items, opt's value (a list of none or one), shape's parts (none, the word, the
# pair) and names, as the program's helpers make them
fn makeName(s str):
	cut("{s}!")

fn makeItems(s str) str[]:
	[s.copy(), cut("{s}2")] if s.len > 1 else []

fn optOf(s str) str[]:
	[cut("{s}?")] if s.len > 1 else []

fn optOr(s str, lit str):
	o = optOf(s)
	o[0].copy() if not o.isEmpty else lit.copy()

fn shapeOf(s str):
	if s.len > 2: return [s[..1].copy(), s[1..len.min(12)].copy()]
	[s.upper()] if not s.isEmpty else []

fn namesOf(s str):
	[s.copy(), cut("{s}1"), cut("{s}22")]

# the value of an operand (see operand)
fn operandValue(env Env, form i64, v i64, lit str):
	s = env.s[v]
	if form == 0 or form == 2: return s.copy()
	if form == 1: return env.rn.copy()
	if form == 3: return ("{s}xyz")[0..3].copy()
	if form == 4: return s.upper()
	if form == 5: return makeName(s)
	if form == 6: return "{s}yy"
	if form == 7: return "<{s}>"
	if form == 8: return lit.copy()
	optOr(s, lit)

# the value of the left side of ?? (see optional): none or one
fn optionalValue(env Env, form i64, v i64):
	s = env.s[v]
	if form == 0: return optOf(s)
	if form == 1:
		items = makeItems(s)
		return [items[0].copy()] if not items.isEmpty else []
	if form == 2:
		l = env.l[v % nList]
		return [l[0].copy()] if not l.isEmpty else []
	if form == 3: return [env.ov.copy()] if env.has else []
	i = env.mk.indexOf(s) ?? -1
	[env.mv[i].copy()] if i >= 0 else []

fn consumeValue(form i64, v str):
	if form == 1: return cut("[{v}]")
	cut("{v}z" if form == 2 else v.copy())

# what a statement over temporaries does to the values (see emitTemps); how it was left
# long: a dispatch on the statement kind, one arm each
fn runTemps(st St, mut env Env):
	k = st.kind
	a = st.a
	b = st.b
	c = st.c
	big = st.lit.len
	sb = env.s[b].copy()
	lb = st.b % nList
	if k == 35:
		v = env.operandValue(st.x, b, st.lit) if env.s[a].len % 2 == 0
			else env.operandValue(st.y, c, st.lit)
		env.s[a] = consumeValue(st.z, v)
	elif k == 36:
		o = env.optionalValue(st.x, b)
		v = o[0].copy() if not o.isEmpty else env.operandValue(st.y, c, st.lit)
		env.s[a] = consumeValue(st.z, v)
	elif k == 37:
		parts = shapeOf(sb)
		n = parts.len
		if st.x == 0:
			env.s[a] = cut(parts[0] + parts[1]) if n == 2
				else parts[0].copy() if n == 1
				else st.lit.copy()
		elif st.x == 1:
			env.s[a] = "<{parts[0]}>" if n == 2
				else cut(parts[0] + env.s[c]) if n == 1
				else env.s[c].copy()
		elif st.x == 2:
			if n > 0:
				env.s[a] = parts[0].copy()
			if n == 2:
				env.s[c] = parts[1].copy()
		else:
			env.s[a] = cut(parts[0] if n > 0 else st.lit)
	elif k == 38:
		o = optOf(sb) if st.x == 0 or st.x == 2 else makeItems(sb)
		if st.x == 0:
			env.s[a] = cut(o[0] + env.s[c]) if not o.isEmpty else st.lit.copy()
		elif st.x == 3:
			if not o.isEmpty:
				env.s[a] = o[len - 1].copy()
		else:
			env.s[a] = cut(o[0] if not o.isEmpty else st.lit)
	elif k == 39:
		items = makeItems(sb)
		first = items[0].copy() if not items.isEmpty else st.lit.copy()
		h = [
			sb.copy(),
			makeName(sb),
			first,
			sb.replace("a", "b").trimmed().copy(),
			"{sb}yy",
			"{sb}{env.s[c]}...."[0..4].copy()
		][st.x]
		if st.z > 0 and h.len > big: return st.z
		env.s[a] = cut(h + env.s[c])
	elif k == 40:
		o = makeItems(sb) if st.x == 3
			else env.l[lb].copy() if st.x == 4
			else optOf(sb.upper() if st.x == 2 else sb.copy())
		if o.isEmpty: return st.z
		env.s[a] = (o[len - 1] if st.x == 4 else o[0]).copy()
	elif k == 41:
		return st.runLeaving(env)
	elif k == 42:
		list = [
			namesOf(sb),
			makeItems(sb),
			env.l[lb].filter(.len > 1),
			env.l[lb].map(cut("{it}m")),
			[sb.copy(), env.s[c].copy()]
		][st.x]
		for e in list:
			if e.len > big:
				env.s[a] = e.copy()
				if st.z == 2: break
				if st.z == 1: continue
			env.s[c] = cut(env.s[c] + e)
	elif k == 43:
		st.runWhileIs(env)
	elif k == 44:
		present = st.x != 0 or sb.len > 1
		sc = env.s[c].copy()
		if st.y == 2:
			env.l[a % nList] = env.l[c % nList].copy() if present else []
		elif present:
			env.s[a] = [
				str(sc.len),
				sc.copy(),
				"",
				makeName(sc),
				optOr(sc, st.lit),
				sc.copy()
			][st.y]
		else:
			env.s[a] = [
				"0",
				st.lit.copy(),
				"",
				makeName(st.lit),
				st.lit.copy(),
				st.lit.copy()
			][st.y]
	0

# a match or an is over a value that may be there, its value's arm assigning and maybe leaving,
# the other arm (of a match) leaving
fn runLeaving(st St, mut env Env):
	sb = env.s[st.b].copy()
	there = []
	if st.x == 0:
		parts = shapeOf(sb)
		if parts.len == 1:
			if st.y == 0:
				env.s[st.a] = parts[0].copy()   # the word's arm
			return 0
		if parts.len == 2:
			there.push(parts[0].copy())
	elif st.x == 1:
		there = optOf(sb)
	elif st.x == 2:
		items = makeItems(sb)
		if not items.isEmpty:
			there.push(items[0].copy())
	elif st.x == 3:
		if env.has:
			there.push(env.ov.copy())
	else:
		l = env.l[st.b % nList]
		if not l.isEmpty:
			there.push(l[0].copy())
	if not there.isEmpty:
		env.s[st.a] = there[0].copy()
		return st.z % 3
	1 + st.z / 3 if st.y == 0 else 0

# the three while x is v loops of emitTemps
fn runWhileIs(st St, mut env Env):
	a = st.a
	c = st.c
	big = st.lit.len
	if st.x == 2:
		g = 0
		while g < big:
			items = makeItems(env.s[st.b])
			if items.isEmpty: break
			g += 1
			env.s[c] = cut(env.s[c] + items[0])
			if st.z == 2 and g > 1: break
		return
	q = namesOf(env.s[st.b]) if st.x == 1 else env.l[st.b % nList].copy()
	while not q.isEmpty:
		v = q.pop() ?? ""
		if st.x == 1:
			if v.len <= big: break
			env.s[c] = cut(env.s[c] + v)
			if st.z == 2 and env.s[c].len > 6: break
		else:
			if v.len > big:
				env.s[a] = v.copy()
				if st.z == 2: break
				if st.z == 1: continue
			env.s[c] = cut(env.s[c] + v)

pub fn expected(sts St[]) str:
	env = Env(
		s = [],
		l = [],
		rn = "r",
		ri = [],
		loops = [],
		mk = [],
		mv = [],
		has = false,
		ov = "",
		gs = "g",
		gl = []
	)
	for i in 0..nStr:
		env.s.push("v{i}")
	loop nList:
		env.l.push([])
	run(sts, env)
	out = []
	for v in env.s:
		out.push(v.copy())
	for v in env.l:
		out.push("{v}")
	out.push(env.rn.copy())
	out.push("{env.ri}")
	keys = env.mk.sorted()
	out.push("{keys}")
	out.push("{keys.map(env.mv[env.mk.indexOf(it) ?? -1].copy())}")
	out.push(env.ov.copy() if env.has else "none")
	out.push(env.gs.copy())
	out.push("{env.gl}")
	"{out.join("\n")}\n"
