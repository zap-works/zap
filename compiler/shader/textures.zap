# The texture reads a stage calls, as methods of a texture (t.sample(uv)): what each takes, in
# what order, and what it gives. gpucheck.zap checks the arguments against this table, irgpuexpr.zap
# lowers them to an irTexture (its constants in the instruction's imm), and irspirv.zap and
# irhlsl.zap find each argument by its role. `size([lod])` is any texture's and is not here.

# A texture method: its name, the sampler kinds that have it, its coordinates' role (uv, or a
# fetch's texel), the roles of its arguments after them and an array's layer, whether a layered
# texture takes the layer, whether a constant offset may follow (a cube's reads take none), and
# its result (the language's type; texel: the kind's vector of four, Vec4, IVec4 or UVec4).
pub type TextureMethod:
	name str
	kinds i64[]
	roles str[]
	at str = "uv"
	layered bool = true
	offset bool = true
	result str = "texel"

fn method(name str, kinds i64[], roles str[]):
	TextureMethod(name = name.copy(), kinds = kinds.copy(), roles = roles.copy())

# the kinds of colors read by filtering, of depths compared, of those a gather reads (a 3D
# texture has none) and of those whose texels are fetched (a cube's are not)
colorKinds = [sampler2D, sampler2DArray, sampler3D, samplerCube, samplerCubeArray]
shadowKinds = [sampler2DShadow, sampler2DArrayShadow]
gatherKinds = [sampler2D, sampler2DArray, samplerCube, samplerCubeArray]
fetchKinds = [sampler2D, sampler2DArray, sampler3D, samplerInt2D, samplerUint2D]

# lod: the level the sampler reads and the one the derivatives ask for (unclamped), of uv alone;
# fetch: the texel at integer coordinates of a level, with no sampler (0 outside the level);
# compare: a shadow map's first level's comparisons, compareLevel and compareBias another's
pub textureMethods = [
	method("sample", colorKinds, []),
	method("sampleLevel", colorKinds, ["lod"]),
	method("sampleBias", colorKinds, ["bias"]),
	method("sampleGrad", colorKinds, ["dx", "dy"]),
	method("gather", gatherKinds, ["component"]),
	TextureMethod(name = "lod", kinds = colorKinds, roles = [], layered = false, offset = false, result = "Vec2"),
	TextureMethod(name = "fetch", kinds = fetchKinds, roles = ["level"], at = "texel"),
	TextureMethod(name = "compare", kinds = shadowKinds, roles = ["depth"], result = "f32"),
	TextureMethod(name = "compareLevel", kinds = shadowKinds, roles = ["depth", "lod"], result = "f32"),
	TextureMethod(name = "compareBias", kinds = shadowKinds, roles = ["depth", "bias"], result = "f32"),
	method("gatherCompare", shadowKinds, ["depth"])]

# the type of an argument of a role on a texture of the kind: the coordinates, gradients and
# offsets vectors of the kind's size (floats, or integers for a texel and an offset), a fetch's
# layer and level, the component integers, the others floats
pub fn textureRoleType(role str, kind i64) str:
	n = coordinateSize(kind)
	if role in ["uv", "dx", "dy"]: return "Vec{n}"
	if role == "texel" or role == "offset": return "IVec{n}"
	if role in ["component", "slice", "level"]: return "i32"
	"f32"

# the language's type a read gives on a texture of the kind
pub fn textureResult(f TextureMethod, kind i64) str:
	if f.result != "texel": return f.result.copy()
	["", "", "IVec4", "UVec4", "Vec4"][samplerKinds[kind - 1].texel].copy()

# whether the read may take a constant offset on a texture of the kind
pub fn takesOffset(f TextureMethod, kind i64) bool:
	f.offset and samplerKinds[kind - 1].dim != dimCube

# the roles whose argument is a constant the instruction carries (irTexture's imm)
pub fn isTextureConstant(role str) bool:
	role == "component" or role == "offset"

# the method m of a texture of the kind, none when it has none of that name
pub fn textureMethodOf(m str, kind i64) TextureMethod?:
	(try textureMethods.find(.name == m and kind in .kinds)).copy()

# the roles of a method's arguments in order on a texture of the kind, with the offset or not
pub fn textureRoles(f TextureMethod, kind i64, withOffset bool) str[]:
	out = [f.at.copy()]
	if isLayered(kind) and f.layered: out.push("layer" if f.at == "uv" else "slice")
	out.extend(f.roles.copy())
	if withOffset: out.push("offset")
	out

# The constants of a read (gather's component, the offset), packed into the instruction's imm:
# the component in bits 0-1, whether an offset is given in bit 2, its x, y and z as signed bytes
# at 8, 16 and 24.
pub type TextureConstants:
	component i64 = 0
	offset bool = false
	x i64 = 0
	y i64 = 0
	z i64 = 0

# the constants as irTexture's imm
pub fn packTextureConstants(k TextureConstants) i64:
	k.component | (4 if k.offset else 0) | (k.x & 0xFF) << 8 | (k.y & 0xFF) << 16 |
		(k.z & 0xFF) << 24

# the constants irTexture's imm holds
pub fn unpackTextureConstants(imm i64) TextureConstants:
	TextureConstants(
		component = imm & 3,
		offset = imm & 4 != 0,
		x = signedByte(imm >> 8),
		y = signedByte(imm >> 16),
		z = signedByte(imm >> 24)
	)

fn signedByte(v i64):
	(v & 0xFF) - 256 if v & 0x80 != 0 else v & 0xFF

# The arguments of an irTexture by role (args[0] the texture, then its arguments in order;
# -1 a role the read has not).
pub type TextureArgs:
	uv i64 = -1   # the coordinates (a fetch's texel)
	layer i64 = -1   # the layer (a fetch's slice)
	level i64 = -1   # sampleLevel's lod, sampleBias's bias, fetch's and size's level
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
		if role == "uv" or role == "texel": out.uv = args[at]
		elif role == "layer" or role == "slice": out.layer = args[at]
		elif role in ["lod", "bias", "level"]: out.level = args[at]
		elif role == "depth": out.depth = args[at]
		elif role == "dx": out.dx = args[at]
		elif role == "dy": out.dy = args[at]
		if not isTextureConstant(role): at += 1
	out
