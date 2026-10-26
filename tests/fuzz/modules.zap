# Programs of several modules that give their types the same names: each module declares its own
# `Body`, `Item`, `Node` or `Tag` (and an `Inner` inside it) with fields of its own drawn at
# random (integers, strings, lists, the inner type), a module variable holding a list of them,
# and functions that make, copy, sum and drop them. The main module makes each module's values,
# copies and moves them, and prints a checksum of each, and instantiates each module's generic
# with a type of its own named like a module's; the fuzzer works out what it must print and runs
# the program as a test (fuzzRun): a crash, a different output or a block never freed is a
# failure, its main kept in build/fuzz/ and its modules shown. Two types of a name in two
# modules once shared their drop and copy functions.
#
#   zap run tests/fuzz/modules.zap [count] [seed]

import fuzzRun
import fs

# the random numbers of the programs made, a sequence each run restarts from its seed
mut rng = Random(0)

names = ["Body", "Item", "Node", "Tag"]

# a field of a module's type: 0 an integer, 1 a str, 2 a list of integers, 3 the module's Inner
type Field:
	kind i64
	name str

type Module:
	name str
	typeName str
	fields Field[]
	innerFields Field[]   # Inner's: integers and strs only
	count i64   # the values make() gives
	seed i64

fn genModule(i i64):
	fields = []
	for k in 0..random(1..=5):
		fields.push(Field(kind = rng.next(0..=3), name = "f{k}"))
	inner = []
	for k in 0..random(1..=3):
		inner.push(Field(kind = rng.next(0..=1), name = "g{k}"))
	Module(
		name = "m{i}",
		typeName = names[rng.next(0..=len - 1)].copy(),
		fields,
		innerFields = inner,
		count = rng.next(1..=6),
		seed = rng.next(1..=50)
	)

# the value an integer field k of element j takes, the length of a str field's, the count of a
# list field's elements (which are j, j + 1, ...)
fn intOf(m Module, j i64, k i64):
	m.seed * 10 + j + k

fn strLenOf(j i64, k i64):
	(j + k) % 5 + 1

fn listLenOf(j i64, k i64):
	(j + k) % 4

# the expression that builds a field's value for element j (`j` a variable of the program)
fn fieldValue(m Module, f Field, k i64, inner bool) str:
	if f.kind == 0: return "{m.seed * 10 + k} + j"
	if f.kind == 1: return "\"x\".repeat((j + {k}) % 5 + 1)"
	if f.kind == 2: return "(0..(j + {k}) % 4).map(q: j + q)"
	parts = []
	for i, innerField in m.innerFields:
		g = innerField
		parts.push("{g.name} = {m.fieldValue(g, i, true)}")
	_ = inner
	"Inner({parts.join(", ")})"

# what a field adds to an element's checksum
fn fieldSum(m Module, f Field, j i64, k i64) i64:
	if f.kind == 0: return m.intOf(j, k)
	if f.kind == 1: return strLenOf(j, k)
	if f.kind == 2:
		n = listLenOf(j, k)
		return n + n * j + n * (n - 1) / 2
	s = 0
	for i, innerField in m.innerFields:
		s += m.fieldSum(innerField, j, i)
	s

# the expression that sums a field of the element `x` (as the program computes it)
fn fieldSumText(f Field, at str):
	if f.kind == 0: return "{at}.{f.name}"
	if f.kind == 1: return "{at}.{f.name}.len"
	if f.kind == 2: return "{at}.{f.name}.len + {at}.{f.name}.sum()"
	"innerSum({at}.{f.name})"

