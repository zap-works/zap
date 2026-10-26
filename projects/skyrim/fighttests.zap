# Combat (game/combat): the inn's actors as the game rates them, and a fight there.

import fs
import skyrim
import skyrim.actor
import skyrim.esm
import skyrim.hkx
import engine
import engine.swf.avm1
import game
import game.sim
import game.combat
import interface

inn = "RiverwoodSleepingGiantInn"

# Combat (game/combat): the inn's actors as the game rates them, and a fight there.
fn withInnFight(seed i64, weapon str) combat.Fight?:
	install, plugin = try skyrim.installAndPlugin()
	f = plugin.cellFight(install, inn, weapon, seed) ?? fail
	f.lighting = plugin.detectionLightingOf(plugin.findCell(inn) ?? fail("no cell"))
	f

fn fighterIn(f combat.Fight, name str):
	f.fighters[f.fighterNamed(name) ?? fail("no {name}")].copy()

test "a Nord at level 1: 100 health, magicka and stamina, 15 in every skill and the race's boosts":
	f = withInnFight(1, "") ?? return
	a = f.w.actors[f.w.player]
	expect a.valueOf("health") == 100.0 and a.valueOf("magicka") == 100.0 and
		a.valueOf("stamina") == 100.0
	boosted = {
		"twohanded": 25.0,
		"onehanded": 20.0,
		"block": 20.0,
		"smithing": 20.0,
		"speechcraft": 20.0,
		"lightarmor": 20.0
	}
	for name in sim.skillNames:
		expect f64(a.valueOf(name)) == (boosted.get(name) ?? 15.0)
	expect a.valueOf("healrate") == 0.7 and a.valueOf("staminarate") == 5.0
	expect a.valueOf("unarmeddamage") == 4.0

test "the player's iron dagger shows 4 at One-Handed 20; fists do the Nord's 4 and reach 96":
	f = withInnFight(1, "IronDagger") ?? return
	x = f.fighterIn("Player")
	expect x.weaponName == "Iron Dagger" and x.baseDamage == 4.0 and x.speed == 1.3
	expect f.w.settings.shownDamage(x.baseDamage, f.w.actors[f.w.player].valueOf(x.skill), true) ==
		4
	g = withInnFight(1, "") ?? return
	fists = g.fighterIn("Player")
	expect fists.weapon == 0 and fists.baseDamage == 4.0 and fists.reach == 96.0

test "Orgnar (level 4) and Delphine (level 10) have the health, magicka and stamina their records store":
	f = withInnFight(1, "") ?? return
	stored = {"Orgnar": [75.0, 60.0, 60.0], "Delphine": [190.0, 95.0, 100.0]}
	for name, want in stored:
		a = f.w.actors[f.fighterIn(name).refId]
		expect sim.attributeNames.map(f64(a.valueOf(it))) == want
	orgnar = f.fighterIn("Orgnar")
	expect orgnar.weaponName == "Iron Mace" and orgnar.ai.confidence == 3 and not orgnar.essential
	expect f.fighterIn("Delphine").essential and
		f.fighterIn("Delphine").style.editorId == "csDelphine"

test "the attacks' timings are measured on the behavior graph: the clips' lengths and their HitFrames":
	f = withInnFight(1, "") ?? return
	right = f.timings.armed.normal[0]
	expect (right.duration - 1.3).abs() < 0.001 and (right.hit - 0.367).abs() < 0.001
	jab = f.timings.unarmed.normal[0]
	expect (jab.duration - 1.1333).abs() < 0.001 and (jab.hit - 0.533).abs() < 0.001
	power = f.timings.armed.power
	expect (power.duration - 1.5).abs() < 0.001 and (power.hit - 0.733).abs() < 0.001
	punch = f.timings.unarmed.power
	expect (punch.duration - 1.6667).abs() < 0.001 and (punch.hit - 0.801).abs() < 0.001
	expect (f.timings.staggers.lengthAt(0.25) - 1.5667).abs() < 0.001
	expect f.speeds.run == 370.0 and f.speeds.sprint == 500.0

# the graph and the clips' lengths, with a sword fighter whose stance the events set
type Staged:
	graph hkx.Graph
	lengths {str: f32}
	fighter combat.Fighter
	animator game.Animator
	seen game.Seen

fn staged() Staged?:
	install, _ = try skyrim.installAndPlugin()
	g = install.readCharacterGraph() ?? fail
	f = try withInnFight(1, "IronSword")
	Staged(graph = g, lengths = install.clipDurations(g.clipNamesOf()),
		fighter = f.fighterIn("Player"), animator = g.newWalker(true).animator, seen = game.Seen())

