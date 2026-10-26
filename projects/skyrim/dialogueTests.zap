# The dialogue's rules without the game: conditions on a world made by hand (their OR groups, the
# run-on target, globals, what is never asked), the choice of a topic's response (say once,
# random), and the voice files' names.

import fs
import skyrim
import skyrim.esm
import skyrim.actor
import game.sim
import game.dialogue
import papyrus

speaker = 0x100
speakerBase = 0x200
faction = 0x300
quest = 0x400
cost = 0x500

# a plugin of only its header, for a talk whose records are made by hand
fn emptyPlugin():
	path = "{testDir()}empty.esm"
	header u8[] = [84, 69, 83, 52]
	loop 20:
		header.push(0)
	fs.writeBytes(path, header) ?? fail("cannot write {path}")
	esm.openEsm(path) ?? fail

# a world of the speaker (in the faction at rank `rank`) and the player with gold
fn handTalk(rank i64) dialogue.Talk:
	vm = papyrus.newVm(none)
	w = sim.newWorld()
	for refId in [speaker, w.player]:
		w.addForm(refId)
	w.actors[speaker] = sim.ActorState(
		npc = speakerBase,
		race = 0,
		level = 1,
		values = {},
		factions = [actor.Membership(faction, rank)]
	)
	w.actors[w.player] = sim.ActorState(npc = 7, race = 0, level = 1, values = {})
	w.ensureInventory(w.player)
	w.inventories[w.player].addItem(0xF, 10)
	w.globals[cost] = 10.0
	w.stages[quest] = 20
	w.runningQuests[quest] = true
	vm.rt.world = w
	names = skyrim.Strings(texts = {})
	lines = skyrim.Strings(texts = {})
	dialogue.newTalk(emptyPlugin(), vm, names, lines, 0)

fn cond(function i64, param1 i64, op i64, value f32):
	esm.Condition(
		op,
		orNext = false,
		useGlobal = false,
		value,
		global = 0,
		function,
		param1,
		param2 = 0,
		runOn = 0,
		reference = 0
	)

fn holds(mut t dialogue.Talk, conditions esm.Condition[]) bool:
	t.conditionsHold(
		conditions,
		dialogue.Scope(subject = speaker, target = t.vm.rt.world.player, quest = quest)
	)

test "a condition's OR group binds before the AND, the faction's rank -1 keeping the actor out":
	t = handTalk(0)
	isOther = cond(72, 0x999, 0, 1.0)
	isOther.orNext = true
	conditions = [isOther, cond(72, speakerBase, 0, 1.0), cond(71, faction, 0, 1.0)]
	expect t.holds(conditions)
	expect not t.holds([cond(72, 0x999, 0, 1.0)])
	out = handTalk(-1)
	expect not out.holds(conditions)

test "stages, globals and the target's gold compare as the conditions say":
	t = handTalk(0)
	expect t.holds([cond(58, quest, 3, 20.0), cond(56, quest, 0, 1.0)])
	expect not t.holds([cond(58, quest, 2, 20.0)])
	gold = cond(47, 0xF, 3, 0.0)
	gold.runOn = esm.runTarget
	gold.useGlobal = true
	gold.global = cost
	expect t.holds([gold.copy()])
	t.vm.rt.world.globals[cost] = 11.0
	expect not t.holds([gold.copy()])
	gold.swap = true
	expect not t.holds([cond(47, 0xF, 3, 1.0)])   # the speaker has none

test "a function without an implementation gives 0 and is counted, unless a failed group came first":
	t = handTalk(0)
	expect not t.holds([cond(72, 0x999, 0, 1.0), cond(1023, 0, 0, 1.0)])
	expect t.unknown.isEmpty
	expect t.holds([cond(1023, 0, 0, 0.0)])
	expect t.unknown[1023] == 1

fn handInfo(id i64, flags i64, conditions esm.Condition[]):
	dialogue.Info(
		formId = id,
		topic = 0x600,
		quest = quest,
		flags,
		resetHours = 0.0,
		links = [],
		sharedInfo = 0,
		responses = [],
		conditions = conditions.copy(),
		promptId = 0,
		speaker = 0,
		vmad = []
	)

test "a topic gives its first line that may be said, a say-once line once":
	t = handTalk(0)
	t.dialogue.quests[quest] = dialogue.Quest(
		formId = quest,
		editorId = "HandQuest",
		flags = 0,
		priority = 0,
		conditions = [],
		stages = [],
		startStage = 0,
		aliases = [],
		vmad = []
	)
	t.dialogue.infos[0x601] = handInfo(0x601, dialogue.flagSayOnce, [])
	t.dialogue.infos[0x602] = handInfo(0x602, 0, [cond(72, 0x999, 0, 1.0)])
	t.dialogue.infos[0x603] = handInfo(0x603, 0, [])
	t.dialogue.topics[0x600] = dialogue.Topic(
		formId = 0x600,
		editorId = "HandTopic",
		quest = quest,
		branch = 0,
		priority = 50.0,
		category = 0,
		subtype = "CUST",
		nameId = 0,
		infos = [0x601, 0x602, 0x603]
	)
	expect t.chooseInfo(0x600, speaker) == 0x601
	t.say(speaker, 0x601)
	expect t.chooseInfo(0x600, speaker) == 0x603
	expect t.talkedTo[speaker]

test "a voice key keeps 25 letters of the quest and the topic, the quest's first 10 when too long":
	expect dialogue.voiceKey("MaleBrute", "DialogueGeneric", "RentRoomTopic", 0x7_9B1A, 1) ==
		"sound/voice/skyrim.esm/malebrute/dialoguege_rentroomtopic_00079b1a_1.fuz"
	expect dialogue.voiceKey(
		"MaleBrute",
		"DialogueRiverwood_Revised",
		"DelphineRumorsBranchRevisedTopic",
		0x4_53ED,
		1
	) == "sound/voice/skyrim.esm/malebrute/dialogueri_delphinerumorsb_000453ed_1.fuz"
	expect dialogue.voiceStem("DA01Intro", "DA01IntroRumorsTopic") == "da01intro_da01introrumorst"
	expect dialogue.voiceStem("CR04", "CR04DoesntMatterNowDoesIt") == "cr04_cr04doesntmatternowdo"
	expect dialogue.voiceStem("CWFortSiegeCapital", "") == "cwfortsiegecapital_"
