# A cell's fight made from the plugin and the install: every actor of the world a fighter, named
# by its base's editor id, in its combat style, with its race's fists and attacks (records.zap's
# RaceCombat), the attacks' timings given (measured on the behavior graph, game/fightClips.zap), the
# speeds from the movement types, the relationships and the factions' reactions, the crime values
# of every crime faction there.

import skyrim.esm
import game.sim

pub fn nameOf(mut plugin esm.Esm, w sim.GameWorld, refId i64) str:
	if refId == w.player: return "Player"
	a = w.actors.get(refId) ?? return "{refId:08X}"
	r = plugin.recordOf(a.npc) ?? return "{refId:08X}"
	esm.textOf(r.body, r.fields, "EDID")

fn tiesOf(mut plugin esm.Esm, w sim.GameWorld):
	reactions {i64: {i64: i64}} = {}
	for a in w.actors.values():
		for m in a.factions:
			if reactions.get(m.faction) == none:
				reactions[m.faction] = plugin.reactionsOf(m.faction)
	Ties(relationships = plugin.relationshipsOf(), reactions)

# The fight of the world's actors, none fighting yet, its rolls from the seed; or why the plugin
# cannot give it.
pub fn sceneFight(
	mut plugin esm.Esm,
	move w sim.GameWorld,
	move timings Timings,
	seed i64
) Fight ? str:
	speeds = try plugin.combatSpeedsOf()
	for a in w.actors.values():
		if a.crimeFaction != 0 and w.crimeValues.get(a.crimeFaction) == none:
			if plugin.crimeValuesOf(a.crimeFaction) is v: w.crimeValues[a.crimeFaction] = v
	ties = plugin.tiesOf(w)
	f = newFight(w, timings, speeds, ties, seed)
	f.floor = f.w.cellBox()
	for refId in f.w.actors.keys().sorted():
		a = f.w.actors[refId].copy()
		if a.dead: continue
		name = plugin.nameOf(f.w, refId)
		style = plugin.combatStyleOf(a.combatStyle)
		settings = f.w.settings.copy()
		fighter = f.w.fighterOf(settings, refId, name, style, plugin.raceCombatOf(a.race))
		f.fighters.push(fighter)
	f

# the fighter named by its editor id (any case), none when there is none
pub fn fighterNamed(f Fight, name str) i64?:
	for k, x in f.fighters:
		if x.name.lower() == name.lower(): return k
	none