# the events of the fighter's state sent, the graph run `seconds` at 60 a second; the times the
# HitFrame fired are returned
fn tellAndRun(mut s Staged, out bool, seconds f32):
	stance = game.Stance(out, right = s.fighter.animation, left = 0)
	s.animator.sendFightEvents(s.seen, s.fighter, stance, none)
	hits = []
	t = f32(0.0)
	while t < seconds:
		s.animator.stepAnimator(s.graph, s.lengths, 1.0 / 60.0)
		t += 1.0 / 60.0
		for fired in s.animator.fired:
			if fired.event == game.hitMark: hits.push(t)
	hits

fn playing(s Staged):
	s.animator.layers[0].clip if not s.animator.layers.isEmpty else ""

test "a sword fighter's draw, swings, block, bash, stagger and sheathe are the graph's own clips":
	s = staged() ?? return
	expect s.fighter.animation == 1
	s.tellAndRun(true, 0.5)
	expect s.playing() == "1hm_equip"
	s.tellAndRun(true, 2.0)
	expect s.playing() == "1hm_idle"
	s.fighter.swing = combat.Swing(strike = .Normal, hitAt = 0.0, endsAt = 1.0)
	hits = s.tellAndRun(true, 0.2)
	expect s.playing() == "1hm_attackright" and hits.isEmpty
	hits = s.tellAndRun(true, 1.5)
	s.fighter.swing = combat.Swing(strike = .Power, hitAt = 0.0, endsAt = 2.0)
	s.tellAndRun(true, 0.3)
	expect s.playing() == "1hm_attackpowerfwd"
	s.tellAndRun(true, 3.0)
	s.fighter.swing = none
	s.fighter.mode = .Block
	s.tellAndRun(true, 0.5)
	expect s.playing() == "1hm_blockidle"
	s.fighter.swing = combat.Swing(strike = .Bash, hitAt = 0.0, endsAt = 1.0)
	s.tellAndRun(true, 0.3)
	expect s.playing() == "1hm_blockbashintro"
	s.tellAndRun(true, 1.5)
	expect s.playing() == "1hm_blockidle"
	s.fighter.swing = none
	s.fighter.mode = .Idle
	s.tellAndRun(true, 2.0)
	s.fighter.mode = .Staggered
	s.tellAndRun(true, 0.3)
	expect s.playing().startsWith("1hm_staggerback")
	s.fighter.mode = .Idle
	s.tellAndRun(true, 3.0)
	expect s.playing() == "1hm_idle"
	s.tellAndRun(false, 0.5)
	expect s.playing() == "1hm_unequip"
	s.tellAndRun(false, 3.0)
	expect s.playing() == "mt_idle"

test "a swing lands at the HitFrame the graph's clip sends, the weapon's speed shortening it":
	s = staged() ?? return
	s.tellAndRun(true, 3.0)
	want = s.fighter.speed
	s.fighter.swing = combat.Swing(strike = .Normal, hitAt = 0.0, endsAt = 1.0)
	hits = s.tellAndRun(true, 1.0)
	expect hits.len == 1
	first = hits[0] - 1.0 / 60.0
	expect (first - 0.367 / want).abs() < 0.03

test "a fighter killed is the ragdoll of the graph's master machine, a bleeding one its bleedout":
	s = staged() ?? return
	s.tellAndRun(true, 2.0)
	s.fighter.mode = .Bleedout
	s.tellAndRun(true, 1.0)
	expect s.animator.stateNameOf(s.graph, "RootBehaviorGraph") == "BleedOut_State"
	s.fighter.mode = .Idle
	s.tellAndRun(true, 3.0)
	s.fighter.ragdoll = true
	s.tellAndRun(true, 0.5)
	expect s.animator.stateNameOf(s.graph, "Master_Behavior") == "FullyRagdoll"

