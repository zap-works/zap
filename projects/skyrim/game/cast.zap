# The cast prepared with the cell (world/actorHead.zap): the men's and the women's skeletons with
# the clips every actor moves by, the player and the NPCs worn as the plugin dresses them and
# toned as the game's skin shader does (Community Shaders' Lighting.hlsl: FACEGEN tints the face
# by its FaceGen tint texture, FACEGEN_RGB_TINT the body by the actor's skin tone, HAIR the hair
# by its color), their textures in one table; the markers they use and the navmesh they walk.

import digest
import engine.gltf
import image
import math
import skyrim
import skyrim.esm
import skyrim.hkx
import skyrim.nif
import skyrim.actor
import world
import image.dds

bakedSize = 1024   # the widest a baked normal map is: as near as the third-person camera comes
# the behavior projects whose clips carry the men's and the women's motion
behaviorProjects = ["defaultmale", "defaultfemale"]

# What the cast carries of the behavior graph: the clips every skeleton plays (the gaits, the
# graph's locomotion and turns, each marker's way in, loop and way out, the fight's) and the
# markers' clips by kind.
pub type CastClips:
	names str[]
	markers world.MarkerClips[]

# the clips of the game's graph the cast plays, run through the graph as the game drives it
pub fn castClips(install skyrim.Install, mut plugin esm.Esm) CastClips:
	g = install.readCharacterGraph() ?? fail
	durations = install.clipDurations(g.clipNamesOf())
	out = playerClips.copy()
	seen = g.locomotionClips(durations)
	markers = g.markerClipsOf(plugin, durations, seen)
	for name in seen:
		if name not in out: out.push(name.copy())
	for set in markers:
		for name in [set.enter.copy(), set.looping.copy(), set.leave.copy()]:
			if name not in out: out.push(name.copy())
	for name in g.fightClipNames(durations):
		if name not in out: out.push(name)
	CastClips(names = out, markers)

# how an actor's skin, hair and face are toned: the skin tone (QNAM), the hair's color (HCLF's)
# and the FaceGen tint's archive key ("" for none)
pub type Tones:
	skin Vec3
	hair Vec3?
	faceTint str

# a grey of 0.5 leaves the skin shader's tints as the textures are
pub neutralTone = Vec3(0.5, 0.5, 0.5)
neutralTint u8[] = [128, 128, 128, 255]
blankDetail u8[] = [64, 64, 64, 255]   # the detail map's grey that multiplies by 1

# the hair's color (its CLFM's CNAM) 0..1, none when the actor names none
pub fn hairColorOf(mut plugin esm.Esm, npc actor.Npc) Vec3?:
	c = try plugin.colorOf(npc.hairColor)
	Vec3(f32(c.r), f32(c.g), f32(c.b)) / 255.0

# a root over the skeleton's that stands Skyrim's Z up as the engine's y up (cell.zap's yUp)
fn standUp(mut m gltf.Model):
	root = m.nodes.len
	for mut n in m.nodes:
		if n.parent < 0: n.parent = root
	m.nodes.push(gltf.Node(name = "y up", parent = -1, translation = Vec3(0, 0, 0),
		rotation = Quat.about(Vec3(1, 0, 0), -pi / 2.0), scale = Vec3(1, 1, 1)))
	order = [root]
	order.extend(m.order)
	m.order = order

# the model-space normal maps the worn parts name, decoded, by archive key
type SkinMaps:
	keys str[] = []
	maps image.Image[] = []

fn isModelSpace(path str):
	path.lower().endsWith("_msn.dds")

# every worn part with a model-space normal map given the map's normals at its vertices
fn readSkinNormals(install skyrim.Install, mut worn actor.BodyPart[]):
	out = SkinMaps()
	for i in 0..worn.len:
		for k in 0..worn[i].parts.len:
			path = worn[i].parts[k].normal.copy()
			if not isModelSpace(path): continue
			key = nif.textureKey(path)
			if key not in out.keys:
				out.keys.push(key.copy())
				out.maps.push((install.installTexture(key) ?? fail).decodeLevel(0))
			worn[i].parts[k].readNormals(out.maps[out.keys.indexOf(key) ?? 0])
	out

