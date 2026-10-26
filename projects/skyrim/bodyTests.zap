# The player's body: its worn models over the skeleton, posed by the CPU and by the engine's palette.

import fs
import math
import skyrim
import skyrim.esm
import skyrim.hkx
import skyrim.nif
import skyrim.actor
import engine
import engine.gltf
import game

fn withPlayer() (skyrim.Install, actor.BodyPart[], hkx.Skeleton)?:
	if not fs.exists(esm.defaultEsm()): return none
	install = skyrim.openInstall(skyrim.defaultInstall) ?? fail
	plugin = esm.openEsm(esm.defaultEsm()) ?? fail
	body = install.playerParts(plugin) ?? fail
	skeleton = install.readCharacterSkeleton() ?? fail
	(install, body, skeleton)

test "the player wears the prisoner's clothes over a Nord's hands and head, every bone in the skeleton":
	_, body, skeleton = withPlayer() ?? return
	models = body.map(.model)
	for key in [
		"clothes/prisoner/prisonerclothes_1.nif",
		"character assets/malehands_1.nif",
		"character assets/malehead.nif"
	]:
		expect models.any(.endsWith(key))
	expect not models.any(.endsWith("malebody_1.nif"))
	binds = skeleton.bindPose()
	for b in body:
		expect not b.parts.isEmpty
		for p in b.parts:
			expect p.unmatchedBones(skeleton).isEmpty and p.skinToBone.len == p.boneNames.len
			if b.slot == "Hands" or b.slot == "Face":
				posed = p.skinVertices(p.partBoneWorlds(skeleton, binds), p.skinToBone)
				expect (0..posed.len).all((posed[it] - p.positions[it]).length() < 0.01)

test "at the idle's first frame the body stands about 128 units tall, no vertex pulled from its bones":
	install, body, skeleton = withPlayer() ?? return
	idle = install.readMaleAnimation("mt_idle") ?? fail
	worlds = skeleton.framePose(idle, 0)
	posed = actor.posedParts(body, skeleton, worlds)
	lo, hi = nif.partPositions(posed).boundsOf()
	expect hi.z - lo.z > 110.0 and hi.z - lo.z < 140.0 and lo.z.abs() < 5.0
	expect hi.x - lo.x < 80.0 and hi.y - lo.y < 80.0
	k = 0
	for b in body:
		for p in b.parts:
			expect p.largestReach(posed[k].positions, p.partBoneWorlds(skeleton, worlds)) < 60.0
			k += 1

test "the engine's palette poses the body model as the CPU skinning does":
	install, body, skeleton = withPlayer() ?? return
	walk = install.readMaleAnimation("mt_walkforward") ?? fail
	expected = nif.partPositions(actor.posedParts(body, skeleton, skeleton.framePose(walk, 17)))
	at = 17.0 * walk.frameDuration
	m = actor.bodyModel(body, skeleton, [("mt_walkforward", walk)])
	expect m.model.vertices.len % gltf.skinVertexFloats == 0 and not m.materials.isEmpty
	expect expected.len == m.model.vertices.len / gltf.skinVertexFloats
	vertices = m.model.vertices
	rig = m.model.rigOf()
	rows = []
	rig.posePalette(engine.Pose(clip = 0, time = at), rows)
	for v in (0..expected.len step 7):
		expect (skinnedAt(vertices, rows, v) - expected[v]).length() < 0.05

# vertex v of a skinned model's vertices (gltf.skinVertexFloats each) moved by the palette's rows
fn skinnedAt(vertices f32[], rows f32[], v i64):
	at = v * gltf.skinVertexFloats
	p = Vec3(0.0, 0.0, 0.0)
	for k in 0..4:
		e = i64(vertices[at + 14 + k]) * 12
		w = vertices[at + 18 + k]
		for r in 0..3:
			p[r] += w *
				(rows[e + r * 4] * vertices[at] + rows[e + r * 4 + 1] * vertices[at + 1] +
						rows[e + r * 4 + 2] * vertices[at + 2] + rows[e + r * 4 + 3])
	p

# The root (NPC Root) stands at the feet: walking, a foot is always on its floor; halfway into the
# run, a foot of the blend sinks no more than a few units.
test "the palette of the walk eased into the run is finite, the lowest foot on the root's floor":
	install, body, skeleton = withPlayer() ?? return
	m = actor.bodyModel(body, skeleton, [])
	_, men = install.prepareSkeleton(false, game.playerClips)
	m.model.clips = men.rig.clips
	vertices = m.model.vertices
	rig = m.model.rigOf()
	gaits = game.gaitsOf(rig.clips, [])
	for cycle in [f32(0.0), 0.3, 0.7]:
		player = game.Player(controller = game.playerController(Vec3(0, 0, 0)), heading = 0.0,
			gaits, gait = 1.5, cycle)
		rows = []
		rig.posePalette(player.poseOf(), rows)
		expect rows.all(hkx.isFinite)
		lowest = (0..vertices.len / gltf.skinVertexFloats)
			.map(skinnedAt(vertices, rows, it).z)
			.min() ??
			0.0
		expect lowest.abs() < 4.0
