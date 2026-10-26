# The dialogue (game/dialogue) of the inn: what its actors say, their topics and the rent.

import fs
import math
import skyrim
import skyrim.esm
import skyrim.nif
import skyrim.actor
import engine
import engine.swf.avm1
import game
import game.sim
import game.dialogue
import interface
import engine.physics
import papyrus
import world

inn = "RiverwoodSleepingGiantInn"

# the inn's dialogue over the archives, read for each test
fn archivesTalk():
	dialogue.talkOfArchives(inn)

fn actorNamed(t dialogue.Talk, editorId str):
	(t.people.values().find(.editorId == editorId) ?? fail("no {editorId} in the inn")).refId

fn topicNames(mut t dialogue.Talk, speaker i64):
	t.topics(speaker).map(t.dialogue.topics[.topic].editorId.copy())

test "Orgnar greets with a line of his own whose voice file reads, its lip track and its sound":
	t = archivesTalk() ?? return
	orgnar = t.actorNamed("Orgnar")
	line = t.greeting(orgnar) ?? fail("Orgnar says nothing")
	expect t.dialogue.quests[t.dialogue.infos[line.info].quest].editorId ==
		"DialogueRiverwood_Revised"
	spoken = t.spokenLines(orgnar, line.info)
	expect spoken.len == 1 and not spoken[0].text.isEmpty
	expect spoken[0].voice.startsWith(
		"sound/voice/skyrim.esm/malebrute/dialogueriverwood_revised__"
	)
	v = dialogue.readVoice(t.vm.install ?? fail("no install"), spoken[0].voice) ?? fail
	expect v.lip.frames.len > 30 and v.seconds > 1.0

test "Orgnar offers the rumors and his goods, the rent once he rents rooms; Delphine rents at a new game":
	t = archivesTalk() ?? return
	orgnar = t.actorNamed("Orgnar")
	topics = t.topicNames(orgnar)
	expect topics == ["TutorialAlchemyPotionTopic", "OfferServicesTopic", "DBRumorsTopic",
		"MG01InitialBranchTopic"]   # as the game's capture lists them
	expect "RentRoomTopic" not in topics   # his rank in JobRentRoomFaction is -1 until Delphine leaves
	expect t.topics(orgnar).any(.prompt == "Heard any rumors lately?")
	expect "DelphineRentRoomTopic" in t.topicNames(t.actorNamed("Delphine"))
	renter = t.plugin.formByEditorId("FACT", "JobRentRoomFaction") ?? fail("no faction")
	at = t.vm.rt.world.actors[orgnar].factions.indexOf(
		actor.Membership(faction = renter, rank = -1)
	) ??
		fail("Orgnar is not listed in JobRentRoomFaction")
	t.vm.rt.world.actors[orgnar].factions[at].rank = 0
	expect "RentRoomTopic" in t.topicNames(orgnar)

test "Orgnar sells his chest's goods at the formula's prices, buys by his list and refuses stolen items":
	t = archivesTalk() ?? return
	orgnar = t.actorNamed("Orgnar")
	player = t.vm.rt.world.player
	vendor = t.vm.rt.world.vendorAt(orgnar) ?? fail("Orgnar has no vendor data")
	expect vendor.chest == 0x7_8C0F and not vendor.onlyStolen and not vendor.notInList
	expect vendor.keywords.sorted() == [0x8_CDEA, 0x8_CDEB, 0xA_0E56]   # food, ingredients, raw food
	expect t.vm.rt.world.vendorGold(vendor) == 100
	apple = 0x6_4B2E
	speech = t.vm.rt.world.actors[player].valueOf("speechcraft")
	factor = 3.3 - 1.3 * f64(speech.min(100.0)) / 100.0
	expect t.vm.rt.world.askingPrice(orgnar, t.vm.rt.world.items[apple]) ==
		i64((3.0 * factor).round())
	expect t.vm.rt.world.askingPrice(orgnar, t.vm.rt.world.items[0x5_08CA]) ==
		i64((20.0 * factor).round())
	stock = t.vm.rt.world.inventories[vendor.chest]
	expect stock.countOf(apple) == 10 and stock.countOf(0x3_4C5E) == 7
	before = t.vm.rt.world.inventories[player].countOf(0xF)
	price = t.vm.rt.world.askingPrice(orgnar, t.vm.rt.world.items[apple])
	expect t.vm.rt.world.buyFrom(orgnar, apple, 4) == none
	expect t.vm.rt.world.inventories[player].countOf(apple) == 4
	expect t.vm.rt.world.inventories[player].countOf(0xF) == before - 4 * price
	expect t.vm.rt.world.inventories[vendor.chest].countOf(apple) == 6
	expect t.vm.rt.world.vendorGold(vendor) == 100 + 4 * price
	expect t.vm.rt.world.buyFrom(orgnar, 0x1_3982, 1) == .NoStock   # the mace is not in his chest
	t.vm.rt.world.inventories[player].takeOut(0xF, 100_000)
	expect t.vm.rt.world.buyFrom(orgnar, apple, 1) == .PlayerPoor
	t.vm.rt.world.inventories[player].addExtra(0x3_4C5E, sim.ItemExtra(count = 2, owner = 0x3_5D44))
	expect t.vm.rt.world.sellTo(orgnar, 0x3_4C5E, 2) == .Stolen
	expect t.vm.rt.world.inventories[player].countOf(0x3_4C5E) == 2
	t.vm.rt.world.inventories[player].addItem(0x1_3982, 1)
	expect t.vm.rt.world.sellTo(orgnar, 0x1_3982, 1) == .NotBought   # not on his list
	expect t.vm.rt.world.sellTo(orgnar, apple, 1) == none   # one of the four
	expect t.vm.rt.world.inventories[player].countOf(0xF) ==
		t.vm.rt.world.payingPrice(orgnar, t.vm.rt.world.items[apple])

