# The functions std/tensor's `Learnable` asks, written for each struct that holds tensors (spec
# 5.4): its fields of std/tensor's Tensor, lists of them, and structs or lists of structs that hold
# them in turn, in the order the struct declares them, numbered from 0. Added to the struct's
# module as Zap source once every module is loaded, as a shader's packer is (gpu.zap):
#   pub fn tensorCount() i64                     how many tensors it holds
#   pub fn tensorAt(k i64) ref Tensor            the k-th, lent
#   pub mut fn tensorAtMut(k i64) mut ref Tensor   the k-th, lent to be changed
# so an optimizer (tensor.Adam) walks a model and its gradient (of the same struct) together. A
# module that declares tensorCount for the struct writes all three itself.

alias pnodes = prog.nodes
alias pkidIds = prog.kidIds

# how a field holds tensors: not at all, as one, as a list of them, as a struct (or a list of
# structs) that holds them
holdsNone = 0
holdsTensor = 1
holdsTensors = 2
holdsStruct = 3
holdsStructs = 4

# a struct of a module, by its module's id and its name
type HolderKey:
	module str
	name str

pub fn addLearnables(mut prog Program):
	holders HolderKey[] = []
	changed = true
	while changed:
		changed = false
		for d in prog.decls:
			if pnodes[d].kind != nStructDecl or not pnodes[d].names(pkidIds).isEmpty: continue
			key = HolderKey(
				module = pnodes[d].mod(pkidIds).copy(),
				name = pnodes[d].text2(pkidIds).copy()
			)
			if key in holders: continue
			fieldNodes = pnodes[d].kids(prog.kidIds).copy()
			if fieldNodes.any(prog.fieldHolds(key.module, it, holders) != holdsNone):
				holders.push(key)
				changed = true
	for key in holders:
		if key.module == "tensor" and key.name == "Tensor": continue
		if prog.declaresTensorCount(key): continue
		decl = prog.decls.find(
			pnodes[it].kind == nStructDecl and pnodes[it].mod(pkidIds) == key.module and
				pnodes[it].text2(pkidIds) == key.name
		) ??
			continue
		prog.adoptGenerated(
			key.module,
			methodsSource(key.name, prog.learnableSource(decl, holders)),
			"<learnable {key.name}>"
		)

# whether the module already declares tensorCount
fn declaresTensorCount(prog Program, key HolderKey):
	prog.decls.any(
		pnodes[it].kind == nFnDecl and pnodes[it].mod(pkidIds) == key.module and
			pnodes[it].text2(pkidIds) == "tensorCount"
	)

# the alias module m imports std/tensor by, "" in the module itself, none when it does not
fn tensorAlias(prog Program, m str) str?:
	if m == "tensor": return ""
	for mod in prog.modules:
		if mod.id != m: continue
		for imp in mod.imports:
			if pnodes[imp].text == "tensor": return pnodes[imp].text2(pkidIds).copy()
	none

# the module an alias names in module m ("" the module itself)
fn aliasedModule(prog Program, m str, alias str):
	if alias.isEmpty: return m.copy()
	for mod in prog.modules:
		if mod.id != m: continue
		for imp in mod.imports:
			if pnodes[imp].text2(pkidIds) == alias: return pnodes[imp].text.copy()
	""

# how field f of a struct of module m holds tensors, given the holders known so far
fn fieldHolds(prog Program, m str, f NodeId, holders HolderKey[]):
	if pnodes[f].types(pkidIds).isEmpty: return holdsNone
	te = pnodes[f].types(pkidIds)[0]
	if pnodes[te].kind != nTyName: return holdsNone
	if pnodes[te].text == "List" and pnodes[te].types(pkidIds).len == 1:
		inner = prog.typeHolds(m, pnodes[te].types(pkidIds)[0], holders)
		return holdsTensors if inner == holdsTensor
			else holdsStructs if inner == holdsStruct
			else holdsNone
	prog.typeHolds(m, te, holders)

