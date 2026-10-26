# The cell's fight played in the scene: the headless combat (game/combat) driven by the player's
# keys and shown by the actors' behavior graphs. R draws or sheathes the equipped weapon (fists
# without one), the left button attacks (held 0.4 s it is a power attack; with the right button
# held it bashes), the right button blocks, as Skyrim's default keys. The fight runs in its own
# fixed steps and tells each fighter's animator what it does (fightEvents.zap): the graph plays the
# draw, the swing, the stagger, the block, the cast and the fall, and a swing lands at the HitFrame
# its clip sends (fightClips.zap measures it). A dead actor falls as its ragdoll (fallen.zap), and
# the HUD shows the player's meters and the foe's health, the enemy meter, for a few seconds after
# a swing at it.

import engine
import engine.physics
import math
import skyrim
import skyrim.esm
import skyrim.hkx
import game.combat
import game.sim
import world

powerHold f32 = 0.4   # seconds the attack button is held before the swing is a power attack
meterTime f32 = 5.0   # seconds the enemy meter stays on a foe
chaseMost f32 = 700.0   # the fastest an actor's body follows its fighter, units a second
runAbove f32 = 250.0   # the speed from which a body runs, units a second
walkAbove f32 = 30.0   # and from which it walks
castOver f32 = 0.8   # seconds a spell let go keeps its hand up after it has gone

# a spell let go, charging in the hand until the graph's clip fires it
pub type PendingCast:
	form i64
	left bool
	fired bool = false
	over f32 = 0.0   # seconds its clip has yet to play once it has fired

# a shout said, its words in the breath until the graph's clip lets the voice go
type PendingShout:
	form i64
	words i64
	fired bool = false
	over f32 = 0.0

pub type FightScene:
	fight combat.Fight
	player i64   # the player's place among the fighters
	links i64[] = []   # by resident: its place among the fighters, -1 for none
	seen Seen[] = []   # by fighter: what its animator was told
	owed f32 = 0.0   # seconds the fight has yet to run
	drawn bool = false   # the weapon (or fists) is out
	held f32 = 0.0   # seconds the attack button has been down
	fired bool = false   # its power attack has started
	rightCast bool = false   # a button holds the spell of the right hand, or of the left
	leftCast bool = false
	meter i64 = -1   # the foe the enemy meter shows, its place among the fighters
	meterLeft f32 = 0.0
	waiting PendingCast? = none
	saying PendingShout? = none
	animated bool = false   # the graphs are told (stepFight), so a spell let go waits for its clip

# the fight as the scene plays it: the player a fighter a person plays
pub fn newFightScene(move fight combat.Fight) FightScene:
	k = fight.fighterNamed("Player") ?? fail("the world has no player")
	fight.fighters[k].controlled = true
	FightScene(fight, player = k)

fn buildFight(dir str, id str, g hkx.Graph, durations {str: f32}) FightScene ? str:
	install = try skyrim.openInstall(dir)
	plugin = try esm.openEsm(install.installPlugin("Skyrim.esm"))
	names = try install.readNames("Skyrim.esm")
	w = try install.worldOfCell(plugin, names, id)
	cell = plugin.findCell(id) ?? return "no cell {id}"
	scene = newFightScene(try plugin.sceneFight(w, try g.fightTimings(durations), 1))
	scene.fight.lighting = plugin.detectionLightingOf(cell)
	scene

# The fight of the cell's actors from the install, its attacks timed by the graph `g` (the clips'
# lengths in `durations`); none without it.
pub fn openFightScene(dir str, id str, g hkx.Graph, durations {str: f32}) FightScene?:
	match buildFight(dir, id, g, durations):
		s: s
		error:
			eprint("no fight: {error}")
			none

# who in the fight a resident is
fn linkResidents(mut s FightScene, rs Residents, cast world.CastHead):
	s.links = []
	for r in rs.all:
		refId = cast.npcs[r.npc].refId
		s.links.push((s.fight.indexOf(refId) ?? -1) if refId != 0 else -1)

# where the player stands and faces, and where each actor the fight does not move does
fn takeBodies(mut s FightScene, rs Residents, player Player):
	s.fight.fighters[s.player].at = player.feetOf()
	s.fight.fighters[s.player].facing = facing(player.heading)
	for i, r in rs.all:
		j = s.links[i]
		if j < 0 or r.fighting or not r.present: continue
		s.fight.fighters[j].at = r.body.feetOf()
		s.fight.fighters[j].facing = facing(r.body.heading)

