# The damage of a melee hit as the game computes it, every number a game setting (settings.zap
# says where each comes from): a weapon's base damage (WEAP DATA) times the skill's multiplier, from
# fDamagePCSkillMin (1) to fDamagePCSkillMax (1.5) over the skill 0 to 100 for the player and
# fDamageSkillMin (1) to fDamageSkillMax (3) for an NPC, which gives 1 + skill / 200 and 1 + skill /
# 50; unarmed, the race's unarmed damage (the unarmeddamage value, RACE DATA at 96: 4 for the
# Nord), which no skill raises; the inventory shows the damage rounded (an iron dagger, 4, at
# One-Handed 20: 4.4, shown 4). A power attack adds fPowerAttackDefaultBonus (1: twice the damage;
# none unarmed, UESP's Skyrim:Damage) and costs (fStaminaAttackWeaponBase 20 +
# fStaminaAttackWeaponMult 1 x the weapon's weight) x fPowerAttackStaminaPenalty 2 stamina, 40 + 2
# x weight; a plain attack costs none. A sneak attack multiplies by fCombatSneak1HDaggerMult and
# the others by weapon type (3 one-handed, 2 two-handed, fCombatSneakHandMult 2 unarmed).
#
# Armor: an armor's rating grows with its skill, rounded up: ceil(rating x lerp(fArmorRatingBase
# 1, fArmorRatingPCMax 1.4, skill / 100)) for the player, fArmorRatingMax 2.5 at 100 for an NPC;
# the damage taken is reduced by min(fMaxArmorRating 80, the rating x fArmorScalingFactor 0.12 +
# 100 x fArmorBaseFactor 0.03 each piece of armor worn, clothing none) percent (UESP's
# Skyrim:Armor). Blocking takes off (SkyrimSE.exe 0x14041f4d0, called by the hit's 0x1407f09d0,
# reference/exe/README.md, "Combat: what the executable computes") (fBlockWeaponBase 0.3 +
# fBlockWeaponScaling 0.2 x the attacker's weapon damage / 100 x the skill's factor) with a weapon,
# (fShieldBaseFactor 0.45 + fShieldScalingFactor 0.2 x the shield's rating / 100 x the factor) with
# a shield, the factor lerp(fArmorRatingBase 1, fArmorRatingMax 2.5, Block / 100), times
# fBlockPowerAttackMult 0.66 against a power attack, at most fPlayerMaxResistance 85% (fBlockMax is
# read by nothing); the shield's ShieldPerks actor value (none without perks) is added to the
# factor; the blocker loses fStaminaBlockDmgMult 0.25 of the damage blocked as stamina. A bash does
# the weapon's base damage x 0.5 x lerp(fWeaponBashPCMin 0.1, fWeaponBashPCMax 0.5, Block / 100) for
# the player (fWeaponBashMin 0.1 to fWeaponBashMax 0.25 for an NPC), a shield's rating in place of
# the damage and fShieldBashPCMin/Max (fShieldBashMin/Max), and costs fStaminaBashBase 35 stamina.
# Difficulty (the world's, Adept by default, which multiplies nothing) multiplies the damage the
# player deals by fDiffMultHPByPC* and the damage the player takes by fDiffMultHPToPC* (strike.zap).

# a strike's kind
import game.sim

pub type Strike:
	Normal
	Power
	Bash

# WEAP DNAM's animation types that are daggers, one-handed, two-handed, bows
dagger = 2
oneHanded = [1, 3, 4]
twoHanded = [5, 6]
bows = [7, 9]

