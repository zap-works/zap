# Combat's rules without the game: the formulas on values by hand (Skyrim.esm's GMSTs as the
# plugin sets them, settings.zap's for the rest), and fights of actors made by hand.

import skyrim.actor
import game.sim
import game.combat
import game.stealth

# the GMSTs the formulas read, as Skyrim.esm sets them
fn esmSettings():
	{
		"fdamagepcskillmax": 1.5,
		"fpowerattackdefaultbonus": 1.0,
		"fstaminaattackweaponbase": 20.0,
		"fstaminaattackweaponmult": 1.0,
		"fpowerattackstaminapenalty": 2.0,
		"farmorscalingfactor": 0.12,
		"farmorbasefactor": 0.03,
		"fmaxarmorrating": 80.0,
		"farmorratingbase": 1.0,
		"farmorratingpcmax": 1.4,
		"farmorratingmax": 2.5,
		"fblockweaponbase": 0.3,
		"fblockweaponscaling": 0.2,
		"fblockpowerattackmult": 0.66,
		"fstaminablockbase": 0.0,
		"fstaminablockdmgmult": 0.25,
		"fcombatsneakhandmult": 2.0,
		"fcombatsneak1hdaggermult": 3.0,
		"fcombatsneak1hswordmult": 3.0,
		"fcombatsneak2hswordmult": 2.0,
		"fcombatdistance": 141.0,
		"fcombatbashreach": 141.0,
		"fstaminabashbase": 35.0,
		"fweaponbashmax": 0.25,
		"fstaggermin": 0.0,
		"fknockbackdamagemult": 5.0,
		"fknockbackforcemax": 128.0,
		"fessentialdeathtime": 20.0,
		"fbleedoutrecover": 0.05,
		"fsneakmaxdistance": 2500.0,
		"fconfidencecautious": 0.375,
		"fconfidenceaverage": 0.15,
		"fconfidencebrave": 0.0375,
		"fcombatblockchanceweaponmult": 0.25,
		"fsprintstaminadrainmult": 7.0,
		"fcombathealthregenratemult": 0.0,
		"fcombatmagickaregenratemult": 0.33,
		"fcombatstaminaregenratemult": 0.35,
		"fdamagedhealthregendelay": 0.5,
		"fdamagedmagickaregendelay": 0.5,
		"fdamagedstaminaregendelay": 0.5
	}

test "an iron dagger shows 4 at One-Handed 20 (4.4), an iron sword 8 (7.7); an NPC's skill counts four times":
	s = esmSettings()
	expect s.weaponDamage(4.0, 20.0, true) == 4.4 and s.shownDamage(4.0, 20.0, true) == 4
	expect s.shownDamage(7.0, 20.0, true) == 8
	expect s.weaponDamage(10.0, 50.0, false) == 20.0
	expect s.shownDamage(7.0, 100.0, true) == 11   # 10.5, rounded up

test "a power attack does twice the damage (fists once) for 40 + 2 x weight stamina":
	s = esmSettings()
	expect s.strikeMultiplier(.Power, false) == 2.0
	expect s.strikeMultiplier(.Power, true) == 1.0
	expect s.powerAttackStamina(2.0) == 44.0 and s.powerAttackStamina(0.0) == 40.0
	expect s.sneakMultiplier(2) == 3.0 and s.sneakMultiplier(0) == 2.0 and
		s.sneakMultiplier(5) == 2.0

test "armor: 0.12% a point and 3% a piece, at most 80%; nothing worn takes the full damage":
	s = esmSettings()
	expect s.armorReduction(0.0, 0) == 0.0
	expect combat.damageTaken(10.0, s.armorReduction(0.0, 0), 0.0) == 10.0
	expect (s.armorReduction(100.0, 4) - 0.24).abs() < 0.0001
	expect s.armorReduction(1000.0, 4) == 0.8
	expect s.armorRating(25.0, 0.0, true) == 25.0 and s.armorRating(25.0, 100.0, true) == 35.0

test "a weapon blocks 30% plus its foe's damage; a shield 45% plus its rating; a power attack less":
	s = esmSettings()
	weapon = s.blockShare(0.0, none, 10.0, .Normal)
	expect (weapon - 0.32).abs() < 0.0001
	shield = s.blockShare(100.0, 20.0, 10.0, .Normal)
	expect (shield - 0.55).abs() < 0.0001
	expect (s.blockShare(100.0, 20.0, 10.0, .Power) - 0.363).abs() < 0.0001

