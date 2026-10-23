# The player's skills advancing by use, and the character's levels, as SkyrimSE.exe 1.7.104 keeps
# them (reference/exe/README.md, "Skills, levels and the stats menu" has the addresses).
# PlayerSkills (a PlayerCharacter's pointer at 0x9c0) holds the character's experience and the
# experience to the next level, and for each of the 18 skills the experience in the level and the
# experience to the next. Using a skill adds its amount times the skill's use mult plus its use
# offset (the AVIF's AVSK: use mult, use offset, improve mult, improve offset); a skill rises one
# level each time its experience reaches pow(level, fSkillUseCurve) times the improve mult plus the
# improve offset, the character gaining the new skill level times fXPPerSkillRank in experience. The
# character rises when its experience reaches level times fXPLevelUpMult plus fXPLevelUpBase: the
# level-up menu raises health, magicka or stamina by iAVDhmsLevelUp (stamina also the carry weight
# by fLevelUpCarryWeightMod), the experience left is kept and health, magicka and stamina come back
# full. The perks' entry point 0x16 (perks.zap; Rested's bonus) changes the amount a use adds; the
# skills' legendary reset is not modelled.

import skyrim
import skyrim.esm

# a skill stops at 100 (the executable's own constant, 0x141b5bf14)
pub skillMax f32 = 100.0

# the sounds the HUD notification of a skill rising (0x1400b8490) and the level rising (0x14078e270,
# 0x140982160) play
pub skillIncreaseSound = "UISkillIncrease"
pub levelUpSound = "UILevelUp"

# the skill AVIF's AVSK: how fast a skill is used up and how much it takes to rise, and its name
pub type SkillUse:
	useMult f32
	useOffset f32
	improveMult f32
	improveOffset f32
	displayName str

# PlayerSkills::Data
pub type Progress:
	xp f32 = 0.0   # the character's experience
	skillXp f32[] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
		0.0, 0.0, 0.0]
	skillAtLevelUp f32[] = []   # each skill's level when the character last rose (SkillData's level)
	perkPoints i64 = 0

# the skill an AVIF's editor id names, "" for a record of no skill: the actor value's name with or
# without "AV" before it (the Illusion skill's record is AVMysticism, from the game it was made for)
pub fn skillOfEditorId(editorId str) str:
	lower = editorId.lower()
	skill = lower[2..] if lower.startsWith("av") else lower
	if skill == "mysticism": return "illusion"
	skill.copy() if skill in skillNames else ""

# the skill AVIFs' AVSK and names, by the skill's actor value name
pub fn loadSkillUses(mut w GameWorld, mut plugin esm.Esm, names skyrim.Strings):
	for id in plugin.formsOfKind("AVIF"):
		r = plugin.recordOf(id) ?? continue
		skill = skillOfEditorId(esm.textOf(r.body, r.fields, "EDID"))
		if skill.isEmpty: continue
		at = esm.dataOf(r.fields, "AVSK") ?? continue
		w.skillUses[skill] = SkillUse(
			useMult = r.body.f32le(at),
			useOffset = r.body.f32le(at + 4),
			improveMult = r.body.f32le(at + 8),
			improveOffset = r.body.f32le(at + 12),
			displayName = names.localText(r, "FULL")
		)

# the experience a skill of this AVSK needs to rise from this level: pow(level, curve) x improve
# mult + improve offset, none at the top
pub fn thresholdOf(use SkillUse, level f32, curve f32) f32:
	if skillMax <= level: return 0.0
	level.pow(curve) * use.improveMult + use.improveOffset

# the experience a skill needs to rise from this level (0x14078dcb0, fSkillUseCurve the curve)
pub fn skillThreshold(w GameWorld, skill str, level f32) f32:
	use = w.skillUses.get(skill) ?? return 0.0
	use.thresholdOf(level, w.settings.gmst("fskillusecurve"))

# a skill's level, its experience in the level and what the level needs, and the character's
# experience, as PlayerSkills keeps them
pub type SkillState:
	level f32
	skillXp f32
	threshold f32
	xp f32