fn toggleDraw(mut s FightScene):
	k = s.player
	if s.fight.fighters[k].isOut(): return
	s.drawn = not s.drawn
	s.fight.note("Player {"draws" if s.drawn else "sheathes"} {s.fight.fighters[k].weaponName}")
	if not s.drawn and s.fight.fighters[k].mode == .Block: s.fight.fighters[k].mode = .Guard
	if not s.drawn: s.fight.stopCast(k)

# the player swings at whom stands before him
fn attack(mut s FightScene, strike combat.Strike):
	k = s.player
	x = s.fight.fighters[k]
	if x.mode in [.Swing, .Staggered, .Bleedout, .Dead]: return
	foe = s.fight.foeAhead(k)
	s.fight.fighters[k].target = s.fight.fighters[foe ?? k].refId if foe != none else 0
	kind = strike
	if x.mode == .Block: kind = .Bash
	cost = s.fight.w.settings.powerAttackStamina(x.weight)
	if kind == .Power and s.fight.w.actors[x.refId].valueOf("stamina") < cost: kind = .Normal
	s.fight.startSwing(k, kind)
	if foe != none:
		s.meter = foe ?? 0
		s.meterLeft = meterTime

# the spell of a hand cast while its button is held (a spell let go is charged, then goes at the
# moment its graph's clip says, fireWaiting), and its casting stopped as it comes up; why not, a
# line of the fight, when it cannot be cast
fn holdCast(mut s FightScene, form i64, left bool, held bool):
	was = s.leftCast if left else s.rightCast
	if left: s.leftCast = held
	else: s.rightCast = held
	k = s.player
	if held and not was:
		if s.animated and s.waiting == none and s.letGo(form):
			if s.fight.whyNotCast(k, form) is why:
				s.fight.note(why)
			else:
				s.waiting = PendingCast(form, left)
			return
		if s.fight.startCast(k, form, left) is why: s.fight.note(why)
	if was and not held and (s.fight.fighters[k].casting?.left ?? false) == left:
		s.fight.stopCast(k)

# whether the spell is let go at once, not held
fn letGo(s FightScene, form i64):
	spell = s.fight.w.spells.get(form) ?? return false
	spell.castType != .Concentration

# how the spell is cast by a hand
fn castKindOfSpell(s FightScene, form i64, left bool):
	spell = s.fight.w.spells[form]
	kind = CastKind(left, held = spell.castType == .Concentration, aimed = spell.target != .Caster)
	intros = s.fight.timings.castIntros
	CastKind(
		left,
		held = kind.held,
		aimed = kind.aimed,
		charge = spell.chargeTime,
		intro = intros[kind.slotOf()] if kind.slotOf() < intros.len else 0.0
	)

# The spell charging in the hand goes when the graph's clip sends its fire mark, and the cast
# is kept up in the animator until the clip is over.
fn fireWaiting(mut s FightScene, a Animator, dt f32):
	p = s.waiting ?? return
	if p.fired:
		s.waiting = PendingCast(p.form, p.left, fired = true, over = p.over - dt)
		if p.over - dt <= 0.0: s.waiting = none
		return
	if not a.fired.any(.event == s.castKindOfSpell(p.form, p.left).fireMark()): return
	s.waiting = PendingCast(p.form, p.left, fired = true, over = castOver)
	if s.fight.startCast(s.player, p.form, p.left) is why: s.fight.note(why)

# The player says the readied shout, this many words of it: the graph is told and its voice leaves
# at the exhale clip's Voice_SpellFire_Event (fireSaying); without graphs, at once. Why not, a line
# of the fight.
pub fn sayShout(mut s FightScene, words i64):
	k = s.player
	form = s.fight.w.actors[s.fight.fighters[k].refId].magic.shout
	if s.fight.whyNotShout(k, form, words) is why:
		s.fight.note(why)
		return
	if not s.animated or s.saying != none:
		if s.fight.startShout(k, form, words) is why: s.fight.note(why)
		return
	gmst = "fshoutrumblebigmotordurationv{words}"
	s.fight.fighters[k].shoutHold = s.fight.w.settings.gmst(gmst)
	s.fight.fighters[k].shouting = words
	s.saying = PendingShout(form, words)

