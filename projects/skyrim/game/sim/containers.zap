# What a new game puts in an inventory: a container's (CONT) or an actor's (NPC_) CNTO entries,
# each an item or a leveled list (LVLI) and a count, the lists read at level 1 by the world's dice
# (the plain dice reads a new game as the first roll would fall: esm/leveled.zap says where the
# game rolls); an actor's outfit (OTFT) put on; the player's own record (0x7) with the prisoner's
# outfit the intro dresses it in. CONT's DATA: flags (2: its contents come back when the cell
# resets) and weight.

import skyrim
import skyrim.esm
import skyrim.actor

flagRespawns = 0x2

# the player's base (NPC_ 0x7), and the outfit a new game dresses it in: the intro's prisoner
# clothes (a tunic and footwraps), in place of the record's DOFT, an iron armor set the intro
# takes away
pub playerBase = 0x7
pub startOutfit = "PrisonerOutfit"

# whether the container's contents come back when its cell resets
pub fn respawns(r esm.Record) bool:
	at = esm.dataOf(r.fields, "DATA") ?? return false
	(r.body[at] & flagRespawns) != 0

# the items a record's CNTO entries give at a new game, leveled lists read with the dice
pub fn startingContents(mut plugin esm.Esm, r esm.Record, mut dice esm.Dice) esm.Counted[]:
	out = []
	for f in r.fields.filter(.tag == "CNTO" and .size >= 8):
		out.extend(
			plugin.leveledCounts(
				r.body.u32le(f.at),
				r.body.i32le(f.at + 4),
				actor.newGameLevel,
				dice
			)
		)
	out

# an inventory of the counted items, each known to the world (learned from the plugin)
pub fn fillInventory(
	mut w GameWorld,
	mut plugin esm.Esm,
	names skyrim.Strings,
	refId i64,
	given esm.Counted[]
):
	w.ensureInventory(refId)
	for c in given:
		w.learnItem(plugin, names, c.form)
		w.inventories[refId].addItem(c.form, c.count)

# learns the item's data (and, for a potion, its magic effects) from the plugin when the world does
# not have it yet; whether it is an item
pub fn learnItem(mut w GameWorld, mut plugin esm.Esm, names skyrim.Strings, form i64) bool:
	if w.items.get(form) != none: return true
	item = plugin.itemOf(names, form) ?? return false
	gives = (item.plantHarvest() ?? Harvest(gives = [], seasons = [])).gives.map(.form)
	if item.kind.Potion is potion:
		for e in potion.effects:
			w.learnMagicEffect(plugin, names, e.effect)
	w.items[form] = item
	for g in gives:
		w.learnItem(plugin, names, g)
	true

# puts the outfit's armors into the actor's inventory and on it
pub fn dress(mut w GameWorld, mut plugin esm.Esm, names skyrim.Strings, refId i64, outfit i64):
	armors = plugin.outfitArmors(outfit)
	w.fillInventory(plugin, names, refId, armors.map(esm.Counted(form = it, count = 1)))
	for form in armors:
		if w.inventories[refId].equip(w.items, form, false) is error:
			w.record("{refId:08X} cannot wear {form:08X}: {error}")

# The actor placed as refId, of the base npc: its values, its record's inventory and its outfit
# worn (the record whose inventory its templates give); the actor is skipped with a line in the
# world's events when the plugin cannot build it.
pub fn addActor(
	mut w GameWorld,
	mut plugin esm.Esm,
	names skyrim.Strings,
	refId i64,
	npc i64,
	outfit i64
):
	match plugin.actorStateOf(w.settings, npc):
		a: w.actors[refId] = a
		error:
			w.record("actor {refId:08X}: {error}")
			return
	w.actors[refId].vendor = plugin.vendorOf(w.actors[refId].factions)
	w.learnMagic(plugin, names, refId, npc)
	r = plugin.recordOf(npc) ?? return
	source = plugin.sourceFor(r, actor.useInventory) ?? r.copy()
	w.fillInventory(plugin, names, refId, plugin.startingContents(source, w.dice))
	w.dress(plugin, names, refId, outfit)