# The loop of 0x14078dcb0 once the amount is known: the amount added, then while the experience
# reaches the threshold the level rises, the threshold is the new level's and the character gains
# floor((n + 1) n / 2) - floor(n (n - 1) / 2) times fXPPerSkillRank (n the new level), up to 100.
# The state after, and whether the skill rose.
pub fn gainExperience(
	start SkillState,
	amount f32,
	use SkillUse,
	curve f32,
	perRank f32
) (SkillState, bool):
	s = start
	s.skillXp = amount + s.skillXp
	raised = false
	loop:
		if s.skillXp < s.threshold: break
		s.skillXp -= s.threshold
		previous = s.level
		s.level = previous + 1.0
		raised = true
		s.threshold = use.thresholdOf(s.level, curve)
		reached = ((s.level + 1.0) * s.level * 0.5).floor()
		before = (s.level * previous * 0.5).floor()
		s.xp = (reached - before) * perRank + s.xp
		if not (s.level < skillMax): break
	(s, raised)

# the experience the character needs to rise from this level (0x14078e320)
pub fn levelThreshold(w GameWorld, level i64) f32:
	f32(level) * w.settings.gmst("fxplevelupmult") + w.settings.gmst("fxplevelupbase")

pub fn playerLevel(w GameWorld) i64:
	w.actors.get(w.player)?.level ?? 1

# the experience to the character's next level
pub fn nextLevelXp(w GameWorld) f32:
	w.levelThreshold(w.playerLevel())

# the character's experience, and what the next level needs (0x14078dc60)
pub fn levelProgress(w GameWorld) (f32, f32):
	(w.progress.xp, w.nextLevelXp())

# a skill's experience in its level, and what the next needs (0x14078dc10)
pub fn skillProgress(w GameWorld, skill str) (f32, f32):
	k = skillNames.indexOf(skill) ?? return (0.0, 0.0)
	level = w.actors.get(w.player)?.baseValueOf(skill) ?? 0.0
	(w.progress.skillXp[k], w.skillThreshold(skill, level))

# whether the experience has reached the next level (0x14078e250)
pub fn canLevelUp(w GameWorld) bool:
	w.progress.xp >= w.nextLevelXp()

# The skill gains `points` of experience as the player uses it (0x14078dcb0 with the use mult
# and offset applied, as PlayerCharacter's UseSkill 0x1407499e0 does): a skill that reaches its
# threshold rises, the character gaining the new level in experience, and says so at the HUD
# (sSkillIncreased: "<skill> Increased to <level>") unless `quiet`.
pub fn addSkillExperience(mut w GameWorld, skill str, points f32, scaled bool, quiet bool):
	k = skillNames.indexOf(skill) ?? return
	level = w.actors.get(w.player)?.baseValueOf(skill) ?? return
	use = w.skillUses.get(skill) ?? return
	if level >= skillMax: return
	amount = use.useMult * points + use.useOffset if scaled else points
	start = SkillState(
		level,
		skillXp = w.progress.skillXp[k],
		threshold = w.skillThreshold(skill, level),
		xp = w.progress.xp)
	after, raised = gainExperience(
		start,
		w.entryPointValue(epModSkillUse, w.player, [], amount),
		use,
		w.settings.gmst("fskillusecurve"), w.settings.gmst("fxpperskillrank"))
	w.progress.skillXp[k] = after.skillXp
	w.progress.xp = after.xp
	for j in 1..=i64(after.level - level):
		w.actors[w.player].setBaseValue(skill, level + f32(j))
		w.record("skill {skill} increased to {i64(level) + j}")
	if raised and not quiet:
		w.notifications.push("{use.displayName} Increased to {i64(after.level)}")
		w.playUi(skillIncreaseSound)

# the skill used for `points` (UseSkill: a skill used up to nothing gains nothing)
pub fn useSkill(mut w GameWorld, skill str, points f32):
	if points > 0.0: w.addSkillExperience(skill, points, true, false)

