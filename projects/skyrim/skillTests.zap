# Skills by use and the character's levels (game/sim/skills.zap, game/combat/practice.zap) on the
# inn's world as a new game has it; skipped quietly without the install. The numbers are Skyrim.esm's:
# fSkillUseCurve 1.95, fXPLevelUpBase 75 and fXPLevelUpMult 25, the skills' AVSK.

import skyrim
import game
import game.sim
import game.combat

inn = "RiverwoodSleepingGiantInn"
orgnar = 0x1_3486
flames = 0x1_2FCD
apple = 0x6_4B2E

fn innWorld() sim.GameWorld?:
	install, plugin = try skyrim.installAndPlugin()
	names = install.readNames("Skyrim.esm") ?? fail
	install.worldOfCell(plugin, names, inn) ?? fail

fn innFight(seed i64, weapon str) combat.Fight?:
	install, plugin = try skyrim.installAndPlugin()
	plugin.cellFight(install, inn, weapon, seed) ?? fail

fn near(a f32, b f32):
	(a - b).abs() < 0.01

fn skillXp(w sim.GameWorld, skill str):
	w.progress.skillXp[sim.skillNames.indexOf(skill) ?? 0]

test "the skills' AVSK are the AVIFs': One-Handed uses up 6.3 a point and takes pow(level, 1.95) x 2":
	w = innWorld() ?? return
	one = w.skillUses["onehanded"]
	expect one.useMult == 6.3 and one.improveMult == 2.0 and one.displayName == "One-handed"
	expect w.skillUses["illusion"].displayName == "Illusion"
	expect w.skillUses.len == 18
	level = w.actors[w.player].valueOf("onehanded")
	expect level == 20.0
	expect near(w.skillThreshold("onehanded", level), 2.0 * f32(20.0.pow(1.95)))
	expect w.skillThreshold("onehanded", sim.skillMax) == 0.0
	expect w.nextLevelXp() == 100.0 and w.levelThreshold(5) == 200.0

test "using a skill adds its amount times the use mult; reaching the threshold raises it and gives the character the new level in experience":
	w = innWorld() ?? return
	need = w.skillThreshold("onehanded", 20.0)
	w.useSkill("onehanded", 100.0)
	expect near(w.skillXp("onehanded"), 630.0) and w.actors[w.player].valueOf("onehanded") == 20.0
	expect w.progress.xp == 0.0 and w.notifications.isEmpty
	w.useSkill("onehanded", 10.0)
	expect w.actors[w.player].valueOf("onehanded") == 21.0
	expect near(w.skillXp("onehanded"), 693.0 - need)
	expect w.progress.xp == 21.0
	expect w.notifications == ["One-handed Increased to 21"]
	w.useSkill("onehanded", 0.0)
	w.useSkill("onehanded", -5.0)
	expect near(w.skillXp("onehanded"), 693.0 - need)

test "a lot of use raises a skill several levels at once, the experience carried over, and not past 100":
	w = innWorld() ?? return
	w.useSkill("lightarmor", 1000.0)
	level = w.actors[w.player].valueOf("lightarmor")
	expect level > 21.0
	expect w.notifications.len == 1 and
		w.notifications[0] == "Light Armor Increased to {i64(level)}"
	gained = (21..=i64(level)).sum()
	expect w.progress.xp == f32(gained)
	w.actors[w.player].setBaseValue("sneak", 100.0)
	w.useSkill("sneak", 1000.0)
	expect w.actors[w.player].valueOf("sneak") == 100.0 and w.skillXp("sneak") == 0.0

test "a skill book or trainer raises the skill a level and keeps the share of the level earned":
	w = innWorld() ?? return
	need = w.skillThreshold("block", 20.0)
	w.progress.skillXp[3] = need / 2.0
	w.incrementSkill("block", 1)
	expect w.actors[w.player].valueOf("block") == 21.0
	expect near(w.skillXp("block"), w.skillThreshold("block", 21.0) / 2.0)
	expect w.notifications == ["Block Increased to 21"]
	w.incrementSkill("block", 3)
	expect w.actors[w.player].valueOf("block") == 24.0
	expect w.notifications.len == 2 and w.notifications[1] == "Block Increased to 24"

test "with the experience for it the character rises by an attribute: +10 and full health, magicka and stamina; stamina adds 5 carry weight; a perk point is earned":
	w = innWorld() ?? return
	expect not w.canLevelUp()
	expect w.levelUp("health") is why and "experience" in why
	w.progress.xp = 130.0
	expect w.canLevelUp()
	expect w.levelUp("luck") is why and "not an attribute" in why
	w.actors[w.player].damageValue("health", 40.0)
	w.actors[w.player].damageValue("magicka", 10.0)
	carry = w.actors[w.player].valueOf("carryweight")
	expect w.levelUp("stamina") == none
	a = w.actors[w.player]
	expect a.level == 2 and a.valueOf("stamina") == 110.0 and a.valueOf("health") == 100.0
	expect a.valueOf("magicka") == 100.0
	expect a.valueOf("carryweight") == carry + 5.0
	expect w.progress.xp == 30.0 and w.nextLevelXp() == 125.0
	expect w.progress.perkPoints == 1 and w.progress.skillAtLevelUp.len == 18
	expect not w.canLevelUp()
	w.progress.xp = 400.0
	expect w.levelUp("health") == none and w.levelUp("magicka") == none
	expect w.actors[w.player].level == 4 and w.actors[w.player].valueOf("health") == 110.0
	expect w.progress.xp == 400.0 - 125.0 - 150.0 and w.progress.perkPoints == 3