test "his goods topic asks for the barter menu once he has answered":
	t = archivesTalk() ?? return
	orgnar = t.actorNamed("Orgnar")
	hello = t.activateActor(orgnar) ?? fail("Orgnar says nothing")
	t.say(orgnar, hello.info)
	expect t.vm.rt.world.barterWith == 0
	goods = (t.menuAfter(orgnar, hello).find(t.dialogue.topics[.topic].editorId == "OfferServicesTopic") ??
			fail("no goods topic")).copy()
	line = t.respond(orgnar, goods.topic) ?? fail("no answer")
	said = t.say(orgnar, line.info)
	expect not said.lines.isEmpty
	expect t.vm.rt.world.barterWith == orgnar

test "renting from Delphine by her dialogue pays 10 gold and makes the bed the player's to sleep in":
	t = archivesTalk() ?? return
	bed = 0x5_EDA7
	player = t.vm.rt.world.player
	a, _ = t.vm.activateRef(bed, player)
	expect a == sim.Activation.Refused("sNoSleepInOwnedBed")
	delphine = t.actorNamed("Delphine")
	hello = t.activateActor(delphine) ?? fail("Delphine says nothing")
	t.say(delphine, hello.info)
	menu = t.menuAfter(delphine, hello)
	rent = (menu.find(t.dialogue.topics[.topic].editorId == "DelphineRentRoomTopic") ??
			fail("no rent topic")).copy()
	expect rent.prompt.endsWith("(10 gold)")
	line = t.respond(delphine, rent.topic) ?? fail("no answer to the rent")
	said = t.say(delphine, line.info)
	expect said.lines[0].text == "Sure thing. It's yours for a day."
	expect said.gold == -10 and said.owners == ["0005EDA7 00000007"]
	b, _ = t.vm.activateRef(bed, player)
	expect b is Used(kind, _, _, _) and kind == nif.furnitureSleep
	again = t.respond(delphine, rent.topic) ?? fail("no answer to a second rent")
	expect t.spokenLines(delphine, again.info)[0].text ==
		"Are you joking? You just rented a room from me."

test "Delphine greets a newcomer to Riverwood at a new game":
	t = archivesTalk() ?? return
	delphine = t.actorNamed("Delphine")
	line = t.greeting(delphine) ?? fail("Delphine says nothing")
	i = t.dialogue.infos[line.info]
	expect t.dialogue.topics[i.topic].subtype == "HELO"
	expect t.dialogue.quests[i.quest].editorId == "DialogueRiverwood_Revised"
	text = t.spokenLines(delphine, line.info)[0].text
	expect text == "You're that visitor, been pokin' around."

frame f32 = 1.0 / 60.0

# the actors need the prepared head and physics only
light = game.Load(textures = false, graph = false, sound = false)

type Inn:
	cell game.PreparedCell
	rs game.Residents
	t dialogue.Talk
	install skyrim.Install