# The skill raised by `count` levels the way a skill book or a trainer does (0x14078e0a0): each level
# the experience it still lacked, the fraction already earned kept of the new level, one notice at
# the end.
pub fn incrementSkill(mut w GameWorld, skill str, count i64):
	k = skillNames.indexOf(skill) ?? return
	n = count.max(1)
	level = w.actors.get(w.player)?.baseValueOf(skill) ?? return
	threshold = w.skillThreshold(skill, level)
	fraction = w.progress.skillXp[k] / threshold if threshold != 0.0 else 0.0
	for i in 0..n:
		now = w.actors[w.player].baseValueOf(skill)
		w.addSkillExperience(skill, w.skillThreshold(skill, now) - w.progress.skillXp[k], false,
			i < n - 1)
	w.progress.skillXp[k] += w.skillThreshold(skill, w.actors[w.player].baseValueOf(skill)) *
		fraction

# the player's attributes the level-up menu raises, with the carry weight stamina adds
pub levelUpAttributes = ["health", "magicka", "stamina"]

# AdvanceLevel (0x14078e320) after the level has risen: the experience of the last level taken
# off, the next level's measured, the skills' levels kept, health raised by fPCHealthLevelBonus and
# health, magicka and stamina restored in full
fn advanceLevel(mut w GameWorld, spent f32):
	w.progress.xp -= spent
	w.progress.skillAtLevelUp = skillNames.map(w.actors[w.player].baseValueOf(it))
	bonus = w.settings.gmst("fpchealthlevelbonus")
	w.actors[w.player].setBaseValue("health", w.actors[w.player].baseValueOf("health") + bonus)
	for name in levelUpAttributes:
		w.actors[w.player].values[name].damage = 0.0

# The level-up menu's choice (0x14094ad60 with UpdateLevel's step 0x14078e270): the character
# rises one level, the attribute by iAVDhmsLevelUp (stamina also the carry weight by
# fLevelUpCarryWeightMod), a perk point is earned; why not when its experience falls short or the
# attribute is not one.
pub fn levelUp(mut w GameWorld, attribute str) str?:
	if not w.canLevelUp(): return "the character has not the experience to rise"
	if attribute not in levelUpAttributes: return "{attribute} is not an attribute to raise"
	spent = w.nextLevelXp()
	w.actors[w.player].level += 1
	w.actors[w.player].setBaseValue(
		attribute,
		w.actors[w.player].baseValueOf(attribute) + w.settings.gmst("iavdhmslevelup")
	)
	if attribute == "stamina":
		w.actors[w.player].modValue("carryweight", w.settings.gmst("flevelupcarryweightmod"))
	w.advanceLevel(spent)
	w.progress.perkPoints += 1
	w.playUi(levelUpSound)
	w.record("level {w.playerLevel()}: {attribute} raised")
	none

# the experience of stealing items worth `value` (0x140421ca0: the value to fPickpocketSkillUsesCurve)
pub fn pickpocketUsage(w GameWorld, value i64) f32:
	f32(f64(value).pow(f64(w.settings.gmst("fpickpocketskillusescurve"))))

# the stealth meter's reading the Sneak skill is used on (0x140421800 over 100 less the highest
# detection): fSkillUsageSneakPerSecond a second while some actor holds the player half-detected
pub fn sneakUsagePerSecond(w GameWorld) f32:
	best, _ = w.highestLevel()
	meter = 100 - best
	if meter == 0 or meter >= i64(w.settings.gmst("iskillusagesneakfulldetection")): return 0.0
	w.settings.gmst("fskillusagesneakpersecond")

# The Sneak skill used for dt seconds sneaking (PlayerCharacter 0x140756950's update): by the
# second in view of someone who is not sure of him, and fSkillUsageSneakHidden when he slips
# out of sight of those who had him (the stealth meter reaching 0, 0x14093a7e0 and 0x140756ab0).
pub fn useSneak(mut w GameWorld, dt f32, hiddenNow bool):
	if not w.stealth.sneaking: return
	w.useSkill("sneak", w.sneakUsagePerSecond() * dt)
	if hiddenNow: w.useSkill("sneak", w.settings.gmst("fskillusagesneakhidden"))
