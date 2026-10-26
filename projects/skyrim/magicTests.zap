# The player's magic (game/sim/spells.zap, game/combat/magic.zap): the spells a new player knows,
# what casting them costs and does, the hands they go in; skipped quietly without the install.

import fs
import skyrim
import skyrim.actor
import skyrim.esm
import skyrim.hkx
import game
import game.sim
import game.combat
import game.stealth

inn = "RiverwoodSleepingGiantInn"
flames = 0x1_2FCD
healing = 0x1_2FCC

fn withInnFight(seed i64) combat.Fight?:
	install, plugin = try skyrim.installAndPlugin()
	names = install.readNames("Skyrim.esm") ?? fail
	w = install.worldOfCell(plugin, names, inn) ?? fail
	plugin.sceneFight(w, install.timingsOf() ?? fail, seed) ?? fail

# the fight with the player at the origin facing east and Orgnar 200 units ahead of him
fn faceToFace() combat.Fight?:
	f = try withInnFight(1)
	k = f.fighterNamed("Player") ?? fail("no player")
	j = f.fighterNamed("Orgnar") ?? fail("no Orgnar")
	f.fighters[k].at = Vec3(0, 0, 0)
	f.fighters[k].facing = Vec3(1, 0, 0)
	f.fighters[j].at = Vec3(200, 0, 0)
	f

test "a new player knows Flames and Healing, a Nord's power, and nothing else to cast":
	f = withInnFight(1) ?? return
	cast = f.w.castableSpells(f.w.player)
	expect flames in cast and healing in cast and cast.len == 3
	known = f.w.actors[f.w.player].magic.known
	expect known.len > cast.len   # the abilities, which no hand casts
	expect f.w.spells[flames].name == "Flames" and f.w.spells[healing].name == "Healing"
	expect f.w.spells[flames].school == "destruction" and
		f.w.spells[healing].school == "restoration"
	expect f.w.spells[flames].level == 0 and f.w.spells[healing].level == 0

test "Flames is a held, aimed spell of 14 magicka a second, 8 fire damage a second; Healing 12 for 10 health":
	f = withInnFight(1) ?? return
	fl = f.w.spells[flames]
	expect fl.cost == 14.0 and fl.castType == .Concentration and fl.target == .Aimed
	expect fl.effects.len == 1 and fl.effects[0].magnitude == 8.0
	m = f.w.magicEffects[fl.effects[0].effect]
	expect m.resist == "fireresist" and m.value == "health" and m.skill == "destruction"
	stream = f.w.projectiles[m.projectile]
	expect stream.kind == sim.projectileFlame and stream.range == 768.0 and stream.speed == 1000.0
	he = f.w.spells[healing]
	expect he.cost == 12.0 and he.target == .Caster and he.effects[0].magnitude == 10.0

test "holding Flames for a second costs 14 magicka and does Orgnar 8 points of fire damage, a crime":
	f = faceToFace() ?? return
	k = f.fighterNamed("Player") ?? fail("no player")
	j = f.fighterNamed("Orgnar") ?? fail("no Orgnar")
	orgnar = f.fighters[j].refId
	magicka = f.w.actors[f.w.player].valueOf("magicka")
	health = f.w.actors[orgnar].valueOf("health")
	expect f.startCast(k, flames, false) == none
	loop 60:
		f.stepOnce()
	f.stopCast(k)
	spent = magicka - f.w.actors[f.w.player].valueOf("magicka")
	expect (spent - 14.0).abs() < 0.3
	expect (health - f.w.actors[orgnar].valueOf("health") - 8.0).abs() < 0.3
	expect f.w.crimes.any(.kind == "assault")

test "Flames reaches the nearest in front within 768 units: nothing behind the caster, nothing beyond":
	f = faceToFace() ?? return
	k = f.fighterNamed("Player") ?? fail("no player")
	j = f.fighterNamed("Orgnar") ?? fail("no Orgnar")
	orgnar = f.fighters[j].refId
	f.fighters[j].at = Vec3(900, 0, 0)
	f.startCast(k, flames, false)
	loop 30:
		f.stepOnce()
	expect f.w.actors[orgnar].valueOf("health") == f.w.actors[orgnar].baseValueOf("health")
	f.fighters[j].at = Vec3(-200, 0, 0)
	loop 30:
		f.stepOnce()
	expect f.w.actors[orgnar].valueOf("health") == f.w.actors[orgnar].baseValueOf("health")
	f.fighters[j].at = Vec3(700, 0, 0)
	loop 30:
		f.stepOnce()
	expect f.w.actors[orgnar].valueOf("health") < f.w.actors[orgnar].baseValueOf("health")