fn moduleSource(m Module):
	t = m.typeName
	out = []
	out.push("# a module of the modules fuzzer")
	out.push("")
	out.push("pub type Inner:")
	for g in m.innerFields:
		out.push("\t{g.name} {"i64" if g.kind == 0 else "str"}")
	out.push("")
	out.push("pub type {t}:")
	for f in m.fields:
		ty = "i64" if f.kind == 0 else "str" if f.kind == 1 else "i64[]" if f.kind == 2 else "Inner"
		out.push("\t{f.name} {ty}")
	out.push("")
	out.push("fn innerSum(x Inner) i64:")
	terms = ["0"]
	for g in m.innerFields:
		terms.push(g.fieldSumText("x"))
	out.push("\t{terms.join(" + ")}")
	out.push("")
	out.push("pub fn one(j i64) {t}:")
	parts = []
	for k, field in m.fields:
		f = field
		parts.push("{f.name} = {m.fieldValue(f, k, false)}")
	out.push("\t{t}({parts.join(", ")})")
	out.push("")
	out.push("pub fn make() {t}[]:")
	out.push("\t(0..{m.count}).map(j: one(j))")
	out.push("")
	out.push("pub fn total(xs {t}[]) i64:")
	out.push("\ts = 0")
	out.push("\tfor x in xs:")
	sums = ["0"]
	for f in m.fields:
		sums.push(f.fieldSumText("x"))
	out.push("\t\ts += {sums.join(" + ")}")
	out.push("\ts")
	out.push("")
	out.push("stock = [one(0), one(1)]")
	out.push("")
	out.push("pub fn stockTotal() i64:")
	out.push("\ttotal(stock.copy())")
	out.push("")
	# a generic the main module instantiates with a type of its own named like this one's: its
	# default and its body still mean this module's names
	out.push("pub type Holder<T>:")
	out.push("\tv T")
	out.push("\tn i64 = mark()")
	out.push("")
	out.push("fn mark() i64:")
	out.push("\t{m.seed}")
	out.push("")
	out.push("pub fn hold<T>(move x T) Holder<T>:")
	out.push("\tHolder<T>(v = x)")
	"{out.join("\n")}\n"

fn mainSource(ms Module[], want str):
	out = []
	for m in ms:
		out.push("import {m.name}")
	# the main module declares the first module's type name, an Inner and a mark of its own
	out.push("")
	out.push("type {ms[0].typeName}:")
	out.push("\tz i64")
	out.push("")
	out.push("type Inner:")
	out.push("\tw str")
	out.push("")
	out.push("fn mark() i64:")
	out.push("\t-1")
	out.push("")
	out.push(fuzzRun.testHeader())
	out.push("\tmine = Inner(w = \"i\")")
	for m in ms:
		out.push(
			"\th{m.name} = {m.name}.hold({ms[0].typeName}(z = {m.seed} + mark() + mine.w.len))"
		)
		out.push("\tprint(h{m.name}.v.z + h{m.name}.n)")
	for m in ms:
		out.push("\ta{m.name} = {m.name}.make()")
		out.push("\tb{m.name} = a{m.name}.copy()")
		out.push("\tc{m.name} {m.name}.{m.typeName}[] = []")
		out.push("\tfor x in a{m.name}:")
		out.push("\t\tc{m.name}.push(x.copy())")
		out.push("\tc{m.name}.push({m.name}.one(7))")
		out.push("\tprint({m.name}.total(move a{m.name}) + {m.name}.total(b{m.name}) + {m.name}.total(c{m.name}) + {m.name}.stockTotal())")
	out.push(fuzzRun.testCheck(want))
	"{out.join("\n")}\n"

# the line main prints for a module
fn expected(m Module):
	one = 0
	for j in 0..m.count:
		for k, field in m.fields:
			one += m.fieldSum(field, j, k)
	seventh = 0
	for k, field in m.fields:
		seventh += m.fieldSum(field, 7, k)
	stock = 0
	for j in 0..2:
		for k, field in m.fields:
			stock += m.fieldSum(field, j, k)
	one * 3 + seventh + stock

a = args
count = i64.parse(a.first ?? "100") ?? 100
seed = (i64.parse(a[1]) ?? 1) if a.len > 1 else 1
failed = fuzzModules(count, seed)
print("{count - failed} of {count} programs right")

test "types of the same name in several modules keep their own drops and copies":
	print("{3 - fuzzModules(3, 5)} of 3 programs right")
	prints "3 of 3 programs right"

# count random programs from seed built, run and compared; how many failed
fn fuzzModules(count i64, seed i64):
	failed = 0
	for n in 0..count:
		rng = Random(seed + n)
		ms = []
		for i in 0..random(2..=4):
			ms.push(genModule(i))
		for m in ms:
			_ = fs.createDir("{testDir()}{m.name}")
			_ = fs.writeFile("{testDir()}{m.name}/{m.name}.zap", m.moduleSource())
		want = ""
		for m in ms:
			want += "{m.seed * 2}\n"
		for m in ms:
			want += "{m.expected()}\n"
		_ = fs.writeFile("{testDir()}mods.zap", mainSource(ms, want))
		if not fuzzRun.passes("{testDir()}mods.zap", seed + n):
			failed += 1
			for m in ms:
				eprint(m.moduleSource())
		for m in ms:
			_ = fs.deleteFile("{testDir()}{m.name}/{m.name}.zap")
	failed