test "punching Orgnar is an assault of 40 to Whiterun: he fights back, Delphine, who saw it, watches; Embry, who did not, stays out of it":
	f = withInnFight(1, "") ?? return
	k = f.fighterNamed("Player") ?? fail("no player")
	orgnar = f.fighterIn("Orgnar")
	f.engage(k, orgnar.refId)
	f.run(4.0)
	expect f.w.bountyOf(0x2_67EA) == 40
	expect f.fighterIn("Orgnar").target == f.w.player and f.fighterIn("Orgnar").isFighting()
	expect f.fighterIn("Delphine").mode == .Alert
	# A punch makes no detection event (only spells, explosions, impacts and scripts do, hearing.zap):
	# Embry, a thousand units off and facing away, has only the player's Normal action noise, which
	# reaches him as no detection and no sound heard, so he stays idle as the exe's rules leave him.
	embry = f.fighterIn("Embry")
	expect f.w.stealth.events.isEmpty and not f.w.stealth.detections[embry.refId].heard
	expect embry.mode == .Idle and not f.w.isDetectedBy(embry.refId)

test "Orgnar dies at 0 health (a murder of 1000), Delphine bleeds out: she is essential":
	f = withInnFight(1, "") ?? return
	k = f.fighterNamed("Player") ?? fail("no player")
	for name in ["Orgnar", "Delphine"]:
		f.hurt(f.fighterNamed(name) ?? fail("no {name}"), k, 1000.0)
	expect f.fighterIn("Orgnar").mode == .Dead and f.fighterIn("Orgnar").ragdoll
	expect f.fighterIn("Delphine").mode == .Bleedout
	expect f.w.bountyOf(0x2_67EA) == 1040   # the murder, then the assault on Delphine

test "the player's fist fight with Orgnar ends within a minute, one of them dead or fled, the same for the seed":
	a = withInnFight(7, "") ?? return
	a.engage(a.fighterNamed("Player") ?? fail("no player"), a.fighterIn("Orgnar").refId)
	expect a.run(60.0) < 60.0
	ends = ["Player", "Orgnar"].map(a.fighterIn(it).mode)
	expect ends.any(it == .Dead or it == .Fled)
	b = withInnFight(7, "") ?? return
	b.engage(b.fighterNamed("Player") ?? fail("no player"), b.fighterIn("Orgnar").refId)
	b.run(60.0)
	expect a.lines == b.lines

fn heldInput(frame i64, draw i64, attackFrom i64, attackTo i64, block bool = false):
	game.Input(forward = 0.0, right = 0.0, run = false, look = IVec2(0, 0), draw = frame == draw,
		attack = frame >= attackFrom and frame < attackTo, block)

# the player drawn beside Orgnar, facing him, as a scene would stand them (no bodies here)
fn playerBeside(mut scene game.FightScene, name str):
	foe = scene.fight.fighters[scene.fight.fighterNamed(name) ?? fail("no {name}")]
	scene.fight.fighters[scene.player].at = foe.at + Vec3(-60.0, 0.0, 0.0)
	scene.fight.fighters[scene.player].facing = Vec3(1.0, 0.0, 0.0)

test "a scripted punch takes the formula's damage off Orgnar, is an assault, and the enemy meter shows it":
	install, _ = skyrim.installAndPlugin() ?? return
	f = withInnFight(1, "") ?? return
	orgnar = f.fighterIn("Orgnar")
	before = f.health(orgnar.refId)
	punch = f.fighterIn("Player").baseDamage * f.w.settings.strikeMultiplier(.Normal, true)
	want = combat.damageTaken(punch, f.w.settings.armorReduction(orgnar.armorRating,
		orgnar.armorPieces), 0.0)
	scene = game.newFightScene(f)
	scene.playerBeside("Orgnar")
	dt f32 = 1.0 / 60.0
	for frame in 0..300:
		scene.controlPlayer(heldInput(frame, 0, 5, 8), dt)
		scene.advanceFight(dt)
		if scene.fight.health(orgnar.refId) < before: break
	expect scene.drawn and (before - scene.fight.health(orgnar.refId) - want).abs() < 0.01
	expect scene.fight.w.crimes.any(.kind == "assault" and .refId == orgnar.refId)
	expect scene.fight.w.bountyOf(0x2_67EA) == 40
	expect scene.fight.lines.any(.endsWith("Orgnar fights Player"))
	shown = interface.HudState(enemy = scene.enemyPercent())
	expect (
		shown.enemy - f64(scene.fight.w.actors[orgnar.refId].percentOf("health")) * 100.0
	).abs() <
		0.01 and shown.enemy < 100.0
	p = install.openHud(1280, 960) ?? fail
	loop 10:
		p.updateHud(shown)
		p.advance()
	expect p.read("HUDMovieBaseInstance.EnemyHealth_mc._alpha") == .Num(100.0)
	expect p.read("HUDMovieBaseInstance.EnemyHealthMeter.CurrentPercent") is Num(x) and
		x.isClose(shown.enemy, 0.5)
	hidden = interface.HudState()
	p.updateHud(hidden)
	expect p.read("HUDMovieBaseInstance.EnemyHealth_mc._alpha") == .Num(0.0)