test "a stagger is the weapon's times the attack's over the mass, less the mass offset; a bash the Block's; a block takes 1.5 off":
	s = esmSettings()
	expect s.hitStagger(1.0, false, 1.0, 1.0) == 1.0   # a sword's power attack on a Nord
	expect s.hitStagger(1.0, false, 1.0, 0.0) == 0.0   # a plain attack: the Nord's ATKD gives 0
	expect (s.hitStagger(2.0, true, 1.0, 1.0) - 0.1).abs() < 0.0001   # the player counts twice its mass: 1/4 - 0.15
	expect s.hitStagger(5.0, false, 1.5, 1.0).abs() < 0.0001   # 0.3 - 0.3
	target = combat.BashTarget(mass = 1.0, staggered = false, running = false, blocking = false)
	expect (s.bashStagger(20.0, false, false, false, 0.5, target) - 0.35).abs() < 0.0001   # (0.5 + 0.2) x 0.5 bare
	expect (s.bashStagger(20.0, false, true, false, 0.5, target) - 0.07).abs() < 0.0001   # x fStagger1WeapMult 0.2
	expect (s.bashStagger(20.0, true, true, false, 0.5, target) - 0.35).abs() < 0.0001   # a shield x 1
	hit = combat.BashTarget(mass = 1.0, staggered = true, running = true, blocking = false)
	expect (s.bashStagger(0.0, true, true, false, 0.5, hit) - 0.5625).abs() < 0.0001   # 0.25 x 1.5 x 1.5
	expect s.blockedStagger(1.0, 20.0, none, 1.0) == 0.0   # 1 - (1 + 0.5 + 0.1), floored at fStaggerMin 0
	expect (s.blockedStagger(3.0, 0.0, 20.0, 1.0) - 1.6).abs() < 0.0001   # a shield of 20: 1 - 0.1 + 0.5

test "a class's level points: the heaviest weight first, ties to health, the last takes the rest":
	expect sim.levelShares(30, [1, 1, 1]) == [10, 10, 10]   # Orgnar, level 4
	expect sim.levelShares(90, [3, 3, 0]) == [45, 45, 0]   # Delphine, level 10
	expect sim.levelShares(70, [1, 1, 1]) == [23, 23, 24]   # UESP's level 8 beggar
	expect sim.levelShares(0, [0, 0, 0]) == [0, 0, 0]

fn handStyle():
	combat.Style(
		editorId = "hand",
		offensive = 0.5,
		defensive = 0.3,
		groupOffensive = 0.4,
		meleeScore = 1.0,
		unarmedScore = 1.0,
		avoidThreat = 0.2,
		attackStaggered = 1.0,
		powerAttackStaggered = 2.0,
		powerAttackBlocking = 2.0,
		bash = 1.0,
		bashRecoil = 1.0,
		bashAttack = 1.0,
		bashPowerAttack = 1.0,
		specialAttack = 0.1,
		circle = 0.3,
		fallback = 0.1,
		flankDistance = 0.2,
		stalkTime = 0.2,
		strafe = 0.2,
		flags = 0
	)

fn handTimings():
	swing = combat.AttackTime(duration = 1.3, hit = 0.367)
	fist = combat.AttackTime(duration = 1.133, hit = 0.533)
	combat.Timings(
		armed = combat.Moveset(normal = [swing, swing], power = combat.AttackTime(duration = 1.367, hit = 0.6)),
		unarmed = combat.Moveset(normal = [fist, fist], power = combat.AttackTime(duration = 1.667, hit = 0.801)),
		bash = combat.AttackTime(duration = 0.267, hit = 0.099),
		staggers = combat.Staggers(magnitudes = [0.0, 1.0], lengths = [1.567, 1.567])
	)

# the Nord's fists and attacks (Skyrim.esm's RACE NordRace: DATA at 100, ATKD at 24 by ATKE)
fn nordCombat():
	combat.RaceCombat(
		reach = 96.0,
		staggers = {
			combat.attackEvent: 0.0,
			combat.powerEvent: 1.0,
			combat.fistsPowerEvent: 0.5,
			combat.bashEvent: 0.5
		}
	)

whiterun = 0x2_67EA
innkeeper = 0x100
patron = 0x101

fn handActor(npc i64, health f32, confidence i64, flags i64):
	a = sim.ActorState(npc, race = 0, level = 1, values = {}, crimeFaction = whiterun, flags)
	for k, value in [health, 100.0, 100.0]:
		a.setBaseValue(sim.attributeNames[k], value)
	a.setBaseValue("healrate", 0.7)
	a.setBaseValue("staminarate", 5.0)
	a.setBaseValue("unarmeddamage", 4.0)
	a.setBaseValue("mass", 1.0)
	a.setBaseValue("onehanded", 20.0)
	a.setBaseValue("confidence", f32(confidence))
	a.setBaseValue("assistance", 1.0)
	a.setBaseValue("aggression", 1.0)
	a

