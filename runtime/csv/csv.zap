# CSV (RFC 4180): the pieces `Row[].fromCsv`, `rows.toCsv()` and std/csv call, loaded when a program
# uses one (runtimeDirs.zap). A record is read at a cursor (as JSON's values are, core/value.zap); an
# error says the line and the column it is at.

# ---------- reading ----------

# the line (from 1) of byte `at`
fn csvLine(s str, at i64) i64:
	line = 1
	for k in 0..at.min(s.len):
		if s[k] == '\n': line += 1
	line

# whether a record is left, past the empty lines
fn csvMore(s str, mut cur Cursor) bool:
	while cur.at < s.len and (s[cur.at] == '\n' or s[cur.at] == '\r'):
		cur.at += 1
	cur.at < s.len

# where the error is: the line of the record that began at byte `start`, and its column
fn csvWhere(s str, start i64, column i64) str:
	"CSV line {csvLine(s, start)}, column {column}"

# The record at the cursor: its fields split at `sep`, a quoted one (`"a,b"`, `""` a quote, a line
# break allowed inside) unquoted, the cursor past the line break. `width` is the fields it must
# have (-1: any number).
fn csvRecord(s str, mut cur Cursor, sep u8, width i64) str[] ? str:
	start = cur.at
	cells str[] = []
	loop:
		if cur.at < s.len and s[cur.at] == '"':
			field u8[] = []
			cur.at += 1
			closed = false
			while cur.at < s.len and not closed:
				b = s[cur.at]
				if b != '"':
					field.push(b)
					cur.at += 1
				elif cur.at + 1 < s.len and s[cur.at + 1] == '"':
					field.push(b)
					cur.at += 2
				else:
					closed = true
					cur.at += 1
			if not closed:
				return "{csvWhere(s, start, cells.len + 1)}: a quoted field is never closed"
			if cur.at < s.len and s[cur.at] != sep and s[cur.at] != '\n' and s[cur.at] != '\r':
				return "{csvWhere(s, start, cells.len + 1)}: text after a closing quote"
			cells.push(str(move field))
		else:
			from = cur.at
			while cur.at < s.len and s[cur.at] != sep and s[cur.at] != '\n' and s[cur.at] != '\r':
				cur.at += 1
			cells.push(s[from..cur.at].copy())
		if cur.at < s.len and s[cur.at] == sep:
			cur.at += 1
			continue
		break
	if cur.at < s.len and s[cur.at] == '\r': cur.at += 1
	if cur.at < s.len and s[cur.at] == '\n': cur.at += 1
	if width >= 0 and cells.len != width:
		return "CSV line {csvLine(s, start)}: {cells.len} columns where the header has {width}"
	cells

# the first record, the header, at the cursor; an error when the text has none
fn csvHeader(s str, mut cur Cursor, sep u8) str[] ? str:
	if not csvMore(s, cur): return "CSV: the text has no header line"
	csvRecord(s, cur, sep, -1)

# A typed read's columns: where each field (named in `names`, each name ended by a quote) is in the
# header, -1 for one not there whose bit of `optional` is set; the error of the first one missing.
fn csvColumns(header str[], names str, optional i64) i64[] ? str:
	columns i64[] = []
	parts = names.split("\"")
	for f in 0..parts.len - 1:
		at = header.indexOf(parts[f]) ?? -1
		if at < 0 and (optional >> f) & 1 == 0: return "CSV line 1: no column \"{parts[f]}\""
		columns.push(at)
	columns

# The cell of field f in the record at byte `start` is not a value of its type: its name and the
# type's are the f-th of `names` and `types` (each ended by a quote).
fn csvBadField(s str, start i64, columns i64[], f i64, cells str[], names str, types str) str:
	name = names.split("\"")[f]
	typeName = types.split("\"")[f]
	"{csvWhere(s, start, columns[f] + 1)} (\"{name}\"): \"{cells[columns[f]]}\" is not a valid {typeName}"

# ---------- writing ----------

# the field, quoted when it holds the separator, a quote or a line break
fn csvOutField(mut out u8[], cell str, sep u8):
	plain = true
	for b in cell.bytes():
		if b == sep or b == '"' or b == '\n' or b == '\r': plain = false
	if plain:
		outStr(out, cell)
		return
	out.push('"')
	for b in cell.bytes():
		if b == '"': out.push(b)
		out.push(b)
	out.push('"')
