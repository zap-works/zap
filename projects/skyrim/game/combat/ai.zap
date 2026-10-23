# The combat AI as a state machine per fighter, from its AIDT and its combat style (CSTY). An idle
# actor whose aggression makes it attack someone in sight (within fSneakMaxDistance) starts a
# fight; one hit turns on its attacker, or flees when cowardly; the others who see it come to the
# victim's aid when their assistance says so, flee when cowardly, else watch (Alert). In a fight it
# runs to its target (NPC_1HM_MT: 370 units a second) until in reach. In reach it decides as the
# game's combat behavior tree does (chances.zap holds the executable's weights, README.md the tree's
# shape): every 0.25 s (the Idle nodes' wait) the Block context weighs a bash, a block against an
# attack coming at it, and an offensive bash against waiting; the Melee context weighs an attack (a
# plain or a power attack among its variants) against waiting; the Close Movement context weighs a
# circle and a fall back against waiting. The style's numbers enter as the executable lerps them
# between the fCombat*Min and Max settings. A fighter keeps its target for
# fCombatSelectTargetSwitchUpdateTime (3 s) against another attacker, and weighs its foes as the
# executable does (select.zap). It flees when its side's threat over its foes' falls under its
# confidence's threshold (flee.zap), running until fCombatFleeDistanceInterior (2048, which the flee
# node at 0x1408a08c0 reads) from its foe. A fighter whose target is gone (dead, fled, bleeding
# out) looks for another, else searches (Alert). The player is played by a script: it attacks
# whenever it can, a power attack every third swing when its stamina pays for it, and never blocks
# nor flees, and sprints (NPC_Sprinting_MT, 500 units a second, for fSprintStaminaDrainMult 7
# stamina a second) after a target that flees.

import game.sim

fn flee(mut f Fight, k i64):
	if f.fighters[k].mode == .Flee: return
	f.fighters[k].mode = .Flee
	f.fighters[k].swing = none
	f.note("{f.fighters[k].name} flees")

# fighter k takes target as its foe
pub fn engage(mut f Fight, k i64, target i64):
	if f.fighters[k].target == target and f.fighters[k].isFighting(): return
	if not f.fighters[k].isFighting(): f.drawConfidenceModifier(k)
	f.fighters[k].target = target
	f.fighters[k].targetSince = f.time
	if f.fighters[k].ai.confidence == 0 and not f.fighters[k].player:
		f.flee(k)
		return
	f.fighters[k].mode = .Approach
	name = f.fighters[f.indexOf(target) ?? k].name.copy()
	f.note("{f.fighters[k].name} fights {name}")

# Fighter j was hit by fighter k: it turns on k, and those who see it take their sides.
pub fn provoke(mut f Fight, j i64, k i64):
	if f.fighters[j].isOut() or f.fighters[j].player: return
	attacker = f.fighters[k].refId
	if f.fighters[j].target != attacker and f.mayChangeTarget(j) or not f.fighters[j].isFighting():
		f.engage(j, attacker)
	victim = f.fighters[j].refId
	for refId in f.witnessesOf(f.fighters[j].at, attacker, [attacker, victim]):
		i = f.indexOf(refId) ?? continue
		w = f.fighters[i]
		if w.player or w.isFighting() or w.isOut(): continue
		if f.w.helps(f.ties, w, victim):
			f.note("{w.name} comes to the aid of {f.fighters[j].name}")
			f.engage(i, attacker)
		elif w.ai.confidence == 0:
			f.fighters[i].target = attacker
			f.flee(i)
		elif w.mode == .Idle:
			f.fighters[i].mode = .Alert
			f.note("{w.name} watches")

# whether fighter j may take a new target: it has none alive, or kept this one long enough
fn mayChangeTarget(f Fight, j i64):
	x = f.fighters[j]
	foe = f.indexOf(x.target) ?? return true
	not x.isFighting() or f.fighters[foe].isOut() or
		f.time - x.targetSince >= f.w.settings.gmst("fcombatselecttargetswitchupdatetime")

# how many living fighters fight the target of fighter k, itself among them
fn membersAgainst(f Fight, k i64):
	target = f.fighters[k].target
	f.fighters.filter(.target == target and .isFighting()).len