test "R draws and sheathes, a sheathed click strikes nothing, the right button blocks, the held left one power attacks":
	f = withInnFight(1, "") ?? return
	scene = game.newFightScene(f)
	scene.playerBeside("Orgnar")
	dt f32 = 1.0 / 60.0
	scene.controlPlayer(heldInput(0, 99, 0, 5), dt)
	expect not scene.drawn and scene.fight.fighters[scene.player].mode == .Idle
	scene.controlPlayer(heldInput(0, 0, 9, 9), dt)
	expect scene.drawn
	scene.controlPlayer(heldInput(1, 99, 9, 9, block = true), dt)
	expect scene.fight.fighters[scene.player].mode == .Block
	scene.controlPlayer(heldInput(2, 99, 9, 9), dt)
	expect scene.fight.fighters[scene.player].mode == .Guard
	for frame in 0..40:
		scene.controlPlayer(heldInput(frame, 99, 0, 40), dt)
		scene.advanceFight(dt)
	expect scene.fight.lines.any(.endsWith("Player power attacks with fists"))
	scene.controlPlayer(heldInput(0, 0, 9, 9), dt)
	expect not scene.drawn

test "the inn's navmesh: 323 vertices, 379 triangles, each neighbour across an edge sharing it":
	_, plugin = skyrim.installAndPlugin() ?? return
	m = plugin.cellNavmesh(inn) ?? fail("no {inn}")
	expect m.vertices.len == 323 and m.triangleCount() == 379
	for t in 0..m.triangleCount():
		for e in 0..3:
			u = m.neighbours[t * 3 + e]
			if u < 0: continue
			expect t in m.neighbours[u * 3..u * 3 + 3]
			a = m.triangles[t * 3 + e]
			b = m.triangles[t * 3 + (e + 1) % 3]
			expect a in m.triangles[u * 3..u * 3 + 3] and b in m.triangles[u * 3..u * 3 + 3]

# The door is the player's start inside the load door; the bar Orgnar's sandbox marker behind the
# counter, which the path goes round: it bends, and each of its legs lies over the navmesh (or on
# its border, where a leg runs along an edge from corner to corner).
test "a path from the door to the bar exists, goes round the counter and stays on the navmesh":
	_, plugin = skyrim.installAndPlugin() ?? return
	m = plugin.cellNavmesh(inn) ?? fail("no {inn}")
	cell = plugin.findCell(inn) ?? fail("no {inn}")
	door = Vec3(-308.0, -337.0, 0.0)
	bar = (cell.refs.find(.formId == 0xB_D056) ?? fail("no marker")).position
	path = m.findPath(door, bar) ?? fail("no path")
	expect path.len >= 4 and (path[0] - door).length() < 1.0
	expect (path[len - 1] - bar).length() < 1.0
	for k in 0..path.len - 1:
		for s in 0..=8:
			p = path[k] + (path[k + 1] - path[k]) * (f32(s) / 8.0)
			_, on = m.nearestPoint(p)
			expect (on - p).length() < 1.0

test "the graph's stagger blend gives the places and lengths a stagger is clamped and timed by":
	f = withInnFight(1, "") ?? return
	s = f.timings.staggers
	expect s.magnitudes == [0.0, 0.25, 0.5, 0.75, 1.0] and s.lengths.all(it > 0.5)
	expect s.clampMagnitude(3.0) == 1.0 and s.clampMagnitude(-1.0) == 0.0
	between = s.lengthAt(0.125)
	expect between >= s.lengths[0].min(s.lengths[1]) and between <= s.lengths[0].max(s.lengths[1])

test "a stagger plays the clip of the magnitude the fighter was hit with":
	s = staged() ?? return
	s.tellAndRun(true, 2.0)
	s.fighter.staggerMagnitude = 1.0
	s.fighter.mode = .Staggered
	s.tellAndRun(true, 0.3)
	big = s.playing()
	expect s.animator.variableOf(game.staggerVariable) == 1.0
	s.fighter.mode = .Idle
	s.tellAndRun(true, 3.0)
	s.fighter.staggerMagnitude = 0.0
	s.fighter.mode = .Staggered
	s.tellAndRun(true, 0.3)
	small = s.playing()
	expect big.startsWith("1hm_staggerback") and small.startsWith("1hm_staggerback") and
		big != small
