# Perks (skyrim/esm/perk.zap, game/sim/perks.zap, perkTree.zap): the records as Skyrim.esm stores
# them, the entry points' functions, and the inn's cases: Armsman raising a hit, Well Rested's skill
# bonus, Haggling, Novice Destruction, choosing perks in a constellation. The semantics tests build
# their worlds by hand; those of the records and the inn are skipped quietly without the install.

import skyrim
import skyrim.esm
import game
import game.sim
import game.combat

inn = "RiverwoodSleepingGiantInn"
orgnar = 0x1_3486

fn near(a f32, b f32):
	(a - b).abs() < 0.001

# a world with only the player, who has 50 in One-Handed
fn bare():
	w = sim.newWorld()
	w.actors[w.player] = sim.ActorState(
		npc = 7,
		race = 1,
		level = 1,
		values = {"onehanded": sim.ActorValue(base = 50.0)}
	)
	w.actors[0x30] = sim.ActorState(npc = 8, race = 1, level = 1, values = {})
	w

fn entry(point i64, function i64, parameters i64, values f32[], rank i64, priority i64):
	esm.PerkEntry(
		kind = esm.entryPoint,
		rank,
		priority,
		point,
		function,
		parameters,
		dataType = values.len,
		values = values.copy()
	)

fn perk(formId i64, ranks i64, entries esm.PerkEntry[]):
	esm.Perk(
		formId,
		editorId = "P{formId:X}",
		conditions = [],
		trait = false,
		minLevel = 0,
		ranks,
		playable = true,
		hidden = false,
		next = 0,
		entries = entries.copy()
	)

fn give(mut w sim.GameWorld, p esm.Perk):
	w.perks[p.formId] = p.copy()
	expect w.addPerk(w.player, p.formId)

fn has(function i64, param i64, value f32):
	esm.Condition(
		op = 0,
		orNext = false,
		useGlobal = false,
		value,
		global = 0,
		function,
		param1 = param,
		param2 = 0,
		runOn = 0,
		reference = 0
	)

test "the functions of an entry point set, add, multiply, take the absolute value, and the later perk's entry is asked first":
	w = bare()
	w.give(perk(0x100, 1, [entry(sim.epModSkillUse, 3, 1, [2.0], 0, 0)]))
	expect near(w.entryPointValue(sim.epModSkillUse, w.player, [], 3.0), 6.0)
	w.give(perk(0x101, 1, [entry(sim.epModSkillUse, 2, 1, [10.0], 0, 0)]))
	expect near(w.entryPointValue(sim.epModSkillUse, w.player, [], 1.0), 22.0)   # (1 + 10) x 2
	w.give(perk(0x102, 1, [entry(sim.epModSkillUse, 1, 1, [4.0], 0, 7)]))
	expect near(w.entryPointValue(sim.epModSkillUse, w.player, [], 1.0), 28.0)   # the higher priority sets first, then (4 + 10) x 2
	w.give(perk(0x103, 1, [entry(sim.epModSkillUse, 7, 1, [], 0, -3)]))
	expect w.entryPointValue(sim.epModSkillUse, w.player, [], 1.0) == -28.0
	other = w.entryPointValue(sim.epModSkillUse, 0x30, [], 5.0)
	expect other == 5.0   # an actor with no perks changes nothing

test "an actor value times a factor sets, adds, multiplies, or multiplies one plus it":
	w = bare()
	w.give(perk(0x110, 1, [entry(sim.epModSkillUse, 14, 1, [6.0, 0.01], 0, 0)]))
	expect near(w.entryPointValue(sim.epModSkillUse, w.player, [], 4.0), 6.0)   # (50 x 0.01 + 1) x 4
	w.removePerk(w.player, 0x110)
	w.give(perk(0x111, 1, [entry(sim.epModSkillUse, 5, 1, [6.0, 0.1], 0, 0)]))
	expect near(w.entryPointValue(sim.epModSkillUse, w.player, [], 4.0), 9.0)   # 4 + 50 x 0.1
	w.removePerk(w.player, 0x111)
	w.give(perk(0x112, 1, [entry(sim.epModSkillUse, 12, 1, [6.0, 0.5], 0, 0)]))
	expect near(w.entryPointValue(sim.epModSkillUse, w.player, [], 4.0), 25.0)
	w.removePerk(w.player, 0x112)
	w.give(perk(0x113, 1, [entry(sim.epModSkillUse, 13, 1, [6.0, 0.5], 0, 0)]))
	expect near(w.entryPointValue(sim.epModSkillUse, w.player, [], 4.0), 100.0)

