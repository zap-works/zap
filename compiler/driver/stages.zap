# The stages a program is checked in (spec 14.2): each dir of the runtime it loads (core first,
# then each after the dirs it reads), each std module after those it imports, then the program's
# own modules, each stage checked alone after those before it, so its types and declarations are
# numbered as they would be whatever comes after it.

# the declarations and modules loaded after the stages already checked put in their stages: those
# of the runtime's dirs in the order the loader put them, the std modules' in their modules' order
# (each after those it imports), then the rest, the program's
fn orderStages(mut prog Program):
	declsAt = 0
	modulesAt = 0
	if prog.stages.last is s:
		declsAt = s.decls
		modulesAt = s.modules
	modules = prog.modules[modulesAt..].copy()
	decls = prog.decls[declsAt..].copy()
	prog.modules.truncate(modulesAt)
	prog.decls.truncate(declsAt)
	of = decls.map(stageOf(prog.nodes, modules, it))
	names str[] = []
	for name in of:
		if name.startsWith("rt/") and name not in names: names.push(name.copy())
	for m in modules:
		if m.isStdStage(): names.push(m.id.copy())
	names.push("")
	for name in names:
		for m in modules:
			if m.moduleStage(name, names): prog.modules.push(m.copy())
		for i, d in decls:
			if of[i] == name: prog.decls.push(d)
		prog.stages.push(CheckStage(name.copy(), prog.decls.len, prog.modules.len))

# the stage of declaration d: its runtime dir's, its std module's, else the program's ("")
fn stageOf(nodes Node[], modules Module[], d NodeId):
	id = nodes[d].mod()
	if id == "rt": return "rt/{runtimeDirOf(nodes[d].file())}"
	if modules.find(.id == id) is m and m.isStdStage(): return id.copy()
	""

# whether module m is checked in a stage of its own: a std module the program imports
fn isStdStage(m Module):
	m.std and not m.unit and m.id != "" and m.id != "derive"

# whether module m goes in the stage named name: rt with the first of the runtime's, a std
# module in its own, the others in the program's
fn moduleStage(m Module, name str, names str[]):
	if m.id == "rt": return name == names[0]
	if m.isStdStage(): return name == m.id
	name == ""
