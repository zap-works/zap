# 11. Shaders
#
# GPU code is Zap, written in files named `*.gpu.zap` inside any module (the modules of these tests
# are in `spec/shaders/`; `lit` is the full example). Their types and enums are ordinary types the
# CPU code uses too; their functions and constants are the GPU's only: the CPU never compiles or
# calls them, and a function taking `self` there is an error. They are checked by the CPU's rules
# (no conversion that loses a value, `mut` to assign again, every binding read), with the GPU's
# numbers: a literal no place types is an `i32` or an `f32`.
#
# `shader(lit.vertex, lit.pixel)` names a program's two entry functions (`shader(screen.pixel)` a
# screen pass; a bare name is the module's own). When the program is built, the compiler lowers
# them and every function they call (of the GPU files of their modules and of the modules those
# import, called as `tonemap.aces(c)`, or any other the GPU can run) to its intermediate form, as
# it lowers the CPU's code, and writes SPIR-V and HLSL from it; the call is a string literal of
# what the GPU needs, so the running program carries no shader compiler. A wrong shader stops the
# compile as any compile error does.

import fs
import shaders.lit
import shaders.screen
import shaders.bindless
import shaders.vecs
import shaders.graded
import shaders.picked
import shaders.letters
import shaders.turned
import shaders.banded
import shaders.packed
import shaders.geometry
import shaders.kernels
import shaders.sampled
import shaders.outputs
import shaders.texels
import shaders.volumes

# **Output.** The literal holds, as little-endian 32-bit words: `ZSH2`; the block's size; each part
# (its name as a length and bytes, its offset, its first texture and their count, its first storage
# buffer and count, its first texture array and count); each texture (binding, kind: 1 2D, 2 2D
# array, 3 shadow, 4 shadow array, 5 of integers, 6 of unsigned integers, 7 3D, 8 cube, 9 cube
# array); each storage buffer (binding); each vertex input (location, component type,
# size, stream: 0 the vertex's, 1 the instance's, offset in the stream's element); the vertex and
# instance strides; the vertex and pixel stages as SPIR-V (Vulkan) and as DXIL (Direct3D 12), each
# as its length and its bytes; each texture array (binding, kind, length, 0 when it has none).
# `describe` reads it back.

fn wordAt(code str, at i64):
	code[at] | i64(code[at + 1]) << 8 | i64(code[at + 2]) << 16 | i64(code[at + 3]) << 24

# the code's reflection as a line per part, and the sizes of its binaries (SPIR-V's magic first);
# a compute program's (`ZSC1`) has its buffers' writes and its groups' size in place of the inputs
fn describe(code str):
	print(code[..4])
	isCompute = code[..4] == "ZSC1"
	at = 4
	print("parameter bytes {wordAt(code, at)}")
	at += 4
	parts = wordAt(code, at)
	at += 4
	loop parts:
		n = wordAt(code, at)
		name = code[at + 4..at + 4 + n]
		at += 4 + (n + 3) / 4 * 4
		print("part {name} at {wordAt(code, at)}: textures {wordAt(code, at + 4)}+{wordAt(code, at + 8)}, buffers {wordAt(code, at + 12)}+{wordAt(code, at + 16)}, arrays {wordAt(code, at + 20)}+{wordAt(code, at + 24)}")
		at += 28
	samplers = wordAt(code, at)
	at += 4
	loop samplers:
		print("texture binding {wordAt(code, at)} kind {wordAt(code, at + 4)}")
		at += 8
	buffers = wordAt(code, at)
	at += 4
	loop buffers:
		if isCompute:
			print("storage binding {wordAt(code, at)} written {wordAt(code, at + 4)}")
			at += 8
		else:
			print("storage binding {wordAt(code, at)}")
			at += 4
	stages = ["compute"] if isCompute else ["vertex", "pixel"]
	if isCompute:
		print("groups {wordAt(code, at)} {wordAt(code, at + 4)} {wordAt(code, at + 8)}")
		at += 12
	else:
		inputs = wordAt(code, at)
		at += 4
		loop inputs:
			print("input location {wordAt(code, at)} type {wordAt(code, at + 4)} size {wordAt(code, at + 8)} stream {wordAt(code, at + 12)} offset {wordAt(code, at + 16)}")
			at += 20
		print("strides {wordAt(code, at)} {wordAt(code, at + 4)}")
		at += 8
	for stage in stages:
		size = wordAt(code, at)
		print("{stage} SPIR-V: {size > 0 and size % 4 == 0} {wordAt(code, at + 4) == 0x07230203}")
		at += 4 + (size + 3) / 4 * 4
	# DXC's container, or nothing on a machine without DXC (a DXC that refuses the HLSL stops
	# the build)
	for stage in stages:
		size = wordAt(code, at)
		print("{stage} DXIL: {size == 0 or code[at + 4] == 'D' and code[at + 5] == 'X' and code[at + 6] == 'B' and code[at + 7] == 'C'}")
		at += 4 + (size + 3) / 4 * 4
	arrays = wordAt(code, at)
	at += 4
	loop arrays:
		print("texture array binding {wordAt(code, at)} kind {wordAt(code, at + 4)} count {wordAt(code, at + 8)}")
		at += 12
	print("{code.len - at} bytes after")