test "Healing held for a second costs 12 magicka and gives back 10 health":
	f = faceToFace() ?? return
	k = f.fighterNamed("Player") ?? fail("no player")
	player = f.w.player
	f.w.actors[player].damageValue("health", 60.0)
	health = f.w.actors[player].valueOf("health")
	magicka = f.w.actors[player].valueOf("magicka")
	expect f.startCast(k, healing, false) == none
	loop 60:
		f.stepOnce()
	f.stopCast(k)
	gained = f.w.actors[player].valueOf("health") - health
	expect gained >= 10.0 and gained < 11.0   # and the race's 0.7 a second regeneration
	expect (magicka - f.w.actors[player].valueOf("magicka") - 12.0).abs() < 0.3

test "a held spell ends when the magicka does; a caster with none cannot start one":
	f = faceToFace() ?? return
	k = f.fighterNamed("Player") ?? fail("no player")
	player = f.w.player
	f.w.actors[player].damageValue("magicka", 95.0)
	f.startCast(k, flames, false)
	loop 60:
		f.stepOnce()
	expect f.fighters[k].casting == none
	f.w.actors[player].damageValue("magicka", 100.0)
	expect f.startCast(k, flames, false) is why and "magicka" in why

test "a spell goes in a hand taking off what held it, a weapon in that hand takes the spell out":
	f = withInnFight(1) ?? return
	player = f.w.player
	install, plugin = skyrim.installAndPlugin() ?? return
	sword = plugin.formByEditorId("WEAP", "IronSword") ?? fail("no IronSword")
	f.w.learnItem(plugin, install.readNames("Skyrim.esm") ?? fail, sword)
	f.w.inventories[player].addItem(sword, 1)
	f.w.inventories[player].equip(f.w.items, sword, false) ?? fail
	expect f.w.inventories[player].isWorn(sword)
	expect f.w.equipSpell(player, flames, false) == none
	expect not f.w.inventories[player].isWorn(sword) and f.w.spellIn(player, false) == flames
	expect f.w.equipSpell(player, healing, true) == none
	expect f.w.spellIn(player, true) == healing and f.w.spellIn(player, false) == flames
	f.w.inventories[player].equip(f.w.items, sword, false) ?? fail
	f.w.settleHands(player)
	expect f.w.spellIn(player, false) == 0 and f.w.spellIn(player, true) == healing
	expect f.w.equipSpell(player, 0x1_0000, false) is why and "no spell" in why

# a caster's animator with the spell hand drawn, run until its stance is ready
fn magicAnimator(g hkx.Graph, lengths {str: f32}, left bool):
	a = g.newWalker(true).animator
	a.takeStance(
		game.handFists if left else game.handSpell,
		game.handSpell if left else game.handFists,
		true)
	a.sendEvent(game.drawMagicEvent)
	loop 60: a.stepAnimator(g, lengths, 1.0 / 30.0)
	a

# the clips (the heaviest each frame, in order) the graph plays for seconds after the cast starts,
# and the second the clips' fire mark came, -1 when it did not
type Casting:
	clips str[]
	fired f32

fn castFor(g hkx.Graph, lengths {str: f32}, k game.CastKind, seconds f32):
	a = g.magicAnimator(lengths, k.left)
	a.startCast(k)
	out = Casting(clips = [], fired = -1.0)
	t = f32(0.0)
	while t < seconds:
		a.stepAnimator(g, lengths, 1.0 / 60.0)
		t += 1.0 / 60.0
		if a.fired.any(.event == k.fireMark()): out.fired = t
		if not a.layers.isEmpty and (out.clips.isEmpty or out.clips[len - 1] != a.layers[0].clip):
			out.clips.push(a.layers[0].clip.copy())
	out

# the kind of cast with the graph's own wind-up and the charge time Firebolt has (SPIT 0.5), a
# held spell's none
fn kindOf(g hkx.Graph, lengths {str: f32}, left bool, held bool, aimed bool):
	plain = game.CastKind(left, held, aimed)
	game.CastKind(left, held, aimed, charge = 0.0 if held else 0.5,
		intro = g.castIntro(lengths, plain))

# the second a spell let go leaves the hand: the begin and start events, the wind-up or the
# charge (the longer, a frame at least), the charge held again before the release, then the release clip's fire mark
fn letGoAt(k game.CastKind, mark f32):
	0.05 + k.intro.max(k.charge).max(0.1) + k.charge.max(0.1) + mark

