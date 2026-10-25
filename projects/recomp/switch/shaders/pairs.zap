# The CPU side of translated programs: which of a run's recorded program sets (a line of
# pairs.txt: the hash stems of the stages' <name>.bin files, vertex first) translated, as the
# `programs` module <dir>/programs/programs.zap for a renderer to build them and fill their
# texture arrays.

pub programsModule = "programs"

# the sets (lines) whose stages all translated, as the names the translation gave and the set
pub type TranslatedSet:
	key str
	names str[]

# The sets of `lines` that are a vertex and a pixel stage, both translated; a stem names its
# program "P<stem>" (readSource).
pub fn translatedSets(lines str[], shaders Shader[]) TranslatedSet[]:
	out = []
	for line in lines:
		names = line.split(" ").filter(not .isEmpty).map("P{it}")
		if names.len != 2: continue
		stages = []
		for name in names:
			if shaders.find(.name == name) is shader: stages.push(shader.stage)
		if stages != [.Vertex, .Pixel]: continue
		out.push(TranslatedSet(key = line.copy(), names))
	out

# the image slots (base included) the programs read, each once, in order
pub fn imageSlots(shaders Shader[]) i64[]:
	out i64[] = []
	for s in shaders:
		for t in s.textures:
			slot = s.stage.textureBase() + t.slot
			if t.kind == .Image and slot not in out: out.push(slot)
	out.sortBy(it)
	out

fn quoted(text str):
	"\"{text}\""

fn entryOf(shaders Shader[], name str):
	for s in shaders:
		if s.name == name: return "{module}.{s.entry}"
	""

# The module: programCode(key) is the `shader` text of a set, programTextures(name) the textures
# of a program (its name as the translated module has it, "P<stem>") as TextureUses whose slot is
# the index in its Params array, programAttributes(name) a vertex program's generic attributes in
# the order of its Attributes' fields (each a Vec4), and setProgramParams the Params a renderer
# cannot name, made from what it filled.
pub fn programsFile(shaders Shader[], sets TranslatedSet[]) str:
	lines = [
		"# The programs of a run's recorded sets, built by recomp.switch.shaders.",
		"",
		"import engine",
		"import recomp.switch.render",
		"import recomp.switch.shaders",
		"import {module}",
		"",
		"# the program set recorded as the line `key` (stage names, vertex first), none if untranslated",
		"pub fn programCode(key str) str?:"
	]
	for s in sets:
		codes = s.names.map(entryOf(shaders, it))
		lines.push("\tif key == {quoted(s.key)}: return shader({codes.join(", ")})")
	lines.push("\tnone")
	lines.push("")
	lines.push("pub fn programTextures(name str) shaders.TextureUse[]:")
	for s in shaders:
		if s.textures.isEmpty: continue
		slots = s.textures.map("shaders.TextureUse(handle = {.handle}, kind = .{.kind}, slot = {s.stage.textureBase() + .slot}, bank = {.bank})")
		lines.push("\tif name == {quoted(s.name)}: return [{slots.join(", ")}]")
	lines.push("\t[]")
	lines.push("")
	lines.push("pub fn programAttributes(name str) i64[]:")
	for s in shaders:
		if s.attributes.isEmpty: continue
		lines.push("\tif name == {quoted(s.name)}: return [{s.attributes.map("{it}").join(", ")}]")
	lines.push("\t[]")
	lines.push("")
	lines.extend(paramsLines(shaders))
	lines.join("\n")

# setProgramParams: the arrays of the kinds no program reads are left out of Params
fn paramsLines(shaders Shader[]):
	fields = ["vertexConstants", "pixelConstants"].map("{it} = {it}.copy()")
	fields.push("computeConstants = [u32(0)]")
	for kind in textureKinds:
		if kind != .Image and shaders.any(.textures.any(.kind == kind)):
			fields.push("{kind.arrayName()} = set.{kind.arrayName()}.copy()")
	for slot in shaders.imageSlots():
		fields.push("{imageField(slot)} = set.images[{slot}] if set.images.len > {slot} else engine.UintImage(id = -1, width = 0, height = 0)")
	[
		"pub fn setProgramParams(",
		"\tp engine.Program,",
		"\tvertexConstants u32[],",
		"\tpixelConstants u32[],",
		"\tset render.TextureSet",
		"):",
		"\tp.setParams({module}.Params({fields.join(", ")}))",
		""
	]