# a new foe for a fighter without one: someone it attacks on sight, else 0
fn findTarget(f Fight, k i64):
	x = f.fighters[k]
	range = f.w.settings.gmst("fsneakmaxdistance")
	for other in f.fighters:
		if other.isOut() or other.refId == x.refId or x.at.distance(other.at) > range: continue
		if f.w.attacksOnSight(f.ties, x, other.refId): return other.refId
	0

fn moveToward(mut f Fight, k i64, point Vec3, speed f32):
	at = f.fighters[k].at
	d = Vec3(point.x - at.x, point.y - at.y, 0)
	if d.length() < 0.001: return
	f.fighters[k].at = f.inside(at + d.normalized() * (speed * f.step).min(d.length()))

fn face(mut f Fight, k i64, point Vec3):
	at = f.fighters[k].at
	d = Vec3(point.x - at.x, point.y - at.y, 0)
	if d.length() > 0.001: f.fighters[k].facing = d.normalized()

fn timed(m Mode):
	m in [.Staggered, .Block, .Circle, .Fallback]

# the timed modes end: a bleedout, a stagger, a block, a circle, a fall back; a swing lands and ends
fn advanceTimed(mut f Fight, k i64):
	x = f.fighters[k].copy()
	if x.mode == .Bleedout and f.time >= x.until: f.recover(k)
	if x.mode.timed() and f.time >= x.until: f.fighters[k].mode = .Guard
	swing = x.swing ?? return
	if not swing.landed and f.time >= swing.hitAt: f.landSwing(k)
	if f.time >= swing.endsAt and f.fighters[k].mode == .Swing:
		f.fighters[k].swing = none
		f.fighters[k].mode = .Guard

fn fleeStep(mut f Fight, k i64, foe Vec3):
	x = f.fighters[k]
	away = Vec3(x.at.x - foe.x, x.at.y - foe.y, 0)
	if away.length() < 0.001: away = Vec3(1, 0, 0)
	f.moveToward(k, x.at + away.normalized() * 100.0, f.speeds.run)
	if f.fighters[k].at.distance(foe) >= f.w.settings.gmst("fcombatfleedistanceinterior"):
		f.fighters[k].mode = .Fled
		f.note("{x.name} gets away")

# One step of fighter k's mind and body.
pub fn think(mut f Fight, k i64):
	f.advanceTimed(k)
	x = f.fighters[k].copy()
	if x.controlled or x.isOut() or x.mode == .Swing or x.mode == .Staggered: return
	j = f.indexOf(x.target) ?? -1
	if j >= 0 and x.mode == .Flee:
		f.fleeStep(k, f.fighters[j].at.copy())
		return
	if j < 0 or f.fighters[j].isOut():
		f.loseTarget(k)
		return
	if x.mode == .Idle or x.mode == .Alert: return
	f.selectTarget(k)
	if f.fighters[k].mode == .Flee: return
	j = f.indexOf(f.fighters[k].target) ?? return
	target = f.fighters[j].copy()
	f.face(k, target.at)
	if not x.player and f.isOutmatched(k):
		f.flee(k)
		return
	if x.player and f.givesUpChase(x, target):
		f.loseTarget(k)
		return
	if x.at.distance(target.at) > x.reach * 0.9 and x.mode != .Fallback:
		f.fighters[k].mode = .Approach
		f.moveToward(k, target.at.copy(), f.chaseSpeed(k, target))
		return
	f.keepMoving(k)
	if f.time < x.nextDecision or x.mode.timed(): return
	f.fighters[k].nextDecision = f.time + idleTime
	if x.player:
		f.playerDecides(k)
	else:
		f.decide(k, target)

# the scripted player stops after a fleeing foe it cannot catch: out of stamina to sprint, and more
# than three reaches behind
fn givesUpChase(f Fight, x Fighter, target Fighter):
	target.mode == .Flee and f.w.actors[x.refId].valueOf("stamina") <= 0.0 and
		x.at.distance(target.at) > x.reach * 3.0

# how fast the fighter runs after its target: the player sprints after one that flees
fn chaseSpeed(mut f Fight, k i64, target Fighter):
	x = f.fighters[k]
	if not x.player or target.mode != .Flee: return f.speeds.run
	if f.w.actors[x.refId].valueOf("stamina") <= 0.0: return f.speeds.run
	f.w.actors[x.refId].damageValue(
		"stamina",
		f.w.settings.gmst("fsprintstaminadrainmult") * f.step
	)
	f.fighters[k].damagedAt["stamina"] = f.time
	f.speeds.sprint

