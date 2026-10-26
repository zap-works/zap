# The program text of the statements over temporaries.

fn emitTemps(st St, pad str, mut out str[]):
	k = st.kind
	a = sv(st.a)
	b = sv(st.b)
	c = sv(st.c)
	n = out.len   # names the statement's own variables
	q = "\""
	lit = "{q}{st.lit}{q}"
	big = st.lit.len   # a length the strings are compared with
	lb = lv(st.b % nList)
	if k <= 36:
		st.emitTempsChoice(pad, a, out)
	elif k <= 38:
		st.emitTempsMatch(pad, a, b, c, lit, out)
	elif k <= 41:
		st.emitTempsLeave(pad, a, b, c, n, big, lb, lit, out)
	else:
		st.emitTempsLoops(pad, a, b, c, n, big, lb, out)

fn emitTempsChoice(st St, pad str, a str, mut out str[]):
	k = st.kind
	if k == 35:
		choice = "({operand(st.x, st.b, st.lit)} if {a}.len % 2 == 0 else {operand(st.y, st.c, st.lit)})"
		out.push("{pad}{a} = {consume(st.z, choice)}")
	elif k == 36:
		out.push(
			"{pad}{a} = {consume(st.z, "{optional(st.x, st.b)} ?? {operand(st.y, st.c, st.lit)}")}"
		)

fn emitTempsMatch(st St, pad str, a str, b str, c str, lit str, mut out str[]):
	k = st.kind
	if k == 37:
		# match over a temporary enum, the arms binding its parts
		head = "{pad}match shape({b}):" if st.x == 2
			else "{pad}{a} = cut(match shape({b}):" if st.x == 3
			else "{pad}{a} = match shape({b}):"
		out.push(head)
		if st.x == 0:
			out.push("{pad}\tPair(p, q): cut(p + q)")
			out.push("{pad}\tWord(w): w.copy()")
			out.push("{pad}\tEmpty: {lit}")
		elif st.x == 1:
			out.push("{pad}\tPair(p, _): \"<\{p}>\"")
			out.push("{pad}\tWord(w): cut(w + {c})")
			out.push("{pad}\tEmpty: {c}.copy()")
		elif st.x == 2:
			out.push("{pad}\tPair(p, q):")
			out.push("{pad}\t\t{a} = p.copy()")
			out.push("{pad}\t\t{c} = q.copy()")
			out.push("{pad}\tWord(w): {a} = w.copy()")
			out.push("{pad}\tEmpty: pass")
		else:
			out.push("{pad}\tPair(p, _): p")
			out.push("{pad}\tWord(w): w")
			out.push("{pad}\tEmpty: {lit}")
		if st.x == 3:
			out.push("{pad})")
	elif k == 38:
		# match and is over a temporary optional
		if st.x == 2:
			out.push("{pad}if opt({b}) is v:")
			out.push("{pad}\t{a} = v")
			out.push("{pad}else:")
			out.push("{pad}\t{a} = {lit}")
		elif st.x == 3:
			out.push("{pad}if make({b}).items.last is v:")
			out.push("{pad}\t{a} = v.copy()")
		else:
			scr = "opt({b})" if st.x == 0 else "make({b}).items.first"
			out.push("{pad}{a} = cut(match {scr}:" if st.x == 4 else "{pad}{a} = match {scr}:")
			out.push(
				[
					"{pad}\tv: cut(v + {c})",
					"{pad}\tv: v.copy()",
					"",
					"",
					"{pad}\tv: v"
				][st.x]
			)
			out.push("{pad}\tnone: {lit}")
			if st.x == 4:
				out.push("{pad})")