# The shout said goes when the graph's exhale clip sends its voice mark, and the fighter is done
# saying it when the clip is over.
fn fireSaying(mut s FightScene, a Animator, dt f32):
	p = s.saying ?? return
	k = s.player
	if p.fired:
		s.saying = PendingShout(p.form, p.words, fired = true, over = p.over - dt)
		if p.over - dt <= 0.0:
			s.saying = none
			s.fight.fighters[k].shouting = 0
		return
	if not a.fired.any(.event == voiceMark): return
	s.saying = PendingShout(p.form, p.words, fired = true, over = castOver)
	if s.fight.startShout(k, p.form, p.words) is why: s.fight.note(why)

# The player's keys of the frame: R draws or sheathes, the left button swings on its release (a
# power attack once held powerHold) or casts the spell in the right hand, the right one blocks or
# casts the spell in the left.
pub fn controlPlayer(mut s FightScene, i Input, dt f32):
	k = s.player
	if i.draw: s.toggleDraw()
	if not s.drawn:
		s.held = 0.0
		s.fired = false
		return
	refId = s.fight.fighters[k].refId
	right = s.fight.w.spellIn(refId, false)
	left = s.fight.w.spellIn(refId, true)
	if right != 0:
		s.holdCast(right, false, i.attack)
	elif i.attack:
		s.held += dt
		if s.held >= powerHold and not s.fired:
			s.fired = true
			s.attack(.Power)
	else:
		if s.held > 0.0 and not s.fired: s.attack(.Normal)
		s.held = 0.0
		s.fired = false
	mode = s.fight.fighters[k].mode
	if mode in [.Swing, .Staggered, .Bleedout, .Dead]: return
	if left != 0:
		s.holdCast(left, true, i.block)
	elif i.block:
		s.fight.fighters[k].mode = .Block
		s.fight.fighters[k].until = s.fight.time + 0.1
	elif mode == .Block:
		s.fight.fighters[k].mode = .Guard

# the player's spells in the hands, as the menus left them in the game's world, taken into the fight
pub fn takeMagic(mut s FightScene, menus sim.GameWorld):
	if menus.actors.get(menus.player) is a:
		s.fight.w.actors[s.fight.w.player].magic = a.magic.copy()
	s.fight.w.stealth = menus.stealth.copy()

# the player's values (health, magicka, stamina) the fight changed, given back to the game's world
# for the HUD to show
pub fn giveValues(s FightScene, mut menus sim.GameWorld):
	menus.stealth.action = s.fight.w.stealth.action
	menus.stealth.actionUntil = s.fight.w.stealth.actionUntil
	menus.stealth.events = s.fight.w.stealth.events.copy()
	if menus.actors.get(menus.player) == none: return
	menus.actors[menus.player].values = s.fight.w.actors[s.fight.w.player].values.copy()

# the fight run over dt in its fixed steps, the enemy meter's time passing
pub fn advanceFight(mut s FightScene, dt f32):
	s.owed += dt
	while s.owed >= s.fight.step:
		s.fight.stepOnce()
		s.owed -= s.fight.step
	if s.meter >= 0:
		foe = s.fight.fighters[s.meter]
		if foe.isFighting() and foe.target == s.fight.fighters[s.player].refId:
			s.meterLeft = meterTime
		s.meterLeft -= dt
		if s.meterLeft <= 0.0: s.meter = -1

# the body goal's gait: standing, walking or running, by how fast it goes
fn gaitFor(speed f32) f32:
	if speed >= runAbove: return 2.0
	1.0 if speed >= walkAbove else 0.0

# the heading that faces where fighter x looks, or runs where it flees
fn facingHeading(x combat.Fighter, delta Vec3) f32:
	way = delta if x.mode == .Flee and delta.length() > 1.0 else x.facing
	way.x.atan2(way.y)

# The bodies of the actors in a fight carried to where the fight put them, through the cell's
# physics, at the gait their speed shows; the fight takes back where the bodies ended.
fn followFighters(mut s FightScene, mut rs Residents, mut w physics.World, dt f32):
	for i in 0..rs.all.len:
		j = s.links[i]
		if j < 0 or not rs.all[i].present or rs.fallenIndex(i) >= 0: continue
		x = s.fight.fighters[j]
		rs.all[i].fighting = x.isFighting() or x.mode == .Bleedout
		if not rs.all[i].fighting: continue
		feet = rs.all[i].body.feetOf()
		delta = Vec3(x.at.x - feet.x, x.at.y - feet.y, 0.0)
		speed = delta.length() / dt
		velocity = delta / dt
		if speed > chaseMost: velocity = delta.normalized() * chaseMost
		rs.all[i].body.controller.walk(w, velocity, dt)
		rs.all[i].body.advanceGait(gaitFor(speed), dt)
		rs.all[i].body.heading = math.turnToward(rs.all[i].body.heading, x.facingHeading(delta),
			2.0 * turnSpeed * dt)
		s.fight.fighters[j].at = rs.all[i].body.feetOf()

