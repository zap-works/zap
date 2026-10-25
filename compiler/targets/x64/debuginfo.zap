# Where the code came from: the source lines of the generated code, the debug table the runtime
# reads when a program stops, and the symbol map (ZAP_RUN=map).

import fs
import perf

alias nodes = g.c.nodes

# the code from here on comes from line:col of file
fn noteDebugLine(mut g Gen, line i64, col i64, file i64):
	if g.codeNoting: g.linesNoted.extend([g.a.code.len, line, col, file])
	g.noteDebugLineAt(g.a.code.len, line, col, file)

# the same of the code at pos
fn noteDebugLineAt(mut g Gen, pos i64, line i64, col i64, file i64):
	n = g.debugLines.len
	if n >= 4 and g.debugLines[n - 4] == pos:
		g.debugLines.truncate(n - 4)   # nothing was emitted for the last note
	g.debugLines.push(i32(pos))
	g.debugLines.push(i32(line))
	g.debugLines.push(i32(col))
	g.debugLines.push(i32(file))

# the source file the code being emitted notes its lines in ("" before any)
fn curFileName(g Gen):
	g.debugFiles[g.curFile].copy() if g.curFile < g.debugFiles.len else ""

# the index of a source file in debugFiles (added when new)
fn debugFile(mut g Gen, path str):
	i = g.debugFiles.indexOf(path) ?? -1
	if i >= 0: return i
	g.debugFiles.push(path.copy())
	g.debugFiles.len - 1

# The expression e is being generated: failures in its code are reported at its place.
fn atNode(mut g Gen, e NodeId):
	if nodes[e].line > 0:
		g.curLine = nodes[e].line
		g.curCol = nodes[e].col

# The table the runtime reads when the program stops on an error (rt failAt, the crash
# handler): the functions by their first byte, the lines by the first byte of their code, the
# files, and their names. Words of 32 bits: "ZDBG", the counts of functions, lines and files,
# the end of the code, then (start, name) per function, (start, line, col, file) per line, (name) per file, then
# the names, each ending in a zero byte. Starts are offsets from the image's base, names
# offsets from the table's start. Its address goes in the runtime's global slot debugTableSlot.
fn writeDebugTable(mut g Gen):
	fns = []   # start, key index, flattened
	keys = []
	for key in g.fnLabels.keys():
		label = g.fnLabels.get(key) ?? -1
		if g.placedFunction(label):
			fns.push(i64(g.a.labelPos[label]))
			fns.push(keys.len)
			keys.push(key.copy())
	nf = fns.len / 2
	order = []
	for i in 0..nf:
		order.push(i)
	order = order.sortedBy(fns[it * 2])
	nl = g.debugLines.len / 4
	nfiles = g.debugFiles.len
	headerWords = 5 + nf * 2 + nl * 4 + nfiles
	names = []
	fnName = []
	for i in order:
		fnName.push(headerWords * 4 + names.len)
		names.extend(tableName(keys[fns[i * 2 + 1]]).bytes())
		names.push(0)
	fileName = []
	for f in g.debugFiles:
		fileName.push(headerWords * 4 + names.len)
		names.extend(portablePath(f).bytes())
		names.push(0)
	bytesAlign(g.a.data, 8)
	at = g.a.data.len
	codeRva = sectRva
	bytesPut32(g.a.data, 1_195_525_210)   # "ZDBG"
	bytesPut32(g.a.data, nf)
	bytesPut32(g.a.data, nl)
	bytesPut32(g.a.data, nfiles)
	bytesPut32(g.a.data, codeRva + g.a.code.len)   # where the code ends
	for k in 0..nf:
		bytesPut32(g.a.data, codeRva + fns[order[k] * 2])
		bytesPut32(g.a.data, fnName[k])
	for k in 0..nl:
		bytesPut32(g.a.data, codeRva + g.debugLines[k * 4])
		bytesPut32(g.a.data, g.debugLines[k * 4 + 1])
		bytesPut32(g.a.data, g.debugLines[k * 4 + 2])
		bytesPut32(g.a.data, g.debugLines[k * 4 + 3])
	for k in 0..nfiles:
		bytesPut32(g.a.data, fileName[k])
	g.a.data.extend(names)
	# the image is loaded at its base, the data right after the code (asmWritePe, asmWriteElf)
	dataRva = dataRvaOf(g.a.code.len)
	g.a.patchAddress(g.globalsOff + debugTableSlot * 8, dataRva + at)

# whether the function's label is placed, its code its own (not merged into another's, samecode.zap)
fn placedFunction(g Gen, label i64):
	label >= 0 and label < g.a.labelPos.len and g.a.labelPos[label] >= 0 and
		label not in g.mergedInto

# a function's name in the debug table: as the program names it, a lambda's and an instance
# made for a given function's without the compiler's numbers for the nodes ($lam, f$given),
# which a change to the compiler moves while the code stays the same
fn tableName(key str):
	if key.startsWith("$lam:"): return "$lam"
	at = key.indexOf("$given") ?? return displayName(key)
	"{displayName(key[..at])}$given"

# a function's key as a program names it: `game__props` is game.props, `rt__fail` rt.fail,
# `a_db__f` (see prefixFor) a.b.f, a together check's source's as its program's own
fn displayName(key str):
	at = key.indexOf("__") ?? -1
	if at < 0: return key.copy()
	if isUnitKey(key): return key[at + 2..].replace("__", ".")
	out = []
	i = 0
	while i < at:
		if key[i] == '_' and i + 1 < at:
			out.push('.' if key[i + 1] == 'd' else '_')
			i += 2
		else:
			out.push(key[i])
			i += 1
	"{str(move out)}.{key[at + 2..].replace("__", ".")}"

# the global slot of the runtime that holds the address of the debug table (runtime/core/core.zap's map)
debugTableSlot = 62

# ZAP_RUN=map: the functions of the program and their code addresses (RVA), one per line
# (exemap.zap reads it)
fn writeSymbolMap(g Gen, exe str):
	path = "{exe}.map"
	lines = [perf.mapHead(exe)]
	for key in g.fnLabels.keys():
		label = g.fnLabels.get(key) ?? -1
		if g.placedFunction(label):
			lines.push("{sectRva + g.a.labelPos[label]} {key}")
	fs.writeFile(path, "{lines.join("\n")}\n") ?? eprint("zap: cannot write {path}: {error}")