# The texture of the material's model-space map baked into one of the surface's bends, masked by
# the highlight's map its material names, else the one beside it (x_msn.dds: x_s.dds); one per
# body, its bends its own.
fn bakedIndex(install skyrim.Install, worn actor.BodyPart[], m actor.BodyMaterial, maps SkinMaps,
	owner str, mut table TextureTable, mut body u8[]):
	path = m.normal
	key = nif.textureKey(path)
	msn = maps.maps[maps.keys.indexOf(key) ?? fail("{key} was not read")]
	parts = worn.flatMap(.parts.filter(.normal == path).map(.copy()))
	maskKey = nif.textureKey(m.shading.specularMap) if not m.shading.specularMap.isEmpty
		else "{key[..key.len - 8]}_s.dds"
	label = "{key} bent for {owner}"
	width = msn.width.min(bakedSize)
	height = msn.height * width / msn.width
	inputs = digest.sha1(parts.toBytes())
	kept = table.cache.bakeKey(install, [key.copy(), maskKey.copy()], "{width}x{height} {inputs}")
	if table.keptIndex(label, kept, body) is k: return k
	mask image.Image? = none
	if install.installTexture(maskKey) is d: mask = d.decodeLevel(0)
	baked = actor.bakeBends(parts, msn, mask, width, height)
	index = table.imageIndex(label, baked, body)
	keep(kept, table.textures[index], body)
	index

# the face's tint and detail textures: its FaceGen tint (else a grey that leaves it as it is)
# and the detail map its model names (else a grey that multiplies by 1)
fn faceMaps(install skyrim.Install, m actor.BodyMaterial, tones Tones, mut table TextureTable,
	mut body u8[]):
	neutral = table.flatIndex("neutral tint", neutralTint, body)
	blank = table.flatIndex("blank detail", blankDetail, body)
	tint = table.textureIndex(install, tones.faceTint, neutral, body)
	(tint, table.textureIndex(install, m.shading.detailMap, blank, body))

fn materialOf(m actor.BodyMaterial, install skyrim.Install, worn actor.BodyPart[],
	maps SkinMaps, tones Tones, owner str, mut table TextureTable, mut body u8[]):
	normalMap = install.bakedIndex(worn, m, maps, owner, table, body)
		if isModelSpace(m.normal) else table.textureIndex(install, m.normal, flatNormal, body)
	tone = m.shading.tone
	tint, detail = 0, 0
	if tone == nif.toneFace: tint, detail = install.faceMaps(m, tones, table, body)
	toneColor = m.shading.toneColor
	if tone == nif.toneSkin: toneColor = tones.skin
	if tone == nif.toneHair: toneColor = tones.hair ?? m.shading.toneColor
	world.ActorMaterial(
		diffuse = table.textureIndex(install, m.diffuse, flatDiffuse, body),
		normalMap,
		look = install.preparedLook(m.shading, m.specularStrength, m.glossiness, table, body),
		cutout = m.cutout,
		tone,
		toneColor,
		tintMap = tint,
		detailMap = detail
	)

# The worn models as a body on the skeleton (the cast's `skeleton`), `scale` times its height,
# toned and its textures laid in the table; `owner` names its own baked maps.
pub fn prepareBody(
	install skyrim.Install,
	mut worn actor.BodyPart[],
	skeletons hkx.Skeleton[],
	skeleton i64,
	scale f32,
	tones Tones,
	faces actor.FaceShape[],
	owner str,
	mut table TextureTable,
	mut body u8[]
) world.ActorHead:
	maps = install.readSkinNormals(worn)
	m = actor.bodyModel(worn, skeletons[skeleton], [])
	m.model.standUp()
	materials = m.materials.map(.materialOf(install, worn, maps, tones, owner, table, body))
	world.ActorHead(
		body = world.actorBodyOf(m.model),
		materials,
		skeleton,
		scale,
		faces = faces.copy()
	)