test "a spell's cast goes through the magic behavior's clips by its kind, from either hand":
	if not fs.exists(esm.defaultEsm()): return
	install = skyrim.openInstall(skyrim.defaultInstall) ?? fail
	g = install.readCharacterGraph() ?? fail
	lengths = install.clipDurations(g.clipNamesOf())
	right = {
		"self let go": ["mrh_selfprecharge", "mrh_selfreadyloop", "mrh_selfrelease", "mrh_idle"],
		"aimed let go": ["mrh_precharge", "mrh_readyloop", "mrh_release", "mrh_idle"],
		"self held": ["mrh_selfchargeloop", "mrh_preselfcon", "mrh_selfconcentration"],
		"aimed held": ["mrh_chargeloop", "mrh_preaimedcon", "mlhmrh_aimedconcentrationloop"]
	}
	kinds = {
		"self let go": g.kindOf(lengths, false, false, false),
		"aimed let go": g.kindOf(lengths, false, false, true),
		"self held": g.kindOf(lengths, false, true, false),
		"aimed held": g.kindOf(lengths, false, true, true)
	}
	for name, want in right:
		got = g.castFor(lengths, kinds[name], 3.0)
		for clip in want: expect clip in got.clips
	left = g.castFor(lengths, g.kindOf(lengths, true, false, true), 3.0)
	expect "mlh_precharge" in left.clips and "mlh_release" in left.clips
	held = g.castFor(lengths, g.kindOf(lengths, true, true, true), 3.0)
	expect "mlh_chargeloop" in held.clips and "mlhmrh_aimedconcentrationloop" in held.clips

test "a spell let go leaves the hand at the fire mark of its release clip; a held one sends none":
	if not fs.exists(esm.defaultEsm()): return
	install = skyrim.openInstall(skyrim.defaultInstall) ?? fail
	g = install.readCharacterGraph() ?? fail
	lengths = install.clipDurations(g.clipNamesOf())
	aimedKind = g.kindOf(lengths, false, false, true)
	aimed = g.castFor(lengths, aimedKind, 3.0)
	expect (aimed.fired - aimedKind.letGoAt(0.167)).abs() < 0.05
	selfKind = g.kindOf(lengths, false, false, false)
	toSelf = g.castFor(lengths, selfKind, 3.0)
	expect (toSelf.fired - selfKind.letGoAt(0.367)).abs() < 0.05
	leftKind = g.kindOf(lengths, true, false, true)
	theLeft = g.castFor(lengths, leftKind, 3.0)
	expect (theLeft.fired - leftKind.letGoAt(0.167)).abs() < 0.05
	flowing = g.castFor(lengths, g.kindOf(lengths, false, true, true), 3.0)
	expect flowing.fired < 0.0

test "stopping the cast brings the hand back to its ready idle":
	if not fs.exists(esm.defaultEsm()): return
	install = skyrim.openInstall(skyrim.defaultInstall) ?? fail
	g = install.readCharacterGraph() ?? fail
	lengths = install.clipDurations(g.clipNamesOf())
	k = g.kindOf(lengths, false, true, true)
	a = g.magicAnimator(lengths, false)
	a.startCast(k)
	loop 120: a.stepAnimator(g, lengths, 1.0 / 30.0)
	expect a.layers[0].clip == "mlhmrh_aimedconcentrationloop"
	a.stopCast(k)
	loop 60: a.stepAnimator(g, lengths, 1.0 / 30.0)
	expect a.layers[0].clip == "mrh_idle"

test "a charged spell's charge time is its record's, and a longer one holds the cast back":
	f = withInnFight(1) ?? return
	install, plugin = skyrim.installAndPlugin() ?? return
	names = install.readNames("Skyrim.esm") ?? fail
	firebolt = plugin.formByEditorId("SPEL", "Firebolt") ?? fail("no Firebolt")
	expect f.w.learnSpell(plugin, names, firebolt)
	expect f.w.spells[firebolt].chargeTime == 0.5 and f.w.spells[flames].chargeTime == 0.0
	g = install.readCharacterGraph() ?? fail
	lengths = install.clipDurations(g.clipNamesOf())
	short = g.kindOf(lengths, false, false, true)
	long = game.CastKind(
		left = false,
		held = false,
		aimed = true,
		charge = 1.5,
		intro = short.intro
	)
	first = g.castFor(lengths, short, 4.0)
	second = g.castFor(lengths, long, 6.0)
	expect first.fired > 0.0 and (second.fired - first.fired - 2.0).abs() < 0.05

