# The derived integer forms of an enum whose variants have values (`Add = 1`, derive.zap).

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

# $valueN(v) i64: the variant's integer
fn writeValue(mut c Checker, i i64, mut src str[]):
	src.push("fn $value{i}(v {tyName(i)}) i64:")
	src.push("\tmatch v:")
	for vn in nodes[declOf(tys, c.deriveTypes[i])].kids(kidIds):
		src.push("\t\t{nodes[vn].text}: {nodes[vn].value(kidIds) ?? 0}")

# $fromvalueN(n) $TyN?: the variant whose integer is n, else none
fn writeFromValue(mut c Checker, i i64, mut src str[]):
	src.push("fn $fromvalue{i}(n i64) {tyName(i)}?:")
	src.push("\tmatch n:")
	for vn in nodes[declOf(tys, c.deriveTypes[i])].kids(kidIds):
		src.push("\t\t{nodes[vn].value(kidIds) ?? 0}: .{nodes[vn].text}")
	src.push("\t\t_: none")