test "the player's landed swing gives the weapon's base damage to its skill; fists give nothing; a bash gives Block 5 with a shield, 1 without":
	f = innFight(1, "IronDagger") ?? return
	k = f.fighterNamed("Player") ?? fail("no player")
	j = f.fighterNamed("Orgnar") ?? fail("no Orgnar")
	f.fighters[k].at = Vec3(0, 0, 0)
	f.fighters[k].facing = Vec3(1, 0, 0)
	f.fighters[j].at = Vec3(60, 0, 0)
	f.fighters[k].controlled = true
	f.fighters[k].target = f.fighters[j].refId
	f.startSwing(k, .Normal)
	loop 90:
		f.stepOnce()
	expect near(f.w.skillXp("onehanded"), 4.0 * 6.3)
	f.w.progress.skillXp[0] = 0.0
	x = f.fighters[k].copy()
	f.practiceHit(x, .Bash, 5.0)
	expect near(f.w.skillXp("block"), 1.0 * 8.1)
	x.shield = 1
	f.practiceHit(x, .Bash, 5.0)
	expect near(f.w.skillXp("block"), 6.0 * 8.1)
	x.weapon = 0
	x.skill = ""
	f.practiceHit(x, .Normal, 5.0)
	expect f.w.skillXp("onehanded") == 0.0

test "a blow that hurts the player trains Block by the damage the block took, else an armor skill by the weights of what he wears":
	f = innFight(1, "") ?? return
	k = f.fighterNamed("Player") ?? fail("no player")
	me = f.fighters[k].copy()
	me.lightWeight = 6
	f.practiceDefence(me, 10.0, 0.0)
	expect near(f.w.skillXp("lightarmor"), 10.0 * 4.0)
	me.lightWeight = 0
	me.heavyWeight = 6
	f.practiceDefence(me, 10.0, 0.0)
	expect near(f.w.skillXp("heavyarmor"), 10.0 * 3.8)
	me.heavyWeight = 0
	f.practiceDefence(me, 10.0, 0.0)
	f.practiceDefence(me, 10.0, 0.5)
	expect near(f.w.skillXp("block"), 5.0 * 8.1)
	other = f.fighters[f.fighterNamed("Orgnar") ?? fail("no Orgnar")].copy()
	other.lightWeight = 6
	f.practiceDefence(other, 10.0, 0.0)
	expect near(f.w.skillXp("lightarmor"), 10.0 * 4.0)

test "holding Flames for a second gives Destruction the spell's cost times its usage; the same spell cast by Orgnar teaches nothing":
	f = innFight(1, "") ?? return
	k = f.fighterNamed("Player") ?? fail("no player")
	school, amount = f.w.spellPractice(f.w.spells[flames])
	expect school == "destruction" and amount > 0.0
	f.fighters[k].at = Vec3(0, 0, 0)
	f.fighters[k].facing = Vec3(1, 0, 0)
	expect f.startCast(k, flames, false) == none
	loop 60:
		f.stepOnce()
	f.stopCast(k)
	expect near(f.w.skillXp("destruction"), amount * 1.35 * f.time)
	before = f.w.skillXp("destruction")
	j = f.fighterNamed("Orgnar") ?? fail("no Orgnar")
	f.fighters[j].at = Vec3(5000, 0, 0)
	f.practiceCast(j, f.w.spells[flames], 1.0)
	expect f.w.skillXp("destruction") == before

test "buying or selling trains Speech by the item's value; stealing by its value to the curve of 1":
	w = innWorld() ?? return
	value = w.items[apple].value
	expect w.buyFrom(orgnar, apple, 2) == none
	expect near(w.skillXp("speechcraft"), f32(value) * 0.36)
	expect w.sellTo(orgnar, apple, 1) == none
	expect near(w.skillXp("speechcraft"), f32(value) * 0.36 * 2.0)
	curve = w.settings.gmst("fpickpocketskillusescurve")
	expect curve == 0.8 and near(w.pickpocketUsage(100), f32(100.0.pow(f64(curve))))
	w.useSkill("pickpocket", w.pickpocketUsage(10))
	expect near(w.skillXp("pickpocket"), w.pickpocketUsage(10) * 8.1)

test "sneaking in view of someone not sure of him trains Sneak half a point a second, slipping out of sight 2.5":
	w = innWorld() ?? return
	w.useSneak(2.0, false)
	expect w.skillXp("sneak") == 0.0
	w.stealth.sneaking = true
	w.useSneak(2.0, false)
	expect w.skillXp("sneak") == 0.0   # nobody has looked: the meter reads 1100
	w.stealth.detections[orgnar] = sim.Detection(level = 50)
	w.useSneak(2.0, false)
	expect near(w.skillXp("sneak"), 0.625 * 2.0 * 11.25)   # fSkillUsageSneakPerSecond is 0.625 in the plugin
	w.stealth.detections[orgnar] = sim.Detection(level = 100)
	w.useSneak(2.0, false)
	expect near(w.skillXp("sneak"), 0.625 * 2.0 * 11.25)   # fully detected: the meter reads 0
	w.useSneak(0.0, true)
	expect near(w.skillXp("sneak"), 0.625 * 2.0 * 11.25 + 2.5 * 11.25)
