# The order of evaluation under random programs: every call of `t(k, v)` logs its number k and
# gives v, and the numbers are given in the order the calls are written, so the log of a right
# program counts up from 0 with each number once. The calls sit in the forms the compiler takes
# apart or reorders: compound and plain assignments by computed indexes (nested, of a map),
# arithmetic of a number with a list or a struct of numbers on either side, struct literals
# with named fields out of order, tuples, destructuring, range bounds, interpolation, calls.
# The fuzzer also works out the values the program must print; a different log or value is a
# failure, kept in build/fuzz/.
#
#   zap run tests/fuzz/order.zap [count] [seed]

import fs
import fuzzRun

# the random numbers of the programs made, a sequence each run restarts from its seed
mut rng = Random(0)

# an expression the generator wrote: its source and the value it has
type Ex:
	src str
	value i64

# what the program's variables hold, as the program must see them
type State:
	acc i64
	xs i64[]
	grid i64[,]
	k0 i64   # the map's two values
	k1 i64

mut next = 0   # the number of the next call written

fn pick(n i64) i64:
	rng.next(0..=n - 1)

fn call():
	k = next
	next += 1
	v = rng.next(-3..=9)
	Ex(src = "t({k}, {v})", value = v)

# i64 % 3 of a value, as the program computes (v).abs() % n
fn slot(v i64, n i64):
	v.abs() % n

fn genExpr(depth i64) Ex:
	if depth == 0 or pick(4) == 0: return call()
	form = pick(12)
	if form == 0:
		a = genExpr(depth - 1)
		b = genExpr(depth - 1)
		return Ex(src = "({a.src} + {b.src})", value = a.value + b.value)
	if form == 1:
		a = genExpr(depth - 1)
		b = genExpr(depth - 1)
		return Ex(src = "({a.src} - {b.src})", value = a.value - b.value)
	if form == 2:
		a = genExpr(depth - 1)
		b = genExpr(depth - 1)
		return Ex(src = "({a.src}).max({b.src})", value = a.value.max(b.value))
	if form == 3:
		a = genExpr(depth - 1)
		b = genExpr(depth - 1)
		return Ex(src = "two({a.src}, {b.src})", value = a.value * 10 + b.value)
	if form == 4:
		a = genExpr(depth - 1)
		b = genExpr(depth - 1)
		c = genExpr(depth - 1)
		d = genExpr(depth - 1)
		values = [a.value, b.value, c.value]
		return Ex(
			src = "[{a.src}, {b.src}, {c.src}][({d.src}).abs() % 3]",
			value = values[slot(d.value, 3)]
		)
	if form == 5:
		a = genExpr(depth - 1)
		b = genExpr(depth - 1)
		return Ex(src = "second(({a.src}, {b.src}))", value = b.value)
	if form == 6:
		a = genExpr(depth - 1)
		b = genExpr(depth - 1)
		return Ex(src = "Pair(b = {a.src}, a = {b.src}).b", value = a.value)
	if form == 7:
		a = genExpr(depth - 1)
		b = genExpr(depth - 1)
		c = genExpr(depth - 1)
		return Ex(
			src = "([{a.src}, {b.src}] * {c.src}).sum()",
			value = (a.value + b.value) * c.value
		)
	if form == 8:
		c = genExpr(depth - 1)
		a = genExpr(depth - 1)
		b = genExpr(depth - 1)
		return Ex(
			src = "({c.src} * [{a.src}, {b.src}]).sum()",
			value = (a.value + b.value) * c.value
		)
	if form == 9:
		a = genExpr(depth - 1)
		b = genExpr(depth - 1)
		c = genExpr(depth - 1)
		return Ex(src = "(V2({a.src}, {b.src}) * {c.src}).x", value = a.value * c.value)
	if form == 10:
		c = genExpr(depth - 1)
		a = genExpr(depth - 1)
		b = genExpr(depth - 1)
		return Ex(src = "({c.src} * V2({a.src}, {b.src})).y", value = b.value * c.value)
	a = call()
	b = call()
	Ex(src = "\"\{{a.src}}:\{{b.src}}\".len", value = "{a.value}:{b.value}".len)

