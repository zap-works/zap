# Stealth's rules without the game (game/stealth): the detection formulas of SkyrimSE.exe on values
# worked by hand (the settings as Skyrim.esm sets them, the executable's for the rest), the light
# level, the pickpocket chance and attempt on a world made by hand, and the sneak toggle.

import game
import game.stealth
import engine.swf.avm1
import interface
import skyrim
import skyrim.esm
import game.sim

# the GMSTs stealth reads that Skyrim.esm sets, as it sets them
fn esmSettings():
	{
		"fsneakmaxdistance": 2500.0,
		"fsneakbasevalue": -15.0,
		"fsneakexteriordistancemult": 2.1,
		"fsneakflyingdistancemult": 3.0,
		"fsneaklightmult": 0.33,
		"fsneaklightexteriormult": 0.5,
		"fsneaksoundlosmult": 0.3,
		"fsneaksoundsmult": 1.0,
		"fsneakactionmult": 2.0,
		"fsneakalertmod": 0.0,
		"fsneakambushnontargetmod": 0.0,
		"fsneaksleepbonus": 0.0,
		"fsneaksleepmod": 0.0,
		"fsneakperceptionskillmin": 0.0,
		"fsneakperceptionskillmax": 100.0,
		"fdetectionsneaklightmod": 15.0,
		"fplayerdetectionsneakbase": 10.0,
		"fplayerdetectionsneakmult": 0.4,
		"ilightlevelinteriormod": 25.0,
		"ilightlevelmax": 300.0,
		"fjoginterpolationbetweenwalkandrun": 0.65,
		"fpickpocketactorskillbase": 20.0,
		"fpickpocketactorskillmult": 1.0,
		"fpickpocketamountmult": -0.1,
		"fpickpocketweightmult": -4.0,
		"fpickpocketmaxchance": 90.0,
		"fpickpocketminchance": 0.0
	}

# an NPC of Sneak 40 watching the player (Sneak 15, whom the plugin's settings raise to 16) 500 units
# away in a lit interior
fn watcher():
	stealth.Watcher(sneakSkill = 40.0)

fn player(sneaking bool, moving bool):
	stealth.Quarry(sneakSkill = 15.0, isPlayer = true, sneaking, moving, equippedWeight = 10.0)

fn lit(distance f32, angle f32):
	stealth.Sight(distance, angle, lightRaw = 100.0, ambientMax = 0.2)

test "the reach is 2500 inside, 2.1 times that outside, 3 times that flying; nothing beyond it":
	s = esmSettings()
	expect stealth.maxDistance(s, false, false) == 2500.0
	expect (stealth.maxDistance(s, true, false) - 5250.0).abs() < 0.01
	expect (stealth.maxDistance(s, true, true) - 15750.0).abs() < 0.1
	far = s.readingOf(watcher(), player(true, false), lit(2600.0, 0.0))
	expect far.level == stealth.unseen and not far.lineOfSight

test "a lit sneaking player in front of a watcher is detected: light 26.5, skill 4.8, base -15":
	s = esmSettings()
	r = s.readingOf(watcher(), player(true, false), lit(500.0, 0.0))
	expect (r.light - 26.496).abs() < 0.001 and (r.skill - 4.8).abs() < 0.001 and r.noise == 0.0
	expect r.level == 16 and r.inCone and r.lineOfSight

test "behind the watcher (past half the 190 degree cone) nothing is seen: only the skills count":
	s = esmSettings()
	r = s.readingOf(watcher(), player(true, false), lit(500.0, 3.0))
	expect r.light == 0.0 and not r.inCone and r.level == -10
	blocked = lit(500.0, 0.0)
	blocked.clear = false
	expect s.readingOf(watcher(), player(true, false), blocked).level == -10

test "a value of 0 counts as -1, and one between 0 and 1 as 1":
	s = esmSettings()
	dark = stealth.Sight(distance = 500.0, lightRaw = 20.0, ambientMax = 0.2)
	expect s.readingOf(watcher(), player(true, false), dark).level == -1   # -0.6

test "walking upright adds the noise of the steps and the skill no longer hidden behind: 35":
	s = esmSettings()
	r = s.readingOf(watcher(), player(false, true), lit(500.0, 0.0))
	expect (r.noise - 10.88).abs() < 0.001 and (r.skill - 12.8).abs() < 0.001
	expect (r.light - 26.761).abs() < 0.001 and r.level == 35

