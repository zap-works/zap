# A Maxwell program translated into a Zap GPU file: its entry function (vertex<name>,
# pixel<name> or compute<name>) taking the module's `Params` (typesFile: the constant buffers as
# one storage buffer, a texture array a kind, shared by every program so a vertex and a pixel
# stage pair), and its vertex inputs (Attributes<name>, a Vec4 a generic attribute). The values a
# vertex stage passes on are the module's `Varyings`: the generic attributes of the `interface`,
# the same for every program built together, so any vertex stage meets any pixel stage.

# A program translated: its entry, the file, what it could not translate, and for a compute
# program its group's size.
pub type Shader:
	name str
	stage Stage
	entry str
	text str
	missing str[]
	textures TextureUse[]
	group i64[] = []
	attributes i64[] = []   # a vertex stage's generic inputs, in its Attributes' field order

# the generic attributes (as Vec4s) the programs pass on or read: vertex outputs, pixel inputs
pub fn interfaceOf(programs Program[]) i64[]:
	out i64[] = []
	for p in programs:
		h = p.header ?? continue
		for g in 0..32:
			uses = false
			for c in 0..4:
				a = generic0 + g * 4 + c
				if (h.stage == .Vertex and h.writesAttribute(a)) or
					(h.stage == .Pixel and h.readsAttribute(a)):
					uses = true
			if uses and g not in out: out.push(g)
	out.sortBy(it)
	out

# the module's file of the types every program shares: Params, with an array of each texture
# kind some program reads, and Varyings (none for an empty interface)
# the Params field of a stage's constant buffers
pub fn constantsName(s Stage) str:
	match s:
		Vertex: "vertexConstants"
		Pixel: "pixelConstants"
		_: "computeConstants"

pub fn typesFile(interface i64[], shaders Shader[]) str:
	lines = [
		"# The types Maxwell programs share, translated by recomp.switch.shaders.",
		"",
		"import engine",
		"",
		"pub type Params:",
		"\t# each stage's constant buffers: bank b's word w at b * {bankWords} + w",
		"\tvertexConstants u32[]",
		"\tpixelConstants u32[]",
		"\tcomputeConstants u32[]"
	]
	for kind in [TextureKind.Plain, TextureKind.Layered, TextureKind.Shadow]:
		if shaders.any(.textures.any(.kind == kind)):
			lines.push("\t{kind.arrayName()} engine.{kind.textureType()}[]")
	lines.push("")
	if not interface.isEmpty:
		lines.push("pub type Varyings:")
		for g in interface:
			lines.push("\tg{g} Vec4")
	lines.push("")
	lines.join("\n")

# The program as a Zap GPU file, or why its control flow could not be rebuilt.
pub fn translateProgram(t OpTable, p Program, name str, interface i64[], group i64[]) Shader ? str:
	if p.stage != .Vertex and p.stage != .Pixel and p.stage != .Compute:
		return "a {p.stage} stage: Zap has vertex, pixel and compute stages"
	code = t.decodeProgram(p.words)
	steps = stepsOf(code)
	e = Emitter(
		name = name.copy(),
		stage = p.stage,
		header = p.header.copy(),
		interface = interface.copy(),
		code
	)
	w = Writer(e, steps, result = "")
	w.result = w.e.resultOf()
	w.region(0, w.e.code.len, -1)
	if w.failure != "": return w.failure.copy()
	text = w.e.fileOf(w.result)
	entry = match p.stage:
		Vertex: "vertex"
		Pixel: "pixel"
		_: "compute"
	Shader(
		name = name.copy(),
		stage = p.stage,
		entry = "{entry}{name}",
		text,
		missing = w.e.missing.copy(),
		textures = w.e.textures.copy(),
		group = group.copy(),
		attributes = w.e.inputs.filter(it < 32) if p.stage == .Vertex else []
	)

# what EXIT returns: the position and the values passed on, the pixel's colors, nothing
fn resultOf(mut e Emitter):
	match e.stage:
		Vertex:
			position = "Vec4(o28, o29, o30, o31)"
			if e.interface.isEmpty: return "return {position}"
			fields = e.interface.map(
				"g{it} = Vec4(o{32 + it * 4}, o{33 + it * 4}, o{34 + it * 4}, o{35 + it * 4})"
			)
			"return ({position}, Varyings({fields.join(", ")}))"
		Pixel: "return {e.pixelResult()}".trimmedEnd().copy()
		_: "return"

