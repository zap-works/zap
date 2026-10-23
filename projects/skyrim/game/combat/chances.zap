# The weights of the combat AI's choices, as the install's SkyrimSE.exe (v1.7.104) computes them:
# the combat behavior tree picks among a node's children by weighted random, and each weight is one
# of a handful of small functions of the combat style (TESCombatStyle: CSGD at +0x20, CSME at +0x48,
# CSCR at +0x68, CommonLibSSE-NG's layout) and of the target's state. Each lerps a pair of game
# settings (fCombat*Min, fCombat*Max) by a style multiplier, min + (max - min) x mult (0x1408f1b70),
# then scales by the situation. The addresses are the executable's; the settings' values are the
# ones it compiles in (settings.zap lists them) unless the plugin sets them; the tree's shape is in
# README.md.
#
#   attack      0x1408f2720  offensive (grouped, 0x1408f1ad0), x the incapacitated mults, x the
#                            blocking mult, x the last-attack ramp
#   variant     0x1408f2830  the attack's own chance (RACE ATKD) x the style's mult for the target
#   block       0x1408f2960  defensive, x fCombatBlockChanceWeaponMult bare-handed
#   bash        0x1408f2b20  defensive, x the target-state mult (0x1408f2be0)
#   off. bash   0x1408f2b80  offensive, x the same
#   circle      0x1408f1ec0, angle 0x1408f1ef0
#   fallback    0x1408f1e00, distance 0x1408f1e30, wait 0x1408f1e90
#   block time  0x1408f2ae0
#
# Not modelled: the special attack (0x1408f2900, the sprint and running attacks), the block attack
# (0x1408f2930), the backoff (a flat fCombatBackoffChance), and the circle's and the fall back's
# floors by the actor's radius (0x140685900).

import game.sim

# The attack variants' own chances, from the Nord race's attack data (Skyrim.esm RACE ATKD,
# attackChance): the plain attackStart is 1, the in-place power attackPowerStartInPlace 0.2.
plainAttackChance f32 = 1.0
powerAttackChance f32 = 0.2

# the weight of the Idle child of a selector; it only waits (an assumption: the executable's
# selector code was not read, only that the Idle node carries no weight function)
pub idleWeight f32 = 1.0

# how long an Idle node waits (its argument in the Melee, Block and Close Movement trees) before
# the repeat node chooses again
pub idleTime f32 = 0.25

fn lerp(f Fight, lo str, hi str, t f32):
	a = f.w.settings.gmst(lo)
	b = f.w.settings.gmst(hi)
	a + (b - a) * t

# The style's will to attack, lowered while a group fights one target: a group offensive mult under
# 1 is raised to the power of the members less one, at least fCombatGroupOffensiveMultMin
# (0x1408f1ad0). The member count is how many fight the same target.
pub fn offensive(f Fight, x Fighter, members i64) f32:
	if x.style.groupOffensive >= 1.0 or members <= 1: return x.style.offensive
	grouped = f32(f64(x.style.groupOffensive).pow(members - 1))
	x.style.offensive * grouped.max(f.w.settings.gmst("fcombatgroupoffensivemultmin"))

# the target cannot answer: staggered or bleeding out
pub fn isIncapacitated(target Fighter) bool:
	target.mode == .Staggered or target.mode == .Bleedout

fn swinging(target Fighter):
	swing = target.swing ?? return false
	not swing.landed

fn powerSwinging(target Fighter):
	swing = target.swing ?? return false
	not swing.landed and swing.strike == .Power

# The weight of the Attack node (0x1408f2720). sinceAttack is the seconds since this fighter's
# last swing, none before its first.
pub fn attack(f Fight, x Fighter, target Fighter, members i64, sinceAttack f32?) f32:
	s = x.style
	w = f.lerp("fcombatattackchancemin", "fcombatattackchancemax", f.offensive(x, members))
	if target.isIncapacitated():
		w *= s.powerAttackStaggered.max(s.attackStaggered)
	elif target.mode == .Block:
		w *= f.lerp(
			"fcombatattackchanceblockingmultmax",
			"fcombatattackchanceblockingmultmin",
			s.defensive
		)
	if sinceAttack != none:
		span = f.w.settings.gmst("fcombatattackchancelastattackbonustime")
		ramp = (sinceAttack ?? 0.0).min(span) / span
		w *= 1.0 + ramp * (f.w.settings.gmst("fcombatattackchancelastattackbonus") - 1.0)
	w

