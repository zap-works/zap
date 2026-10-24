# `zap build --loadable`: a build another build of the same program loads while it runs
# (runtime/core/loaded.zap's loadBuild), sharing its state: on Windows a PE, on Linux and Android the
# ELF the target's executable is, never run alone. Its code reaches the state (the global slots and
# the module variables) as any build's does; the `.load` file beside the image lists those
# references, each by the module variable it falls in, so the loader leads it to the running
# program's variable of that name, and names the entry, main as a function value is called. A
# program that loads builds carries the table of its module variables (name, type, place) for
# that; the two need not import the same modules, only lay out alike each variable the loaded
# build reaches, so a loaded build outlives a change to the program's other variables.

import fs

alias nodes = g.c.nodes
alias tys = g.c.types

# whether this build is one a program loads (zap build --loadable)
mut loadableBuild = false

# the global slots of the runtime that hold the address of the state's table and of the module
# variables (runtime/core/core.zap's map)
stateTableSlot = 14
moduleVariablesSlot = 15

# the bytes of the global slots (genX64's first data)
globalSlotsSize = 64 * 8

# a module variable as a loaded build finds it: its name, type, place among the variables (from
# their start), size
type StateVariable:
	name str
	key str
	at i64
	size i64

# a reference of the code to the state: the RVA of its field, how the field holds the place
# (referenceKinds), the variable it falls in (its line in the build's table, 0xFFFF_FFFF for the
# global slots) and its offset there
type StateReference:
	field i64
	kind n64
	variable i64
	offset i64

# the fixups that reach the data, by the kind of reference the loader leads (runtime/core/
# loaded.zap's leadTo): x64's 32-bit displacement (0); AArch64's adrp of the page (1), the add of
# the offset in it (2), the ldr of a double word there (3)
fn referenceKind(fixKind i64) n64?:
	[fxData, fxA64Page, fxA64Low, fxA64LowLoad].indexOf(fixKind)

# the entry of a loadable build: main as a function value (called as a closure is), planned when new
fn loadableEntry(mut g Gen, entry str) i64:
	g.irFnValueLabel(entry, tyFn(g.c.types, [], none))

# the module variables in the order of their places (a variable of no bytes before the one at its
# place, so a place inside the latter finds it)
fn stateVariables(mut g Gen):
	out = []
	for d in g.c.decls:
		if g.hasStorage(d):
			name = nodes[d].text.copy()
			t = g.c.constTypeOf(d)
			out.push(
				StateVariable(
					name,
					key = typeKey(tys, t),
					at = g.globalOf(name) - bssBase,
					size = g.c.slotSize(t)
				)
			)
	out.sortedBy((.at, .size))

# a variable's line in a table: its name, type, place and size
fn stateLine(v StateVariable):
	"{v.name}\t{v.key}\t{v.at}\t{v.size}\n"

# The table of the module variables in the data of a program that loads builds, its address in
# its slot: its length (4 bytes), then a line each (stateLine)
fn writeStateTable(mut g Gen):
	if not g.loadsBuilds(): return
	text = g.stateVariables().map(.stateLine()).join("")
	bytesAlign(g.a.data, 8)
	at = g.a.data.len
	bytesPut32(g.a.data, text.len)
	bytesPutStr(g.a.data, text)
	g.a.patchAddress(g.globalsOff + stateTableSlot * 8, dataRvaOf(g.a.code.len) + at)

# The `.load` file beside a loadable build's image: "ZLOD", the entry's RVA, the length of the
# table of the variables its code reaches (stateLine's, in their order) and the table, the count of
# references, then each reference as four little-endian u32: the RVA of its field, its kind
# (referenceKind), the variable it falls in (by its line) or 0xFFFF_FFFF for the global slots,
# and its offset in it; last the count of the C library's functions it calls on Linux (ccall.zap's
# libcSlot), each the RVA of the data word that holds its address, its name's length and name.
fn writeLoadFile(mut g Gen, exePath str, entryLabel i64):
	variables = g.stateVariables()
	starts = variables.map(.at)
	reached {i64: i64} = {}   # a variable -> its line
	lines = []
	refs = []
	for i, fixKind in g.a.fixKind:
		kind = referenceKind(fixKind) ?? continue
		target = g.a.fixTarget[i]
		if target >= bssBase:
			v = upperBound(starts, target - bssBase) - 1
			if v < 0: continue
			if v not in reached:
				reached[v] = lines.len
				lines.push(variables[v].stateLine())
			refs.push(
				StateReference(
					field = sectRva + g.a.fixAt[i],
					kind,
					variable = reached[v],
					offset = target - bssBase - variables[v].at
				)
			)
		elif target >= g.globalsOff and target < g.globalsOff + globalSlotsSize:
			refs.push(
				StateReference(
					field = sectRva + g.a.fixAt[i],
					kind,
					variable = 0xFFFF_FFFF,
					offset = target - g.globalsOff
				)
			)
	table = lines.join("")
	out = []
	bytesPutStr(out, "ZLOD")
	bytesPut32(out, sectRva + g.a.labelPos[entryLabel])
	bytesPut32(out, table.len)
	bytesPutStr(out, table)
	bytesPut32(out, refs.len)
	for r in refs:
		bytesPut32(out, r.field)
		bytesPut32(out, r.kind)
		bytesPut32(out, r.variable)
		bytesPut32(out, r.offset)
	bytesPut32(out, g.a.libcNames.len)
	for i, name in g.a.libcNames:
		bytesPut32(out, dataRvaOf(g.a.code.len) + g.a.libcAt[i])
		bytesPut32(out, name.len)
		bytesPutStr(out, name)
	fs.writeBytes("{exePath}.load", out) ?? exit(1, "zap: cannot write {exePath}.load: {error}")

# the count of xs (ascending) at or below x
fn upperBound(xs i64[], x i64):
	lo = 0
	hi = xs.len
	while lo < hi:
		mid = (lo + hi) / 2
		if xs[mid] <= x: lo = mid + 1
		else: hi = mid
	lo
