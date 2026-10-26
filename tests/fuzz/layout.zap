# The layouts of values under random programs: structs of fields of every width (u8, u16,
# bool, i32, f32, i64, f64) in random orders, so their sizes are seldom a multiple of 8, put in
# tuples beside other values, in lists, maps, optionals and enum payloads, copied, taken apart,
# passed through functions, changed field by field, a field or the whole taken out (move).
# The fuzzer knows what every field must hold after each step, writes the program and the text
# it must print, and runs it as a test (fuzzRun): a different output, a crash or a block never
# freed is a failure, kept in build/fuzz/. The bugs this hunts: a copy or a
# zeroing that runs past a value's own bytes, a field read at a wrong offset, a part of a
# constant freed under it.
#
# The suite runs a few programs from a fixed seed; for a long hunt:
#
#   zap run tests/fuzz/layout.zap [count] [seed]

import fuzzRun
import fs

# the random numbers of the programs made, a sequence each run restarts from its seed
mut rng = Random(0)

kinds = ["u8", "u16", "bool", "i32", "f32", "i64", "f64"]

type Field:
	kind i64

type StructType:
	fields Field[]

# a variable of the program: its struct type, its fields' values as printed, whether it may change
type Var:
	name str
	typ i64
	values str[]
	changeable bool

type Gen:
	types StructType[]
	vars Var[]
	lines str[]   # the statements of main
	want str[]   # what the program must print
	count i64   # names made so far

fn pick(n i64) i64:
	rng.next(0..=n - 1)

# a value of a kind, as written in the source and as printed (they are the same text here)
fn value(kind i64):
	k = kinds[kind]
	if k == "bool": return "false" if pick(2) == 0 else "true"
	if k == "f32" or k == "f64":
		quarters = rng.next(-40..=40)
		whole = quarters / 4
		rest = quarters % 4
		if rest == 0: return "{whole}"
		# k / 4 exactly: an f32 and an f64 print it the same way
		sign = "-" if quarters < 0 else ""
		a = quarters.abs()
		frac = ["", ".25", ".5", ".75"][a % 4]
		return "{sign}{a / 4}{frac}"
	if k == "u8": return "{rng.next(1..=250)}"
	if k == "u16": return "{rng.next(1..=60000)}"
	"{rng.next(-30000..=30000)}"

# the literal of a value in the source: a float needs its point
fn literal(kind i64, v str):
	k = kinds[kind]
	if (k == "f32" or k == "f64") and "." not in v: return "{v}.0"
	v.copy()

fn zeroOf(kind i64):
	"false" if kinds[kind] == "bool" else "0"

fn fieldName(i i64):
	"f{i}"

fn newName(mut g Gen, prefix str):
	g.count += 1
	"{prefix}{g.count}"

# S3(f0 = 2, f1 = 0.5)
fn construct(g Gen, t i64, values str[]):
	parts = []
	for i, value in values:
		parts.push("{fieldName(i)} = {literal(g.types[t].fields[i].kind, value)}")
	"S{t}({parts.join(", ")})"

fn freshValues(g Gen, t i64):
	out = []
	for f in g.types[t].fields:
		out.push(value(f.kind))
	out

fn printVar(mut g Gen, v Var):
	parts = []
	for i in 0..v.values.len:
		parts.push("\{{v.name}.{fieldName(i)}}")
	g.lines.push("print(\"{v.name}: {parts.join(" ")}\")")
	g.want.push("{v.name}: {v.values.join(" ")}")

fn addVar(mut g Gen, move name str, t i64, move values str[], changeable bool):
	g.vars.push(Var(name, typ = t, values, changeable))
	g.vars.len - 1

# a variable that may change, -1 when there is none
fn changeableVar(g Gen):
	options = []
	for i in 0..g.vars.len:
		if g.vars[i].changeable:
			options.push(i)
	-1 if options.isEmpty else options[pick(len)]

