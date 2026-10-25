# A GPU function (flagGpu: a function of a `.gpu.zap` file) is checked as any other, in the
# GPU's terms: a number literal no place types is an i32 or an f32 (the GPU has no 64-bit
# numbers), and a stage may read what only a GPU has: the textures' reads (t.sample(uv), the
# others of shader.textureMethods, t.size()), the derivatives of a float or a vector across the pixels (ddx, ddy, fwidth),
# discard(), the values the GPU gives (gpuValues), a compute stage's barrier() and the operations
# across the lanes that run together (x.laneSum(), b.laneAny()...). The CPU's code never calls a
# GPU function.

import shader

alias nodes = c.nodes
alias kidIds = c.kidIds
alias tys = c.types

fn gpuDerivative(m str):
	m in ["ddx", "ddy", "fwidth"]

# a value the GPU gives a stage's code, by its name: its type (the language's), and the stage
# that has it (shader.stageFragment, shader.stageCompute)
type GpuValue:
	name str
	typeName str
	stage i64

# the pixel's window place, depth and 1 / w (a pixel stage's); a compute stage's invocation's
# place in the whole dispatch, in its group and its group's, its index in its group, its lane
# among those that run together and their count
gpuValues = [
	GpuValue("pixelPosition", "Vec4", shader.stageFragment),
	GpuValue("globalId", "IVec3", shader.stageCompute),
	GpuValue("localId", "IVec3", shader.stageCompute),
	GpuValue("groupId", "IVec3", shader.stageCompute),
	GpuValue("localIndex", "i32", shader.stageCompute),
	GpuValue("lane", "i32", shader.stageCompute),
	GpuValue("laneCount", "i32", shader.stageCompute)
]

# the type of the value the GPU gives that `name` names, none for any other name
fn gpuValueType(mut c Checker, name str) TypeId?:
	v = try gpuValues.find(.name == name)
	tyInt(32, true) if v.typeName == "i32" else c.languageType(v.typeName)

# How many arguments a method across the lanes that run together takes (-1: not one): their
# sum, least, greatest, the first lane's value, lane i's (laneAt(i)), the sum of the lanes
# before this one (lanePrefixSum), and a bool's laneAny and laneAll.
fn gpuLaneArity(m str):
	if m in ["laneSum", "laneMin", "laneMax", "laneFirst", "lanePrefixSum"] or m in laneBoolMethods:
		return 0
	1 if m == "laneAt" else -1

# a bool's methods across the lanes: whether it holds in any (every) lane that runs with this one
laneBoolMethods = ["laneAny", "laneAll"]

# one of the engine's textures as a stage reads it: Texture, TextureArray, ShadowMap, ShadowMapArray
fn gpuTexture(c Checker, t TypeId):
	shader.samplerKinds.any(.zap == nodes[declOf(tys, t)].text2())

# the language's type of that name (Vec4, IVec2...)
fn languageType(mut c Checker, name str) TypeId:
	tyOfDecl(tys, nodes, c.findDeclInModule("rt", nStructDecl, name) ?? fail("rt has no {name}"))

# a texture's read (shader.textureMethods): its arguments checked by their roles, gather's
# component and the offset constants; its size at a level (an IVec2, or an IVec3 for a 3D
# texture's depth or an array's layers)
fn checkTextureMethod(mut c Checker, e NodeId, t TypeId, move m str) TypeId:
	name = nodes[declOf(tys, t)].text2().copy()
	kind = (shader.samplerKinds.findIndex(.zap == name) ?? 0) + 1
	n = c.argCount(e)
	if m == "size" and n <= 1:
		if n == 1: c.checkTextureArg(e, m, 0, "i32")
		return c.languageType("IVec{shader.sizeComponents(kind)}")
	f = shader.textureMethodOf(m, kind) ?? return c.textureReadError(e, name)
	roles = f.textureRoles(
		kind,
		f.takesOffset(kind) and n == f.textureRoles(kind, false).len + 1
	)
	if not c.expectArgs(e, m, roles.len): return tyError
	for i, role in roles:
		c.checkTextureArg(e, m, i, shader.textureRoleType(role, kind))
		if shader.isTextureConstant(role) and c.textureConstant(c.argAt(e, i), role, kind) == none:
			a = c.argAt(e, i)
			c.errorAt(
				nodes[a].line,
				nodes[a].col,
				compileError("TextureConstant", ["{m}", "{role}"])
			)
	result = f.textureResult(kind)
	if result == "none": return tyUnit
	if result in ["f32", "i32", "u32"]: return c.gpuNumberType(result)
	c.languageType(result)

# the GPU's number of that name: i32, u32, f32
fn gpuNumberType(c Checker, name str):
	tyFloat(32) if name == "f32" else tyInt(32, name == "i32")

fn textureReadError(mut c Checker, e NodeId, name str):
	c.errorAt(nodes[e].line, nodes[e].col, compileError("TextureRead", ["{name}"]))
	tyError

# argument i of a texture read, checked against its role's type
fn checkTextureArg(mut c Checker, e NodeId, m str, i i64, typeName str):
	wanted = c.gpuNumberType(typeName) if typeName in ["i32", "u32", "f32"]
		else c.languageType(typeName)
	a = c.argAt(e, i)
	at = c.derefIfRef(a, c.checkExpr(a, wanted))
	if not isAssignable(tys, at, wanted):
		errorAt(
			c,
			nodes[a].line,
			nodes[a].col,
			compileError("GpuArgumentType", ["{m}", "{c.showTy(wanted)}", "{c.showTy(at)}"])
		)

# A constant argument of a texture read: gather's component (0 to 3, x to w), or an offset in
# texels written IVec2(x, y) (IVec3(x, y, z) on a 3D texture) of literals from -8 to 7 (what both
# APIs take); none when e is not one.
pub fn textureConstant(c Checker, e NodeId, role str, kind i64) shader.TextureConstants?:
	if role == "component":
		v = try foldedInt(nodes, kidIds, e, x: none)
		return shader.TextureConstants(component = v) if v >= 0 and v <= 3 else none
	k = nodes[e].kind
	if k != nCall and k != nStructLit: return none
	parts = nodes[e].kidsFrom(kidIds, 1 if k == nCall else 0)
	if parts.len != shader.coordinateSize(kind): return none
	values = [0, 0, 0]
	for i, p in parts:
		named = nodes[p].kind == nNamedArg
		v = try foldedInt(nodes, kidIds, nodes[p].kids(kidIds)[0] if named else p, x: none)
		if v < -8 or v > 7: return none
		at = i
		if named: at = shader.componentOf(nodes[p].text) ?? 0
		values[at] = v
	shader.TextureConstants(offset = true, x = values[0], y = values[1], z = values[2])
