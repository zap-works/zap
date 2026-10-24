# A replacement read as Python's `re.sub` reads it: text with groups written into it. `\1` to `\99`
# and `\g<1>`, `\g<name>` stand for a group (`\g<0>` for the whole match), `\\` for a backslash and
# `\n`, `\t` and `\r` for those bytes; a backslash before any other punctuation is kept as written.

# the replacement as text between group references: `literals` holds one more than `refs`
type Template:
	literals str[]
	refs i64[]

# the group a `\g<label>` names, -1 when the pattern has none
fn groupOfLabel(label str, groups i64, names str[]) i64:
	if label.isEmpty: return -1
	if label.bytes().all(it >= '0' and it <= '9'):
		number = i64.parse(label) ?? -1
		return number if number <= groups else -1
	if names.indexOf(label) is k: return k + 1
	-1

# the template of the replacement `by` for a pattern with that many groups and those names, or
# why it is not one
fn readTemplate(by str, groups i64, names str[]) Template ? str:
	src = by.bytes()
	template = Template(literals = [], refs = [])
	literal u8[] = []
	i = 0
	while i < src.len:
		c = src[i]
		i += 1
		if c != '\\':
			literal.push(c)
			continue
		if i >= src.len: return "regex: a replacement ends in a backslash"
		d = src[i]
		i += 1
		group = -1
		if d == '\\':
			literal.push('\\')
		elif d == 'n':
			literal.push(10)
		elif d == 't':
			literal.push(9)
		elif d == 'r':
			literal.push(13)
		elif d >= '1' and d <= '9':
			group = d - '0'
			if i < src.len and src[i].isDigit():
				group = group * 10 + src[i] - '0'
				i += 1
			if group > groups: return "regex: the replacement uses group {group} of a pattern with {groups}"
		elif d == 'g':
			close = i
			while close < src.len and src[close] != '>':
				close += 1
			if i >= src.len or src[i] != '<' or close >= src.len:
				return "regex: a replacement's \\g needs a group between < and >"
			label = src[i + 1..close].text()
			group = groupOfLabel(label, groups, names)
			if group < 0: return "regex: the replacement uses the group {label}, which the pattern lacks"
			i = close + 1
		elif d.isAlpha() or d.isDigit():
			return "regex: the escape \\{[d].text()} is unsupported in a replacement"
		else:
			literal.push('\\')
			literal.push(d)
		if group >= 0:
			template.literals.push(literal.text().copy())
			literal.clear()
			template.refs.push(group)
	template.literals.push(literal.text().copy())
	template