# The stagger a hit gives, as SkyrimSE.exe computes it (0x1407f0690 and its helpers,
# reference/exe/README.md, "Combat: what the executable computes"), every number a game setting: a
# hit's magnitude is the weapon's stagger (WEAP DNAM, 1 for fists) times the attack's (the race's
# ATKD) divided by the target's mass term (fStaggerMassMult x mass + fStaggerMassBase, the player's
# mass x fStaggerPlayerMassMult), less the mass offset max(0, (mass - fStaggerMassOffsetBase) x
# fStaggerMassOffsetMult); a bash's is (fStaggerAttackBase + fStaggerAttackMult x the attacker's
# Block) over the mass term, times the weapon's kind (fStaggerShieldMult with a shield,
# fStagger2WeapMult or fStagger1WeapMult by hand, 1 bare), times the attack's, times
# fStaggerRecoilingMult when the target is staggered, fStaggerRunningMult when it runs and
# fStaggerBlockingMult when it blocks; a blocked hit loses fStaggerBlockAttackShieldBase +
# fStaggerBlockAttackShieldMult x the shield's rating + fStaggerBlockBase + fStaggerBlockMult x the
# blocker's Block + its mass offset; every result at least fStaggerMin. The ward term of a staff or
# bow is left out (no magic weapon in the inn).

# the mass term a hit's magnitude is divided by, and the target's mass offset
fn massTerm(settings {str: f64}, mass f32):
	settings.gmst("fstaggermassmult") * mass + settings.gmst("fstaggermassbase")

fn massOffset(settings {str: f64}, mass f32):
	(
		(mass - settings.gmst("fstaggermassoffsetbase")) * settings.gmst("fstaggermassoffsetmult")
	).max(0.0)

# the magnitude of a hit on a target of this mass
pub fn hitStagger(
	settings {str: f64},
	targetMass f32,
	targetPlayer bool,
	weaponStagger f32,
	attackStagger f32
) f32:
	mass = targetMass * (settings.gmst("fstaggerplayermassmult") if targetPlayer else 1.0)
	term = settings.massTerm(mass)
	base = (1.0 / term if term.abs() > 0.0001 else 1.0) * weaponStagger * attackStagger
	(base - settings.massOffset(mass)).max(settings.gmst("fstaggermin"))

# what the target holds and does, as the bash's stagger weighs it
pub type BashTarget:
	mass f32
	staggered bool
	running bool
	blocking bool

# the magnitude of a bash by a fighter of this Block skill holding a shield, a weapon of a kind
# (two-handed or not) or nothing
pub fn bashStagger(
	settings {str: f64},
	block f32,
	shield bool,
	armed bool,
	twoHanded bool,
	attackStagger f32,
	target BashTarget
) f32:
	kind = f32(1.0)
	if shield: kind = settings.gmst("fstaggershieldmult")
	elif twoHanded: kind = settings.gmst("fstagger2weapmult")
	elif armed: kind = settings.gmst("fstagger1weapmult")
	state = settings.gmst("fstaggerrecoilingmult") if target.staggered else 1.0
	if target.running: state *= settings.gmst("fstaggerrunningmult")
	if target.blocking: state *= settings.gmst("fstaggerblockingmult")
	attack = settings.gmst("fstaggerattackbase") + settings.gmst("fstaggerattackmult") * block
	(attack / settings.massTerm(target.mass) * kind * attackStagger * state).max(
		settings.gmst("fstaggermin")
	)

# the magnitude left to a hit the target blocks with its Block skill and its shield's rating (none
# for a weapon)
pub fn blockedStagger(
	settings {str: f64},
	magnitude f32,
	block f32,
	shieldRating f32?,
	targetMass f32
) f32:
	taken = settings.gmst("fstaggerblockattackshieldbase") +
		settings.gmst("fstaggerblockattackshieldmult") * (shieldRating ?? 0.0) +
		settings.gmst("fstaggerblockbase") + settings.gmst("fstaggerblockmult") * block +
		settings.massOffset(targetMass)
	(magnitude - taken).max(settings.gmst("fstaggermin"))

# the skill's damage multiplier for the player or an NPC
pub fn skillMultiplier(settings {str: f64}, skill f32, player bool) f32:
	at = skill.clamp(0.0, 100.0) / 100.0
	if player:
		return settings.gmst("fdamagepcskillmin") +
			(settings.gmst("fdamagepcskillmax") - settings.gmst("fdamagepcskillmin")) * at
	settings.gmst("fdamageskillmin") +
		(settings.gmst("fdamageskillmax") - settings.gmst("fdamageskillmin")) * at

