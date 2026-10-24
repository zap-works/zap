# CSV (RFC 4180) and JSON's indentation: the pieces `Row[].fromCsv`, `rows.toCsv()`, `v.toJson(indent)`
# and std/csv call. A record is read at a cursor (as JSON's values are, value.zap); an error says
# the line and the column it is at.

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
			if not closed: return "{csvWhere(s, start, cells.len + 1)}: a quoted field is never closed"
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

# a typed read's header lacks the column of a field
fn csvNoColumn(name str) str:
	"CSV line 1: no column \"{name}\""

# a cell of the record at byte `start` is not a value of its field's type
fn csvBadCell(s str, start i64, column i64, name str, cell str, typeName str) str:
	"{csvWhere(s, start, column)} (\"{name}\"): \"{cell}\" is not a valid {typeName}"

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

# ---------- JSON, indented ----------

# Compact JSON text spread out, one value a line, `indent` spaces a level and a space after each
# key's colon (Python's `json.dumps(v, indent=2)`); an empty container stays `[]` or `{}`.
fn jsonIndented(compact str, indent i64) str:
	if indent <= 0: return compact.copy()
	out u8[] = []
	depth = 0
	quoted = false
	k = 0
	while k < compact.len:
		b = compact[k]
		if quoted:
			out.push(b)
			if b == 92:
				k += 1
				out.push(compact[k])
			elif b == '"':
				quoted = false
		elif b == '"':
			out.push(b)
			quoted = true
		elif b == '{' or b == '[':
			out.push(b)
			if k + 1 < compact.len and (compact[k + 1] == '}' or compact[k + 1] == ']'):
				k += 1
				out.push(compact[k])
			else:
				depth += 1
				jsonLineBreak(out, indent, depth)
		elif b == '}' or b == ']':
			depth -= 1
			jsonLineBreak(out, indent, depth)
			out.push(b)
		elif b == ',':
			out.push(b)
			jsonLineBreak(out, indent, depth)
		elif b == ':':
			outStr(out, ": ")
		else:
			out.push(b)
		k += 1
	str(move out)

fn jsonLineBreak(mut out u8[], indent i64, depth i64):
	out.push('\n')
	outStr(out, " ".repeat(indent * depth))