# the player and an innkeeper 100 units apart, a patron near, the fight's rolls from the seed
fn handFight(seed i64, innkeeperFlags i64):
	w = sim.newWorld()
	w.settings = esmSettings()
	w.crimeValues[whiterun] = sim.CrimeValues(
		arrest = true,
		attackOnSight = true,
		murder = 1000,
		assault = 40,
		trespass = 5,
		pickpocket = 25,
		stealMult = 0.5,
		escape = 100,
		werewolf = 1000
	)
	for refId in [w.player, innkeeper, patron]:
		w.addForm(refId)
	w.forms[innkeeper].x = 100.0
	w.forms[patron].y = 300.0
	w.actors[w.player] = handActor(7, 100.0, 4, 0)
	w.actors[innkeeper] = handActor(0x200, 75.0, 3, innkeeperFlags)
	w.actors[patron] = handActor(0x201, 75.0, 0, 0)
	speeds = combat.Speeds(walk = 80.0, run = 370.0, backRun = 205.25, sprint = 500.0)
	f = combat.newFight(
		w,
		handTimings(),
		speeds,
		combat.Ties(relationships = [], reactions = {}),
		seed
	)
	f.lighting = stealth.Lighting(ambient = 1.0, ambientMax = 0.25)   # a lit interior
	names = ["Player", "Innkeeper", "Patron"]
	for k, refId in [f.w.player, innkeeper, patron]:
		settings = f.w.settings
		f.fighters.push(f.w.fighterOf(settings, refId, names[k], handStyle(), nordCombat()))
	f

fn playerAttacks(mut f combat.Fight):
	f.engage(f.indexOf(f.w.player) ?? fail("no player"), innkeeper)

test "fists hit an unarmored actor for the race's unarmed damage: an assault of 40, he turns on the player, the coward flees":
	f = handFight(1, 0)
	f.playerAttacks()
	f.run(1.0)
	expect f.health(innkeeper) == 71.0
	expect f.w.bountyOf(whiterun) == 40 and f.w.crimes[0].kind == "assault"
	keeper = f.fighters[f.indexOf(innkeeper) ?? fail("no innkeeper")]
	expect keeper.target == f.w.player and keeper.isFighting()
	expect f.fighters[f.indexOf(patron) ?? fail("no patron")].mode == .Flee

test "a fight ends within its seconds, one side dead or fled; the same seed gives the same fight":
	a = handFight(5, 0)
	a.playerAttacks()
	ran = a.run(120.0)
	expect ran < 120.0
	out = a.fighters.filter(.mode == .Dead or .mode == .Fled)
	expect not out.isEmpty
	b = handFight(5, 0)
	b.playerAttacks()
	b.run(120.0)
	expect a.lines == b.lines

test "a fighter weighs its foes as the executable: who hurt it lately, its current foe, the nearer, both in melee":
	f = handFight(1, 0)
	keeper = f.indexOf(innkeeper) ?? fail("no innkeeper")
	player = f.indexOf(f.w.player) ?? fail("no player")
	other = f.indexOf(patron) ?? fail("no patron")
	expect f.foeWeight(keeper, player, 1) == 0.0   # a lone foe
	# 100 units off, both bare-handed: (1 - 100 / 2048) x 1000 + 100
	expect (f.foeWeight(keeper, player, 2) - 1051.17).abs() < 0.01
	f.fighters[keeper].target = f.w.player
	f.fighters[keeper].struckBy = f.w.player
	f.fighters[keeper].struckAt = f.time
	expect (f.foeWeight(keeper, player, 2) - 2151.17).abs() < 0.01   # plus 1000 struck, 100 current
	f.fighters[other].mode = .Flee
	# the patron, about 316 units off and fleeing: (1 - 316.2 / 2048) x 1000 + 100 - 500
	expect (f.foeWeight(keeper, other, 2) - 445.59).abs() < 0.01

test "flight as the executable: confidence read between levels, fleeing when outmatched":
	f = handFight(1, 0)
	keeper = f.indexOf(innkeeper) ?? fail("no innkeeper")
	s = f.w.settings
	f.fighters[keeper].ai.confidence = 2
	f.fighters[keeper].confidenceModifier = 0.5
	average = s.gmst("fconfidenceaverage")
	brave = s.gmst("fconfidencebrave")
	expect (f.fleeThreshold(f.fighters[keeper]) - (average + (brave - average) * 0.5)).abs() <
		0.0001
	f.fighters[keeper].ai.confidence = 4   # foolhardy: no modifier
	expect f.fleeThreshold(f.fighters[keeper]) == s.gmst("fconfidencefoolhardy")
	# alone against the player, the innkeeper's side holds his own threat over the player's
	f.playerAttacks()
	f.engage(keeper, f.w.player)
	player = f.indexOf(f.w.player) ?? fail("no player")
	ratio = f.threatOf(f.fighters[keeper]) / f.threatOf(f.fighters[player])
	expect (f.threatRatio(keeper) - ratio).abs() < 0.0001

