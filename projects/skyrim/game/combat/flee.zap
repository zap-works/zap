# Whether a fighter flees, as SkyrimSE.exe decides it (reference/exe/README.md, "Combat: what the
# executable computes"): its side's threat over its foes' (0x140856b90, the combat group's sums of
# 0x14081f4d0) against a threshold from its Confidence (0x140856ce0): the fConfidence settings,
# Cowardly for 0 up to Foolhardy for 4, read between levels at its Confidence plus the modifier it
# drew when the fight began (0x140855990; none at 0 or 4); it flees when the threshold is over the
# ratio. A fighter's threat (0x1406c9130) is its damage a second over what armor leaves (1 - its
# share, at most 0.99) times its health; the damage a second (0x1406cc570, 0x14041ec50) its weapon's
# damage in its skill's hands times the weapon's speed times fCombatDPSMeleeSpeedMult
# (fCombatDPSBowSpeedMult for a bow or crossbow).

import game.sim

confidenceNames = ["fconfidencecowardly", "fconfidencecautious", "fconfidenceaverage",
	"fconfidencebrave", "fconfidencefoolhardy"]
mostArmor f32 = 0.99

# fighter x's damage a second
fn damagePerSecond(f Fight, x Fighter):
	a = f.w.actors[x.refId]
	skill = a.valueOf(x.skill) if x.skill != "" else 0.0
	damage = f.w.settings.weaponDamage(x.baseDamage, skill, x.player)
	mult = "fcombatdpsbowspeedmult" if x.animation in bows else "fcombatdpsmeleespeedmult"
	damage * x.speed * f.w.settings.gmst(mult)

# fighter x's threat: its damage a second over what its armor leaves of a hit, times its health
pub fn threatOf(f Fight, x Fighter) f32:
	armor = (
		x.armorRating * f.w.settings.gmst("farmorscalingfactor") * 0.01 +
			f32(x.armorPieces) * f.w.settings.gmst("farmorbasefactor")
	).min(mostArmor)
	f.damagePerSecond(x) / (1.0 - armor) * f.health(x.refId)

# the threshold of fighter x's confidence, the settings read between levels
pub fn fleeThreshold(f Fight, x Fighter) f32:
	level = x.ai.confidence.clamp(0, 4)
	at = f32(level)
	if level != 0 and level != 4: at += x.confidenceModifier
	at = at.clamp(0.0, 4.0)
	low = i64(at.floor())
	high = (low + 1).min(4)
	a = f.w.settings.gmst(confidenceNames[low])
	a + (f.w.settings.gmst(confidenceNames[high]) - a) * (at - f32(low))

# fighter k's side's threat over its foes': its own and its allies' (those fighting its foe) over
# those it fights
pub fn threatRatio(f Fight, k i64) f32:
	x = f.fighters[k]
	ours = 0.0
	theirs = 0.0
	for i, o in f.fighters:
		if o.isOut(): continue
		if i == k or (o.isFighting() and o.target == x.target and x.target != 0):
			ours += f.threatOf(o)
		elif o.target == x.refId or o.refId == x.target:
			theirs += f.threatOf(o)
	ours / theirs if theirs > 0.0 else 100.0

# whether fighter k is outmatched enough to flee now
pub fn isOutmatched(f Fight, k i64) bool:
	f.fleeThreshold(f.fighters[k]) > f.threatRatio(k)

# fighter k draws the modifier its confidence keeps for the fight
pub fn drawConfidenceModifier(mut f Fight, k i64):
	low = f.w.settings.gmst("fcombatconfidencemodifiermin")
	high = f.w.settings.gmst("fcombatconfidencemodifiermax")
	f.fighters[k].confidenceModifier = f32(f.rng.nextFloat(f64(low), f64(high)))
