# The dialogue of the Sleeping Giant Inn as the game evaluates it (game/dialogue): what each actor
# says, the topics offered and the responses with their voice files; a conversation played on the
# console; a voice file's lip track. Run from the repository root:
#
#   zap run projects/skyrim/dialogueInfo.zap --inn [--hour 12]           each actor's hello and topics
#   zap run projects/skyrim/dialogueInfo.zap --talk <name> [--choose 1,2] a conversation, topics by number
#   zap run projects/skyrim/dialogueInfo.zap --lip <voice key>            a voice file's lip frames
#   zap run projects/skyrim/dialogueInfo.zap --install D:/Data ...        another install

import skyrim
import skyrim.esm
import game.dialogue

inn = "RiverwoodSleepingGiantInn"

# whether the voice file is there and what it holds
fn voiceText(t dialogue.Talk, key str):
	if key.isEmpty: return "a sound of its own"
	install = t.vm.install ?? return "{key} (no install)"
	match install.readVoice(key):
		v: "{key} ({v.lip.frames.len} lip frames, {v.seconds:.2} s)"
		error: "missing: {error}"

fn printLine(t dialogue.Talk, s dialogue.Spoken, indent str):
	print("{indent}\"{s.text}\"")
	print("{indent}  voice {t.voiceText(s.voice)}")

fn infoText(t dialogue.Talk, info i64):
	i = t.dialogue.infos[info]
	quest = t.dialogue.quests.get(i.quest)?.editorId ?? ""
	topic = t.dialogue.topics.get(i.topic)?.editorId ?? ""
	"INFO {info:08X} of {quest} {topic}{" (goodbye)" if i.isGoodbye() else ""}"

fn printPerson(mut t dialogue.Talk, p dialogue.Person):
	voice = t.plugin.baseRecord(p.voice)?.editorId ?? "none"
	print("{p.name} ({p.editorId}, ref {p.refId:08X}), voice {voice}")
	match t.greeting(p.refId):
		line:
			print("  hello: {t.infoText(line.info)}")
			for s in t.spokenLines(p.refId, line.info):
				t.printLine(s, "    ")
		none: print("  hello: none")
	for m in t.topics(p.refId):
		print("  topic \"{m.prompt}\": {t.infoText(m.info)}")
		for s in t.spokenLines(p.refId, m.info):
			t.printLine(s, "    ")

fn printSaid(t dialogue.Talk, s dialogue.Said):
	for line in s.lines:
		t.printLine(line, "  ")
	for stage in s.stages:
		print("  stage set: {stage}")
	if s.gold != 0: print("  gold: {s.gold}")
	for refId in s.unlocked:
		print("  unlocked: {refId:08X}")
	for owner in s.owners:
		print("  owner: {owner}")
	for line in s.log:
		print("  script: {line}")

fn printMenu(menu dialogue.MenuTopic[]):
	for k, m in menu:
		print("  {k + 1}. {m.prompt}")

# plays the conversation with the actor named, the topics chosen by their numbers in turn
fn playTalk(mut t dialogue.Talk, name str, choices f64[]):
	lower = name.lower()
	p = t.people.values().find(.name.lower().startsWith(lower) or .editorId.lower() == lower) ??
		fail("no actor {name} in the inn")
	speaker = p.refId
	line = t.activateActor(speaker) ?? fail("{p.name} has nothing to say")
	print("{p.name}: {t.infoText(line.info)}")
	t.printSaid(t.say(speaker, line.info))
	menu = t.menuAfter(speaker, line)
	for choice in choices:
		printMenu(menu)
		k = i64(choice) - 1
		if k < 0 or k >= menu.len: fail("no topic {choice}")
		print("> {menu[k].prompt}")
		chosen = dialogue.Line(topic = menu[k].topic, info = menu[k].info)
		print("{p.name}: {t.infoText(chosen.info)}")
		said = t.say(speaker, chosen.info)
		t.printSaid(said)
		if said.goodbye: return
		menu = t.menuAfter(speaker, chosen)
	printMenu(menu)

fn printLip(install skyrim.Install, key str):
	v = install.readVoice(key) ?? fail
	print("{key}: {v.lip.frames.len} frames at {skyrim.lipFramesPerSecond} a second, sound {v.seconds:.3} s, lead {v.lip.lead}")
	for f in v.lip.frames:
		weights = []
		for k, w in f.weights:
			if w >= 0.05: weights.push("{skyrim.lipTarget(k)} {w:.2}")
		print("  {f.time:.3} {weights.join(", ")}")

install = skyrim.openInstall(args.option("--install") ?? skyrim.defaultInstall) ?? fail
if args.option("--lip") is key:
	install.printLip(key)
	return
plugin = esm.openEsm(install.installPlugin("Skyrim.esm")) ?? fail
t = dialogue.talkInCell(install, plugin, inn) ?? fail
hour = f64.parse(args.option("--hour") ?? "8") ?? fail("--hour takes a number")
t.vm.rt.world.daysPassed = t.vm.rt.world.daysPassed.floor() + hour / 24.0
if args.hasFlag("--inn"):
	for p in t.people.values().sortedBy(.name):
		if p.refId != t.vm.rt.world.player: t.printPerson(p)
	if not t.unknown.isEmpty:
		print("condition functions without an implementation: {t.unknown.keys().sorted().map("{esm.conditionFunctions.get(it) ?? "?"} ({t.unknown[it]})").join(", ")}")
elif args.option("--talk") is name:
	t.playTalk(name, args.optionNumbers("--choose"))
else:
	fail("give --inn, --talk <name> [--choose 1,2] or --lip <voice key>")
