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

fn quoted(text str):
	"\"{text}\""

fn entryOf(shaders Shader[], name str):
	for s in shaders:
		if s.name == name: return "{module}.{s.entry}"
	""

# The module: programCode(key) is the `shader` text of a set, programTextures(name) the textures
# of a program (its name as the translated module has it, "P<stem>") by handle, kind and the
# index in its Params array.
pub fn programsFile(shaders Shader[], sets TranslatedSet[]) str:
	lines = [
		"# The programs of a run's recorded sets, built by recomp.switch.shaders.",
		"",
		"import {module}",
		"",
		"pub type TextureKind:",
		"\tPlain   # Params.textures",
		"\tLayered   # Params.layers",
		"\tShadow   # Params.shadows",
		"",
		"pub type TextureSlot:",
		"\thandle i64   # the texture constant buffer's word",
		"\tkind TextureKind",
		"\tindex i64   # in the kind's array",
		"",
		"# the program set recorded as the line `key` (stage names, vertex first), none if untranslated",
		"pub fn programCode(key str) str?:"
	]
	for s in sets:
		codes = s.names.map(entryOf(shaders, it))
		lines.push("	if key == {quoted(s.key)}: return shader({codes.join(", ")})")
	lines.push("\tnone")
	lines.push("")
	lines.push("pub fn programTextures(name str) TextureSlot[]:")
	for s in shaders:
		if s.textures.isEmpty: continue
		slots = s.textures.map("TextureSlot(handle = {.handle}, kind = .{.kind}, index = {s.stage.textureBase() + .slot})")
		lines.push("\tif name == {quoted(s.name)}: return [{slots.join(", ")}]")
	lines.push("\t[]")
	lines.push("")
	lines.join("\n")
