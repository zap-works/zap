# The types of the shaders and their SPIR-V forms: scalars, vectors, matrices (columns of float
# vectors), arrays, structs and samplers. A type laid out for a block (a uniform or storage
# buffer) is a SPIR-V type of its own, with its strides and offsets decorated.

pub bVoid = 0
pub bBool = 1
pub bInt = 2
pub bUint = 3
pub bFloat = 4
pub bStruct = 5
pub bSampler = 6

pub type Ty:
	base i64
	rows i64   # a vector's components (1: a scalar); a matrix's rows
	cols i64   # a matrix's columns (1 otherwise)
	arr i64   # -1 not an array, 0 unsized, else its length
	sid i64   # a struct's index among the stage's structs; a sampler's kind (sampler2D...)
	wide bool = false   # a float of 64 bits (f64), a scalar's alone

pub sampler2D = 1
pub sampler2DArray = 2
pub sampler2DShadow = 3
pub sampler2DArrayShadow = 4
pub samplerInt2D = 5
pub samplerUint2D = 6
pub sampler3D = 7
pub samplerCube = 8
pub samplerCubeArray = 9
pub imageFloat = 10
pub imageUint = 11
pub imageInt = 12

# SPIR-V's dimensions of an image
pub dim2D = 1
pub dim3D = 2
pub dimCube = 3

# A sampler kind: the engine's type in Zap, the tree's (GLSL's), HLSL's texture and sampler that
# stand for it, its dimension, whether it reads layers and depths by comparisons, and the base of
# the numbers it reads (bFloat, bInt, bUint); a storage image (read and written by integer
# coordinates, no sampler) with its SPIR-V format (0 any, the device reading and writing it
# without one; R32ui 33 and R32i 21 for atomics).
pub type SamplerKind:
	zap str
	glsl str
	hlslTexture str
	hlslSampler str
	dim i64 = dim2D
	layered bool = false
	shadow bool = false
	texel i64 = bFloat
	storage bool = false
	format i64 = 0

fn samplerKind(zap str, glsl str, hlslTexture str, comparing bool = false):
	SamplerKind(
		zap = zap.copy(),
		glsl = glsl.copy(),
		hlslTexture = hlslTexture.copy(),
		hlslSampler = "SamplerComparisonState" if comparing else "SamplerState"
	)

# the sampler kinds, kind k at k - 1
pub samplerKinds = [
	samplerKind("Texture", "sampler2D", "Texture2D"),
	SamplerKind(..samplerKind("TextureArray", "sampler2DArray", "Texture2DArray"), layered = true),
	SamplerKind(..samplerKind("ShadowMap", "sampler2DShadow", "Texture2D", true), shadow = true),
	SamplerKind(
		..samplerKind("ShadowMapArray", "sampler2DArrayShadow", "Texture2DArray", true),
		layered = true,
		shadow = true
	),
	SamplerKind(..samplerKind("IntTexture", "isampler2D", "Texture2D<int4>"), texel = bInt),
	SamplerKind(..samplerKind("UintTexture", "usampler2D", "Texture2D<uint4>"), texel = bUint),
	SamplerKind(..samplerKind("Texture3D", "sampler3D", "Texture3D"), dim = dim3D),
	SamplerKind(..samplerKind("TextureCube", "samplerCube", "TextureCube"), dim = dimCube),
	SamplerKind(
		..samplerKind("TextureCubeArray", "samplerCubeArray", "TextureCubeArray"),
		dim = dimCube,
		layered = true
	),
	SamplerKind(
		..samplerKind("Image", "image2D", "RWTexture2D<float4>"),
		hlslSampler = "",
		storage = true
	),
	SamplerKind(
		..samplerKind("UintImage", "uimage2D", "RWTexture2D<uint>"),
		hlslSampler = "",
		storage = true,
		texel = bUint,
		format = 33
	),
	SamplerKind(
		..samplerKind("IntImage", "iimage2D", "RWTexture2D<int>"),
		hlslSampler = "",
		storage = true,
		texel = bInt,
		format = 21
)]

# whether a kind is a storage image's
pub fn isStorage(kind i64) bool:
	samplerKinds[kind - 1].storage

# whether a sampler kind reads layers (its coordinates take the layer after uv)
pub fn isLayered(kind i64) bool:
	samplerKinds[kind - 1].layered

# whether a sampler kind reads depths by comparisons
pub fn isShadow(kind i64) bool:
	samplerKinds[kind - 1].shadow

# the components of a kind's coordinates, a layer aside: 2 for a 2D texture's uv, 3 for a 3D
# texture's or a cube's direction
pub fn coordinateSize(kind i64) i64:
	2 if samplerKinds[kind - 1].dim == dim2D else 3

# the components of a kind's size at a level: width and height (a cube's face's), then a 3D
# texture's depth or an array's layers (a cube array's cubes)
pub fn sizeComponents(kind i64) i64:
	k = samplerKinds[kind - 1]
	3 if k.dim == dim3D or k.layered else 2

# each base's words, by base up to bFloat: its scalar in Zap and in the tree (GLSL's and HLSL's
# alike), its vectors' prefix in Zap and in the tree (Vec3, vec3)
# a scalar's name in Zap and in GLSL, and the prefix of its vectors' names in each
pub type BaseWords:
	zap str
	glsl str
	zapVector str
	glslVector str