# The weight of one attack among the Attack node's variants (0x1408f2830): its own chance, times the
# style's mult against a target that cannot answer (the plain attack's or the power attack's) or,
# for a power attack, against one that blocks.
pub fn variant(s Style, target Fighter, power bool) f32:
	own = powerAttackChance if power else plainAttackChance
	if target.isIncapacitated():
		return own * (s.powerAttackStaggered if power else s.attackStaggered)
	if power and target.mode == .Block: return own * s.powerAttackBlocking
	own

# The weight of blocking (0x1408f2960); bare hands block a quarter as often.
pub fn block(f Fight, x Fighter) f32:
	w = f.lerp("fcombatblockchancemin", "fcombatblockchancemax", x.style.defensive)
	w * (f.w.settings.gmst("fcombatblockchanceweaponmult") if x.weapon == 0 else 1.0)

# The bash weights' shared factor (0x1408f2be0): the style's bash mult, times its recoil mult against
# a staggered target, its power attack mult against one swinging a power attack, its attack mult
# against one swinging, and fCombatBashTargetBlockingMult (0) against one that blocks.
fn bashState(f Fight, s Style, target Fighter):
	if target.isIncapacitated(): return s.bash * s.bashRecoil
	if target.powerSwinging(): return s.bash * s.bashPowerAttack
	if target.swinging(): return s.bash * s.bashAttack
	if target.mode == .Block: return s.bash * f.w.settings.gmst("fcombatbashtargetblockingmult")
	s.bash

# the weight of a bash made as a defense (0x1408f2b20)
pub fn bash(f Fight, x Fighter, target Fighter) f32:
	w = f.lerp("fcombatbashchancemin", "fcombatbashchancemax", x.style.defensive)
	w * f.bashState(x.style, target)

# the weight of a bash made as an attack (0x1408f2b80)
pub fn offensiveBash(f Fight, x Fighter, target Fighter, members i64) f32:
	w = f.lerp(
		"fcombatoffensivebashchancemin",
		"fcombatoffensivebashchancemax",
		f.offensive(x, members)
	)
	w * f.bashState(x.style, target)

pub fn circle(f Fight, x Fighter) f32:
	f.lerp("fcombatcirclechancemin", "fcombatcirclechancemax", x.style.circle)

pub fn fallback(f Fight, x Fighter) f32:
	f.lerp("fcombatfallbackchancemin", "fcombatfallbackchancemax", x.style.fallback)

# The angle a circle goes round the target, in degrees: from fCombatCircleAngleMin up to the
# style's top, three quarters of it round the player (0x1408f1ef0); `roll` is the random 0..1.
pub fn circleAngle(f Fight, x Fighter, target Fighter, roll f32) f32:
	lo = f.w.settings.gmst("fcombatcircleanglemin")
	top = f.lerp("fcombatcircleanglemin", "fcombatcircleanglemax", x.style.circle)
	angle = lo + (top - lo) * roll
	angle * (f.w.settings.gmst("fcombatcircleangleplayermult") if target.player else 1.0)

# how far a fall back goes (0x1408f1e30)
pub fn fallbackDistance(f Fight, x Fighter) f32:
	f.lerp("fcombatfallbackdistancemin", "fcombatfallbackdistancemax", x.style.fallback)

# how long it waits after falling back (0x1408f1e90)
pub fn fallbackWait(f Fight, x Fighter) f32:
	f.lerp("fcombatfallbackwaittimemin", "fcombatfallbackwaittimemax", x.style.fallback)

# How long a block lasts at most (0x1408f2ae0): fCombatBlockTimeMin (4 s) for a defensive mult up to
# 0.5, rising through fCombatBlockTimeMid (8 s) at 0.5 to fCombatBlockTimeMax (no limit) at 1.
pub fn blockTime(f Fight, x Fighter) f32:
	t = x.style.defensive * 2.0 - 1.0
	if t <= 0.0: return f.w.settings.gmst("fcombatblocktimemin")
	mid = f.w.settings.gmst("fcombatblocktimemid")
	mid + (f.w.settings.gmst("fcombatblocktimemax") - mid) * t

# The index of the weight a roll in 0..1 lands on when each takes a share of their sum (the
# weighted random child selector); the last when all are 0.
pub fn pick(weights f32[], roll f32) i64:
	total = weights.sum()
	if total <= 0.0: return weights.len - 1
	at = roll * total
	run = f32(0.0)
	for i, w in weights:
		run += w
		if at < run: return i
	weights.len - 1
