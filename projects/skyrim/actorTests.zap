# The inn's NPCs: their records, bodies, FaceGen heads and packages.

import fs
import skyrim
import skyrim.esm
import skyrim.nif
import skyrim.actor
import game.sim

inn = "RiverwoodSleepingGiantInn"

type InnActors:
	install skyrim.Install
	plugin esm.Esm
	actors sim.CellActor[]

# the install, its plugin and the inn's actors, read once for the file; none without the install
fn readInnActors() InnActors?:
	install, plugin = try skyrim.installAndPlugin()
	actors = plugin.cellActors(inn) ?? fail("no {inn}")
	InnActors(install, plugin, actors)

fn innActors():
	readInnActors()

fn placedActor(actors sim.CellActor[], mut plugin esm.Esm, editorId str):
	at = -1
	for k, a in actors:
		if (plugin.npcOf(a.npc) ?? fail).editorId == editorId: at = k
	if at < 0: fail("no {editorId} in the inn")
	actors[at].copy()

test "the inn places Orgnar, Delphine and Embry, and its packages bring Sven, Alvor and Hod":
	g = innActors() ?? return
	editorIds = g.actors.map((g.plugin.npcOf(.npc) ?? fail).editorId)
	for name in ["Orgnar", "Delphine", "Embry"]:
		expect g.actors.placedActor(g.plugin, name).achr != none
	for name in ["Sven", "Alvor", "Hod"]:
		expect name in editorIds and g.actors.placedActor(g.plugin, name).achr == none

test "Orgnar and Delphine wear their outfits over their race's skin with their baked heads, every bone in the skeleton":
	g = innActors() ?? return
	skeleton = g.install.readCharacterSkeleton() ?? fail
	names = g.install.readNames("Skyrim.esm") ?? fail
	for (name, race, female, clothes) in [
		("Orgnar", "NordRace", false, "clothes/barkeeper/m/torso_1.nif"),
		("Delphine", "BretonRace", true, "clothes/farmclothes04/robef_1.nif")
	]:
		a = g.actors.placedActor(g.plugin, name)
		look = g.install.npcLook(g.plugin, names, g.plugin.npcOf(a.npc) ?? fail)
		expect look.name == name and look.race == race and look.female == female
		expect look.faceGeom != "" and look.faceTint != ""
		body = g.install.npcParts(g.plugin, a.achr ?? fail("not placed")) ?? fail
		slots = body.map(.slot)
		for slot in ["BODY", "Hands", "Feet", "FaceGen"]:
			expect slot in slots
		expect body.any(.model.endsWith(clothes))
		for b in body:
			expect not b.parts.isEmpty
			for p in b.parts:
				expect p.unmatchedBones(skeleton).isEmpty and p.skinToBone.len == p.boneNames.len

# the mean distance between the vertices of two parts of the same mesh
fn meanDistance(a nif.Part, b nif.Part):
	(0..a.positions.len).map((a.positions[it] - b.positions[it]).length()).sum() /
		f32(a.positions.len)

test "Orgnar's head morphed from his sliders and presets is his baked head, and its triangles are short":
	g = innActors() ?? return
	npc = g.plugin.npcOf(g.actors.placedActor(g.plugin, "Orgnar").npc) ?? fail
	baked = g.install.readModel(actor.faceGeomKey("Skyrim.esm", npc.formId)) ?? fail
	race = g.plugin.recordOf(npc.race) ?? fail("no race")
	weights = npc.faceMorphWeights(esm.textOf(race.body, race.fields, "EDID"))
	heads = (g.plugin.npcHeadParts(npc) ?? fail).filter(.headKind() == "Face").map(.copy())
	morphed = g.install.morphedHead(heads, weights) ?? fail
	head = morphed[0].parts[0]
	bakedHead = baked.drawParts().find(.name == "MaleHeadNord") ??
		fail("no head in the baked model")
	expect head.positions.len == bakedHead.positions.len
	expect head.meanDistance(bakedHead) < 0.01
	for t in 0..head.indices.len / 3:
		c = (0..3).map(head.positions[i64(head.indices[t * 3 + it])])
		expect (c[0] - c[1]).length() < 4.0 and (c[1] - c[2]).length() < 4.0