# One step on the variables, written as a statement (or a few) and followed in the values.
fn step(mut g Gen):
	op = pick(10)
	v = g.changeableVar()
	if v < 0 or op == 0:
		# a new struct
		t = pick(g.types.len)
		vals = g.freshValues(t)
		name = g.newName("v")
		g.lines.push("{name} = {g.construct(t, vals)}")
		g.addVar(name, t, vals, true)
		return
	t = g.vars[v].typ
	src = g.vars[v].name.copy()
	nf = g.types[t].fields.len
	if op <= 3:
		g.stepFields(op, v, t, src, nf)
	else:
		g.stepWrapped(op, v, t, src, nf)

fn stepFields(mut g Gen, op i64, v i64, t i64, src str, nf i64):
	if op == 1:
		# a copy, which then changes apart from the original
		name = g.newName("v")
		g.lines.push("{name} = {src}")
		c = g.addVar(name, t, g.vars[v].values.copy(), true)
		f = pick(nf)
		nv = value(g.types[t].fields[f].kind)
		g.lines.push("{g.vars[c].name}.{fieldName(f)} = {literal(g.types[t].fields[f].kind, nv)}")
		g.vars[c].values[f] = nv
		g.printVar(g.vars[c])
	elif op == 2:
		# a field changed
		f = pick(nf)
		nv = value(g.types[t].fields[f].kind)
		g.lines.push("{src}.{fieldName(f)} = {literal(g.types[t].fields[f].kind, nv)}")
		g.vars[v].values[f] = nv
	elif op == 3:
		# a field taken out: the value comes out, zero stays
		f = pick(nf)
		name = g.newName("x")
		g.lines.push("{name} = move {src}.{fieldName(f)}")
		g.lines.push("print(\"{name}: \{{name}}\")")
		g.want.push("{name}: {g.vars[v].values[f]}")
		g.vars[v].values[f] = zeroOf(g.types[t].fields[f].kind)

fn stepWrapped(mut g Gen, op i64, v i64, t i64, src str, nf i64):
	if op == 4:
		# through a tuple beside an f32 and a u8, taken apart
		name = g.newName("v")
		k = value(4)
		b = value(0)
		g.lines.push("{name}, k{g.count}, b{g.count} = tuple{t}({src}, {literal(4, k)}, {b})")
		g.lines.push("print(\"k{g.count}: \{k{g.count}} b{g.count}: \{b{g.count}}\")")
		g.want.push("k{g.count}: {k} b{g.count}: {b}")
		c = g.addVar(name, t, g.vars[v].values.copy(), false)
		g.printVar(g.vars[c])
	elif op == 5:
		# in a list beside another, one read back and changed
		other = g.freshValues(t)
		list = g.newName("l")
		name = g.newName("v")
		g.lines.push("{list} = [{g.construct(t, other)}, {src}]")
		g.lines.push("{name} = {list}[1]")
		f = pick(nf)
		nv = value(g.types[t].fields[f].kind)
		g.lines.push("{list}[0].{fieldName(f)} = {literal(g.types[t].fields[f].kind, nv)}")
		g.lines.push("print({list}.len)")
		g.want.push("2")
		c = g.addVar(name, t, g.vars[v].values.copy(), true)
		g.printVar(g.vars[c])
	elif op == 6:
		# in a map, changed where it is (at), read back
		m = g.newName("m")
		name = g.newName("v")
		f = pick(nf)
		nv = value(g.types[t].fields[f].kind)
		g.lines.push("{m} \{i64: S{t}} = \{}")
		g.lines.push("{m}[7] = {src}")
		g.lines.push(
			"if {m}.get(7) is w:\n\t\tw.{fieldName(f)} = {literal(g.types[t].fields[f].kind, nv)}"
		)
		g.lines.push("{name} = {m}.get(7) ?? fail(\"lost\")")
		vals = g.vars[v].values.copy()
		vals[f] = nv
		c = g.addVar(name, t, vals, false)
		g.printVar(g.vars[c])
	elif op == 7:
		# an enum's payload beside an f32, taken apart by a match
		e = g.newName("e")
		k = value(4)
		g.lines.push("{e} = Holder{t}.Some({src}, {literal(4, k)})")
		name = g.newName("v")
		g.lines.push("{name} = match {e}:\n\t\tSome(s, k):\n\t\t\tprint(\"k: \{k}\")\n\t\t\ts\n\t\tNothing: fail(\"empty\")")
		g.want.push("k: {k}")
		c = g.addVar(name, t, g.vars[v].values.copy(), false)
		g.printVar(g.vars[c])
	elif op == 8:
		# the whole taken out: the place keeps zeros
		name = g.newName("v")
		g.lines.push("{name} = move {src}")
		c = g.addVar(name, t, g.vars[v].values.copy(), false)
		zeros = []
		for fd in g.types[t].fields:
			zeros.push(zeroOf(fd.kind))
		g.vars[v].values = zeros
		g.printVar(g.vars[c])
	else:
		# through a function and an optional
		name = g.newName("v")
		g.lines.push("{name} = maybe{t}({src}) ?? fail(\"none\")")
		g.addVar(name, t, g.vars[v].values.copy(), false)

