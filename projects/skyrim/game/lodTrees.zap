# The distant trees of an exterior world as SkyrimSE.exe's BGSDistantTreeBlock reads them: the
# world's tree list (Meshes\Terrain\<world>\Trees\<world>.lst: a count, then per kind eight words:
# its number, the billboard's width and height, and the atlas rectangle's left, top, right and
# bottom, then a pad word), each level 4 block's tree file (<world>.4.<x>.<y>.btt: a count of
# groups, each a kind and a count of instances of 32 bytes: x, y, z, turn, scale, the reference, and
# eight bytes the game does not read here), and the atlas Textures\Terrain\<world>\Trees\
# <world>TreeLOD.dds. A kind's mesh is two crossed vertical quads, width wide and height high
# (0x14050c410), drawn by shaders/treeLod.gpu.zap. Trees within fTreeLoadDistance of the eye.
#
# The way in, for the cell agent:
#   t = install.treesOf("tamriel", eye, loaded, settings)   the distant trees seen from the eye
#   sc.showTrees(t)                                         into the cell's scene

import skyrim
import world
import world.shaders

treeLoadDistance = "fTreeLoadDistance:TerrainManager"

# a kind of distant tree: its billboard's size in game units and its rectangle of the atlas
pub type TreeKind:
	width f32
	height f32
	left f32
	top f32
	right f32
	bottom f32

# a placed tree: its kind, where it stands (z up), its turn about the vertical, its scale and the
# reference it stands for
pub type TreeInstance:
	kind i64
	place Vec3
	turn f32
	scale f32
	reference i64

listEntryBytes = 32
instanceBytes = 32

# the kinds of a tree list file
pub fn treeKinds(lst u8[]) TreeKind[]:
	out = []
	for k in 0..i64(lst.u32le(0)):
		at = 4 + k * listEntryBytes
		out.push(
			TreeKind(
				width = lst.f32le(at + 4),
				height = lst.f32le(at + 8),
				left = lst.f32le(at + 12),
				top = lst.f32le(at + 16),
				right = lst.f32le(at + 20),
				bottom = lst.f32le(at + 24)
			)
		)
	out

# the trees of a block's file
pub fn treeInstances(btt u8[]) TreeInstance[]:
	out = []
	at = 4
	loop i64(btt.u32le(0)):
		kind = i64(btt.u32le(at))
		count = i64(btt.u32le(at + 4))
		at += 8
		loop count:
			out.push(
				TreeInstance(
					kind,
					place = Vec3(btt.f32le(at), btt.f32le(at + 4), btt.f32le(at + 8)),
					turn = btt.f32le(at + 12),
					scale = btt.f32le(at + 16),
					reference = btt.u32le(at + 20)
				)
			)
			at += instanceBytes
	out

# The distant trees seen from an eye: the vertices of their crossed quads, the triangles, and the
# atlas.
pub type Trees:
	vertices shaders.TreeVertex[]
	indices u32[]
	atlas world.PreparedTexture
	body u8[]
	count i64

# the corners of one quad of a kind: (x, z) across and up, and its normal; `along` x or y
fn addQuad(
	mut t Trees,
	k TreeKind,
	i TreeInstance,
	place Vec3,
	along bool,
	atlas f32
):
	half = k.width * 0.5
	first = u32(t.vertices.len)
	plane = Vec3(0.0, 1.0, 0.0) if along else Vec3(1.0, 0.0, 0.0)
	instance = Vec4(i.turn.cos(), i.turn.sin(), i.scale, atlas)
	for row in 0..2:
		for column in 0..2:
			across = (f32(column) * 2.0 - 1.0) * half
			up = k.height * (1.0 - f32(row))
			t.vertices.push(
				shaders.TreeVertex(
					place,
					corner = Vec3(across, 0.0, up) if along else Vec3(0.0, across, up),
					uv = Vec2(k.left if column == 0 else k.right, k.top if row == 0 else k.bottom),
					plane,
					instance
				)
			)
	for corner in [0, 1, 2, 1, 3, 2]:
		t.indices.push(first + u32(corner))

fn toEngine(p Vec3):
	Vec3(p.x, p.z, -p.y)

# The distant trees of the world's blocks within the loading distance of the eye, the loaded
# area's cells left to the near trees.
pub fn treesOf(
	install skyrim.Install,
	world str,
	eye Vec2,
	area LoadedArea,
	settings skyrim.IniSettings
) Trees:
	body = []
	table = newTextureTable(body)
	reach = f32(settings.iniNumber(treeLoadDistance))
	capital = "{world[..1].upper()}{world[1..]}"
	atlasPath = "Data\\Textures\\Terrain\\{capital}\\Trees\\{capital}TreeLOD.DDS"
	atlas = table.textureIndex(install, atlasPath, flatDiffuse, body)
	kinds = treeKinds(install.installRead("meshes/terrain/{world}/trees/{world}.lst") ?? [])
	t = Trees(
		vertices = [],
		indices = [],
		atlas = table.textures[atlas].copy(),
		body = [],
		count = 0
	)
	smallest = lodLevels[0]
	for y in floorTo(eye.y - reach, smallest) / smallest..=floorTo(eye.y + reach, smallest) /
		smallest:
		for x in floorTo(eye.x - reach, smallest) / smallest..=floorTo(eye.x + reach, smallest) /
			smallest:
			b = LodBlock(smallest, x * smallest, y * smallest)
			if eye.nearestSquared(b) > reach * reach or b.coveredBy(area): continue
			bytes = install.installRead(lodKey(world, "btt", b)) ?? continue
			for i in treeInstances(bytes):
				if i.kind >= kinds.len or area.holds(i.place): continue
				place = i.place.toEngine()
				t.addQuad(kinds[i.kind], i, place, true, 0.0)
				t.addQuad(kinds[i.kind], i, place, false, 0.0)
				t.count += 1
	t.body = body
	t

# the distant trees in the scene: the atlas sent to the GPU, drawn with the cell
pub fn showTrees(mut sc world.CellScene, t Trees):
	sc.addTreeMesh(t.vertices, t.indices, world.gpuTexture(t.body, t.atlas))
