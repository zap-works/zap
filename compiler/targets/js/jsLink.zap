# The JS target's module put together (jsModule.zap): the functions and module variables its
# roots reach, in the order written. A test that reaches what the target does not write is left
# out, its function saying why when the tests run (as a test of another system's is skipped); a
# build that reaches such a thing elsewhere fails, each thing said.

alias nodes = g.c.nodes

fn jsLinked(mut g Gen, mut js Js, roots str[]) str?:
	memo {str: str} = {}
	reached {str: bool} = {}
	cut {str: str} = {}
	stack = roots.copy()
	while stack.pop() is n:
		if n in reached: continue
		reached[n.copy()] = true
		if js.tests.get(n) is at:
			open {str: bool} = {}
			why = js.jsRefusalIn(n, memo, open)
			if why != "":
				cut[n.copy()] = "skipped {at}: {why}"
				continue
		for c in js.calls.get(n) ?? []:
			if c not in reached: stack.push(c.copy())
	said = false
	for n in reached.keys().sorted():
		if n not in cut and js.refusals.get(n) is all:
			for line in all:
				eprint(line)
			said = true
	if said: return none
	g.jsAssembled(js, reached, cut)

# the first thing the function `name`, or one it reaches, holds that the target does not write;
# "" for none
fn jsRefusalIn(js Js, name str, mut memo {str: str}, mut open {str: bool}) str:
	if memo.get(name) is known: return known.copy()
	if name in open: return ""
	open[name.copy()] = true
	why = ""
	if js.refusals.get(name) is all and not all.isEmpty:
		why = all[0].copy()
	else:
		for c in js.calls.get(name) ?? []:
			found = js.jsRefusalIn(c, memo, open)
			if found != "":
				why = found
				break
	memo[name.copy()] = why.copy()
	why

# the reached module variables declared, the reached functions (a cut test's saying why it is
# skipped), then $init giving the variables their values in the order their values read them
fn jsAssembled(mut g Gen, js Js, reached {str: bool}, cut {str: str}) str:
	out str[] = []
	globals = js.globals.filter("$value:{nodes[it].text}" in reached)
	out.push(globals.map("let {jsSafe(nodes[it].text)};").join("\n"))
	for n in js.order:
		if n.startsWith("$value:") or n not in reached: continue
		if cut.get(n) is why:
			out.push("function {n}() \{\n\trt$skip({jsQuote(why)});\n\}\n")
		else:
			out.push((js.texts.get(n) ?? "").copy())
	ordered, _ = g.c.initOrder(globals.copy())
	inits str[] = []
	for d in ordered:
		if js.texts.get("$value:{nodes[d].text}") is text and text != "": inits.push(text.copy())
	out.push("function $init() \{\n{inits.join("\n")}\n\}\n")
	out.join("\n")