# **Entries.** `vertex(v[, instance][, params])` returns the clip position (depth -1..1, y up) or
# `(Vec4, B)`, the position and a struct passed on. `v` and `instance` are structs of the vertex and
# instance streams (fields in order, packed), or an `i32`, the vertex's or the instance's number,
# for a draw without buffers; of two parameters a struct second one is the parameters. `pixel([b][,
# params])` takes the struct passed on (its fields meet the vertex's by name and type, so one
# module's vertex stage serves another's pixel stage; an integer is not interpolated) and returns
# the color, a struct of its outputs, or nothing (depth only). A struct's `Vec4` field writes the
# target its place among the `Vec4`s names, or N when it is named `targetN` (0 to 7), so a stage
# writes target 5 alone; an `f32` field is the pixel's depth, written in place of the triangle's.
#
# **Parameters.** Each stage takes at most one parameters struct; two types make two parts of one
# block, one std140 uniform buffer at binding 32 (a constant buffer at `b0` on Direct3D). Its
# numbers are laid out std140 (Direct3D's packing agrees: the compiler places each member): `f32 i32
# u32`, `bool` (a word), enums (the variant's number), `Vec2..4`, `Mat2..4`, `T[N]`, nested structs.
# Its resources are `Texture`, `TextureArray`, `ShadowMap`, `ShadowMapArray`, `IntTexture` and
# `UintTexture` (a texture of integers, R32I or R32UI..., read as they are), `Texture3D`,
# `TextureCube` and `TextureCubeArray` (handles, made by what owns the texture:
# `GpuTexture.texture()`, `GpuTextureArray.textureArray()`, `RenderTarget.colorTexture()`,
# `GpuTexture.intTexture()`, `GpuTexture.volume()`, `GpuTexture.cube()`...), keeping
# their bindings (`t`/`s` registers), and `T[]`, a storage buffer moved to 16 + its binding (T a
# number, `Vec2`, `Vec4` or a struct of those ordered so std430 and Direct3D agree: `Vec4`s, then
# `Vec2`s, then scalars). A function may take the parameters (`fn shade(n Vec3, p Params)`): they
# are the program's, not copied.
#
# **Code** is Zap: bindings, `mut`, compound assignment, `if`/`else`, `for i in a..b`, `while`,
# `loop`, `break`, `continue`, `return`, trailing results, tuples, enums compared with `==` or
# matched (`match` as a statement), `.Variant` where the enum is known, `discard()`. Types: `f32 i32
# u32 bool`, `Vec2..4`, `IVec2..4`, `UVec2..4`, `Mat2..4` (7.8), `T[N]` (a local
# `mut a T[N]` given no values starts as zeros), structs.
#
# **Math is the CPU's.** Values are made by their types' names (`Vec3(x, y, z)`, `Mat2(a, b, c, d)`,
# `v.withW(w)`, swizzles of any value, `f32(x)`, a float's bits `x.toBits()` and back
# `f32.fromBits(u)`); `%` is the truncated remainder; `@` is the matrix
# and dot product (GLSL's `*` on them), `*` element by element. Methods: `abs sign floor ceil round
# trunc fract sqrt inverseSqrt exp exp2 ln log2 sin cos tan asin acos atan atan2 sinh cosh tanh
# radians degrees pow min max clamp lerp step smoothstep mulAdd length distance cross normalized
# reflect refract transpose ddx ddy fwidth`. Textures, an array's taking its layer after uv:
# `t.sample(uv)`, `t.sampleLevel(uv, lod)`, `t.sampleBias(uv, bias)`, `t.sampleGrad(uv, dx, dy)`
# (the derivatives of uv across the pixels), `t.gather(uv, component)` (that component of the four
# texels a linear filter reads, a literal 0 to 3), `t.lod(uv)` (no layer: the level the sampler
# reads and the one the derivatives ask, unclamped), `t.fetch(texel, level)` (the texel at an
# `IVec2` of integer coordinates, an array's layer an `i32` after them, of an `i32` level, with no
# sampler: 0 outside the level or past the levels, as both APIs make it; an integer texture's one
# read, an `IVec4` or a `UVec4`), `t.size([lod])`; a shadow map or a shadow map
# array `s.compare(uv, depth)` (the fraction lit, at the first level: a shadow map has one),
# `s.gatherCompare(uv, depth)` (the four texels' comparisons), `s.compareLevel(uv, depth, lod)` and
# `s.compareBias(uv, depth, bias)` (another level's: on Direct3D shader model 6.7's SampleCmpLevel,
# and 6.8's SampleCmpBias in a pixel stage, the stage built for the least model its reads need).
# A 3D texture's `uv` is a `Vec3` (its texel an `IVec3`), a cube's a `Vec3` direction (a cube
# array's cube after it as a layer); a 3D texture has no gather, a cube no fetch. The reads but
# `lod` and `size` take a last offset in texels, `IVec2(x, y)` (a 3D texture's `IVec3`) of literals
# -8 to 7, but on a cube. A stage without derivatives (the vertex
# one) reads the first level, or the bias's; its `lod` is (0, 0).

