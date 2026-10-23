# How well one actor notices another, as SkyrimSE.exe 1.7.104 works it out (reference/exe/README.md,
# "Stealth: sneaking, detection and pickpocketing" holds the addresses). Actor::CalculateDetection
# (0x1406a33b0) reads the two actors and what lies between them, finds the watcher's reach
# (0x14041cd30), and gives the detection value a sum of three terms (0x14041cd90): what the watched
# makes heard (its noise, with the weight it carries and how it moves), what the watcher sees of it
# (the light on it, in front of the watcher and through a line of sight) and the contest of the
# watcher's Sneak skill against the watched one's, less fSneakBaseValue. The watcher has detected
# the watched while the value is above 0; between detections the value is kept for
# fDetectionUpdateTimeMin seconds (0x1420b8ab8). The perks' entry points (0x39, 0x30, 0x2f, 0xf)
# change nothing here: the game has no perks yet.

import game.sim

# the watcher, as the formula reads it
pub type Watcher:
	sneakSkill f32   # its Sneak actor value, which the contest takes for its perception
	isPlayer bool = false
	blindness f32 = 0.0   # its Blindness actor value (percent)
	nightEye bool = false   # its Night Eye actor value is above 0
	alerted bool = false   # it is in combat (Actor::IsInCombat, vtable 0x718)
	fightsOther bool = false   # its combat target is not the one watched
	sleeping bool = false
	flying bool = false
	ambush i64 = 0   # 0 for none, 1 the watched is the target of its ambush package, 2 it is not

# the watched, as the formula reads it
pub type Quarry:
	sneakSkill f32   # its Sneak actor value, which hides it while it sneaks
	isPlayer bool = false
	sneaking bool = false
	moving bool = false   # its speed is at least 5 units a second
	running bool = false   # its speed is past the walk and the run blended by fJogInterpolationBetweenWalkAndRun
	invisible bool = false   # its Invisibility actor value is above 0
	size i64 = 1   # its race's size: 0 small, 1 medium, 2 large, 3 very large
	equippedWeight f32 = 0.0   # the weight of the armor it wears and the weapons it holds
	movementNoise f32 = 1.0   # its Movement Noise Mult actor value
	action i64 = 0   # the sound level of its last action (Actor.actionValue, 0x11c), 0 once it fades
	flying bool = false

# what lies between them
pub type Sight:
	distance f32
	angle f32 = 0.0   # radians between the way the watcher faces and the watched, 0 to pi
	exterior bool = false   # they stand outside
	clear bool = true   # a ray from the watcher's eye reaches a point of the watched body
	lightRaw f32 = 0.0   # the watched's light level before the cell's ambient is taken off (lighting.zap)
	ambientMax f32 = 0.0   # the highest component of the cell's ambient color, 0..1

# the value and its parts
pub type Reading:
	level i64   # above 0: the watcher has detected the watched
	noise f32 = 0.0
	light f32 = 0.0
	skill f32 = 0.0
	inCone bool = false
	lineOfSight bool = false
	heard bool = false   # level 0 for a sound it heard (hearing.zap), noiseAt its place
	noiseAt Vec3 = Vec3(0, 0, 0)

# the level of a watcher that never looked, and of one beyond its reach
pub unseen = -1000

fn flag(b bool) f32:
	1.0 if b else 0.0

# x, 0 below it (maxss with 0: a zero of either sign, or a NaN, gives +0)
fn atLeastZero(x f32):
	x if x > 0.0 else 0.0

# The farthest the watcher notices at: fSneakMaxDistance, twice outside (fSneakExteriorDistanceMult)
# and more when either flies (fSneakFlyingDistanceMult).
pub fn maxDistance(settings {str: f64}, exterior bool, flying bool) f32:
	range = settings.gmst("fsneakmaxdistance")
	if exterior: range = settings.gmst("fsneakexteriordistancemult") * range
	if flying: range *= settings.gmst("fsneakflyingdistancemult")
	range

# The reach narrowed for what is off to the side or behind: past fDetectionLOSDistanceAngle degrees
# off the facing it shrinks to fDetectionLOSDistanceMultInterior (outside, ...Exterior) at straight
# behind.
fn reachFacing(settings {str: f64}, range f32, angle f32, exterior bool):
	limit = settings.gmst("fdetectionlosdistanceangle").radians()
	if angle <= limit: return range
	end = settings.gmst(
		"fdetectionlosdistancemultexterior" if exterior else "fdetectionlosdistancemultinterior"
	)
	range * (((angle - limit) / (pi - limit)) * (end - 1.0) + 1.0)

