# The one decoder of the tables: a row is an instruction's bits (`0` and `1` fixed, a letter a
# field's bit, `-` any) and the assembly it is, its fields written in `<...>`. The first row whose
# fixed bits match is the instruction: its template, the fields put in, is read by `assemble`.
#
# In a template, `<f>` is field f's value; letters side by side join their fields, the first
# letter's bits highest (`<hl:target2>`). After the letters: `*k` the value times k, `?a|b` a if
# the value is not 0 else b (`?a` alone: nothing for 0), `@a,b,c` the value's word of the list,
# and `:name` one of templateWord's.

pub type Field:
	letter u8
	bits i64[]   # the field's bit positions, its highest first

pub type Row:
	mask u32
	value u32
	wide bool   # 32 bits (all of ARM, Thumb's pair of a bl)
	fields Field[]
	template str

	# the field's value in the word, and its width
	fn fieldValue(letter u8, word u32):
		f = fields[fieldIndex(fields, letter) ?? fail("no field {str([letter])} in {template}")]
		v u32 = 0
		for pos in f.bits:
			v = (v << 1) | ((word >> pos) & 1)
		(v, f.bits.len)

	# the template with the word's fields put in
	pub fn expand(word u32, at i64, thumb bool) str:
		out = ""
		t = template
		i = 0
		while i < t.len:
			if t[i] != '<':
				start = i
				while i < t.len and t[i] != '<':
					i += 1
				out += t[start..i]
				continue
			close = i + (t[i..].indexOf(">") ?? fail("no > in {t}"))
			out += self.spec(t[i + 1..close], word, at, thumb)
			i = close + 1
		out

	fn spec(s str, word u32, at i64, thumb bool):
		k = 0
		v = 0
		width = 0
		while k < s.len and isLetter(s[k]):
			part, w = self.fieldValue(s[k], word)
			v = (v << w) | part
			width += w
			k += 1
		if k == s.len: return "{v}"
		rest = s[k + 1..]
		match s[k]:
			'*': "{v * (i64.parse(rest) ?? fail("bad scale in {s}"))}"
			'?':
				choices = rest.split("|")
				if v != 0: return str(choices[0])
				str(choices[1]) if choices.len > 1 else ""
			'@': str(rest.split(",")[v])
			':': templateWord(rest, v, width, at, thumb)
			_: fail("bad template part <{s}>")

# the rows of a table's text: a line each, its bits, ` = `, its template
pub fn rowsOf(table str) Row[]:
	rows = []
	for line in table.lines():
		if line.indexOf(" = ") is at:
			rows.push(row(line[..at], line[at + 3..]))
	rows

# a row from its bits and its template
pub fn row(bits str, template str) Row:
	pattern = bits.replace(" ", "")
	width = pattern.len
	mask = 0
	value = 0
	fields = []
	for i, ch in pattern.bytes():
		pos = width - 1 - i
		if ch == '0' or ch == '1':
			mask |= u32(1) << pos
			if ch == '1': value |= u32(1) << pos
		elif ch != '-':
			match fieldIndex(fields, ch):
				k: fields[k].bits.push(pos)
				none: fields.push(Field(letter = ch, bits = [pos]))
	if width != 16 and width != 32: fail("a row of {width} bits: {bits}")
	Row(mask, value, wide = width == 32, fields, template = template.copy())

fn fieldIndex(fields Field[], letter u8) i64?:
	for i, f in fields:
		if f.letter == letter: return i
	none

# the value sign-extended from its width
pub fn signed(v u32, width i64) i64:
	shift = 64 - width
	i64(u64(v) << shift) >> shift

# the text of a named word of a template: a value of `width` bits for the instruction at `at`
fn templateWord(name str, v u32, width i64, at i64, thumb bool):
	match name:
		"cond": condNames[v]
		"list": listText(v)
		"list14": listText((v & 0xFF) | (i64(v >> 8) << 14))
		"list15": listText((v & 0xFF) | (i64(v >> 8) << 15))
		"n32": "{32 if v == 0 else v}"
		"shift": shiftText(v >> 5, v & 31)
		"regshift": ", {shiftNames[v >> 4]} {regName((v & 15))}"
		"rotimm": rotatedText(v >> 8, v & 0xFF)
		"target2": "0x{at + (4 if thumb else 8) + signed(v, width) * 2:08X}"
		"target4": "0x{at + (4 if thumb else 8) + signed(v, width) * 4:08X}"
		"hex": "0x{v:X}"
		"psrmask": psrMaskText(v)
		_: fail("no template word {name}")

# ", lsr #3"; an amount of 0 is none for lsl, 32 for lsr and asr, rrx for ror
fn shiftText(kind i64, amount i64):
	if amount == 0:
		match kind:
			0: return ""
			3: return ", rrx"
			_: return ", {shiftNames[kind]} #32"
	", {shiftNames[kind]} #{amount}"

# an 8-bit immediate turned right by twice the rotation: the value, or the pair when the
# rotation is not the one the value implies
fn rotatedText(rotation i64, imm u32):
	rot = rotation * 2
	v = imm.rotateRight(rot)
	if (rot == 0) == (v <= 255): return "#{v}"
	"#{imm}, {rot}"

fn isLetter(c u8):
	(c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z')