test "a program's reflection: its parameter struct a part of the block, its textures, buffers and inputs":
	describe(shader(lit.vertex, lit.pixel))
	prints fs.readFile("spec/shaders/lit/reflection.expected") ?? ""

test "every texture read on each kind of texture, in a vertex and a pixel stage":
	describe(shader(sampled.vertex, sampled.pixel))
	prints """
		ZSH2
		parameter bytes 0
		part shaders.sampled.Params at 0: textures 0+4, buffers 0+0, arrays 0+0
		texture binding 0 kind 1
		texture binding 1 kind 2
		texture binding 2 kind 3
		texture binding 3 kind 4
		strides 0 0
		vertex SPIR-V: true true
		pixel SPIR-V: true true
		vertex DXIL: true
		pixel DXIL: true
		0 bytes after
		"""

test "texels fetched from color, layered and integer textures, and the integer vectors":
	describe(shader(texels.vertex, texels.pixel))
	prints """
		ZSH2
		parameter bytes 0
		part shaders.texels.Params at 0: textures 0+4, buffers 0+0, arrays 0+0
		texture binding 0 kind 1
		texture binding 1 kind 2
		texture binding 2 kind 6
		texture binding 3 kind 5
		strides 0 0
		vertex SPIR-V: true true
		pixel SPIR-V: true true
		vertex DXIL: true
		pixel DXIL: true
		0 bytes after
		"""