fn emitTempsLeave(
	st St,
	pad str,
	a str,
	b str,
	c str,
	n i64,
	big i64,
	lb str,
	lit str,
	mut out str[]
):
	k = st.kind
	if k == 39:
		# a binding that borrows from a temporary, the temporary kept while it is used
		bind = [
			"\" \{({b})} \".trimmed()",
			"make({b}).name",
			"make({b}).items.first ?? {lit}",
			"{b}.replace(\"a\", \"b\").trimmed()",
			"make(\"\{({b})}yy\").items[0]", "\"\{{b}}\{{c}}....\"[0..4]"][st.x]
		out.push("{pad}h{n} = {bind}")
		pushLeave(pad, "h{n}.len > {big}", st.z, out)
		out.push("{pad}{a} = cut(h{n} + {c})")
	elif k == 40:
		# ?? continue, ?? break
		if st.x == 3:
			out.push("{pad}h{n} = make({b}).items.first ?? {leave(st.z)}")
			out.push("{pad}{a} = h{n}.copy()")
		elif st.x == 4:
			out.push("{pad}{a} = ({lb}.last ?? {leave(st.z)}).copy()")
		else:
			arg = [b.copy(), "\"\{{b}}\"", "{b}.upper()"][st.x]
			out.push("{pad}{a} = opt({arg}) ?? {leave(st.z)}")
	elif k == 41:
		# break and continue out of a match or an is over a temporary (or a place)
		scr = ["shape({b})", "opt({b})", "make({b}).items.first", "o", "{lb}.first"][st.x]
		part = "p" if st.x == 0 else "v"
		some = "Pair(p, _)" if st.x == 0 else "v"
		arm = pad.copy() if st.y == 1 else "{pad}\t"   # where the block of the value's arm starts
		out.push("{pad}if {scr} is {some}:" if st.y == 1 else "{pad}match {scr}:")
		if st.y == 0:
			out.push("{arm}{some}:")
		out.push("{arm}\t{a} = {part}.copy()")
		if st.z % 3 > 0:
			out.push("{arm}\t{leave(st.z % 3)}")
		if st.y == 0:
			if st.x == 0:
				out.push("{arm}Word(w): {a} = w.copy()")
			out.push("{arm}{"Empty" if st.x == 0 else "none"}: {leave(1 + st.z / 3)}")

fn emitTempsLoops(st St, pad str, a str, b str, c str, n i64, big i64, lb str, mut out str[]):
	k = st.kind
	if k == 42:
		# for over a temporary list, leaving early
		list = [
			"names({b})",
			"make({b}).items",
			"{lb}.filter(y: y.len > 1)",
			"{lb}.map(y: cut(\"\{y}m\"))",
			"\"\{{b}}-\{{c}}\".split(\"-\")"][st.x]
		out.push("{pad}for e{n} in {list}:")
		out.push("{pad}\tif e{n}.len > {big}:")
		out.push("{pad}\t\t{a} = e{n}.copy()")
		if st.z > 0:
			out.push("{pad}\t\t{leave(st.z)}")
		out.push("{pad}\t{c} = cut({c} + e{n})")
	elif k == 43:
		# while x is v, ending by its condition or leaving early
		if st.x == 2:
			out.push("{pad}g{n} = 0")
			out.push("{pad}while make({b}).items.first is v and g{n} < {big}:")
			out.push("{pad}\tg{n} += 1")
			out.push("{pad}\t{c} = cut({c} + v)")
			pushLeave("{pad}\t", "g{n} > 1", st.z, out)
		elif st.x == 1:
			out.push("{pad}q{n} = names({b})")
			out.push("{pad}while q{n}.pop() is v and v.len > {big}:")
			out.push("{pad}\t{c} = cut({c} + v)")
			pushLeave("{pad}\t", "{c}.len > 6", st.z, out)
		else:
			out.push("{pad}q{n} = {lb}.copy()")
			out.push("{pad}while q{n}.pop() is v:")
			out.push("{pad}\tif v.len > {big}:")
			out.push("{pad}\t\t{a} = v.copy()")
			if st.z > 0:
				out.push("{pad}\t\t{leave(st.z)}")
			out.push("{pad}\t{c} = cut({c} + v)")
	elif k == 44:
		# one generic for several types in the program
		if st.y == 5:
			out.push("{pad}h{n} (ref str)[] = [{b}, {c}]")
		target = lv(st.a % nList) if st.y == 2 else a
		out.push("{pad}{target} = {st.genericCall("h{n}")}")
