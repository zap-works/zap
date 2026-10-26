# The actors of a cell detecting the player: each watcher's reading of him (detection.zap) worked
# out from the world's actors, their places and their light, and kept in the world's stealth state
# (game/sim/stealth.zap) for fDetectionUpdateTimeMin seconds before it is read again (the game
# queues a new reading when the kept one is older, 0x1407c3eb0). A watcher is told by the caller:
# where it stands, how it moves, whether it sleeps or fights, and whether its eye reaches the player
# (a ray cast on the cell's geometry, or true where there is none).

import game.sim

# an actor placed for detection
pub type Placed:
	actor i64
	feet Vec3
	heading f32   # radians from north toward east
	speed f32 = 0.0   # units a second
	walkSpeed f32 = 82.0   # the speeds its gaits carry it at, which tell a walk from a run
	runSpeed f32 = 351.0
	sneaking bool = false
	sleeping bool = false
	fighting bool = false
	foe i64 = 0   # whom it fights, 0 for none
	clear bool = true   # a watcher's eye reaches the player
	friendly bool = false   # a watcher whose faction reaction to the player is ally or friend
	hostile bool = false   # a watcher that would attack the player on sight
	eventClear bool = true   # a watcher's eye reaches the place of the player's detection event

# whether the actor's speed is the game's moving: at least 5 units a second (0x1406aefa0)
pub fn isMoving(p Placed) bool:
	p.speed >= 5.0

# whether it runs: past the walk and the run blended by fJogInterpolationBetweenWalkAndRun
# (0x1406742a0)
pub fn isRunning(p Placed, settings {str: f64}) bool:
	run = (settings.gmst("fjoginterpolationbetweenwalkandrun") + 1.0) * 0.5
	p.speed >= (1.0 - run) * p.walkSpeed + run * p.runSpeed

# The weight of what the actor wears and holds (0x14023bd30): its worn armor and, for each hand, the
# weapon in it.
pub fn equippedWeightOf(w sim.GameWorld, actor i64) f32:
	inv = w.inventories.get(actor) ?? return 0.0
	total = 0.0
	for s in inv.stacks:
		item = w.items.get(s.form) ?? continue
		worn = s.extras.filter(.worn).map(.count).sum()
		left = s.extras.filter(.wornLeft).map(.count).sum()
		if item.kind.Armor != none or item.kind.Weapon != none: total += item.weight * f32(worn + left)
	total

# the player makes a noise of this sound level (a swing, a shout); it is heard for
# fActorAlertSoundTimer seconds
pub fn makeNoise(mut w sim.GameWorld, level i64):
	w.stealth.action = level
	w.stealth.actionUntil = w.stealth.clock + w.settings.gmst("factoralertsoundtimer")

fn watcherOf(w sim.GameWorld, p Placed):
	a = w.actors.get(p.actor) ?? return Watcher(sneakSkill = 0.0)
	Watcher(
		sneakSkill = a.valueOf("sneak"),
		blindness = a.valueOf("blindness"),
		nightEye = a.valueOf("nighteye") > 0.0,
		alerted = p.fighting,
		fightsOther = p.fighting and p.foe != w.player,
		sleeping = p.sleeping
	)

fn quarryOf(w sim.GameWorld, p Placed):
	a = w.actors.get(w.player) ?? return Quarry(sneakSkill = 0.0, isPlayer = true)
	heard = w.stealth.action if w.stealth.clock < w.stealth.actionUntil else 0
	Quarry(
		sneakSkill = a.valueOf("sneak"),
		isPlayer = true,
		sneaking = p.sneaking,
		moving = p.isMoving(),
		running = p.isRunning(w.settings),
		invisible = a.valueOf("invisibility") > 0.0,
		equippedWeight = w.equippedWeightOf(w.player),
		movementNoise = a.valueOf("movementnoisemult"),
		action = heard
	)

fn sightOf(lighting Lighting, watcher Placed, player Placed):
	Sight(
		distance = watcher.feet.distance(player.feet),
		angle = angleToward(watcher.heading, watcher.feet, player.feet),
		exterior = lighting.exterior,
		clear = watcher.clear,
		lightRaw = lighting.lightRawAt(player.feet),
		ambientMax = lighting.ambientMax
	)

fn earOf(lighting Lighting, watcher Placed, player Placed):
	Ear(
		feet = watcher.feet,
		eye = watcher.feet.eyeAt(watcher.sneaking),
		heading = watcher.heading,
		sleeping = watcher.sleeping,
		exterior = lighting.exterior,
		friendly = watcher.friendly,
		fights = watcher.fighting,
		watchedFights = player.fighting,
		hostile = watcher.hostile,
		eventClear = watcher.eventClear
	)

# What the watcher hears of the player when its sight gave no level above 0 (the second half of
# 0x1406a33b0): his detection event, else his projectiles in the air; a reading of level 0 with the
# place of the sound, none when it hears nothing.
fn hearingOf(w sim.GameWorld, lighting Lighting, watcher Placed, player Placed) Reading?:
	ear = lighting.earOf(watcher, player)
	if not ear.canHear(): return none
	if w.eventOf(player.actor) is ev and w.settings.hearEvent(ear, ev) is h:
		return Reading(level = 0, heard = true, noiseAt = h.at)
	shots = w.stealth.flying.filter(.owner == player.actor)
	h = try w.settings.hearProjectiles(ear, shots)
	Reading(level = 0, heard = true, noiseAt = h.at)

# the watcher's reading of the player now
pub fn readWatcher(w sim.GameWorld, lighting Lighting, watcher Placed, player Placed) Reading:
	seen = w.settings.readingOf(
		w.watcherOf(watcher),
		w.quarryOf(player),
		lighting.sightOf(watcher, player)
	)
	if seen.level > 0: return seen
	w.hearingOf(lighting, watcher, player) ?? seen

# One step of dt seconds: every watcher whose kept reading is older than fDetectionUpdateTimeMin
# (or that never looked) reads the player again.
pub fn stepDetections(
	mut w sim.GameWorld,
	lighting Lighting,
	player Placed,
	watchers Placed[],
	dt f32
):
	every = w.settings.gmst("fdetectionupdatetimemin")
	seenBefore, _ = w.highestLevel()
	for p in watchers:
		if p.actor == w.player: continue
		if w.stealth.detections.get(p.actor) is d and w.stealth.clock - d.at < every: continue
		r = w.readWatcher(lighting, p, player)
		w.stealth.detections[p.actor] = sim.Detection(
			level = r.level,
			inCone = r.inCone,
			lineOfSight = r.lineOfSight,
			at = w.stealth.clock,
			heard = r.heard,
			noiseAt = r.noiseAt
		)
	kept {i64: sim.Detection} = {}
	for p in watchers:
		if w.stealth.detections.get(p.actor) is d: kept[p.actor] = d.copy()
	w.stealth.detections = kept
	w.stealth.clock += dt
	seenNow, _ = w.highestLevel()
	w.useSneak(dt, seenBefore > 0 and seenNow <= 0)

# every watcher reads the player again at once, as before a crime is judged
pub fn lookAgain(mut w sim.GameWorld, lighting Lighting, player Placed, watchers Placed[]):
	w.stealth.detections = {}
	w.stepDetections(lighting, player, watchers, 0.0)

# The actor notices the player at once (0x1406a2580: its state set to level 100), as the victim of a
# caught pickpocket does.
pub fn notice(mut w sim.GameWorld, watcher i64):
	w.stealth.detections[watcher] = sim.Detection(level = 100, at = w.stealth.clock)