# the share of the noise and the light that survives the distance
fn attenuation(settings {str: f64}, range f32, distance f32) f32:
	atLeastZero((range - distance) / range).pow(settings.gmst("fsneakdistanceattenuationexponent"))

# the light on the watched as the contest takes it (Actor::CalculateDetection): its light level
# truncated, tripled for a watcher with night eye, less the cell's ambient (the interior's capped at
# iLightLevelInteriorMod, outside iLightLevelExteriorMod), kept between 0 and iLightLevelMax
pub fn lightLevelOf(settings {str: f64}, s Sight, nightEye bool) i64:
	level = i64(s.lightRaw)
	if nightEye: level *= i64(settings.gmst("fdetectionnighteyebonus"))
	taken = i64(settings.gmst("ilightlevelexteriormod"))
	if not s.exterior:
		taken = i64(s.ambientMax * 100.0).min(i64(settings.gmst("ilightlevelinteriormod")))
	(level - taken).clamp(0, i64(settings.gmst("ilightlevelmax")))

# the detection value as the game keeps it: a value from 1 up, or from 0 down, truncated; one
# between 0 and 1 counts as 1
fn valueOf(total f32):
	i64(total) if total >= 1.0 or total <= 0.0 else 1

fn sizeMult(settings {str: f64}, size i64):
	match size:
		0: settings.gmst("fsneakdetectionsizesmall")
		1: settings.gmst("fsneakdetectionsizenormal")
		2: settings.gmst("fsneakdetectionsizelarge")
		3: settings.gmst("fsneakdetectionsizeverylarge")
		_: 1.0

# what the watched makes heard: the sound of its last action and of its steps (the weight it
# carries, doubled running), the more the nearer, a quarter as much without a line of sight
fn noiseOf(settings {str: f64}, w Watcher, q Quarry, hearing f32):
	run = settings.gmst("fsneakrunningmult") if q.running else 1.0
	weight = settings.gmst("fsneakequippedweightmult") * q.equippedWeight +
		settings.gmst("fsneakequippedweightbase")
	steps = run * (weight * (atLeastZero(q.movementNoise) * flag(q.moving)))
	acted = f32(i64(settings.gmst("fsneakactionmult")) * q.action)
	asleep = settings.gmst("fsneaksleepbonus") if w.sleeping else 0.0
	atLeastZero((acted + steps) * (settings.gmst("fsneaksoundsmult") * hearing) * (asleep + 1.0))

# what the watcher sees of the watched: its light level, in the watcher's sight, when it is not
# invisible and the watcher is awake, less the watcher's blindness
fn lightOf(
	settings {str: f64},
	w Watcher,
	q Quarry,
	s Sight,
	attenuated f32,
	seen bool,
	light i64
):
	visible = seen and not q.invisible
	gait = flag(q.running) * settings.gmst("fsneaklightrunmult") +
		(settings.gmst("fsneaklightmovemult") * flag(q.moving) + 1.0)
	lit = settings.gmst("fsneaklightexteriormult" if s.exterior else "fsneaklightmult")
	awake = f32(0.0) if w.sleeping else (100.0 - f32(i64(w.blindness))) * 0.01
	atLeastZero(flag(visible) * attenuated * gait * (f32(light) * lit + settings.gmst("fdetectionsneaklightmod")) *
			awake * (settings.gmst("fdetectionlargeactorsizemult") * settings.sizeMult(q.size)))

# the watcher's Sneak skill against the watched one's: the watcher's perception, with its alertness,
# sleep, other fight and ambush, against the skill the watched hides behind while it sneaks
fn skillOf(
	settings {str: f64},
	w Watcher,
	q Quarry,
	attenuated f32,
	perception f32,
	hidden f32
):
	alert = flag(w.alerted) * settings.gmst("fsneakalertmod") + 1.0
	fight = flag(w.fightsOther) * settings.gmst("fsneakcombatmod")
	sleep = flag(w.sleeping) * settings.gmst("fsneaksleepmod")
	ambush = match w.ambush:
		1: settings.gmst("fsneakambushtargetmod")
		2: settings.gmst("fsneakambushnontargetmod")
		_: 0.0
	low = settings.gmst("fsneakperceptionskillmin")
	scale = (settings.gmst("fsneakperceptionskillmax") - low) * perception * 0.01 + low
	(attenuated * ((alert + sleep + fight + ambush) * scale) - flag(q.sneaking) * hidden) *
		settings.gmst("fsneakskillmult")