test "an essential actor bleeds out at 0 health instead of dying, then gets up and yields":
	f = handFight(2, actor.flagEssential)
	j = f.indexOf(innkeeper) ?? fail("no innkeeper")
	k = f.indexOf(f.w.player) ?? fail("no player")
	f.hurt(j, k, 500.0)
	expect f.fighters[j].mode == .Bleedout and not f.w.actors[innkeeper].dead
	expect f.health(innkeeper) == 0.0
	f.time = 21.0
	f.think(j)
	expect f.fighters[j].mode == .Alert and f.health(innkeeper) > 0.0
	g = handFight(2, 0)
	g.hurt(j, k, 500.0)
	expect g.fighters[j].mode == .Dead and g.fighters[j].ragdoll
	expect g.w.bountyOf(whiterun) == 1000   # killed at once: a murder only

fn near(a f32, b f32):
	(a - b).abs() < 0.0001

test "the AI's weights are the executable's: the settings lerped by the style, scaled by the situation":
	f = handFight(1, 0)
	x = f.fighters[f.indexOf(innkeeper) ?? fail("no innkeeper")]
	player = f.fighters[f.indexOf(f.w.player) ?? fail("no player")]
	expect near(f.attack(x, player, 1, none), 0.525)
	expect near(f.attack(x, player, 2, none), 0.24)
	expect near(f.attack(x, player, 1, 5.0), 0.7875)
	expect near(f.block(x), 0.075)
	expect near(f.bash(x, player), 0.0775)
	expect near(f.circle(x), 0.225)
	expect near(f.fallback(x), 0.05)
	expect near(f.circleAngle(x, player, 1.0), 36.0)
	expect near(f.blockTime(x), 4.0)
	expect combat.pick([1.0, 1.0, 2.0], 0.6) == 2
	expect combat.pick([1.0, 1.0], 0.4) == 0

test "a stagger's length is the blend of the two clips either side of its magnitude, clamped to the places":
	s = combat.Staggers(magnitudes = [0.0, 0.5, 1.0], lengths = [1.0, 2.0, 4.0])
	expect s.lengthAt(0.25) == 1.5 and s.lengthAt(0.75) == 3.0
	expect s.lengthAt(9.0) == 4.0 and s.lengthAt(-1.0) == 1.0
	expect s.clampMagnitude(0.3) == 0.3 and s.clampMagnitude(2.0) == 1.0

test "only an actor that detected the player witnesses his crime: one with its back to him does not":
	f = handFight(1, 0)
	keeper = f.indexOf(innkeeper) ?? fail("no innkeeper")
	other = f.indexOf(patron) ?? fail("no patron")
	f.fighters[keeper].facing = Vec3(1, 0, 0)   # the player stands at the origin, behind him
	f.fighters[other].facing = Vec3(0, 1, 0)   # and behind the patron
	expect f.reportCrime("assault", f.w.player, innkeeper) == none
	expect f.w.bountyOf(whiterun) == 0
	f.fighters[keeper].facing = Vec3(-1, 0, 0)   # he turns round: the player is in front, in the light
	expect f.reportCrime("assault", f.w.player, innkeeper) != none
	expect f.w.bountyOf(whiterun) == 40
	expect f.w.isDetectedBy(innkeeper) and not f.w.isDetectedBy(patron)

test "a sneak attack on an actor that has not detected the player does twice a fist's damage":
	f = handFight(1, 0)
	f.w.stealth.sneaking = true
	keeper = f.indexOf(innkeeper) ?? fail("no innkeeper")
	f.fighters[keeper].facing = Vec3(1, 0, 0)   # looking away from the player
	f.playerAttacks()
	f.run(1.0)
	expect f.health(innkeeper) == 67.0   # 75 less 4 x fCombatSneakHandMult 2
	expect f.lines.any(.endsWith("sneak attacks Innkeeper"))
	g = handFight(1, 0)
	g.fighters[g.indexOf(innkeeper) ?? fail("no innkeeper")].facing = Vec3(1, 0, 0)
	g.playerAttacks()
	g.run(1.0)
	expect g.health(innkeeper) == 71.0   # not sneaking: a plain hit