test "hearing needs no line of sight but less of it: the noise is 0.3 of what a clear path gives":
	s = esmSettings()
	open = s.readingOf(watcher(), player(false, true), lit(500.0, 0.0))
	shut = lit(500.0, 0.0)
	shut.clear = false
	closed = s.readingOf(watcher(), player(false, true), shut)
	expect (closed.noise - open.noise * 0.3).abs() < 0.001 and closed.light == 0.0

test "a loud action is heard without being seen: a swing of sound level 100 at 1000 units is 21.6":
	s = esmSettings()
	swing = stealth.Quarry(sneakSkill = 15.0, isPlayer = true, action = 100)
	r = s.readingOf(watcher(), swing, stealth.Sight(distance = 1000.0, angle = 3.0))
	expect (r.noise - 21.6).abs() < 0.001   # 100 x 2 x 0.3 x 0.36
	expect r.level == 13

test "the light level: night eye triples it, the interior's ambient (at most 25) is taken off":
	s = esmSettings()
	sight = lit(100.0, 0.0)
	expect s.lightLevelOf(sight, false) == 80   # 100 less the ambient's 20
	expect s.lightLevelOf(sight, true) == 280
	bright = stealth.Sight(distance = 1.0, lightRaw = 500.0, ambientMax = 0.9)
	expect s.lightLevelOf(bright, false) == 300   # 475, held at iLightLevelMax
	outside = stealth.Sight(distance = 1.0, exterior = true, lightRaw = 100.0, ambientMax = 0.9)
	expect s.lightLevelOf(outside, false) == 100

test "a lamp lights a point by its color's mean times its dimmer, less with the square of the distance":
	lamp = stealth.Lamp(
		at = Vec3(0, 0, 0),
		radius = 200.0,
		color = Vec3(1.0, 0.5, 0.0),
		dimmer = 2.0
	)
	lighting = stealth.Lighting(lamps = [lamp], ambient = 0.1, directional = 0.2)
	expect (lighting.lightRawAt(Vec3(0, 0, 0)) - 130.0).abs() < 0.01   # (1 + 0.1 + 0.2) x 100
	half = lighting.lightRawAt(Vec3(100, 0, 0))
	expect (half - ((0.1 + 0.2 + 1.0 * 0.75) * 100.0)).abs() < 0.01
	expect (lighting.lightRawAt(Vec3(300, 0, 0)) - 30.0).abs() < 0.01

test "a sound the player did not make himself: a very loud one carries 3072 units":
	s = esmSettings()
	expect s.heardLevel(200, 2400.0, true, true, false, false) > 0
	expect s.heardLevel(100, 2400.0, true, true, false, false) < 0
	expect s.heardLevel(50, 100.0, false, false, false, false) <
		s.heardLevel(50, 100.0, true, true, false, false)

test "the sight: eyes at 121, 0.57 of it sneaking; the angle is the turn from the facing":
	expect stealth.eyeAt(Vec3(0, 0, 0), false).z == 121.0
	expect (stealth.eyeAt(Vec3(0, 0, 0), true).z - 68.97).abs() < 0.01
	points = stealth.bodyPoints(Vec3(0, 0, 0), 128.0, false)
	expect (points[0].z - 64.0).abs() < 0.001 and (points[1].z - 108.8).abs() < 0.001 and
		(points[2].z - 19.2).abs() < 0.001
	expect stealth.angleToward(0.0, Vec3(0, 0, 0), Vec3(0, 10, 0)).abs() < 0.0001
	expect (stealth.angleToward(0.0, Vec3(0, 0, 0), Vec3(10, 0, 0)) - pi * 0.5).abs() < 0.0001
	expect (stealth.angleToward(pi * 0.75, Vec3(0, 0, 0), Vec3(0, -10, 0)) - pi * 0.25).abs() <
		0.0001

test "the pickpocket chance: 34 for one 100 gold item of weight 1, 25 less seen, kept between the bounds":
	s = esmSettings()
	expect stealth.chanceOf(s, 15.0, 30.0, 100, 1.0, false) == 34   # 33.5
	expect stealth.chanceOf(s, 15.0, 30.0, 100, 1.0, true) == 9   # 8.5
	expect stealth.chanceOf(s, 15.0, 30.0, 1000, 5.0, false) == 0
	expect stealth.chanceOf(s, 100.0, 0.0, 1, 0.0, false) == 90