test "a new player knows no shout; given two words of Fire Breath he says one or two, then recovers":
	f = faceToFace() ?? return
	install, plugin = skyrim.installAndPlugin() ?? return
	names = install.readNames("Skyrim.esm") ?? fail
	k = f.fighterNamed("Player") ?? fail("no player")
	player = f.w.player
	shout = plugin.formByEditorId("SHOU", "FireBreathShout") ?? fail("no FireBreathShout")
	expect f.w.knownShouts(player).isEmpty
	expect f.w.learnShout(plugin, names, shout)
	expect f.startShout(k, shout, 1) is why and "does not know" in why
	expect f.w.giveShout(player, shout, 2) == none
	expect f.w.wordsKnown(player, shout) == 2 and f.w.actors[player].magic.shout == shout
	expect f.startShout(k, shout, 3) is why and "2 words" in why
	expect f.startShout(k, shout, 2) == none
	expect f.startShout(k, shout, 1) is why and "cannot shout again" in why
	f.time += 51.0
	expect f.startShout(k, shout, 1) == none

# the clips (the heaviest each frame, in order) of a shout of this many words said with the hand
# types given, and the second its voice leaves, -1 when it does not
fn shoutFor(g hkx.Graph, lengths {str: f32}, words i64, right i64, ready bool):
	a = g.newWalker(true).animator
	a.takeStance(right, game.handFists, ready)
	if ready:
		a.sendEvent(game.drawEvent)
		loop 120: a.stepAnimator(g, lengths, 1.0 / 30.0)
	a.startShout(words, 0.8, true, ready)
	out = Casting(clips = [], fired = -1.0)
	t = f32(0.0)
	while t < 4.0:
		a.stepAnimator(g, lengths, 1.0 / 60.0)
		t += 1.0 / 60.0
		if a.fired.any(.event == game.voiceMark): out.fired = t
		if not a.layers.isEmpty and (out.clips.isEmpty or out.clips[len - 1] != a.layers[0].clip):
			out.clips.push(a.layers[0].clip.copy())
	out

test "a shout goes through the graph's inhale and the exhale of its word count, the voice leaving with it":
	if not fs.exists(esm.defaultEsm()): return
	install = skyrim.openInstall(skyrim.defaultInstall) ?? fail
	g = install.readCharacterGraph() ?? fail
	lengths = install.clipDurations(g.clipNamesOf())
	two = g.shoutFor(lengths, 2, game.handFists, false)
	expect "mt_shout_inhale" in two.clips and "mt_shout_exhale_medium" in two.clips
	expect two.fired > 0.8 and two.fired < 1.5
	one = g.shoutFor(lengths, 1, game.handFists, false)
	expect one.clips.any("shout_exhale" in it) and
		not one.clips.any("exhale_medium" in it or "exhale_long" in it)
	armed = g.shoutFor(lengths, 3, game.handSword, true)
	expect armed.clips.any("shout_inhale" in it) and armed.clips.any("shout_exhale_long" in it)
	expect armed.fired > 0.8

test "casting Flames is heard: the caster's detection event is as loud as the effect's casting sound level":
	f = faceToFace() ?? return
	k = f.fighterNamed("Player") ?? fail("no player")
	m = f.w.magicEffects[f.w.spells[flames].effects[0].effect]
	expect m.soundLevel == 0   # Loud
	expect f.w.eventOf(f.w.player) == none
	expect f.startCast(k, flames, false) == none
	ev = f.w.eventOf(f.w.player) ?? fail("no event")
	expect ev.sound == 100 and ev.at == Vec3(0, 0, 0) and ev.owner == f.w.player
	expect f.w.stealth.action == 100   # and the player's own action as the sum reads it
	f.stepOnce()
	f.w.stealth.clock += 6.0
	expect f.w.eventOf(f.w.player) == none

test "Embry, 1400 units behind the caster and facing away, has not detected him but hears the spell and looks up":
	f = faceToFace() ?? return
	k = f.fighterNamed("Player") ?? fail("no player")
	e = f.fighterNamed("Embry") ?? fail("no Embry")
	f.fighters[e].at = Vec3(-1400, 0, 0)
	f.fighters[e].facing = Vec3(-1, 0, 0)
	f.fighters[e].mode = .Idle
	f.engage(k, f.fighters[f.fighterNamed("Orgnar") ?? fail("no Orgnar")].refId)
	f.lookAtPlayer()
	before = f.w.stealth.detections[f.fighters[e].refId]
	expect before.level <= 0 and not before.heard
	expect f.startCast(k, flames, false) == none
	after = f.w.stealth.detections[f.fighters[e].refId]
	expect after.heard and after.level == 0 and after.noiseAt == Vec3(0, 0, 0)
	expect not f.w.isDetectedBy(f.fighters[e].refId)
	expect f.fighters[e].mode == .Alert and f.fighters[e].facing.x > 0.99
	expect f.lines.any(.endsWith("Embry hears a noise and looks up"))
