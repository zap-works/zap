# A program: its two stages made from the GPU files of their modules (lower.zap lays out the
# entry functions), linked.
#   - the values the vertex stage passes on meet the pixel stage's by name, at locations in
#     their order (Lowering.between);
#   - the parameter structs' numbers are one std140 block at binding 32 of set 0, each struct a
#     part of it at a multiple of 16 bytes; a stage declares the parts it reads;
#   - a texture keeps its binding (numbered across the parts), a storage buffer moves to
#     16 + its binding;
#   - a texture array (`Texture[]`, or `TextureArray[N]`) has its binding in set 1 (space1
#     on Direct3D), a table of descriptors the RHI binds once per frame;
#   - the vertex stage's depth goes from the engine's -1..1 (its projection matrices') to 0..1,
#     and its x and y turn by the cosine and sine its pipeline gives specialization constants
#     turnCosine and turnSine (1 and 0 by default): a screen the system turns is drawn turned.

pub paramsBinding = 32
pub bufferBase = 16
pub textureArraySet = 1
pub turnCosine = 0
pub turnSine = 1

# a number of the parameter block: its name (zapP<part>_<field>), its type in the tree's words,
# its array's length (-1 none) and where it is in the block
pub type Param:
	name str
	tname str
	arr i64
	offset i64
	pos i64   # its field's place

# a texture a program reads: its binding and its kind (sampler2D, sampler2DArray, sampler2DShadow)
pub type SamplerSlot:
	binding i64
	kind i64

# a texture array a program reads: its binding (in set textureArraySet), its textures' kind and
# its length (0: as many as the RHI binds)
pub type TextureArray:
	binding i64
	kind i64
	count i64

# a vertex input: its location, its component type (bFloat, bInt, bUint), its size, the stream
# it is read from (0 the vertex's, 1 the instance's) and its offset in that stream's element
pub type VertexInput:
	location i64
	base i64
	rows i64
	stream i64
	offset i64

# the vertex stage of a program that writes none: one triangle that covers the target, the
# pixel stage given where it is across it (0..1); mc checks and lowers it as it does a GPU
# file's function (gpu.zap)
pub screenVertex = """
	fn zapScreenVertex(corner i32) (Vec4, Vec2):
		p = Vec2(f32((corner & 1) * 4 - 1), f32((corner >> 1) * 4 - 1))
		(Vec4(p.x, p.y, 0.0, 1.0), p * 0.5 + 0.5)
	"""

# ---------- the tree ----------

# the tree's name of a type's Zap word (f32 float, Vec3 vec3, Quat vec4, Texture
# sampler2D; a struct's or an enum's own name)
pub fn typeName(word str) str:
	if word == "Quat": return "vec4"
	for BaseWords(zapScalar, scalarWord, zapPrefix, prefix) in baseWords:
		if zapScalar != "" and word == zapScalar: return scalarWord.copy()
		for n in 2..5:
			if zapPrefix != "" and word == "{zapPrefix}{n}": return "{prefix}{n}"
	for n in 2..5:
		if word == "Mat{n}": return "mat{n}"
	if samplerKinds.find(.zap == word) is k: return k.glsl.copy()
	word.copy()
