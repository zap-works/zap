# What a fighter does in the fight, told to its animator as the events the game sends its behavior
# graph: the weapon drawn or sheathed (WeapEquip, Unequip; Magic_Equip for spells), a swing
# (attackStart; attackPowerStartForward then attackRelease; bashStart), a block (blockStart,
# blockStop), a stagger (staggerStart), a spell or a shout (fightMagic.zap), bleeding out (bleedOutStart), the
# fall of the dead (Ragdoll).
# The graph decides from them which clips play; a fighter's `Seen` is what was already told.

import game.combat

# what the animator was told of a fighter
pub type Seen:
	out bool = false
	right i64 = 0
	left i64 = 0
	swing f32 = -1.0   # when the swing told ends
	blocking bool = false
	staggered bool = false
	casting CastKind? = none
	fallen bool = false
	bleeding bool = false
	shouting i64 = 0

# how the fighter stands: what it holds in each hand, and whether it holds it out
pub type Stance:
	out bool
	right i64
	left i64

fn drawEventOf(s Stance):
	drawMagicEvent if handSpell in [s.right, s.left] else drawEvent

fn sendSwing(mut a Animator, x combat.Fighter, s combat.Swing):
	a.setVariable("weaponSpeedMult", 1.0 if s.strike == .Bash else x.speed)
	match s.strike:
		Normal: a.sendEvent(attackEvent)
		Power:
			a.sendEvent(powerEventOf(x.animation))
			a.sendEvent(releaseEvent)
		Bash: a.sendEvent(bashEvent)

fn sendDrawn(mut a Animator, mut seen Seen, s Stance):
	if s.out != seen.out or s.right != seen.right or s.left != seen.left:
		a.takeStance(s.right, s.left, s.out)
		if s.out:
			a.sendEvent(s.drawEventOf())
		elif seen.out:
			a.sendEvent(sheatheEvent)
		seen.out = s.out
		seen.right = s.right
		seen.left = s.left

fn sendCast(mut a Animator, mut seen Seen, kind CastKind?):
	if seen.casting is was:
		if kind is same and same == was: return
		a.stopCast(was)
		seen.casting = none
	if kind is k:
		a.startCast(k)
		seen.casting = k.copy()

# Tells the animator what changed in fighter x since it was last told: `stance` is how it stands
# now and `cast` how it casts, if it does.
pub fn sendFightEvents(
	mut a Animator,
	mut seen Seen,
	x combat.Fighter,
	stance Stance,
	cast CastKind?
):
	a.sendDrawn(seen, stance)
	if x.ragdoll and not seen.fallen:
		seen.fallen = true
		a.sendEvent(deathEvent)
	if x.shouting != seen.shouting:
		seen.shouting = x.shouting
		if x.shouting > 0: a.startShout(x.shouting, x.shoutHold, x.player, stance.out)
	if not stance.out or seen.fallen: return
	if x.swing is s and s.endsAt != seen.swing:
		seen.swing = s.endsAt
		a.sendSwing(x, s)
	blocking = x.mode == .Block
	if blocking != seen.blocking:
		seen.blocking = blocking
		a.setVariable("iWantBlock", 1.0 if blocking else 0.0)
		a.sendEvent(blockEvent if blocking else unblockEvent)
	bleeding = x.mode == .Bleedout
	if bleeding != seen.bleeding: a.sendEvent(bleedEvent if bleeding else bleedEndEvent)
	seen.bleeding = bleeding
	staggered = x.mode == .Staggered
	if staggered and not seen.staggered:
		a.setVariable(staggerVariable, x.staggerMagnitude)
		a.sendEvent(staggerEvent)
	seen.staggered = staggered
	a.sendCast(seen, cast)