whiterun = 0x2_67EA
victim = 0x300
gem = 0x400

fn thief(skill f32):
	a = sim.ActorState(npc = 0x7, race = 0, level = 1, values = {}, crimeFaction = 0)
	a.setBaseValue("pickpocket", skill)
	a

fn mark(skill f32):
	a = sim.ActorState(npc = 0x900, race = 0, level = 1, values = {}, crimeFaction = whiterun)
	a.setBaseValue("pickpocket", skill)
	a

# the player sneaking, and an actor holding three gems (value 100, weight 1); `chance` the pickpocket
# chance every attempt has (the settings' bounds both set to it)
fn handWorld(chance f32):
	w = sim.newWorld()
	w.settings = esmSettings()
	w.settings["fpickpocketminchance"] = f64(chance)
	w.settings["fpickpocketmaxchance"] = f64(chance)
	w.stealth.sneaking = true
	for id in [w.player, victim]:
		w.addForm(id)
	w.actors[w.player] = thief(15.0)
	w.actors[victim] = mark(30.0)
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
	w.items[gem] = sim.Item(formId = gem, kind = "MISC", editorId = "gem", name = "Gem", model = "",
		value = 100, weight = 1.0, keywords = [])
	w.inventories[victim] = sim.Inventory()
	w.inventories[victim].addItem(gem, 3)
	w

test "the Sneak command toggles sneaking; only a sneaking player can pickpocket a living actor of a race that allows it":
	w = handWorld(50.0)
	expect w.canPickpocket(victim)
	expect not w.toggleSneak() and not w.canPickpocket(victim)
	expect w.toggleSneak() and w.canPickpocket(victim)
	w.actors[victim].dead = true
	expect not w.canPickpocket(victim)
	w.actors[victim].dead = false
	w.actors[victim].pickpocketable = false
	expect not w.canPickpocket(victim) and not w.canPickpocket(w.player)

test "activating an actor sneaking opens the pickpocket, else the dialogue":
	w = handWorld(50.0)
	w.forms[victim].baseKind = "NPC_"
	expect w.activate(victim, w.player) == sim.Activation.Pickpocketing(victim)
	w.stealth.sneaking = false
	expect w.activate(victim, w.player) == sim.Activation.Talked(victim)

test "the chance shown for a stack is for one item that weighs something, the whole stack of gold":
	w = handWorld(50.0)
	w.settings = esmSettings()
	stack = w.takableFrom(victim)[0]
	expect stack.count == 3 and w.shownChance(victim, stack) == 34   # 20 + 15 + 20 - 7.5 - 10 - 4
	w.items[gem].weight = 0.0
	expect w.shownChance(victim, stack) == 18   # all three: 300 gold, -30, no weight
	w.stealth.detections[victim] = sim.Detection(level = 5)
	w.items[gem].weight = 1.0
	expect w.shownChance(victim, stack) == 9

test "a worn item cannot be taken; the loose ones can":
	w = handWorld(100.0)
	w.inventories[victim].stacks[0].extras.push(sim.ItemExtra(count = 1, worn = true))
	expect w.takableFrom(victim)[0].count == 2
	r = w.attempt(victim, gem, 5)
	expect r == stealth.Pickpocket.Stole(gem, 2)
	expect w.inventories[victim].countOf(gem) == 1 and w.inventories[w.player].countOf(gem) == 2
	expect w.attempt(victim, gem, 1) == stealth.Pickpocket.Refused("{gem:08X} cannot be taken")

test "a pickpocket that succeeds moves the item, stolen from the victim, and no crime follows":
	w = handWorld(100.0)
	expect w.attempt(victim, gem, 2) == stealth.Pickpocket.Stole(gem, 2)
	expect w.inventories[w.player].stacks[0].extras[0].owner == 0x900
	expect w.crimes.isEmpty and not w.isDetectedBy(victim)

test "one that fails makes the victim notice the player and adds a pickpocket crime of 25":
	w = handWorld(0.0)
	expect w.attempt(victim, gem, 1) == stealth.Pickpocket.Caught(25)
	expect w.crimes[0].kind == "pickpocket" and w.crimes.map(.bounty).sum() == 25
	expect w.isDetectedBy(victim) and w.stealth.detections[victim].level == 100
	expect w.notifications.any(it == stealth.caughtText)
	expect w.inventories[victim].countOf(gem) == 3 and w.inventories.get(w.player) == none