# the Sneak skill of an actor the player's detection settings stretch: 0.4 x skill + 10 as the plugin sets them
fn skillSeenBy(settings {str: f64}, skill f32, isPlayer bool):
	if not isPlayer: return skill
	settings.gmst("fplayerdetectionsneakmult") * skill + settings.gmst("fplayerdetectionsneakbase")

# The detection value of 0x14041cd90 for a watcher within reach of the watched.
pub fn valueAt(settings {str: f64}, w Watcher, q Quarry, s Sight, seen bool, los bool) Reading:
	range = maxDistance(settings, s.exterior, w.flying or q.flying)
	near = attenuation(settings, range, s.distance)
	hearing = near
	if not los and w.ambush != 1: hearing = settings.gmst("fsneaksoundlosmult") * near
	noise = settings.noiseOf(w, q, hearing)
	light = settings.lightOf(w, q, s, near, seen, settings.lightLevelOf(s, w.nightEye))
	skill = settings.skillOf(w, q, near, settings.skillSeenBy(w.sneakSkill, w.isPlayer),
		settings.skillSeenBy(q.sneakSkill, q.isPlayer))
	total = noise + settings.gmst("fsneakbasevalue") + light + skill
	Reading(level = valueOf(total), noise, light, skill, inCone = seen, lineOfSight = los)

# What the watcher makes of the watched (Actor::CalculateDetection 0x1406a33b0): nothing beyond its
# reach (a fighter watching another has three quarters of it); within it the detection value, the
# line of sight kept to the watcher's view cone (fDetectionViewCone degrees, 190) and to the reach
# narrowed for what is behind it. A value of 0 counts as -1.
pub fn readingOf(settings {str: f64}, w Watcher, q Quarry, s Sight) Reading:
	range = maxDistance(settings, s.exterior, w.flying or q.flying)
	if w.fightsOther and not q.isPlayer:
		range *= settings.gmst("fdetectioncombatnontargetdistancemult")
	if s.distance >= range: return Reading(level = unseen)
	front = settings.gmst("fdetectionviewcone").radians() * 0.5
	los = s.clear and s.angle < front and
		s.distance < settings.reachFacing(range, s.angle, s.exterior)
	r = settings.valueAt(w, q, s, los, los)
	if r.level == 0: r.level = -1
	r

# The detection value of a sound the watched did not make itself (a detection event, 0x14041d230):
# a sound of this level at this distance, with the light on its source, heard by an awake or
# sleeping watcher, outside or in. The sound's reach is fSneakMaxDistance, that of fDetectEvent
# SneakDistanceVeryLoud for a very loud one, and a quarter of what it carries is lost without a
# line of sight (`clear`); the light term needs the sound inside the watcher's view cone.
pub fn heardLevel(
	settings {str: f64},
	sound i64,
	distance f32,
	clear bool,
	inCone bool,
	sleeping bool,
	exterior bool
) i64:
	range = settings.gmst("fsneakmaxdistance")
	if sound >= i64(settings.gmst("isoundlevelveryloud")):
		range = settings.gmst("fdetecteventsneakdistanceveryloud")
	if exterior: range = settings.gmst("fsneakexteriordistancemult") * range
	near = settings.attenuation(range, distance)
	hearing = near
	if not clear: hearing = settings.gmst("fsneaksoundlosmult") * near
	loud = (f32(i64(settings.gmst("fsneakactionmult")) * sound) * settings.gmst("fsneaksoundsmult") *
			hearing).max(0.0)
	lit = settings.gmst("fsneaklightexteriormult" if exterior else "fsneaklightmult")
	source = settings.gmst(
		"idetecteventlightlevelexterior" if exterior else "idetecteventlightlevelinterior"
	)
	awake = 0.0 if sleeping else 1.0
	seen = (
		flag(inCone) * near * (source * lit + settings.gmst("fdetectionsneaklightmod")) * awake
	).max(0.0)
	valueOf(seen + loud + settings.gmst("fsneakbasevalue"))