fn loseTarget(mut f Fight, k i64):
	x = f.fighters[k]
	next = f.findTarget(k)
	if next != 0:
		f.engage(k, next)
		return
	if x.mode == .Idle or x.mode == .Alert: return
	f.fighters[k].mode = .Alert
	f.fighters[k].target = 0
	f.note("{x.name} stops fighting and searches")

# circling and falling back go on between decisions
fn keepMoving(mut f Fight, k i64):
	x = f.fighters[k].copy()
	if x.mode == .Circle:
		side = Vec3(-x.facing.y, x.facing.x, 0) * x.circleSide
		f.moveToward(k, x.at + side * 100.0, f.speeds.walk)
	if x.mode == .Fallback and f.time < x.movingUntil:
		f.moveToward(k, x.at - x.facing * 100.0, f.speeds.backRun)

fn roll(mut f Fight):
	f32(f.rng.nextFloat(0.0, 1.0))

# the seconds since the fighter's last swing began
fn sinceSwing(f Fight, x Fighter) f32?:
	at = try x.lastSwingAt
	f.time - at

fn waits(mut f Fight, k i64):
	f.fighters[k].mode = .Guard

# the Block context: a bash, a block (only against an attack coming), an offensive bash, or wait;
# true when it acted
fn decideBlockContext(mut f Fight, k i64, target Fighter):
	x = f.fighters[k].copy()
	coming = target.swing != none and not (target.swing?.landed ?? true)
	weights = [
		f.bash(x, target),
		f.block(x) if coming else 0.0,
		f.offensiveBash(x, target, f.membersAgainst(k)),
		idleWeight
	]
	match pick(weights, f.roll()):
		0: f.startSwing(k, .Bash)
		1:
			f.fighters[k].mode = .Block
			f.fighters[k].until = (target.swing?.endsAt ?? f.time).min(f.time + f.blockTime(x)) +
				0.1
			f.note("{x.name} blocks")
		2: f.startSwing(k, .Bash)
		_: return false
	true

# the Melee context: an attack or wait; the variant is a weighted pick of the plain and the power
# attack (a power attack needs stamina); true when it swung
fn decideMeleeContext(mut f Fight, k i64, target Fighter):
	x = f.fighters[k].copy()
	weight = f.attack(x, target, f.membersAgainst(k), f.sinceSwing(x))
	if pick([weight, idleWeight], f.roll()) != 0: return false
	canPay = f.w.actors[x.refId].valueOf("stamina") > 0.0
	power = x.style.variant(target, true) if canPay else 0.0
	f.startSwing(
		k,
		.Power if pick([x.style.variant(target, false), power], f.roll()) == 1 else .Normal
	)
	true

# the Close Movement context: circle round the target, fall back, or wait
fn decideMovementContext(mut f Fight, k i64, target Fighter):
	x = f.fighters[k].copy()
	match pick([f.circle(x), f.fallback(x), idleWeight], f.roll()):
		0:
			angle = f.circleAngle(x, target, f.roll()).radians()
			f.fighters[k].mode = .Circle
			f.fighters[k].circleSide = 1.0 if f.roll() < 0.5 else -1.0
			f.fighters[k].until = f.time + x.at.distance(target.at) * angle / f.speeds.walk
		1:
			moving = f.fallbackDistance(x) / f.speeds.backRun
			f.fighters[k].mode = .Fallback
			f.fighters[k].movingUntil = f.time + moving
			f.fighters[k].until = f.time + moving + f.fallbackWait(x)
		_: f.waits(k)

fn decide(mut f Fight, k i64, target Fighter):
	if f.decideBlockContext(k, target) or f.decideMeleeContext(k, target): return
	f.decideMovementContext(k, target)

fn playerDecides(mut f Fight, k i64):
	x = f.fighters[k]
	cost = f.w.settings.powerAttackStamina(x.weight)
	if x.combo % 3 == 2 and f.w.actors[x.refId].valueOf("stamina") >= cost:
		f.fighters[k].combo += 1
		f.startSwing(k, .Power)
	else:
		f.startSwing(k, .Normal)