fn sixAttempts(mut w sim.GameWorld):
	got = []
	loop 6:
		w.inventories[victim] = sim.Inventory()
		w.inventories[victim].addItem(gem, 1)
		got.push(w.attempt(victim, gem, 1).stole())
	got

fn stole(r stealth.Pickpocket):
	match r:
		Stole: true
		_: false

test "the rolls come from the world's own sequence: the same state gives the same attempts":
	a = handWorld(50.0)
	b = handWorld(50.0)
	expect a.sixAttempts() == b.sixAttempts() and a.stealth.roll == b.stealth.roll
	expect a.stealth.roll != 17

test "the player's noise is heard for fActorAlertSoundTimer seconds, then fades":
	w = handWorld(50.0)
	player = stealth.Placed(actor = w.player, feet = Vec3(0, 0, 0), heading = 0.0)
	watcher = stealth.Placed(actor = victim, feet = Vec3(0, 800, 0), heading = 0.0)   # facing away
	lighting = stealth.Lighting()
	w.actors[victim].setBaseValue("sneak", 50.0)
	w.stepDetections(lighting, player, [watcher], 1.0)
	quiet = w.stealth.detections[victim].level
	w.makeNoise(100)
	w.stealth.detections = {}
	w.stepDetections(lighting, player, [watcher], 1.0)
	loud = w.stealth.detections[victim].level
	expect loud > quiet and loud > 0 and quiet <= 0
	w.stealth.clock += 6.0
	w.stealth.detections = {}
	w.stepDetections(lighting, player, [watcher], 1.0)
	expect w.stealth.detections[victim].level == quiet

test "a reading is kept for fDetectionUpdateTimeMin seconds before the watcher looks again":
	w = handWorld(50.0)
	player = stealth.Placed(actor = w.player, feet = Vec3(0, 0, 0), heading = 0.0)
	watcher = stealth.Placed(actor = victim, feet = Vec3(0, 300, 0), heading = pi)
	lighting = stealth.Lighting(ambient = 1.0, ambientMax = 0.25)
	w.stepDetections(lighting, player, [watcher], 0.4)
	first = w.stealth.detections[victim]
	expect first.level > 0 and first.inCone and first.at == 0.0
	moved = stealth.Placed(actor = victim, feet = Vec3(0, 300, 0), heading = 0.0)   # turns away
	w.stepDetections(lighting, player, [moved], 0.4)
	expect w.stealth.detections[victim].level == first.level   # 0.4 s: not read again
	w.stepDetections(lighting, player, [moved], 0.4)
	w.stepDetections(lighting, player, [moved], 0.4)
	expect w.stealth.detections[victim].level < 0 and w.stealth.detections[victim].at > 1.0

test "a sound level code is the setting's value: Loud 100, Normal 50, Silent 0, Very Loud 200":
	s = esmSettings()
	expect [0, 1, 2, 3].map(s.soundValue(it)) == [100, 50, 0, 200]
	expect s.soundValue(9) == 0

test "a detection event is one an actor, replaced by the next, gone after fDetectionEventExpireTime":
	w = handWorld(50.0)
	w.createEvent(victim, Vec3(1, 2, 3), 50)
	expect w.eventOf(victim)?.sound == 50 and w.eventOf(victim)?.at == Vec3(1, 2, 3)
	w.createEvent(victim, Vec3(4, 5, 6), 100)
	expect w.eventOf(victim)?.sound == 100 and w.stealth.events.len == 1
	w.stealth.clock += 4.9
	expect w.eventOf(victim) != none
	w.stealth.clock += 0.2
	expect w.eventOf(victim) == none
	expect w.stealth.action == 0   # a noise of someone else is not the player's action
	w.createEvent(w.player, Vec3(0, 0, 0), 100)
	expect w.stealth.action == 100

test "an event carries 1536 units, twice that when very loud, and only the player's own distance counts":
	s = esmSettings()
	expect s.eventReach(100) == 1536.0 and s.eventReach(200) == 3072.0
	ear = stealth.Ear(feet = Vec3(0, 1500, 0), eye = Vec3(0, 1500, 121), watchedFights = true)
	near = sim.DetectionEvent(sound = 100, at = Vec3(0, 0, 0), time = 0.0)
	expect s.hearEvent(ear, near) != none
	far = stealth.Ear(feet = Vec3(0, 1600, 0), eye = Vec3(0, 1600, 121), watchedFights = true)
	expect s.hearEvent(far, near) == none
	loud = sim.DetectionEvent(sound = 200, at = Vec3(0, 0, 0), time = 0.0)
	expect s.hearEvent(far, loud) != none

