# JSON's indentation: what `v.toJson(2)` and `Doc.text(indent)` call (runtimeDirs.zap loads this dir
# for a program that writes JSON).

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
