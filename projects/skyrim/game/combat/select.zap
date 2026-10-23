# The choice of a foe, as SkyrimSE.exe's CombatTargetSelectorStandard makes it (0x140862040 and
# 0x1408622e0, reference/exe/README.md, "Combat: what the executable computes"): every
# fCombatSelectTargetUpdateTime (1 s), or fCombatSelectTargetSwitchUpdateTime (3 s) after a change,
# each foe in sight is weighed and the heaviest taken. With more than one foe the weight is: 1000
# when the foe hurt the fighter within 2 s, else 1000 when it is the current foe and the fighter
# hurt it within 2 s, plus 100 when the fighter hurt it within 2 s (the combat memory's two flags,
# read here as who struck whom); 100 for the current foe; 100 when both fight in melee or both at
# range; (1 - distance / 2048) x 1000 with the distance at most 2048; 2000 less out of sight (here
# beyond fSneakMaxDistance, as witnesses are) and 500 less when the foe flees. A lone foe weighs 0.

import game.sim

recentHit f32 = 2.0
farthest f32 = 2048.0

fn meleeFighter(x Fighter):
	x.animation <= 6

# whether fighter k may count fighter i among its foes
fn isFoe(f Fight, k i64, i i64):
	x = f.fighters[k]
	other = f.fighters[i]
	if i == k or other.isOut() or other.mode == .Fled: return false
	other.target == x.refId or other.refId == x.target or f.w.attacksOnSight(f.ties, x, other.refId)

# the weight fighter k gives fighter i among `count` foes
pub fn foeWeight(f Fight, k i64, i i64, count i64) f32:
	if count <= 1: return 0.0
	x = f.fighters[k]
	c = f.fighters[i]
	current = c.refId == x.target
	weight = 0.0
	if x.struckBy == c.refId and f.time - x.struckAt <= recentHit:
		weight += 1000.0
	elif current and x.landedOn == c.refId and f.time - x.landedAt <= recentHit:
		weight += 1000.0
	if x.landedOn == c.refId and f.time - x.landedAt <= recentHit: weight += 100.0
	if current: weight += 100.0
	if x.meleeFighter() == c.meleeFighter(): weight += 100.0
	d = x.at.distance(c.at)
	weight += (1.0 - d.min(farthest) / farthest) * 1000.0
	if d > f.w.settings.gmst("fsneakmaxdistance"): weight -= 2000.0
	if c.mode == .Flee: weight -= 500.0
	weight

# fighter k weighs its foes when its timer says so and takes the heaviest
pub fn selectTarget(mut f Fight, k i64):
	x = f.fighters[k]
	if x.player or x.controlled or f.time < x.targetCheckAt: return
	foes = (0..f.fighters.len).filter(f.isFoe(k, it))
	best = -1
	most = 0.0
	for i in foes:
		w = f.foeWeight(k, i, foes.len)
		if best < 0 or w > most:
			best = i
			most = w
	changed = best >= 0 and f.fighters[best].refId != x.target
	wait = "fcombatselecttargetswitchupdatetime" if changed else "fcombatselecttargetupdatetime"
	f.fighters[k].targetCheckAt = f.time + f.w.settings.gmst(wait)
	if changed: f.engage(k, f.fighters[best].refId)