test "3D textures, cubes and cube arrays read, and shadow maps compared at a level and with a bias":
	describe(shader(volumes.vertex, volumes.pixel))
	prints """
		ZSH2
		parameter bytes 0
		part shaders.volumes.Params at 0: textures 0+5, buffers 0+0, arrays 0+0
		texture binding 0 kind 7
		texture binding 1 kind 8
		texture binding 2 kind 9
		texture binding 3 kind 3
		texture binding 4 kind 4
		strides 0 0
		vertex SPIR-V: true true
		pixel SPIR-V: true true
		vertex DXIL: true
		pixel DXIL: true
		0 bytes after
		"""

test "a texture read's offset is a constant" refuses TextureConstant:
	import shaders.varied

	print(shader(varied.pixel).len)

test "pixel stages writing target 5 alone, targets 0 and 3, a color and the depth":
	expect [shader(outputs.fifth), shader(outputs.pair), shader(outputs.deep)].all(not .isEmpty)

test "two fields of a pixel stage's result on one target" refuses PixelOutputTwice:
	import shaders.twice

	print(shader(twice.pixel).len)

# **Packer.** For each parameters struct the compiler adds to its module `gpuName()` (the part's
# name, `module.Type`) and `gpuWrite(...)`, which stores the struct's numbers as the block's words
# at the part's offset, its textures' ids and its lists' bytes (`rawBytes()`) where the RHI binds
# them. The engine's `setParams(program, params)` calls it; `ZAP_RUN=packers` prints the code.

test "a parameter struct written as the GPU reads it, by the packer the compiler gave it":
	a f32[16]
	a[0] = 1.0
	a[5] = 1.0
	a[10] = 1.0
	a[12] = 2.0
	a[13] = 3.0
	a[15] = 1.0
	m = Mat4(m = a)
	p = lit.Params(
		viewProjection = m,
		tint = Vec3(x = 0.5, y = 1.0, z = 1.5),
		weights = [1.0, 2.0, 3.0],
		fog = lit.Fog(color = Vec4(r = 1.0, g = 0.0, b = 0.0, a = 0.5), density = 0.25),
		lit = true,
		wrap = .Mirror,
		strength = 5.0,
		picture = vecs.Texture(id = 7), shadow = vecs.ShadowMap(id = 9), lights = [
			Vec4(x = 1.0, y = 2.0, z = 3.0, w = 4.0),
			Vec4(x = 5.0, y = 6.0, z = 7.0, w = 8.0)
	])
	words = fill(44, u32(0))
	textures = fill(2, -1)
	buffers u8[,] = [[]]
	arrays = []
	print(p.gpuName())
	p.gpuWrite(words, 0, textures, 0, buffers, 0, arrays, 0)
	print(words[..16])
	print(words[16..32])
	print(words[32..44])
	print(textures)
	print("{buffers[0].len} bytes, {buffers[0][0..8]}")
	prints """
		shaders.lit.Params
		[1065353216, 0, 0, 0, 0, 1065353216, 0, 0, 0, 0, 1065353216, 0, 1073741824, 1077936128, 0, 1065353216]
		[1056964608, 1065353216, 1069547520, 0, 1065353216, 0, 0, 0, 1073741824, 0, 0, 0, 1077936128, 0, 0, 0]
		[1065353216, 0, 0, 1056964608, 1048576000, 0, 0, 0, 1, 1, 1084227584, 0]
		[7, 9]
		32 bytes, [0, 0, 128, 63, 0, 0, 0, 64]
		"""

# A screen pass's pixel stage takes `uv Vec2` first: one triangle covers the target.
# `pixelPosition` is the pixel's window place.

test "a pass over a whole target: the compiler writes its vertex stage":
	describe(shader(screen.pixel))
	prints """
		ZSH2
		parameter bytes 16
		part shaders.screen.Exposure at 0: textures 0+1, buffers 0+0, arrays 0+0
		texture binding 0 kind 2
		strides 0 0
		vertex SPIR-V: true true
		pixel SPIR-V: true true
		vertex DXIL: true
		pixel DXIL: true
		0 bytes after
		"""