test "an entry of rank n applies at the perk's rank n + 1 only":
	w = bare()
	w.give(perk(0x120, 2, [entry(sim.epModSkillUse, 3, 1, [2.0], 0, 0),
		entry(sim.epModSkillUse, 3, 1, [3.0], 1, 0)]))
	expect w.perkRank(w.player, 0x120) == 1
	expect near(w.entryPointValue(sim.epModSkillUse, w.player, [], 1.0), 2.0)
	expect w.addPerk(w.player, 0x120) and w.perkRank(w.player, 0x120) == 2
	expect near(w.entryPointValue(sim.epModSkillUse, w.player, [], 1.0), 3.0)
	expect w.addPerk(w.player, 0x120) and w.perkRank(w.player, 0x120) == 2   # no third rank
	w.removePerk(w.player, 0x120)
	expect not w.hasPerk(w.player, 0x120)
	expect near(w.entryPointValue(sim.epModSkillUse, w.player, [], 1.0), 1.0)

test "an entry's conditions are asked of the form at each parameter; an absent form meets none":
	w = bare()
	w.keywords[0x5000] = [0x777]
	w.keywords[0x5001] = [0x778]
	e = entry(sim.epModAttackDamage, 3, 3, [1.5], 0, 0)
	e.tabs = [esm.PerkTab(index = 1, conditions = [has(560, 0x777, 1.0)])]
	w.give(perk(0x130, 1, [e.copy()]))
	hit = sim.epModAttackDamage
	expect near(w.entryPointValue(hit, w.player, [0x5000, 0x30], 10.0), 15.0)
	expect near(w.entryPointValue(hit, w.player, [0x5001, 0x30], 10.0), 10.0)   # no such keyword
	expect near(w.entryPointValue(hit, w.player, [0, 0x30], 10.0), 10.0)   # no weapon: fists
	expect near(w.entryPointValue(hit, w.player, [0x5000], 10.0), 10.0)   # one parameter short
	either = has(560, 0x778, 1.0)
	either.orNext = true
	first = has(560, 0x777, 1.0)
	first.orNext = true
	e.tabs = [esm.PerkTab(index = 1, conditions = [first, either])]
	w.perks[0x130] = perk(0x130, 1, [e.copy()])
	expect near(w.entryPointValue(hit, w.player, [0x5001, 0x30], 10.0), 15.0)   # the OR group holds
	owned = entry(hit, 3, 3, [2.0], 0, 0)
	owned.tabs = [esm.PerkTab(index = 0, conditions = [has(448, 0x131, 0.0)])]   # until it has 0x131
	w.give(perk(0x132, 1, [owned.copy()]))
	expect near(w.entryPointValue(hit, w.player, [0x5000, 0x30], 10.0), 30.0)
	w.give(perk(0x131, 1, []))
	expect near(w.entryPointValue(hit, w.player, [0x5000, 0x30], 10.0), 15.0)

test "a perk's ability entry gives the spell and its quest entry the stage, at their rank":
	w = bare()
	ability = esm.PerkEntry(kind = esm.entryAbility, rank = 0, priority = 0, form = 0x900)
	quest = esm.PerkEntry(kind = esm.entryQuest, rank = 0, priority = 0, form = 0x901, stage = 20)
	w.give(perk(0x140, 1, [ability, quest]))
	expect 0x900 in w.actors[w.player].magic.known and w.stages[0x901] == 20
	w.removePerk(w.player, 0x140)
	expect 0x900 not in w.actors[w.player].magic.known

fn innWorld() (sim.GameWorld, esm.Esm, skyrim.Strings)?:
	install, plugin = try skyrim.installAndPlugin()
	names = install.readNames("Skyrim.esm") ?? fail("not found")
	w = install.worldOfCell(plugin, names, inn) ?? fail("not found")
	(w, plugin, names)

fn perkId(mut plugin esm.Esm, editorId str):
	plugin.formByEditorId("PERK", editorId) ?? fail("no perk {editorId}")

