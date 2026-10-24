# CSV (RFC 4180), read and written: `import csv`.
#
# A CSV whose columns the program knows is read into its own type, checked once, the header's
# names matched to the type's fields: `rows = Row[].fromCsv(text) ?? fail` (a `str` field is the
# cell, an optional one is none for an empty cell, any other the cell as the JSON of its type:
# `12`, `2.5`, `true`), and written back by `rows.toCsv()`. Both take a separator, `'\t'` for a TSV
# (`Row[].fromCsv(text, '\t')`, `rows.toCsv(sep = '\t')`). This module is for a CSV whose shape the
# program does not know: `csv.parse(text)` is a `Csv` of text cells and the header's names.
# Quotes follow RFC 4180: a field with the separator, a quote or a line break is quoted, a quote in
# one doubled. Empty lines are skipped, a line ends at `\n` or `\r\n`, and an error says the line
# and the column.

# a CSV read whole: the names of its columns and each record's cells, as many as the header's
pub type Csv:
	header str[]
	rows str[,]

	# the index of the column named name, in the header and in each row
	fn col(name str) n64?:
		header.indexOf(name)

	# the table as CSV text (Python's `csv.writer`), a line to each record, the header first
	fn text(sep u8 = ',') str:
		out u8[] = []
		writeRecord(out, header, sep)
		for row in rows:
			writeRecord(out, row, sep)
		str(move out)

# The text read as a table, or the line and column that cannot be read: a quote never closed, text
# after a closing quote, a record with more or fewer cells than the header (`csv.DictReader`).
pub fn parse(text str, sep u8 = ',') Csv ? str:
	cur = Cursor(at = 0)
	header = try rt.csvHeader(text, cur, sep)
	rows str[,] = []
	while rt.csvMore(text, cur):
		rows.push(try rt.csvRecord(text, cur, sep, header.len))
	Csv(header, rows)

# the cells as CSV text, a line each, quoted where they need it
pub fn text(rows str[,], sep u8 = ',') str:
	out u8[] = []
	for row in rows:
		writeRecord(out, row, sep)
	str(move out)

fn writeRecord(mut out u8[], cells str[], sep u8):
	for k, cell in cells:
		if k > 0: out.push(sep)
		rt.csvOutField(out, cell, sep)
	out.push('\n')