pub baseWords = [
	BaseWords("", "void", "", ""),
	BaseWords("bool", "bool", "BVec", "bvec"),
	BaseWords("i32", "int", "IVec", "ivec"),
	BaseWords("u32", "uint", "UVec", "uvec"),
	BaseWords("f32", "float", "Vec", "vec")
]

pub fn scalar(base i64) Ty:
	Ty(base, rows = 1, cols = 1, arr = -1, sid = 0)

pub fn vector(base i64, n i64) Ty:
	Ty(base, rows = n, cols = 1, arr = -1, sid = 0)

pub fn matrix(n i64) Ty:
	Ty(base = bFloat, rows = n, cols = n, arr = -1, sid = 0)

pub fn isScalar(t Ty) bool:
	t.arr < 0 and t.rows == 1 and t.cols == 1 and t.base != bStruct and t.base != bSampler and
		t.base != bVoid

pub fn isVector(t Ty) bool:
	t.arr < 0 and t.rows > 1 and t.cols == 1

pub fn isMatrix(t Ty) bool:
	t.arr < 0 and t.cols > 1

pub fn isNumeric(t Ty) bool:
	t.arr < 0 and (t.base in [bInt, bUint, bFloat])

pub fn isSameTy(a Ty, b Ty) bool:
	a.base == b.base and a.rows == b.rows and a.cols == b.cols and a.arr == b.arr and a.sid == b.sid and
		a.wide == b.wide

# the type a parameter of type t is stored as in the block: a bool as a word (uint)
pub fn storedTy(t Ty) Ty:
	scalar(bUint) if t.base == bBool else t

# an array's element; a matrix's column; a vector's component
pub fn elemOf(t Ty) Ty:
	if t.arr >= 0: return Ty(..t, arr = -1)
	if t.cols > 1: return vector(bFloat, t.rows)
	scalar(t.base)

pub fn withRows(t Ty, n i64) Ty:
	Ty(..scalar(t.base), wide = t.wide) if n == 1 else vector(t.base, n)

pub fn arrayOf(t Ty, n i64) Ty:
	Ty(..t, arr = n)

# the letters of a vector's components, each set in their order: x y z w, r g b a (a color's),
# s t p q; the tree writes the first
pub swizzleSets = ["xyzw", "rgba", "stpq"]

# the component a letter of any set names
pub fn componentOf(letter str) i64?:
	for set in swizzleSets:
		if set.indexOf(letter) is k: return k
	none

# the type a name of the tree stands for (structs by their name)
pub fn tyOfName(word str, structs str[]) Ty?:
	for base in 0..baseWords.len:
		if word == baseWords[base].glsl: return scalar(base)
		for n in 2..5:
			if base != bVoid and word == "{baseWords[base].glslVector}{n}": return vector(base, n)
	for n in 2..5:
		if word == "mat{n}": return matrix(n)
	if samplerKinds.findIndex(.glsl == word) is k:
		return Ty(base = bSampler, rows = 1, cols = 1, arr = -1, sid = k + 1)
	if structs.indexOf(word) is k: return Ty(base = bStruct, rows = 1, cols = 1, arr = -1, sid = k)
	none

pub fn tyText(t Ty) str:
	s = ""
	if t.base == bStruct:
		s = "struct {t.sid}"
	elif t.base == bSampler:
		s = samplerKinds[t.sid - 1].glsl.copy()
	elif t.cols > 1:
		s = "mat{t.cols}"
	elif t.rows > 1:
		s = "{baseWords[t.base].glslVector}{t.rows}"
	elif t.wide:
		s = "double"
	else:
		s = baseWords[t.base].glsl.copy()
	if t.arr >= 0:
		s += "[{t.arr}]"
	s

# ---------- std140 and std430 layout ----------

# The alignment and the size of a type in a block: std140 rounds arrays' and structs' up to 16,
# a struct is aligned as its widest member (16 at least in std140) and its size rounded up to
# that. `members` holds each struct's member types, by its sid.
pub fn layoutOf(t Ty, std140 bool, members Ty[,]) (i64, i64):
	if t.arr >= 0:
		ea, es = t.elemOf().layoutOf(std140, members)
		stride = es.alignUp(ea)
		a = ea
		if std140:
			stride = stride.alignUp(16)
			a = 16
		return (a, stride * t.arr.max(1))
	if t.base == bStruct:
		end = 0
		a = 16 if std140 else 4
		for mt in members[t.sid]:
			ma, ms = mt.layoutOf(std140, members)
			end = end.alignUp(ma) + ms
			a = a.max(ma)
		return (a, end.alignUp(a))
	if t.cols > 1:
		colAlign = 8 if t.rows == 2 and not std140 else 16
		return (colAlign, colAlign * t.cols)
	if t.wide: return (8, 8)
	if t.rows == 1: return (4, 4)
	if t.rows == 2: return (8, 8)
	(16, t.rows * 4)

# an array element's stride in a block
pub fn strideOf(t Ty, std140 bool, members Ty[,]) i64:
	ea, es = t.elemOf().layoutOf(std140, members)
	stride = es.alignUp(ea)
	stride.alignUp(16) if std140 else stride

# each member's offset in a block, in their order
pub fn offsetsOf(types Ty[], std140 bool, members Ty[,]) i64[]:
	out = []
	offset = 0
	for t in types:
		a, size = t.layoutOf(std140, members)
		offset = offset.alignUp(a)
		out.push(offset)
		offset += size
	out