test "Skyrim.esm's Armsman reads as an entry point of attack damage with the keywords of its weapons":
	_, plugin, _ = innWorld() ?? return
	armsman = plugin.perkOf(plugin.perkId("Armsman00")) ?? fail("not found")
	expect armsman.next == plugin.perkId("Armsman20") and armsman.ranks == 1 and armsman.playable
	expect armsman.conditions.isEmpty and armsman.entries.len == 1
	e = armsman.entries[0]
	expect e.kind == esm.entryPoint and e.point == 0x23 and e.function == 3 and e.parameters == 3
	expect e.dataType == 1 and near(e.values[0], 1.2) and e.rank == 0 and e.priority == 0
	expect e.tabs.len == 2 and e.tabs[0].index == 0 and e.tabs[1].index == 1
	expect e.tabs[0].conditions[0].function == 448 and e.tabs[0].conditions[0].value == 0.0
	expect e.tabs[1].conditions.len == 4 and e.tabs[1].conditions.all(.function == 560 and .orNext)
	forty = plugin.perkOf(plugin.perkId("Armsman40")) ?? fail("not found")
	need = forty.conditions[0]   # One-Handed, the actor value 6, at least 40
	expect need.function == 277 and need.param1 == 6 and need.value == 40.0 and need.op == 3
	expect forty.conditions[1].function == 448 and forty.conditions[1].param1 == forty.next - 1

test "the One-Handed tree has its root, the nodes' perks and the children they lead to":
	_, plugin, _ = innWorld() ?? return
	avif = plugin.formByEditorId("AVIF", "AVOneHanded") ?? fail("not found")
	tree = plugin.skillTreeOf(avif) ?? fail("not found")
	expect tree.nodes.len > 10 and tree.nodes[0].index == 0 and tree.nodes[0].perk == 0
	expect tree.nodes[0].children.len == 1
	armsman = tree.nodes.find(.perk == plugin.perkId("Armsman00")) ?? fail("no Armsman node")
	expect armsman.skill == avif and not armsman.children.isEmpty

test "Well Rested multiplies what a use of a skill adds by 1.1 through the perk of its ability":
	w, plugin, names = innWorld() ?? return
	rested = plugin.formByEditorId("SPEL", "WellRested") ?? fail("not found")
	expect w.learnSpell(plugin, names, rested)
	base = w.progress.skillXp[sim.skillNames.indexOf("onehanded") ?? 0]
	w.useSkill("onehanded", 10.0)
	plain = w.progress.skillXp[sim.skillNames.indexOf("onehanded") ?? 0] - base
	expect plain > 0.0 and not w.hasPerk(w.player, plugin.perkId("RestedWellPerk"))
	w.actors[w.player].magic.known.push(rested)
	expect w.hasPerk(w.player, plugin.perkId("RestedWellPerk"))
	before = w.progress.skillXp[sim.skillNames.indexOf("onehanded") ?? 0]
	w.useSkill("onehanded", 10.0)
	expect near(w.progress.skillXp[sim.skillNames.indexOf("onehanded") ?? 0] - before, plain * 1.1)
	w.actors[w.player].magic.known = []
	expect not w.hasPerk(w.player, plugin.perkId("RestedWellPerk"))

# the health the swing takes off Orgnar, the player holding the weapon and having the perks
fn swingDamage(weapon str, perks str[]) f32?:
	install, plugin = try skyrim.installAndPlugin()
	names = install.readNames("Skyrim.esm") ?? fail("not found")
	w = install.worldOfCell(plugin, names, inn) ?? fail("not found")
	form = plugin.formByEditorId("WEAP", weapon) ?? fail("no {weapon}")
	w.inventories[w.player].equip(w.items, form, false) ?? fail("not found")
	for editorId in perks:
		id = plugin.perkId(editorId)
		expect w.learnPerk(plugin, names, id) != none
		expect w.addPerk(w.player, id)
	f = plugin.sceneFight(w, install.timingsOf() ?? fail, 1) ?? fail("not found")
	k = f.fighterNamed("Player") ?? fail("no player")
	j = f.fighterNamed("Orgnar") ?? fail("no Orgnar")
	before = f.w.actors[f.fighters[j].refId].valueOf("health")
	f.fighters[k].at = Vec3(0, 0, 0)
	f.fighters[k].facing = Vec3(1, 0, 0)
	f.fighters[j].at = Vec3(60, 0, 0)
	f.fighters[k].controlled = true
	f.fighters[k].target = f.fighters[j].refId
	f.startSwing(k, .Normal)
	loop 90:
		f.stepOnce()
	before - f.w.actors[f.fighters[j].refId].valueOf("health")