# how each clip carries the actor of the behavior project (none for one whose motion the files do
# not give)
fn clipMotions(install skyrim.Install, project str, names str[]):
	motions = install.readMotions(project, names) ?? return fill(names.len, actor.stillMotion())
	motions.map(it ?? actor.stillMotion())

# A skeleton (the women's when `female`) with the clips given (the cast's) the archives have for it.
pub fn prepareSkeleton(
	install skyrim.Install,
	female bool,
	clips str[]
) (hkx.Skeleton, world.SkeletonHead):
	skeleton = install.readSkeletonOf(female) ?? fail
	animations = []
	names = []
	for name in clips:
		match install.readActorAnimation(name, female):
			a:
				animations.push((name.copy(), a))
				names.push(name.copy())
			error: eprint("no clip: {error}")
	m = actor.bodyModel([], skeleton, animations)
	m.model.standUp()
	motions = install.clipMotions(behaviorProjects[1 if female else 0], names)
	speeds = motions.map(.speedOf())
	ragdoll hkx.Ragdoll? = none
	match install.readRagdollOf(female):
		r: ragdoll = r
		error: eprint("no ragdoll: {error}")
	(
		skeleton.copy(),
		world.SkeletonHead(rig = world.actorBodyOf(m.model), motions, speeds, bones = skeleton,
			ragdoll)
	)

# the AI's game settings, the plugin's (the executable's own defaults where it sets none are not
# read: those below stand in)
fn aiSettingsOf(mut plugin esm.Esm):
	s = plugin.gameSettings()
	at = (name str, otherwise f64): f32(s.get(name) ?? otherwise)
	world.AiSettings(
		dwellBase = at("fsandboxdurationbase", 0.2),
		dwellFurniture = at("fsandboxdurationmultfurniture", 3.0),
		dwellIdleMarker = at("fsandboxdurationmultidlemarker", 1.5),
		trackSpeedMin = at("fheadtrackspeedmin", 60.0),
		trackSpeedMinAngle = at("fheadtrackspeedminangle", 5.0),
		trackSpeedMax = at("fheadtrackspeedmax", 200.0),
		trackSpeedMaxAngle = at("fheadtrackspeedmaxangle", 10.0)
	)

# The cast of the cell prepared, its textures laid in the body: the player facing `focus` (Z up)
# from its load door, the actors the cell places and those its packages bring, the markers and
# the navmesh.
pub fn prepareCast(
	install skyrim.Install,
	mut plugin esm.Esm,
	cell esm.Cell,
	focus Vec3,
	cache TextureCache,
	mut body u8[]
) world.CastHead:
	table = newTextureTable(body)
	table.cache = cache.copy()
	clips = install.castClips(plugin)
	male, maleHead = install.prepareSkeleton(false, clips.names)
	female, femaleHead = install.prepareSkeleton(true, clips.names)
	skeletons = [male, female]
	player = install.preparePlayer(plugin, skeletons, table, body)
	start, heading = plugin.startOf(cell, focus)
	npcs = install.prepareNpcs(plugin, cell, skeletons, table, body)
	for missing in table.missing:
		eprint("no texture: {missing}")
	world.CastHead(
		textures = table.textures.copy(),
		skeletons = [maleHead, femaleHead],
		player,
		start,
		heading,
		npcs,
		markers = install.prepareMarkers(plugin, cell),
		markerClips = clips.markers.copy(),
		doors = plugin.prepareDoors(cell),
		navmesh = plugin.cellNavmesh(cell.editorId) ?? fail("no navmesh for {cell.editorId}"),
		ai = plugin.aiSettingsOf()
	)