test "a watcher listens when it fights, the player fights or it would attack him, never to a friend":
	quiet = stealth.Ear(feet = Vec3(0, 0, 0), eye = Vec3(0, 0, 121))
	expect not quiet.canHear()
	expect stealth.Ear(feet = quiet.feet, eye = quiet.eye, fights = true).canHear()
	expect stealth.Ear(feet = quiet.feet, eye = quiet.eye, watchedFights = true).canHear()
	expect stealth.Ear(feet = quiet.feet, eye = quiet.eye, hostile = true).canHear()
	expect not stealth.Ear(
		feet = quiet.feet,
		eye = quiet.eye,
		fights = true,
		friendly = true
	).canHear()

test "a sound behind the watcher is in its view cone when its eye reaches it, and a hidden one is not":
	s = esmSettings()
	expect s.isInCone(true, pi) and not s.isInCone(false, 0.0)
	behind = s.heardLevel(100, 800.0, true, true, false, false)
	hidden = s.heardLevel(100, 800.0, false, false, false, false)
	expect behind == 118 and hidden == 12
	expect s.heardLevel(100, 800.0, true, true, true, false) < behind   # asleep: the light is lost

test "a watcher that heard the player's event reads level 0 and the place of the sound, and has not detected him":
	w = handWorld(50.0)
	player = stealth.Placed(actor = w.player, feet = Vec3(0, 0, 0), heading = 0.0, fighting = true)
	watcher = stealth.Placed(actor = victim, feet = Vec3(0, 800, 0), heading = 0.0)   # facing away
	lighting = stealth.Lighting()
	w.stepDetections(lighting, player, [watcher], 1.0)
	expect not w.stealth.detections[victim].heard
	w.createEvent(w.player, Vec3(10, 20, 0), 50)
	w.stealth.detections = {}
	w.stepDetections(lighting, player, [watcher], 1.0)
	d = w.stealth.detections[victim]
	expect d.heard and d.level == 0 and d.noiseAt == Vec3(10, 20, 0)
	expect not w.isDetectedBy(victim)
	w.stealth.clock += 6.0   # the event is gone
	w.stealth.detections = {}
	w.stepDetections(lighting, player, [watcher], 1.0)
	expect not w.stealth.detections[victim].heard
	calm = stealth.Placed(actor = w.player, feet = Vec3(0, 0, 0), heading = 0.0)
	w.createEvent(w.player, Vec3(10, 20, 0), 50)
	w.stealth.detections = {}
	w.stepDetections(lighting, calm, [watcher], 1.0)   # nobody fights: nobody listens
	expect not w.stealth.detections[victim].heard

test "a sight above 0 is kept over a noise, and the watched's projectiles in the air are heard within 1024":
	w = handWorld(50.0)
	player = stealth.Placed(actor = w.player, feet = Vec3(0, 0, 0), heading = 0.0, fighting = true)
	lighting = stealth.Lighting(ambient = 1.0, ambientMax = 0.25)
	seeing = stealth.Placed(actor = victim, feet = Vec3(0, 300, 0), heading = pi)
	w.createEvent(w.player, Vec3(0, 0, 0), 100)
	w.stepDetections(lighting, player, [seeing], 1.0)
	expect w.stealth.detections[victim].level > 0 and not w.stealth.detections[victim].heard
	away = stealth.Placed(actor = victim, feet = Vec3(0, 1300, 0), heading = 0.0)
	w.stealth.events = {}
	w.stealth.flying = [sim.FlyingProjectile(owner = victim, at = Vec3(0, 1000, 0))]
	w.stealth.detections = {}
	w.stepDetections(lighting, player, [away], 1.0)
	expect not w.stealth.detections[victim].heard   # not the player's projectile
	w.stealth.flying = [sim.FlyingProjectile(owner = w.player, at = Vec3(0, 1000, 0))]
	w.stealth.detections = {}
	w.stepDetections(lighting, player, [away], 1.0)
	d = w.stealth.detections[victim]
	expect d.heard and d.noiseAt == Vec3(0, 1000, 0)
	w.stealth.flying = [sim.FlyingProjectile(owner = w.player, at = Vec3(0, 200, 0))]
	w.stealth.detections = {}
	w.stepDetections(lighting, player, [away], 1.0)   # 1100 from the head
	expect not w.stealth.detections[victim].heard