test "Armsman raises the damage of an iron sword by 20 percent, Armsman at the second rank by 40 and not by both":
	plain = swingDamage("IronSword", []) ?? return
	first = swingDamage("IronSword", ["Armsman00"]) ?? return
	second = swingDamage("IronSword", ["Armsman00", "Armsman20"]) ?? return
	expect plain > 0.0
	expect near(first, plain * 1.2) and near(second, plain * 1.4)
	dagger = swingDamage("IronDagger", ["Armsman00"]) ?? return
	expect near(dagger, (swingDamage("IronDagger", []) ?? return) * 1.2)

test "Haggling lowers what Orgnar asks and raises what he pays, at the first rank only":
	w, plugin, names = innWorld() ?? return
	asking = w.buyMultiplier(orgnar)
	paying = w.sellMultiplier(orgnar)
	one = plugin.perkId("Haggling00")
	expect w.learnPerk(plugin, names, one) != none
	expect w.addPerk(w.player, one)
	expect (w.buyMultiplier(orgnar) - asking * 0.91).abs() < 0.001
	expect (w.sellMultiplier(orgnar) - paying * 1.1).abs() < 0.001
	two = plugin.perkId("Haggling20")
	expect w.learnPerk(plugin, names, two) != none
	expect w.addPerk(w.player, two)
	expect w.buyMultiplier(orgnar) < asking * 0.91   # the first rank's entry ended

test "Novice Destruction halves the cost of Flames; Cutpurse adds 50 to the chance of taking gold only":
	w, plugin, names = innWorld() ?? return
	flames = 0x1_2FCD
	expect w.spells[flames].castingPerk == plugin.perkId("DestructionNovice00")
	cost = w.spells[flames].cost
	expect w.spellCost(w.player, w.spells[flames]) == cost
	novice = plugin.perkId("DestructionNovice00")
	expect w.learnPerk(plugin, names, novice) != none
	expect w.addPerk(w.player, novice)
	expect near(w.spellCost(w.player, w.spells[flames]), cost * 0.5)
	cutpurse = plugin.perkId("Cutpurse")
	expect w.learnPerk(plugin, names, cutpurse) != none
	expect w.addPerk(w.player, cutpurse)
	expect near(w.entryPointValue(sim.epModPickpocketChance, w.player, [orgnar, 0xF], 10.0), 60.0)
	expect near(
		w.entryPointValue(sim.epModPickpocketChance, w.player, [orgnar, 0x1_2EB7], 10.0),
		10.0
	)

test "a perk point chooses the perk of a node, the requirements of its record hold the next ones back":
	w, plugin, names = innWorld() ?? return
	expect w.learnSkillTree(plugin, names, "onehanded")
	armsman = plugin.perkId("Armsman00")
	node = w.skillTrees["onehanded"].nodes.find(.perk == armsman) ?? fail("no Armsman node")
	expect w.whyNotChoose("onehanded", node.index) == "no perk point to spend"
	w.progress.perkPoints = 3
	expect w.choosePerk("onehanded", node.index) == none
	expect w.hasPerk(w.player, armsman) and w.progress.perkPoints == 2
	expect w.choosePerk("onehanded", node.index) == none   # the next rank: One-Handed 20 holds
	expect w.hasPerk(w.player, plugin.perkId("Armsman20")) and w.progress.perkPoints == 1
	why = w.choosePerk("onehanded", node.index) ?? fail("Armsman40 needs One-Handed 40")
	expect why.startsWith("the character does not meet") and w.progress.perkPoints == 1
	w.actors[w.player].setBaseValue("onehanded", 40.0)
	expect w.choosePerk("onehanded", node.index) == none and w.progress.perkPoints == 0
	expect w.choosePerk("onehanded", 12_345) == "onehanded has no node 12345"
	root = w.skillTrees["onehanded"].nodes[0].index
	expect w.choosePerk("onehanded", root) == "node 0 of onehanded offers no perk"