# the inn at 8 of a new game: its actors at their packages and the game's model; none without the
# install
fn readInn() Inn?:
	if not fs.exists(esm.defaultEsm()): return none
	cell = game.openOrPrepare(inn, light)
	cast = cell.head.cast
	rs = cast.newResidents(cast.skeletons.map(.skeletonRig()), cast.skeletons.map(.speeds.copy()),
		8.0, light)
	install = skyrim.openInstall(skyrim.defaultInstall) ?? fail
	plugin = esm.openEsm(install.installPlugin("Skyrim.esm")) ?? fail
	t = dialogue.talkInCell(install, plugin, inn) ?? fail
	t.vm.rt.world.daysPassed = 8.0 / 24.0
	Inn(cell, rs, t, install = skyrim.openInstall(skyrim.defaultInstall) ?? fail)

fn openedInn():
	readInn()

# the inn of the file, a copy of its own for each test
fn withInn():
	openedInn()

fn refOf(t dialogue.Talk, editorId str):
	(t.people.values().find(.editorId == editorId) ?? fail("no {editorId} in the inn")).refId

fn keys(pressed engine.Key[]):
	game.Input(
		forward = 0.0,
		right = 0.0,
		run = false,
		look = IVec2(0, 0),
		pressed = pressed.copy()
	)

# the menu run for this many frames with no input
fn idle(mut d interface.DialogueMenu, mut t dialogue.Talk, frames i64):
	loop frames:
		d.updateDialogue(t, keys([]), frame)

fn text(mut d interface.DialogueMenu, path str):
	match d.p.read(path):
		Str(s): s.copy()
		_: ""

# the texts of the menu's topic list, as its entryList holds them
fn listed(mut d interface.DialogueMenu):
	list = d.p.read("DialogueMenu_mc.TopicListHolder.List_mc.entryList")
	out = []
	if d.p.member(list, "length") is Num(n):
		for k in 0..i64(n):
			match d.p.member(d.p.member(list, "{k}"), "text"):
				Str(s): out.push(s.copy())
				_: out.push("")
	out

# Orgnar's conversation opened in the menu as the player activates him, subtitles on
fn talkToOrgnar(mut inn Inn):
	c = inn.t.startConversation(inn.t.refOf("Orgnar")) ?? fail("Orgnar says nothing")
	d = inn.install.openDialogue(c, true, 1280, 960) ?? fail
	d.idle(inn.t, 60)
	d

orgnarTopics = ["Can I use the alchemy lab?", "What have you got for sale?",
	"Heard any rumors lately?", "Where can I learn more about magic?"]

test "activating Orgnar opens the dialogue menu with his hello's text and his topics, as the game's capture lists them":
	inn = withInn() ?? return
	d = inn.talkToOrgnar()
	orgnar = inn.t.refOf("Orgnar")
	expect inn.t.partner == orgnar   # IsInDialogueWithPlayer
	hello = d.c.lineText() ?? fail("no line said")
	expect not hello.isEmpty and d.text("DialogueMenu_mc.SubtitleText.text") == hello
	expect d.text("DialogueMenu_mc.SpeakerName.text") == "Orgnar"
	expect d.c.topics.map(.prompt.copy()) == orgnarTopics and d.listed() == orgnarTopics

test "choosing the rumors topic by the keys says a line whose FUZ is there, waits its length, then lists the topics after it":
	inn = withInn() ?? return
	d = inn.talkToOrgnar()
	d.idle(inn.t, 360)   # the greeting's 5 s said
	expect d.c.phase == .Choosing and d.text("DialogueMenu_mc.SubtitleText.text").trimmed() == ""
	d.updateDialogue(inn.t, keys([.Down]), frame)
	d.updateDialogue(inn.t, keys([.Down]), frame)
	d.updateDialogue(inn.t, keys([.Enter]), frame)
	expect d.c.phase == .Answering and d.c.chosen == 2
	voice = d.c.lines[0].voice.copy()
	expect voice.indexOf("dbrumorstopic") != none and inn.install.installHas(voice)
	seconds = (inn.install.readVoice(voice) ?? fail).seconds
	answer = d.c.answer ?? fail("no answer")
	waited = 0
	while d.c.phase == .Answering and waited < 1200:
		d.updateDialogue(inn.t, keys([]), frame)
		waited += 1
	expect (f64(waited) * f64(frame) - seconds).abs() < 0.05
	for topic in inn.t.linked(answer.info):
		expect d.c.topics.any(.topic == topic)
	after = ["Can I use the alchemy lab?", "What have you got for sale?",
		"Have you heard any rumors?", "Where can I learn more about magic?"]
	expect d.c.topics.map(.prompt.copy()) == after and d.listed() == after