# **Bindless.** `textures Texture[]` is an array of textures with no length (as many as the RHI
# binds), `layers TextureArray[4]` one of four; `p.textures[i].sample(uv)` reads the texture at an
# index the shader computes, typically from a storage buffer of records (`materials Material[]`). An
# index that is not a literal is taken as non-uniform. A texture array keeps its binding in
# descriptor set 1, apart from set 0's per-draw bindings, so the RHI binds that table once (a
# variable-count, partially bound, update-after-bind layout for the one without a length); on
# Direct3D it is an array of textures and one of samplers at `t0`/`s0` of space 1 + its binding (an
# unbounded array takes its space's every register after it, hence a space each).

test "bindless: texture arrays in set 1 (one with no length), a storage buffer of material records":
	bindlessProgram = shader(bindless.vertex, bindless.pixel)
	describe(bindlessProgram)
	prints """
		ZSH2
		parameter bytes 80
		part shaders.bindless.Scene at 0: textures 0+0, buffers 0+1, arrays 0+2
		storage binding 16
		input location 0 type 4 size 3 stream 0 offset 0
		input location 1 type 4 size 2 stream 0 offset 12
		strides 20 0
		vertex SPIR-V: true true
		pixel SPIR-V: true true
		vertex DXIL: true
		pixel DXIL: true
		texture array binding 0 kind 1 count 0
		texture array binding 1 kind 2 count 4
		0 bytes after
		"""

# An array is read where it is: a function takes the index, not the array or one of its textures.

test "a texture array is not a parameter" refuses TextureArrayRead:
	import shaders.arrayparam

	print(shader(arrayparam.pixel).len)

test "an element of a texture array is not an argument" refuses TextureOfArrayRead:
	import shaders.elementarg

	print(shader(elementarg.pixel).len)

test "a material record laid out alike for Vulkan and Direct3D" refuses ShaderMemberOffset("is at byte 16 for Vulkan and 4 for Direct3D"):
	import shaders.badrecord

	print(shader(badrecord.pixel).len)

# The stages are functions of a GPU file of a module the file imports.

test "a struct a pixel stage unpacks from its bits and packs again, on the CPU":
	word = packed.Texel(shade = packed.Shade(args.len + 9), lit = true, layer = 31).toBits()
	print("{word} {packed.Texel.fromBits(word)}")
	prints "2025 Texel(shade = 9, lit = true, layer = 31)"

# A `Quat` is a `vec4` in a shader, `q @ r` the runtime's product of turns, as on the CPU.

# **std/math in a shader.** A stage calls any function whose code the GPU can run (numbers,
# vectors, matrices, structs, fixed arrays, branches, loops): std/math's projections, views,
# turns and frustum tests are compiled for the GPU from the same Zap the CPU runs, the language's
# operations on vectors and matrices the GPU's own instructions.

test "pixel stages: GPU functions of imported modules, range types, packed structs, letter sets, turns, std/math":
	programs = [
		shader(graded.pixel),
		shader(banded.pixel),
		shader(packed.pixel),
		shader(picked.pixel),
		shader(letters.pixel),
		shader(turned.pixel),
		shader(geometry.pixel)
	]
	expect programs.all(not .isEmpty)

# **Compute.** `compute(kernels.sum, 64)` names a compute stage, a function of a GPU file run by
# groups of 64 invocations (`compute(f, x, y[, z])`: x * y * z, 1024 at most), and is the string
# literal of its program: `ZSC1`; the parameter block's size, its parts and textures as a
# program's; each storage buffer (its binding, and 1 when the stage writes it); the groups' size
# (x, y, z); the SPIR-V and the DXIL; the texture arrays. The entry takes its parameters struct (or
# nothing) and gives nothing: it writes storage buffers (`p.totals[i] = v`, a writable buffer an
# unordered access view on Direct3D). Its code reads `globalId`, `localId` and `groupId` (`IVec3`:
# the invocation's place in the whole dispatch, in its group, its group's), `localIndex` (its
# index in its group), `lane` and `laneCount` (its place among the invocations the GPU runs
# together, a subgroup or a wave, and their count). A `mut` variable of a GPU file is the group's
# memory, shared by its invocations (`mut partial f32[64]`); `barrier()` waits for the group's
# invocations, their writes to it seen by all. The lanes that run together combine a number or a
# vector: `x.laneSum()`, `x.laneMin()`, `x.laneMax()`, `x.lanePrefixSum()` (the lanes' before
# this one), `x.laneFirst()`, `x.laneAt(i)`, and a bool's `b.laneAny()` and `b.laneAll()` (any
# stage may combine lanes). A pixel stage's values and discard() are its own, a compute stage's
# values, memory, barrier and writes its own.