# the dead fall as their skeleton's ragdoll
fn raiseDead(
	s FightScene,
	mut rs Residents,
	cast world.CastHead,
	rigs engine.Rig[],
	mut w physics.World,
	dt f32
):
	for i in 0..rs.all.len:
		j = s.links[i]
		if j >= 0 and rs.all[i].present and s.fight.fighters[j].ragdoll and rs.fallenIndex(i) < 0:
			rs.fall(cast, i, rigs, w, dt)

# fighter j's stance: what it holds in each hand, and whether it holds it out (the player's
# weapon drawn with R, an actor's while it fights or bleeds)
fn stanceOf(s FightScene, j i64, out bool):
	x = s.fight.fighters[j]
	refId = x.refId
	right = x.animation
	left = handShield if x.shield != 0 else handFists
	if x.player:
		if s.fight.w.spellIn(refId, false) != 0: right = handSpell
		if s.fight.w.spellIn(refId, true) != 0: left = handSpell
	Stance(out, right, left)

# how fighter j casts the spell it holds up or charges, none when it casts none
fn castKindOf(s FightScene, j i64) CastKind?:
	if j == s.player and s.waiting is p: return s.castKindOfSpell(p.form, p.left)
	c = try s.fight.fighters[j].casting
	s.castKindOfSpell(c.spell, c.left)

# fighter j's animator told what the fight did since the last time
fn tell(mut s FightScene, j i64, mut a Animator, out bool):
	while s.seen.len <= j: s.seen.push(Seen())
	x = s.fight.fighters[j]
	a.sendFightEvents(s.seen[j], x, s.stanceOf(j, out), s.castKindOf(j))

# The animators of the player and of the actors in the fight told what the fight did, so that the
# graphs play it: the drawing, the swings, the blocks, the staggers, the spells, the fall.
fn tellAnimators(mut s FightScene, mut rs Residents, mut walker Walker):
	s.tell(s.player, walker.animator, s.drawn)
	for i in 0..rs.all.len:
		j = s.links[i]
		if j < 0 or not rs.all[i].present: continue
		x = s.fight.fighters[j]
		s.tell(j, rs.walkers[i].animator, rs.all[i].fighting or x.ragdoll)

# One frame: the actors' bodies given to the fight, the player's keys played, the fight run over
# dt, the actors that are in it carried where it puts them, their graphs told what happened, the
# dead fallen. `cameraHeading` is the way the camera looks, which a player standing with his
# weapon out faces.
pub fn stepFight(
	mut s FightScene,
	mut rs Residents,
	cast world.CastHead,
	mut player Player,
	mut walker Walker,
	i Input,
	cameraHeading f32,
	rigs engine.Rig[],
	mut w physics.World,
	dt f32
):
	if s.links.len != rs.all.len: s.linkResidents(rs, cast)
	if s.drawn and i.forward == 0.0 and i.right == 0.0:
		player.heading = math.turnToward(player.heading, cameraHeading, 2.0 * turnSpeed * dt)
	s.takeBodies(rs, player)
	s.controlPlayer(i, dt)
	s.advanceFight(dt)
	s.followFighters(rs, w, dt)
	s.raiseDead(rs, cast, rigs, w, dt)
	s.animated = true
	s.tellAnimators(rs, walker)
	s.fireWaiting(walker.animator, dt)
	s.fireSaying(walker.animator, dt)

# the percent of the foe's health the enemy meter shows, below 0 while it is not up
pub fn enemyPercent(s FightScene) f64:
	if s.meter < 0: return -1.0
	foe = s.fight.w.actors[s.fight.fighters[s.meter].refId]
	f64(foe.percentOf("health")) * 100.0

# what happened in the fight, each line with its time
pub fn fightLines(s FightScene) str[]:
	s.fight.lines.copy()
