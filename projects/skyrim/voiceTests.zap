# The voices of the inn's lines (game/dialogue): every line has its voice file, a lip track follows the words.

import skyrim
import skyrim.actor
import game.dialogue
import game.sim
import world
import engine.gltf
import game

inn = "RiverwoodSleepingGiantInn"
test "every line the inn's actors may say in their hellos and topics has its voice file, every condition function known":
	t = dialogue.talkOfArchives(inn) ?? return
	install = t.vm.install ?? fail("no install")
	lines = 0
	missing = []
	for refId in t.people.keys().sorted():
		if refId == t.vm.rt.world.player: continue
		for line in t.sayable(refId):
			for s in t.spokenLines(refId, line.info):
				lines += 1
				if not s.voice.isEmpty and not install.installHas(s.voice):
					missing.push(s.voice.copy())
	expect lines > 100 and missing.isEmpty
	expect t.unknown.isEmpty

test "a lip track's strongest phonemes follow the words, its targets the head's morphs":
	install = skyrim.installOfArchives() ?? return
	v = install.readVoice("sound/voice/skyrim.esm/malebrute/da10__00023c2d_1.fuz") ??   # "No."
		fail
	seen str[] = []
	for f in v.lip.frames:
		k = f.strongestPhoneme() ?? continue
		if f.weights[k] > 0.3 and (seen.last ?? "") != skyrim.lipPhonemes[k]:
			seen.push(skyrim.lipPhonemes[k].copy())
	expect seen == ["N", "Oh", "OohQ"]
	tri = install.readTriKey("meshes/actors/character/character assets/malehead.tri") ??
		fail
	morphs = tri.morphs.map(.name)
	expect skyrim.lipPhonemes.all(it in morphs)
	expect skyrim.lipModifiers
		.filter(not .startsWith("Head") and not .startsWith("Look"))
		.all(it in morphs)

test "a head's lip targets are morphs of its shapes, and a frame's weights move its vertices within the frame's budget":
	install, plugin = skyrim.installAndPlugin() ?? return
	actors = plugin.cellActors(inn) ?? fail("no {inn}")
	npc = actors.map(plugin.npcOf(.npc) ?? fail).find(.editorId == "Orgnar") ??
		fail("no Orgnar")
	worn = install.npcBodyParts(plugin, npc) ?? fail
	shapes = install.faceShapes(plugin.npcHeadParts(npc) ?? fail, worn)
	targets = skyrim.lipPhonemes.len + skyrim.lipModifiers.len
	expect shapes.len >= 2
	counts = shapes.map(.morphs.len)
	print("Orgnar's lip morphs by shape: {counts}")
	head = shapes.find(.morphs.len == (counts.max() ?? 0)) ?? fail("no shape")
	expect head.morphs.len >= skyrim.lipPhonemes.len + 2
	for k in 0..skyrim.lipPhonemes.len:
		expect head.morphs.any(.target == k)
	model = actor.bodyModel(worn, install.readSkeletonOf(false) ?? fail, []).model
	floats = gltf.skinVertexFloats
	rests = shapes.map(model.vertices[.first * floats..(.first + .count) * floats].copy())
	rest = rests[shapes.indexOf(head) ?? 0]
	still f32[] = fill(targets, 0.0)
	expect head.shapeMoved(rest, still) == rest
	open f32[] = fill(targets, 0.0)
	open[0] = 1.0   # Aah
	moved = head.shapeMoved(rest, open)
	farthest f32 = 0.0
	for v in 0..head.count:
		d = Vec3(moved[v * floats], moved[v * floats + 1], moved[v * floats + 2]) -
			Vec3(rest[v * floats], rest[v * floats + 1], rest[v * floats + 2])
		farthest = farthest.max(d.length())
	expect farthest > 0.1
	worst f32[] = fill(targets, 0.5)
	frame f32[] = fill(targets, 0.0)
	frame[0] = 0.6   # Aah, W and BMP as a lip track's frame has them
	frame[15] = 0.3
	frame[2] = 0.2
	frame[16] = 0.5   # a blink halfway
	frame[17] = 0.5
	for weights in [frame, worst]:
		# the fastest of 100 frames: the cost itself, not the other programs sharing the CPU
		each = 1000.0
		loop 100:
			started = clockSeconds()
			for k, shape in shapes:
				shape.shapeMoved(rests[k], weights)
			each = each.min((clockSeconds() - started) * 1000.0)
		print("a frame's face on the CPU: {each:.3} ms with {weights.count(.abs() > 0.001)} targets on")
		if weights.count(.abs() > 0.001) < 10: expect each < 0.2

test "an actor blinks every few seconds, both eyes closing and opening again":
	shut = 0
	for npc in 0..3:
		for tenth in 0..300:
			w = game.blinkWeight(npc, tenth / 10.0)
			expect w >= 0.0 and w <= 1.0
			if w > 0.5: shut += 1
	expect shut >= 6
	expect game.blinkWeight(0, 0.0) == 0.0
	blink = game.faceWeights(1, none, 0.0)
	expect blink.len == skyrim.lipPhonemes.len + skyrim.lipModifiers.len
	expect blink[skyrim.lipPhonemes.len] == blink[skyrim.lipPhonemes.len + 1]
