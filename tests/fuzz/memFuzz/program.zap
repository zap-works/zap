# The whole generated test file around the statements.

import fuzzRun

# the fixed helper functions and types of the generated file, up to the test's first line
fn programPrelude():
	[
		"type Rec:",
		"\tname str",
		"\titems str[]",
		"",
		"\tfn add(move v str):",
		"\t\tif items.len < 20:",
		"\t\t\titems.push(v.copy())",
		"\t\tname = v",
		"",
		"\tfn label() str:",
		"\t\tcut(\"\{name}!\")",
		"",
		"fn cut(s str) str:",
		"\ts[0..len.min(12)].copy()",
		"",
		"fn join2(a str, b str) str:",
		"\tcut(a + b)",
		"",
		"fn addTo(mut xs str[], move v str):",
		"\tif xs.len < 20:",
		"\t\txs.push(v)",
		"",
		"fn lastOr(xs str[], d str) str:",
		"\tif xs.len == 0:",
		"\t\treturn d.copy()",
		"\txs[xs.len - 1].copy()",
		"",
		"fn eatLen(move s str) i64:",
		"\ts.len",
		"",
		"fn keep(move xs str[]) str[]:",
		"\txs",
		"",
		"fn firstLong(xs str[], n i64) str:",
		"\tfor x in xs:",
		"\t\tif x.len > n:",
		"\t\t\treturn x.copy()",
		"\t\"none\"",
		"",
		"fn make(s str) Rec:",
		"\tRec(name = cut(\"\{s}!\"), items = [s.copy(), cut(\"\{s}2\")] if s.len > 1 else [])",
		"",
		"fn opt(s str) str?:",
		"\tif s.len > 1:",
		"\t\treturn cut(\"\{s}?\")",
		"\tnone",
		"",
		"type Sh:",
		"\tWord(w str)",
		"\tPair(a str, b str)",
		"\tEmpty",
		"",
		"fn shape(s str) Sh:",
		"\tif s.len > 2:",
		"\t\treturn Sh.Pair(s[0..1].copy(), s[1..len.min(12)].copy())",
		"\tSh.Word(s.upper()) if s.len > 0 else Sh.Empty",
		"",
		"fn names(s str) str[]:",
		"\t[s.copy(), cut(\"\{s}1\"), cut(\"\{s}22\")]",
		"",
		"fn wrapIf<T>(c bool, move v T) T?:",
		"\tif c:",
		"\t\treturn v",
		"\tnone",
		"",
		"fn same<T>(move v T) T?:",
		"\tv",
		"",
		"fn lastOf<T>(xs T[]) T?:",
		"\tif xs.len == 0:",
		"\t\treturn none",
		"\txs[xs.len - 1].copy()",
		"",
		"fn pairOf<T>(a T, b T) T[]:",
		"\t[a.copy(), b.copy()]",
		"",
		"fn pickAt<T>(xs T[], i i64) ref T:",
		"\txs[i]",
		"",
		"fn firstOr<T>(xs T[], d T) T:",
		"\t(xs.first ?? d).copy()",
		"",
		"fn boxed<T>(move v T) T?[]:",
		"\tout T?[] = [none]",
		"\tout.push(v)",
		"\tout",
		"",
		"fn keepOpt<T>(move v T) T?:",
		"\to T? = none",
		"\to = v",
		"\to",
		"",
		"mut gs = \"g\"",
		"mut gl str[] = []",
		"",
		fuzzRun.testHeader(),
	]

pub fn program(sts St[], want str) str:
	out = programPrelude()
	flat = []
	flatten(sts, true, flat)
	body = []
	emit(sts, 0, 0, flat, 0, body)
	for i in 0..nStr:
		out.push("\t{sv(i)} = \"v{i}\"")
	for i in 0..nList:
		out.push("\t{lv(i)} str[] = []")
	out.push("\tr = Rec(name = \"r\", items = [])")
	out.push("\tm \{str: str} = \{}")
	out.push("\to str? = none")
	# one moved whole stays usable, empty, where what follows changes it (spec 2.4)
	changes = []
	for i in 0..nStr:
		if fuzzRun.movesWhole(body, 0, sv(i)): changes.push("\t{sv(i)} = \"\"")
	for i in 0..nList:
		if fuzzRun.movesWhole(body, 0, lv(i)): changes.push("\t{lv(i)}.clear()")
	if fuzzRun.movesWhole(body, 0, "r"): changes.push("\tr.name = \"\"")
	if fuzzRun.movesWhole(body, 0, "m"): changes.push("\tm.clear()")
	if fuzzRun.movesWhole(body, 0, "o"): changes.push("\to = none")
	out.extend(body)
	for i in 0..nStr:
		out.push("\tprint({sv(i)})")
	for i in 0..nList:
		out.push("\tprint({lv(i)})")
	out.push("\tprint(r.name)")
	out.push("\tprint(r.items)")
	out.push("\tprint(m.keys().sorted())")
	out.push("\tprint(m.keys().sorted().map(k: (m.get(k) ?? \"\").copy()))")
	out.push("\tprint(o ?? \"none\")")
	out.push("\tprint(gs)")
	out.push("\tprint(gl)")
	out.extend(changes)
	out.push("\texpect peakMemory() <= 64 * 1048576")
	out.push(fuzzRun.testCheck(want))
	"{out.join("\n")}\n"