test "Orgnar sandboxes behind his counter at noon and at 2 (no sleep package), Delphine and Embry sleep at 2":
	g = innActors() ?? return
	cell = g.plugin.findCell(inn) ?? fail("no {inn}")
	orgnar = g.actors.placedActor(g.plugin, "Orgnar")
	packages = g.plugin.npcPackages(orgnar.achr ?? fail("not placed"))
	for hour in [f32(12.0), 2.0]:
		p = actor.activePackage(packages, hour, 0) ?? fail("no package at {hour}")
		expect p.editorId == "OrgnarWorkInn0x24" and "Sandbox" in p.procedures
		place = p.location ?? fail("no location")
		expect place.kind == 0 and cell.refs.any(.formId == place.form)
	for (name, sleep) in [("Delphine", "DelphineSleep0x6"), ("Embry", "EmbrySleep0x7")]:
		a = g.actors.placedActor(g.plugin, name)
		p = actor.activePackage(g.plugin.npcPackages(a.achr ?? fail("not placed")), 2.0, 0)
		expect (p ?? fail("no package")).editorId == sleep and "Sleep" in (p ?? fail("")).procedures
	delphine = g.plugin.npcPackages(g.actors.placedActor(g.plugin, "Delphine").achr ?? fail(""))
	expect (actor.activePackage(delphine, 12.0, 0) ?? fail("")).editorId ==
		"DelphineInnServices6x18"
	start = g.plugin.activePackageAtStart(delphine, 12.0, 0, 0x1_3163) ?? fail("none at start")
	expect start.editorId == "DelphineStartInRoom"

test "a schedule takes in the hours from its start for its duration, past midnight too":
	night = actor.Schedule(
		month = -1,
		dayOfWeek = -1,
		date = 0,
		hour = 22,
		minute = 0,
		duration = 240
	)
	expect night.scheduleMatches(23.5, 0) and night.scheduleMatches(1.0, 3)
	expect not night.scheduleMatches(2.0, 0) and not night.scheduleMatches(12.0, 0)
	weekdays = actor.Schedule(
		month = -1,
		dayOfWeek = 7,
		date = 0,
		hour = -1,
		minute = -1,
		duration = 0
	)
	expect weekdays.scheduleMatches(12.0, 1) and not weekdays.scheduleMatches(12.0, 0)

# the vertices on the part's open edges (an edge of one triangle only)
fn openEdgeVertices(p nif.Part):
	edges {str: i64} = {}
	for t in 0..p.indices.len / 3:
		for e in 0..3:
			a, b = i64(p.indices[t * 3 + e]), i64(p.indices[t * 3 + (e + 1) % 3])
			edges.add("{a.min(b)} {a.max(b)}", 1)
	out {i64: bool} = {}
	for key, count in edges:
		if count != 1: continue
		for v in key.split(" "):
			out[i64.parse(v) ?? 0] = true
	out.keys().sorted()

test "the baked heads sit on the necks: the neck's open edge meets the body's at the idle's first frame":
	g = innActors() ?? return
	skeleton = g.install.readCharacterSkeleton() ?? fail
	worlds = skeleton.framePose(g.install.readMaleAnimation("mt_idle") ?? fail, 0)
	for name in ["Orgnar", "Delphine"]:
		npc = g.plugin.npcOf(g.actors.placedActor(g.plugin, name).npc) ?? fail
		body = g.install.npcBodyParts(g.plugin, npc) ?? fail
		heads = (g.plugin.npcHeadParts(npc) ?? fail).filter(.headKind() == "Face")
		faceName = esm.textOf(heads[0].body, heads[0].fields, "EDID")
		posed = actor.posedParts(body, skeleton, worlds)
		head = posed.find(.name == faceName) ?? fail("no {faceName}")
		lowest = head.positions.map(.z).min() ?? 0.0
		rest = posed.filter(.name != faceName and "body" in .diffuse.lower())
		others = nif.partPositions(rest)
		worst f32 = 0.0
		for v in head.openEdgeVertices():
			p = head.positions[v]
			if p.z > lowest + 4.0: continue
			nearest = others.map((it - p).length()).min() ?? 1.0e9
			worst = worst.max(nearest)
		expect worst < 0.5

# The items and their activation (game/sim), with the scripts bound (papyrus).
