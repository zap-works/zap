# The CSV reader and writer of a list of structs (`Row[].fromCsv(text)`, `rows.toCsv()`), written
# per type (derive.zap): the header's names matched to the struct's fields once, then each record
# read into the fields by their types. A str field takes its cell as it is; an optional one is none
# for an empty cell; any other reads its cell as the JSON of its type (`12`, `2.5`, `true`), so
# the types `fromJson` reads are read here. The records and their quotes are the runtime's
# (runtime/core/csv.zap).

alias nodes = c.nodes
alias tys = c.types

# $fromcsvN(s, sep): the rows of the text s, or the line and the column that cannot be read; the
# header's columns found by the runtime, each record's cells read by $csvrowN, the error of a
# cell said at one place
fn writeFromCsv(mut c Checker, i i64, mut src str[]):
	elem = innerOf(tys, c.deriveTypes[i])
	d = declOf(tys, elem)
	fts = c.fieldTypes(d)
	names = []
	optional = 0
	for f, ft in fts:
		names.push(c.fieldName(d, f).copy())
		if c.tKind(ft) == tOption: optional |= 1 << f
	quoted = names.map("{it}\\\"").join("")
	types = fts.map("{c.showTy(innerOf(tys, it) if c.tKind(it) == tOption else it)}\\\"").join("")
	src.push("fn $fromcsv{i}(s str, sep u8) {tyName(i)} ? str:")
	src.push("\tcur = Cursor(at = 0)")
	src.push("\theader = try csvHeader(s, cur, sep)")
	src.push("\tc = try csvColumns(header, \"{quoted}\", {optional})")
	src.push("\trows {tyName(i)} = []")
	src.push("\twhile csvMore(s, cur):")
	src.push("\t\tat = cur.at")
	src.push("\t\tcells = try csvRecord(s, cur, sep, header.len)")
	src.push(
		"\t\trows.push($csvrow{i}(cells, c) ?? return csvBadField(s, at, c, error, cells, \"{quoted}\", \"{types}\"))"
	)
	src.push("\trows")
	j = c.noteDerive(elem, 0)
	src.push("fn $csvrow{i}(cells str[], c i64[]) {tyName(j)} ? i64:")
	for f, ft in fts:
		c.writeCsvCell(f, ft, src)
	src.push("\t{c.structMade(j, elem, d, fts.len)}")

# the lines reading the cell of field f (of type ft) into g{f}, f the error of one not of its type
fn writeCsvCell(mut c Checker, f i64, ft TypeId, mut src str[]):
	cell = "cells[c[{f}]]"
	if c.tKind(ft) != tOption:
		src.push("\tg{f} = {c.csvCellRead(f, ft, cell)}")
		return
	j = c.noteDerive(ft, 0)
	src.push("\tg{f} {tyName(j)} = none")
	src.push("\tif c[{f}] >= 0 and {cell} != \"\":")
	src.push("\t\tg{f} = {c.csvCellRead(f, innerOf(tys, ft), cell)}")

# the expression reading the cell of type t: str as it is, else its JSON, or field f's error
fn csvCellRead(mut c Checker, f i64, t TypeId, cell str):
	if c.tKind(t) == tStr: return "{cell}.copy()"
	j = c.noteDerive(t, deriveUnjson)
	"$fromjson{j}({cell}) ?? return {f}"

# $tocsvN(rows, sep): the header, then a line a row, a cell quoted where it needs
fn writeToCsv(mut c Checker, i i64, mut src str[]):
	elem = innerOf(tys, c.deriveTypes[i])
	d = declOf(tys, elem)
	fts = c.fieldTypes(d)
	names = []
	for f in 0..fts.len:
		names.push(c.fieldName(d, f).copy())
	src.push("fn $tocsv{i}(rows {tyName(i)}, sep u8) str:")
	src.push("\tout u8[] = []")
	for f in 0..fts.len:
		if f > 0: src.push("\tout.push(sep)")
		src.push("\tcsvOutField(out, \"{names[f]}\", sep)")
	src.push("\tout.push(10)")
	src.push("\tfor row in rows:")
	for f, ft in fts:
		if f > 0: src.push("\t\tout.push(sep)")
		if c.tKind(ft) == tOption:
			src.push("\t\tmatch row.{names[f]}:")
			src.push("\t\t\tx: csvOutField(out, {c.csvCellWrite(innerOf(tys, ft), "x")}, sep)")
			src.push("\t\t\tnone: csvOutField(out, \"\", sep)")
		else:
			src.push("\t\tcsvOutField(out, {c.csvCellWrite(ft, "row.{names[f]}")}, sep)")
	src.push("\t\tout.push(10)")
	src.push("\tstr(move out)")

# the text of a cell holding the value v of type t: a str as it is, else its JSON
fn csvCellWrite(mut c Checker, t TypeId, v str):
	if c.tKind(t) == tStr: return v.copy()
	"$tojson{c.noteDerive(t, deriveJson)}({v})"