# one statement: its source lines, its effect on the state, and the value it prints (if any)
fn genStmt(n i64, mut st State, mut out str[]) i64?:
	form = pick(9)
	d = rng.next(0..=2)
	if form == 0:
		e = genExpr(d)
		out.push("acc += {e.src}")
		st.acc += e.value
	elif form == 1:
		i = genExpr(d)
		e = genExpr(d)
		out.push("xs[({i.src}).abs() % 3] = {e.src}")
		st.xs[slot(i.value, 3)] = e.value
	elif form == 2:
		i = genExpr(d)
		e = genExpr(d)
		out.push("xs[({i.src}).abs() % 3] += {e.src}")
		st.xs[slot(i.value, 3)] += e.value
	elif form == 3:
		r = genExpr(d)
		c = genExpr(d)
		e = genExpr(d)
		out.push("grid[({r.src}).abs() % 2][({c.src}).abs() % 2] += {e.src}")
		st.grid[slot(r.value, 2)][slot(c.value, 2)] += e.value
	elif form == 4:
		k = genExpr(d)
		e = genExpr(d)
		out.push("m[key({k.src})] += {e.src}")
		if slot(k.value, 2) == 0:
			st.k0 += e.value
		else:
			st.k1 += e.value
	elif form == 5:
		lo = genExpr(d)
		hi = genExpr(d)
		out.push("for i in ({lo.src}).abs() % 3..({hi.src}).abs() % 3 + 2:")
		out.push("\tacc += i")
		for i in slot(lo.value, 3)..slot(hi.value, 3) + 2:
			st.acc += i
	elif form == 6:
		a = genExpr(d)
		b = genExpr(d)
		out.push("p{n}, q{n} = {a.src}, {b.src}")
		out.push("acc += p{n} * 7 + q{n}")
		st.acc += a.value * 7 + b.value
	elif form == 7:
		a = genExpr(d)
		b = genExpr(d)
		out.push("v{n} = V2(y = {a.src}, x = {b.src})")
		out.push("acc += v{n}.x * 3 - v{n}.y")
		st.acc += b.value * 3 - a.value
	else:
		e = genExpr(d)
		out.push("print({e.src})")
		out.push("printed += 1")
		return e.value
	none

fn program(lines str[]):
	src = [
		"mut log i64[] = []",
		"",
		"fn t(k i64, v i64) i64:",
		"\tlog.push(k)",
		"\tv",
		"",
		"fn two(a i64, b i64) i64:",
		"\ta * 10 + b",
		"",
		"fn second(p (i64, i64)) i64:",
		"\t_, b = p",
		"\tb",
		"",
		"fn key(x i64) str:",
		"\t\"k\{x.abs() % 2}\"",
		"",
		"type Pair:",
		"\ta i64",
		"\tb i64",
		"",
		"type V2:",
		"\tx i64",
		"\ty i64",
		"",
		"mut acc = 0",
		"mut printed = 0",
		"mut xs = [0, 0, 0]",
		"mut grid = [[0, 0], [0, 0]]",
		"mut m \{str: i64} = \{ \"k0\": 0, \"k1\": 0 }",
	]
	for l in lines:
		src.push(l.copy())
	src.push("print(\"acc \{acc} \{xs} \{grid} \{m[\"k0\"]} \{m[\"k1\"]} \{printed >= 0}\")")
	src.push("print(log)")
	"{src.join("\n")}\n"

a = args
count = i64.parse(a.first ?? "100") ?? 100
seed = (i64.parse(a[1]) ?? 1) if a.len > 1 else 1
failed = fuzzOrder(count, seed)
print("{count - failed} of {count} programs right")

test "random programs evaluate every call once, in the order it is written":
	print("{4 - fuzzOrder(4, 5)} of 4 programs right")
	prints "4 of 4 programs right"

# count random programs from seed built, run and compared; how many failed
fn fuzzOrder(count i64, seed i64):
	failed = 0
	for n in 0..count:
		rng = Random(seed + n)
		next = 0
		st = State(acc = 0, xs = [0, 0, 0], grid = [[0, 0], [0, 0]], k0 = 0, k1 = 0)
		lines = []
		shown = []
		for s in 0..random(3..=12):
			if genStmt(s, st, lines) is v:
				shown.push("{v}")
		source = program(lines)
		log = []
		for k in 0..next:
			log.push(k)
		shown.push("acc {st.acc} {st.xs} {st.grid} {st.k0} {st.k1} true")
		shown.push("{log}")
		want = "{shown.join("\n")}\n"
		file = "{testDir()}of.zap"
		_ = fs.writeFile(file, source)
		exe = builtExe("of")
		_ = fs.deleteFile(exe)
		built = Process.output("{zapPath()} build {file}")
		problem = ""
		if built.code != 0:
			problem = "does not compile: {built.out.trimmed()}"
		else:
			ran = Process.output(exe)
			got = ran.out.replace("\r", "")
			if ran.code != 0:
				problem = "exits with {ran.code}: {got.trimmed()}"
			elif got != want:
				problem = "prints\n{got}instead of\n{want}"
		if problem != "":
			failed += 1
			keep = fuzzRun.keptFailure(file, seed + n)
			_ = fs.writeFile(keep, source)
			eprint("FAIL seed {seed + n} ({keep}): {problem}")
	failed