inn = "RiverwoodSleepingGiantInn"
orgnar = 0x1_3486

# the inn as a new game has it: its world, and the light its cell gives
fn innByNight() (sim.GameWorld, stealth.Lighting)?:
	install, plugin = try skyrim.installAndPlugin()
	names = install.readNames("Skyrim.esm") ?? fail("no names")
	w = install.worldOfCell(plugin, names, inn) ?? fail("no world")
	cell = plugin.findCell(inn) ?? fail("no cell")
	(w, plugin.detectionLightingOf(cell))

# a body placed at `feet`, facing `heading`
fn placedAt(actor i64, feet Vec3, heading f32, sneaking bool):
	stealth.Placed(actor, feet, heading, sneaking)

test "in the inn Orgnar sees a player come up to the bar and has not seen one who sneaks up behind him":
	w, lighting = innByNight() ?? return
	form = w.forms[orgnar]
	here = Vec3(form.x, form.y, form.z)
	facing = form.rotation.z
	ahead = Vec3(facing.sin(), facing.cos(), 0.0)
	watcher = placedAt(orgnar, here, facing, false)
	front = placedAt(w.player, here + ahead * 250.0, facing + pi, false)
	back = placedAt(w.player, here - ahead * 250.0, facing, true)
	w.stealth.sneaking = false
	seen = w.readWatcher(lighting, watcher, front)
	expect seen.level > 0 and seen.lineOfSight
	w.stealth.sneaking = true
	behind = w.readWatcher(lighting, watcher, back)
	expect behind.level <= 0 and not behind.lineOfSight

test "in the inn a sneaking player pickpockets Orgnar: his loose items with their chances, a failure costs the hold's 25":
	w, _ = innByNight() ?? return
	expect w.activate(orgnar, w.player) == sim.Activation.Talked(orgnar)
	w.stealth.sneaking = true
	expect w.activate(orgnar, w.player) == sim.Activation.Pickpocketing(orgnar)
	loose = w.takableFrom(orgnar)
	expect not loose.isEmpty
	for s in loose:
		chance = w.shownChance(orgnar, s)
		expect chance >= 0 and chance <= 90
	w.settings["fpickpocketminchance"] = 0.0
	w.settings["fpickpocketmaxchance"] = 0.0
	faction = w.actors[orgnar].crimeFaction
	r = w.attempt(orgnar, loose[0].form, 1)
	expect r == stealth.Pickpocket.Caught(w.crimeValues[faction].pickpocket)
	expect w.isDetectedBy(orgnar) and w.crimes[0].kind == "pickpocket"

test "the HUD's eye comes up while the player sneaks and closes on 100 once someone detects him":
	install, _ = skyrim.installAndPlugin() ?? return
	p = install.openHud(1280, 720) ?? fail("no hud")
	eye = interface.StealthEye()
	p.updateStealth(eye, 0, true)
	expect eye.visible and eye.shown == 0
	loop 40:
		p.updateStealth(eye, 100, true)
		p.advance()
	expect eye.shown == 100 and eye.settled == 100
	frame = p.read("HUDMovieBaseInstance.StealthMeterInstance.SneakAnimInstance._currentframe")
	expect frame.primitiveNumber() > 100.0
	p.updateStealth(eye, 100, false)
	expect not eye.visible

test "the pickpocket menu opens on Orgnar's loose items, each card carrying the chance of taking it":
	install, _ = skyrim.installAndPlugin() ?? return
	w, _ = innByNight() ?? return
	w.stealth.sneaking = true
	texts = install.openTexts(w.settings) ?? fail("no texts")
	menu = install.openPickpocket(texts, w, orgnar, 1280, 720) ?? fail("no menu")
	expect menu.pickpocket and menu.open and menu.container == orgnar
	first = menu.p.read("Menu_mc.InventoryLists_mc.ItemsList.entryList.0.card.pickpocketChance")
	expect first.primitiveNumber() >= 0.0 and first.primitiveNumber() <= 90.0
	expect menu.p.read("Menu_mc.bNPCMode").primitiveNumber() > 0.0
