# The stats menu (statsMenu.swf) and the level-up menu (levelupmenu.swf) filled as SkyrimSE.exe
# 1.7.104 fills them. The stats menu (StatsMenu 0x140976a50...) is told the skills by
# StatsMenu.SkillStatsA, five values for each of the 18 skills (UpdateSkillList 0x140979790): the
# current value rounded down, the name, the percent of the way to the next level
# (experience over threshold, 0x14078dc10), the colour of the value (white, green when raised and
# red when lowered, 0x140992510) and the legendary count; then UpdateSkillList(english). The
# player's card is SetPlayerInfo (0x14097da30): the name, the level, the percent of the way to the
# next, the race, then magicka, health and stamina each as current, maximum and colour; and
# SetStatsMode(no perk points, perk points) (0x14097a0d0). Choosing a perk of a constellation is
# chooseSkillPerk (perkTree.zap). The constellations' 3D scene, a skill's description card
# (SetDescriptionCard) and the legendary button are not filled. The level-up menu calls the game
# back with addHealth, addMagicka or addStamina (0x14094aa80) and the game raises that attribute
# (skills.zap).

import engine.swf.avm1
import game.sim
import skyrim

# the colours the values take (0x140992510), the margin below which a change is none
raisedColor = "#189515"
loweredColor = "#FF0000"
plainColor = "#FFFFFF"
colorMargin f32 = 0.001

# the game's calls of the level-up menu and the attribute each raises
levelUpCalls = ["addHealth", "addMagicka", "addStamina"]

# the colour the value of the actor value is written in: green when something raises it above its
# base, red when something lowers it
fn colorOf(a sim.ActorState, name str):
	v = a.values.get(name) ?? return plainColor
	shift = v.modifier
	if shift < -colorMargin: return loweredColor
	raisedColor if shift > colorMargin else plainColor

# the value rounded down, never below 0 (the card's numbers)
fn shownValue(a sim.ActorState, name str) f64:
	f64(a.valueOf(name).max(0.0).floor())

# the five values of each skill for StatsMenu.SkillStatsA
fn skillRows(mut t GameTexts, w sim.GameWorld):
	a = w.actors[w.player].copy()
	out avm1.Value[] = []
	for name in sim.skillNames:
		xp, threshold = w.skillProgress(name)
		percent = xp / threshold * 100.0 if threshold > 0.0 else 0.0
		out.push(.Num(f64(a.valueOf(name).floor())))
		out.push(.Str(t.skillName(name)))
		out.push(.Num(f64(percent)))
		out.push(.Str(a.colorOf(name)))
		out.push(.Num(0.0))
	out

# one attribute's three values on the card: current, maximum, colour
fn attributeCard(a sim.ActorState, name str) avm1.Value[]:
	full = a.baseValueOf(name) + (a.values.get(name)?.modifier ?? 0.0)
	[.Num(a.shownValue(name)), .Num(f64(full.max(0.0).floor())), .Str(a.colorOf(name))]

# the player's card: SetPlayerInfo's arguments
fn playerCard(mut t GameTexts, w sim.GameWorld, name str):
	a = w.actors[w.player].copy()
	xp, needed = w.levelProgress()
	out avm1.Value[] = [.Str(name.copy()), .Num(f64(w.playerLevel())),
		.Num(f64(xp / needed * 100.0) if needed > 0.0 else 0.0), .Str(t.nameOf(a.race))]
	for attribute in ["magicka", "health", "stamina"]:
		out.extend(a.attributeCard(attribute))
	out

# the perk points the player has to spend
fn perkPointsOf(w sim.GameWorld):
	w.progress.perkPoints

# the stats menu's lists and card filled from the world
pub fn showStats(mut p avm1.Player, mut t GameTexts, w sim.GameWorld, name str):
	p.write("StatsMenu.SkillStatsA", p.newList(t.skillRows(w)))
	p.delegate("UpdateSkillList", [.Bool(true)])
	p.delegate("SetPlayerInfo", t.playerCard(w, name))
	p.showPerkPoints(w)

# the perk points left, as SetStatsMode(no perk points, perk points) tells the menu
fn showPerkPoints(mut p avm1.Player, w sim.GameWorld):
	points = w.perkPointsOf()
	p.invoke("StatsMenuBaseInstance.SetStatsMode", [.Bool(points == 0), .Num(f64(points))])

# The player chooses the perk of a node of the skill's constellation (the menu's confirmation,
# 0x1409790a0): the world takes the perk and a perk point, and the menu is told how many are left;
# why not when the choice is refused (perkTree.zap).
pub fn chooseSkillPerk(mut p avm1.Player, mut w sim.GameWorld, skill str, node i64) str?:
	if w.choosePerk(skill, node) is why: return why
	p.showPerkPoints(w)
	none

# the stats menu opened over the world as the tween menu's Up opens it
pub fn openStats(
	install skyrim.Install,
	mut t GameTexts,
	w sim.GameWorld,
	name str,
	width i64,
	height i64
) avm1.Player ? str:
	p = try install.openPlayer("interface/statsmenu.swf", width, height)
	p.invokeText("InitExtensions()")
	p.invokeText("SetPlatform(0, false)")
	p.showStats(t, w, name)
	p

# the level-up menu opened as sleeping with enough experience opens it
pub fn openLevelUp(install skyrim.Install, width i64, height i64) avm1.Player ? str:
	p = try install.openPlayer("interface/levelupmenu.swf", width, height)
	p.invokeText("InitExtensions()")
	p.invokeText("SetPlatform(0, false)")
	p

# The attribute the level-up menu's call raised in the world, none for a call that is not a choice
# (the attribute raises, the level rises).
pub fn answerLevelUp(mut w sim.GameWorld, call avm1.ExternalCall) str?:
	k = try levelUpCalls.indexOf(call.name)
	attribute = sim.levelUpAttributes[k]
	if w.levelUp(attribute) is why:
		w.record(why)
		return none
	attribute.copy()