fn typeHolds(prog Program, m str, te NodeId, holders HolderKey[]):
	if pnodes[te].kind != nTyName or not pnodes[te].types(pkidIds).isEmpty: return holdsNone
	alias = pnodes[te].text2(pkidIds).copy()
	if pnodes[te].text == "Tensor" and prog.tensorAlias(m) is ta and ta == alias: return holdsTensor
	key = HolderKey(module = prog.aliasedModule(m, alias), name = pnodes[te].text.copy())
	holdsStruct if key in holders else holdsNone

# the three methods of struct d
fn learnableSource(prog Program, d NodeId, holders HolderKey[]):
	m = pnodes[d].mod(pkidIds)
	alias = prog.tensorAlias(m) ?? "tensor"
	tensorT = "Tensor" if alias.isEmpty else "{alias}.Tensor"
	name = pnodes[d].text2(pkidIds)
	fields = []
	kinds = []
	for f in pnodes[d].kids(prog.kidIds):
		k = prog.fieldHolds(m, f, holders)
		if k != holdsNone:
			fields.push(pnodes[f].text.copy())
			kinds.push(k)
	out = ["pub fn tensorCount() i64:", "\tzapCount = 0"]
	for i, f in fields:
		k = kinds[i]
		if k == holdsTensor: out.push("\tzapCount += 1")
		elif k == holdsTensors: out.push("\tzapCount += {f}.len")
		elif k == holdsStruct: out.push("\tzapCount += {f}.tensorCount()")
		else:
			out.push("\tfor zapPart in {f}:")
			out.push("\t\tzapCount += zapPart.tensorCount()")
	out.push("\tzapCount")
	out.extend(learnableAt(name, tensorT, fields, kinds, false))
	out.extend(learnableAt(name, tensorT, fields, kinds, true))
	"{out.join("\n")}\n"

# tensorAt (or tensorAtMut): each field's tensors in turn, the index less those before
fn learnableAt(name str, tensorT str, fields str[], kinds i64[], changed bool):
	lend = "mut ref " if changed else ""
	out = [
		"pub fn tensorAt(zapK i64) ref {tensorT}:" if not changed
		else "pub mut fn tensorAtMut(zapK i64) mut ref {tensorT}:",
		"\tzapAt = zapK"
	]
	for i, f in fields:
		k = kinds[i]
		last = i == fields.len - 1
		if k == holdsTensor:
			if last:
				out.push("\tif zapAt != 0: fail(\"no such tensor in a {name}\")")
				out.push("\t{lend}{f}")
			else:
				out.push("\tif zapAt == 0: return {lend}{f}")
				out.push("\tzapAt -= 1")
		elif k == holdsTensors:
			if last:
				out.push("\t{lend}{f}[zapAt]")
			else:
				out.push("\tif zapAt < {f}.len: return {lend}{f}[zapAt]")
				out.push("\tzapAt -= {f}.len")
		elif k == holdsStruct:
			call = "{f}.tensorAt{"Mut" if changed else ""}(zapAt)"
			if last:
				out.push("\t{call}")
			else:
				out.push("\tzapN{i} = {f}.tensorCount()")
				out.push("\tif zapAt < zapN{i}: return {call}")
				out.push("\tzapAt -= zapN{i}")
		else:
			out.push("\tfor zapI{i} in 0..{f}.len:")
			out.push("\t\tzapN{i} = {f}[zapI{i}].tensorCount()")
			out.push("\t\tif zapAt < zapN{i}: return {f}[zapI{i}].tensorAt{"Mut" if changed else ""}(zapAt)")
			out.push("\t\tzapAt -= zapN{i}")
			if last:
				out.push("\tfail(\"no such tensor in a {name}\")")
				out.push("\t{f}[0].tensorAt{"Mut" if changed else ""}(zapAt)")
	out
