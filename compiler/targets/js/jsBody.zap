# The JS target's body being written (jsModule.zap): its lines, its scopes and the names they bind,
# the temporaries; and what it refuses to write.

alias nodes = g.c.nodes

# a form this target does not write, noted for the function being written: a build that reaches
# it fails naming it and where it is (a test that reaches it is skipped)
fn jsRefuse(mut js Js, g Gen, e NodeId, what str):
	within = "the value of {js.b.name[7..]}" if js.b.name.startsWith("$value:") else js.b.name.copy()
	said = "{js.b.file}:{nodes[e].line}: the JS target does not write {what} (in {within})"
	if js.refusals.get(js.b.name) is known:
		known.push(said)
	else:
		js.refusals[js.b.name.copy()] = [said]

# the function being written names the function or module variable `name`
fn jsCalled(mut js Js, name str):
	if js.calls.get(js.b.name) is known:
		known.push(name.copy())
	else:
		js.calls[js.b.name.copy()] = [name.copy()]

# the JS of the function or module variable's value `name`, written
fn jsWritten(mut js Js, name str, text str):
	js.texts[name.copy()] = text.copy()
	js.order.push(name.copy())

# ---------- the body being written ----------

fn jsLine(mut js Js, text str):
	js.b.lines.push("{"\t".repeat(js.b.depth)}{text}")

fn jsOpen(mut js Js, text str):
	js.jsLine("{text} \{")
	js.b.depth += 1
	js.b.scopes.push(JsScope())

fn jsClose(mut js Js, text str = "}"):
	js.b.depth -= 1
	js.b.scopes.truncate(js.b.scopes.len - 1)
	js.jsLine(text)

# a fresh name for a value the code keeps a moment
fn jsTemp(mut js Js):
	js.b.temps += 1
	"$t{js.b.temps}"

# the JS text a Zap name reads, innermost scope first
fn jsLookup(js Js, name str) str?:
	i = js.b.scopes.len - 1
	while i >= 0:
		if js.b.scopes[i].names.get(name) is v: return v.copy()
		i -= 1
	none

fn jsBind(mut js Js, name str, text str):
	js.b.scopes[js.b.scopes.len - 1].names[name.copy()] = text.copy()

# a new JS name for the Zap name in the innermost scope: the name itself, or numbered when the
# function already declares it (JS refuses a second `let` in a block, and a shadowed name is
# another variable) or a function of the module has it
fn jsDeclare(mut js Js, g Gen, name str):
	out = js.jsFresh(g, name)
	js.jsBind(name, out)
	out

# a JS name for the Zap name no other variable of the function has, not bound yet
fn jsFresh(mut js Js, g Gen, name str):
	base = jsSafe(name)
	out = base.copy()
	n = 1
	while out in js.b.declared or g.c.findFunc(out) != none:
		n += 1
		out = "{base}${n}"
	js.b.declared[out.copy()] = true
	out
