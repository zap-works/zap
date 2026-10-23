# The texture reads a stage calls, as methods of a texture (t.sample(uv)): what each takes, in
# what order, and what it gives. gpucheck.zap checks the arguments against this table, irgpuexpr.zap
# lowers them to an irTexture (its constants in the instruction's imm), and irspirv.zap and
# irhlsl.zap find each argument by its role. `size([lod])` is any texture's and is not here.

# A texture method: its name, whether a shadow map's (else a color texture's), the roles of its
# arguments after uv and an array's layer, whether a layered texture takes the layer, whether a
# constant offset may follow, and its result (the language's type).
pub type TextureMethod:
	name str
	shadow bool
	roles str[]
	layered bool = true
	offset bool = true
	result str = "Vec4"

fn method(name str, shadow bool, roles str[]):
	TextureMethod(name = name.copy(), shadow, roles = roles.copy())

# lod: the level the sampler reads and the one the derivatives ask for (unclamped), of uv alone
pub textureMethods = [
	method("sample", false, []),
	method("sampleLevel", false, ["lod"]),
	method("sampleBias", false, ["bias"]),
	method("sampleGrad", false, ["dx", "dy"]),
	method("gather", false, ["component"]),
	TextureMethod(name = "lod", shadow = false, roles = [], layered = false, offset = false, result = "Vec2"),
	TextureMethod(name = "compare", shadow = true, roles = ["depth"], result = "f32"),
	method("gatherCompare", true, ["depth"])]

# the type of an argument of a role: uv, the gradients and the offset vectors, the component an
# integer, the others floats
pub fn textureRoleType(role str) str:
	if role in ["uv", "dx", "dy"]: return "Vec2"
	if role == "offset": return "IVec2"
	if role == "component": return "i32"
	"f32"

# the roles whose argument is a constant the instruction carries (irTexture's imm)
pub fn isTextureConstant(role str) bool:
	role == "component" or role == "offset"

# the method m of a texture of the kind, none when it has none of that name
pub fn textureMethodOf(m str, kind i64) TextureMethod?:
	(try textureMethods.find(.name == m and .shadow == isShadow(kind))).copy()

# the roles of a method's arguments in order on a texture of the kind, with the offset or not
pub fn textureRoles(f TextureMethod, kind i64, withOffset bool) str[]:
	out = ["uv"]
	if isLayered(kind) and f.layered: out.push("layer")
	out.extend(f.roles.copy())
	if withOffset: out.push("offset")
	out

# The constants of a read (gather's component, the offset), packed into the instruction's imm:
# the component in bits 0-1, whether an offset is given in bit 2, its x and y as signed bytes at
# 8 and 16.
pub type TextureConstants:
	component i64 = 0
	offset bool = false
	x i64 = 0
	y i64 = 0

# the constants as irTexture's imm
pub fn packTextureConstants(k TextureConstants) i64:
	k.component | (4 if k.offset else 0) | (k.x & 0xFF) << 8 | (k.y & 0xFF) << 16

# the constants irTexture's imm holds
pub fn unpackTextureConstants(imm i64) TextureConstants:
	TextureConstants(
		component = imm & 3,
		offset = imm & 4 != 0,
		x = signedByte(imm >> 8),
		y = signedByte(imm >> 16)
	)

fn signedByte(v i64):
	(v & 0xFF) - 256 if v & 0x80 != 0 else v & 0xFF

# The arguments of an irTexture by role (args[0] the texture, then its arguments in order;
# -1 a role the read has not).
pub type TextureArgs:
	uv i64 = -1
	layer i64 = -1
	level i64 = -1   # sampleLevel's lod, sampleBias's bias, size's level
	depth i64 = -1
	dx i64 = -1
	dy i64 = -1
	constants TextureConstants = TextureConstants()

# the arguments of read m of a texture of the kind by role, from irTexture's args and imm
pub fn textureArgsOf(kind i64, m str, args i64[], imm i64) TextureArgs:
	out = TextureArgs(constants = unpackTextureConstants(imm))
	if m == "size":
		if args.len == 2: out.level = args[1]
		return out
	f = textureMethodOf(m, kind) ?? fail("shader: a texture of kind {kind} has no {m}")
	at = 1
	for role in f.textureRoles(kind, false):
		if role == "uv": out.uv = args[at]
		elif role == "layer": out.layer = args[at]
		elif role == "lod" or role == "bias": out.level = args[at]
		elif role == "depth": out.depth = args[at]
		elif role == "dx": out.dx = args[at]
		elif role == "dy": out.dy = args[at]
		if not isTextureConstant(role): at += 1
	out
