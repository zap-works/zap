# Where each name stands in a list of declarations that grows and shrinks at its end (the scopes
# of a function: the checker's variables, the lowering's names, the ownership pass's): a name's
# positions in order, kept with the list (noted as one is pushed, forgotten as it is truncated),
# so the innermost declaration of a name is found at once, not by a walk over every name.
type NameIndex:
	at {str: i64[]} = {}

	# the name declared at pos, the list's new end
	fn noteName(name str, pos i64):
		if at.get(name) is mut positions:
			positions.push(pos)
		else:
			at[name.copy()] = [pos]

	# the last declaration of name gone (the list truncated past it)
	fn forgetName(name str):
		if at.get(name) is mut positions:
			positions.pop()

	# the first position of name from start on, -1 for none
	fn firstFrom(name str, start i64):
		positions = at.get(name) ?? return -1
		first = -1
		k = positions.len - 1
		while k >= 0 and positions[k] >= start:
			first = positions[k]
			k -= 1
		first

	# the last position of name, -1 for none
	fn lastOf(name str):
		(at.get(name) ?? return -1).last ?? -1