test "a compute stage: buffers read and written, the group's memory, a barrier, the lanes' sum":
	describe(compute(kernels.sum, 64))
	prints """
		ZSC1
		parameter bytes 16
		part shaders.kernels.Sums at 0: textures 0+0, buffers 0+2, arrays 0+0
		storage binding 16 written 0
		storage binding 17 written 1
		groups 64 1 1
		compute SPIR-V: true true
		compute DXIL: true
		0 bytes after
		"""

test "a compute stage reads a float's bits and makes one of bits, its local array starting as zeros":
	expect not compute(kernels.halves, 64).isEmpty

test "a compute stage's value in a pixel stage" refuses GpuStageOnly:
	import shaders.misplaced

	code = shader(misplaced.pixel)
	print(code.isEmpty)

test "a compute stage gives nothing" refuses ComputeStage:
	import shaders.misplaced

	kernel = compute(misplaced.counted, 64)
	print(kernel.isEmpty)

# A call's GPU compile ends at its first error, which the compile reports as any other: the
# other calls are compiled still, so one call's error hides none of another's.

test "a call's error laying out its stages hides none of another call's" refuses ComputeStage:
	import shaders.badrecord
	import shaders.misplaced

	print(shader(badrecord.pixel).len)
	print(compute(misplaced.counted, 64).len)

test "a call's error lowering its stages hides none of another call's" refuses TextureOfArrayRead:
	import shaders.arrayparam
	import shaders.elementarg

	print(shader(arrayparam.pixel).len)
	print(shader(elementarg.pixel).len)

# **SPIR-V and DXIL.** The compiler writes SPIR-V itself and checks it with its own validator: a
# texture array is an `OpTypeArray` or `OpTypeRuntimeArray` of sampled images, an index that is not
# a literal makes the access, the texture and an image queried from it `NonUniform`, and the stage
# declares `RuntimeDescriptorArray`, `ShaderNonUniform` and `SampledImageArrayNonUniformIndexing` as
# it needs them (core in SPIR-V 1.5; Vulkan 1.2's `descriptorIndexing`). DXIL goes through HLSL: the
# compiler writes shader model 6.0 HLSL from the same intermediate form (a texture array's index through
# `NonUniformResourceIndex`; 6.6's `ResourceDescriptorHeap` was not taken, it needs the 6.6 profiles
# and a root signature flag) and runs DXC, Microsoft's compiler, found through `dxc` in ZAP_SETUP (the
# program or its dir), else the machine's copy (13.1.1), fetched from Microsoft's latest release by
# the first build that needs it. Results are cached in `build/shaders/` by the HLSL's hash. Without DXC (none
# named, none fetched) the DXIL is empty, a note says so, and only Vulkan can draw the program. The
# engine's RHI (`rhi/`) lays out both backends from the reflection.

test "a DXC that dxc in ZAP_SETUP names and is not there leaves the DXIL empty, and the build says so":
	dir = testProgram(
		"glow/glow.gpu.zap",
		"pub fn pixel(uv Vec2) Vec4:\n\tVec4(uv.x, uv.y, 0.0, 1.0)\n",
		"dxcnote.zap",
		"import glow\n\nprint(shader(glow.pixel).len > 0)\n"
	)
	said = Process.output(
		"{zapPath()} build {dir}dxcnote.zap",
		vars = ["ZAP_SETUP=dxc={dir}nowhere"]
	).out
	print("note: no DXC" in said)
	prints "true"