# a weapon's damage in the skill's hands, before armor
pub fn weaponDamage(settings {str: f64}, baseDamage f32, skill f32, player bool) f32:
	baseDamage * settings.skillMultiplier(skill, player)

# the damage the inventory shows
pub fn shownDamage(settings {str: f64}, baseDamage f32, skill f32, player bool) i64:
	i64(settings.weaponDamage(baseDamage, skill, player).round())

# a strike's multiplier of the damage
pub fn strikeMultiplier(settings {str: f64}, strike Strike, unarmed bool) f32:
	match strike:
		Normal: 1.0
		Power: 1.0 if unarmed else 1.0 + settings.gmst("fpowerattackdefaultbonus")
		Bash: 0.5

# the stamina a power attack with a weapon of this weight costs
pub fn powerAttackStamina(settings {str: f64}, weight f32) f32:
	(
		settings.gmst("fstaminaattackweaponbase") +
			settings.gmst("fstaminaattackweaponmult") * weight
	) *
		settings.gmst("fpowerattackstaminapenalty")

# a sneak attack's multiplier by the weapon's animation type (0 unarmed)
pub fn sneakMultiplier(settings {str: f64}, animation i64) f32:
	if animation == 0: return settings.gmst("fcombatsneakhandmult")
	if animation == dagger: return settings.gmst("fcombatsneak1hdaggermult")
	if animation in oneHanded: return settings.gmst("fcombatsneak1hswordmult")
	if animation in twoHanded: return settings.gmst("fcombatsneak2hswordmult")
	if animation in bows: return settings.gmst("fcombatsneakbowmult")
	1.0

# an armor's rating in the skill's hands
pub fn armorRating(settings {str: f64}, rating f32, skill f32, player bool) f32:
	top = settings.gmst("farmorratingpcmax" if player else "farmorratingmax")
	low = settings.gmst("farmorratingbase")
	(rating * (low + (top - low) * skill.clamp(0.0, 100.0) / 100.0)).ceil()

# the share of physical damage armor of this total rating and this many pieces takes off
pub fn armorReduction(settings {str: f64}, rating f32, pieces i64) f32:
	percent = rating * settings.gmst("farmorscalingfactor") +
		f32(pieces) * settings.gmst("farmorbasefactor") * 100.0
	percent.min(settings.gmst("fmaxarmorrating")) / 100.0

# the share of a hit a block takes off: with a shield of this rating, else with a weapon against an
# attacker's weapon of this base damage
pub fn blockShare(
	settings {str: f64},
	block f32,
	shieldRating f32?,
	attackerDamage f32,
	strike Strike
) f32:
	base = settings.gmst("farmorratingbase")
	factor = base + (settings.gmst("farmorratingmax") - base) * block * 0.01
	share = match shieldRating:
		rating: settings.gmst("fshieldbasefactor") +
			settings.gmst("fshieldscalingfactor") * rating / 100.0 * factor
		none: settings.gmst("fblockweaponbase") +
			settings.gmst("fblockweaponscaling") * attackerDamage / 100.0 * factor
	if strike == .Power: share *= settings.gmst("fblockpowerattackmult")
	share.min(settings.gmst("fplayermaxresistance") * 0.01)

# the stamina a block of this much damage costs the blocker
pub fn blockStamina(settings {str: f64}, blocked f32) f32:
	settings.gmst("fstaminablockbase") + settings.gmst("fstaminablockdmgmult") * blocked

# a bash's damage with a weapon of this base damage, or a shield of this rating
pub fn bashDamage(settings {str: f64}, base f32, shield bool, block f32, player bool) f32:
	kind = "shield" if shield else "weapon"
	who = "pc" if player else ""
	low = settings.gmst("f{kind}bash{who}min")
	high = settings.gmst("f{kind}bash{who}max")
	base * 0.5 * (low + (high - low) * block.clamp(0.0, 100.0) / 100.0)

# The damage a hit does: its damage before armor less what the armor and a block take off.
pub fn damageTaken(raw f32, armorShare f32, blockedShare f32) f32:
	raw * (1.0 - armorShare) * (1.0 - blockedShare)
