# The actors of an interior cell: those it places (its ACHR refs) and those whose packages bring
# them there (a package whose location or target is the cell, a ref in it or the location its
# actors are in).

import skyrim.esm
import skyrim.actor

# an actor of the cell: placed in it, or brought by its packages
pub type CellActor:
	npc i64
	achr esm.Record?   # the placed actor, none for a visitor
	location i64   # the ACHR's XLCN, 0 for a visitor
	visits str[]   # the editor ids of a visitor's packages that bring it

# the forms an actor's package can name to send it to the cell: the cell, its refs, its location
fn cellForms(cell esm.Cell, placed esm.Record[]):
	forms {i64: bool} = {}
	forms[cell.formId] = true
	for r in cell.refs:
		forms[r.formId] = true
	for r in placed:
		forms[r.formId] = true
		if r.formOf("XLCN") is l: forms[l] = true
	forms

# the packages of the plugin that send an actor into the cell, by form id
pub fn packagesInto(mut plugin esm.Esm, forms {i64: bool}) {i64: str}:
	out {i64: str} = {}
	for id in plugin.formsOfKind("PACK"):
		r = plugin.recordOf(id) ?? continue
		for f in r.fields:
			if (f.tag == "PLDT" or f.tag == "PTDA") and f.size >= 8 and
				i64(r.body.u32le(f.at + 4)) in forms:
				out[id] = esm.textOf(r.body, r.fields, "EDID")
	out

# the race of the actor is one of people (ActorTypeNPC): the town's creatures are not in the cast
fn isPerson(mut plugin esm.Esm, npc i64):
	n = plugin.npcOf(npc) ?? return false
	race = plugin.recordOf(n.race) ?? return false
	actorTypeNpc in esm.formsOf(race.body, race.fields, "KWDA")

actorTypeNpc = 0x1_3794

# whether a placed actor is in the cell's cast: an interior's all, an exterior's people that a
# script does not place (initially disabled ones come with their quests)
fn isInCast(mut plugin esm.Esm, cell esm.Cell, achr esm.Record):
	if not cell.exterior: return true
	(achr.flags & 0x800) == 0 and plugin.isPerson(achr.achrBase())

# The actors of the interior cell with this editor id, or of the exterior area with this id (its
# people only): those it places, then every actor of the plugin with a package that sends it
# there, in form id order; none when there is no such cell.
pub fn cellActors(mut plugin esm.Esm, editorId str) CellActor[]?:
	cell = try plugin.findCell(editorId)
	placed = (plugin.cellRecords(editorId) ?? [])
		.filter(.kind == "ACHR" and plugin.isInCast(cell, it))
		.map(.copy())
	out = []
	for r in placed:
		out.push(
			CellActor(
				npc = r.achrBase(),
				achr = r.copy(),
				location = r.formOf("XLCN") ?? 0,
				visits = []
			)
		)
	into = plugin.packagesInto(cell.cellForms(placed))
	for id in plugin.formsOfKind("NPC_"):
		if out.any(.npc == id) or (cell.exterior and not plugin.isPerson(id)): continue
		r = plugin.recordOf(id) ?? continue
		visits = esm
			.formsOf(r.body, r.fields, "PKID")
			.filter(it in into)
			.map((into.get(it) ?? "").copy())
		if not visits.isEmpty: out.push(CellActor(npc = id, achr = none, location = 0, visits))
	out