fn program(mut g Gen, want str):
	src = []
	for t in 0..g.types.len:
		src.push("type S{t}:")
		for i in 0..g.types[t].fields.len:
			src.push("\t{fieldName(i)} {kinds[g.types[t].fields[i].kind]}")
		src.push("")
		src.push("type Holder{t}:\n\tSome(s S{t}, k f32)\n\tNothing")
		src.push("")
		src.push("fn tuple{t}(s S{t}, k f32, b u8) (S{t}, f32, u8):\n\t(s, k, b)")
		src.push("")
		src.push("fn maybe{t}(s S{t}) S{t}?:\n\ts")
		src.push("")
	src.push(fuzzRun.testHeader())
	for l in g.lines:
		src.push("\t{l}")
	for v in g.vars:
		parts = []
		for i in 0..v.values.len:
			parts.push("\{{v.name}.{fieldName(i)}}")
		src.push("\tprint(\"{v.name}: {parts.join(" ")}\")")
	for v in g.vars:
		# one moved whole stays usable, empty, where what follows changes it (spec 2.4)
		if fuzzRun.movesWhole(g.lines, 0, v.name):
			src.push("\t{v.name} = {g.construct(v.typ, v.values)}")
	src.push(fuzzRun.testCheck(want))
	"{src.join("\n")}\n"

fn expected(g Gen):
	out = g.want.copy()
	for v in g.vars:
		out.push("{v.name}: {v.values.join(" ")}")
	"{out.join("\n")}\n"

fn newGen():
	g = Gen(types = [], vars = [], lines = [], want = [], count = 0)
	loop rng.next(1..=3):
		fields = []
		loop rng.next(1..=6):
			fields.push(Field(kind = pick(kinds.len)))
		g.types.push(StructType(fields))
	g

a = args
count = i64.parse(a.first ?? "100") ?? 100
seed = (i64.parse(a[1]) ?? 1) if a.len > 1 else 1
failed = fuzzLayouts(count, seed)
print("{count - failed} of {count} programs right")

test "values of every width keep their bytes through copies, takes, tuples, lists, maps and enums":
	print("{4 - fuzzLayouts(4, 5)} of 4 programs right")
	prints "4 of 4 programs right"

# count random programs from seed built, run and compared; how many failed
fn fuzzLayouts(count i64, seed i64):
	failed = 0
	for n in 0..count:
		rng = Random(seed + n)
		g = newGen()
		loop rng.next(4..=16):
			g.step()
		want = g.expected()
		_ = fs.writeFile("{testDir()}lf.zap", g.program(want))
		if not fuzzRun.passes("{testDir()}lf.zap", seed + n):
			failed += 1
	failed