# the colors from the registers: each written target's written components in turn from r0
fn pixelResult(mut e Emitter):
	h = e.header ?? return ""
	colors = []
	r = 0
	for target in 0..8:
		parts = []
		for c in 0..4:
			if h.writesTarget(target, c):
				parts.push(e.f(r))
				r += 1
			else:
				parts.push("0.0")
		if parts.any(it != "0.0"):
			e.targets.push(target)
			colors.push("Vec4({parts.join(", ")})")
	if h.writesDepth() or h.writesSampleMask():
		e.missing.push(
			"a pixel stage's depth or sample mask output (Zap's pixel stage returns colors only)"
		)
	for k, target in e.targets:
		if target != k: e.missing.push("render target {target} written without those before it (Zap numbers targets by their order)")
	if colors.isEmpty: return ""
	if e.targets == [0]: return colors[0].copy()
	fields = []
	for k, target in e.targets:
		fields.push("c{target} = {colors[k]}")
	"Targets{e.name}({fields.join(", ")})"

# the whole file: imports, parameter and input types, the entry
fn fileOf(mut e Emitter, result str):
	body = e.body()
	out = ["# Maxwell program {e.name} ({e.stage}), translated by recomp.switch.shaders.", ""]
	out.push("import recomp.switch.shaders.maxwell")
	out.push("")
	if e.stage == .Compute and e.sharedWords > 0:
		out.push("mut shared{e.name} u32[{e.sharedWords}]")
		out.push("")
	out.extend(e.entryLines())
	out.extend(e.prologue())
	out.extend(body)
	endsReturning = false
	if e.lines.last is l: endsReturning = l.depth == 1 and l.text.startsWith("return")
	if result != "return" and not endsReturning: out.push("	{result["return ".len..]}")
	out.push("")
	out.join("\n")

# the entry's signature (and the types it alone needs)
fn entryLines(mut e Emitter):
	out = []
	match e.stage:
		Vertex:
			generic = e.inputs.filter(it < 32)
			if not generic.isEmpty:
				out.push("pub type Attributes{e.name}:")
				for g in generic:
					out.push("\tg{g} Vec4")
				out.push("")
			first = ["v Attributes{e.name}"] if not generic.isEmpty
				else ["id i32"] if vertexId in e.inputs
				else []
			if instanceId in e.inputs: first.push("instance i32")
			if vertexId in e.inputs and not generic.isEmpty: e.missing.push("the vertex's number beside its attributes (Zap's vertex stage takes one or the other)")
			returns = "Vec4" if e.interface.isEmpty else "(Vec4, Varyings)"
			out.push("pub fn vertex{e.name}({first.join(", ")}{", " if not first.isEmpty else ""}p Params) {returns}:")
		Pixel:
			kind = "" if e.targets.isEmpty else " Vec4" if e.targets == [0] else " Targets{e.name}"
			if kind == " Targets{e.name}":
				out.push("pub type Targets{e.name}:")
				for target in e.targets:
					out.push("\tc{target} Vec4")
				out.push("")
			first = ["b Varyings"] if not e.interface.isEmpty else []
			out.push("pub fn pixel{e.name}({first.join(", ")}{", " if not first.isEmpty else ""}p Params){kind}:")
		_:
			out.push("pub fn compute{e.name}(p Params):")
	out

# the locals the body reads besides the registers: the outputs, local memory
fn prologue(e Emitter):
	out = []
	if e.stage == .Vertex:
		for a in 28..32:
			out.push("\to{a} = 0.0")
		for g in e.interface:
			for c in 0..4:
				out.push("\to{32 + g * 4 + c} = 0.0")
	if e.stage == .Vertex and vertexId in e.inputs and e.inputs.any(it < 32):
		out.push("\tid i32 = 0")
	words = e.localWords
	if e.header is h: words = words.max(h.localMemory / 4)
	if words > 0: out.push("\tlocal u32[{words}]")
	out