# the resident of the actor, and the scene's frame run with the player standing at `player`
fn residentOf(inn Inn, editorId str):
	inn.rs.residentOf(inn.cell.head.cast, inn.t.vm.rt.world, inn.t.refOf(editorId))

fn stepScene(mut inn Inn, player Vec3, frames i64):
	evaluate {i64: bool} = {}
	loop frames:
		inn.rs.stepResidents(inn.cell.head.cast, 8.0, 20.0, evaluate, player,
			inn.cell.physics.world, frame)
		inn.cell.physics.world.step(frame)
	_ = inn.rs.placeInWorld(inn.cell.head.cast, inn.t.vm.rt.world)

test "renting from Delphine in her room: she turns to the player, takes 10 gold, and the bed then sleeps":
	inn = withInn() ?? return
	k = inn.residentOf("Delphine")
	player = inn.rs.all[k].body.feetOf() + Vec3(-90.0, -40.0, 0.0)
	settings = skyrim.readIniSettings()
	inn.rs.holdForTalk(k, true, player, settings)
	delphine = inn.t.refOf("Delphine")
	c = inn.t.startConversation(delphine) ?? fail("Delphine says nothing")
	inn.stepScene(player, 90)
	to = player - inn.rs.all[k].body.feetOf()
	expect math.angleBetween(inn.rs.all[k].body.heading, to.x.atan2(to.y)).abs() < 0.05
	rent = c.topics.findIndex(.prompt.endsWith("(10 gold)")) ?? fail("no rent topic")
	gold = inn.t.vm.rt.world.inventories[inn.t.vm.rt.world.player].countOf(0xF)
	c.chooseTopic(inn.t, rent)
	loop 600:
		c.stepConversation(inn.t, frame)
	expect inn.t.vm.rt.world.inventories[inn.t.vm.rt.world.player].countOf(0xF) == gold - 10
	bed, _ = inn.t.vm.activateRef(0x5_EDA7, inn.t.vm.rt.world.player)
	expect bed is Used(kind, _, _, _) and kind == nif.furnitureSleep

test "leaving Orgnar by Tab ends the dialogue and lets his package go on where it held":
	inn = withInn() ?? return
	k = inn.residentOf("Orgnar")
	plan = inn.rs.all[k].plan
	player = inn.rs.all[k].body.feetOf() + Vec3(130.0, 0.0, 0.0)
	d = inn.talkToOrgnar()
	inn.rs.holdForTalk(k, true, player, skyrim.readIniSettings())
	inn.stepScene(player, 120)
	expect inn.rs.all[k].talking and inn.rs.all[k].plan == plan
	d.updateDialogue(inn.t, keys([.Tab]), frame)
	d.idle(inn.t, 30)
	expect d.c.phase == .Ended and d.done and inn.t.partner == 0
	inn.rs.holdForTalk(k, false, player, skyrim.readIniSettings())
	inn.stepScene(player, 60)
	expect not inn.rs.all[k].talking and inn.rs.all[k].plan == plan and inn.rs.all[k].present

test "eight hours slept in the inn pass the clock and PlayerSleepQuest gives Well Rested":
	t = archivesTalk() ?? return
	expect not t.vm.rt.sleepers.isEmpty   # its start-up stage's fragment registered it
	wellRested = t.plugin.formByEditorId("SPEL", "WellRested") ?? fail("no WellRested")
	before = t.vm.rt.world.daysPassed
	t.vm.rt.world.startSleepWait(8, true)
	t.vm.sendSleepStart(before, before + 8.0 / 24.0)
	frames = 0
	while not t.vm.rt.world.stepSleepWait(): frames += 1
	expect frames == 31   # 900 game seconds a frame: 32 frames for 8 hours
	expect (t.vm.rt.world.daysPassed - before - 8.0 / 24.0).abs() < 0.000001
	t.vm.sendSleepStop(false)
	t.vm.runThreads()
	expect wellRested in (t.vm.rt.world.actors[t.vm.rt.world.player].magic.known)
	expect not t.vm.rt.world.shownMessages.isEmpty
