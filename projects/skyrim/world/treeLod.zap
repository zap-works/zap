# The distant trees on the GPU: the crossed quads of every tree in one buffer, the atlas sent with its
# levels and read by index (bindless) among the cell's, drawn after the distant land and objects
# (shaders/treeLod.gpu.zap), both sides of each quad.

import engine
import world.shaders

# The vertex stage and the pixel stage of the distant trees, one program for every batch of a scene.
pub fn newTreeProgram() engine.Program:
	engine.newProgram(shader(shaders.treeVertex, shaders.treePixel))

# a vertex with its atlas index moved by `by` (the atlas joined to a longer list)
fn shifted(v shaders.TreeVertex, by f32):
	shaders.TreeVertex(
		place = v.place,
		corner = v.corner,
		uv = v.uv,
		plane = v.plane,
		instance = Vec4(v.instance.x, v.instance.y, v.instance.z, v.instance.w + by)
	)

# The distant trees added to a scene: the atlas joins the cell's textures, which the vertices index
# from where the cell's end.
pub fn addTreeMesh(
	mut sc CellScene,
	vertices shaders.TreeVertex[],
	indices u32[],
	move atlas engine.GpuTexture
):
	first = f32(sc.params.textures.len)
	sc.params.textures.push(atlas.texture())
	draw = newMeshDraw(vertices.map(.shifted(first)), indices)
	draw.textures = [atlas]
	sc.treeDraws.push(draw)

pub fn drawTrees(mut r engine.Renderer, sc CellScene):
	if sc.treeDraws.isEmpty: return
	program = sc.treeProgram
	program.setParams(sc.params)
	for t in sc.treeDraws:
		r.setDepth(true, true, false)
		r.drawIndexed(program, t.model, t.indices, t.indices.count)
