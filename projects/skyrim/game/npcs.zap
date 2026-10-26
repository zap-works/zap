# The inn's people: the actors its cell places (its ACHR refs) and those whose packages bring them
# there (a package whose location or target is the cell, a ref in it or the location its actors
# are in), with what they wear and do.

import skyrim
import skyrim.esm
import skyrim.hkx
import skyrim.actor
import game.sim
import world

# the day of the week the AI reads at a new game, as npcInfo's: no package of the inn's actors
# depends on it
pub newGameDay = 0

# where a placed actor (ACHR) stands (Z up) and the way it faces (DATA's position and angles)
pub fn placeOf(achr esm.Record) (Vec3, f32):
	at = esm.dataOf(achr.fields, "DATA") ?? return (Vec3(0, 0, 0), 0.0)
	b = achr.body
	(Vec3(b.f32le(at), b.f32le(at + 4), b.f32le(at + 8)), b.f32le(at + 20))

# the place a package names in the cell: its centre and whether it is in the cell (a ref of the
# cell, the cell itself, the ref the actor is linked to, or the actor's own place: its editor
# location, its current one, itself)
fn placeIn(cell esm.Cell, p actor.Package, start Vec3, achr esm.Record?):
	placed = achr != none
	place = p.location ?? return (start, placed)
	match place.kind:
		0:
			r = cell.refs.find(.formId == place.form) ?? return (start, false)
			(r.position, true)
		1: (start, place.form == cell.formId)
		2, 3, 12: (start, placed)
		6:
			if achr is r and r.linkedRef(place.form) is linked and
				cell.refs.find(.formId == linked) is marker:
				return (marker.position, true)
			(start, false)
		_: (start, false)

fn inputOn(p actor.Package, name str):
	(p.inputs.get(name) ?? 0.0) != 0.0

# a package as the AI runs it, its conditions read as a new game has them
fn planOf(
	mut plugin esm.Esm,
	p actor.Package,
	cell esm.Cell,
	a sim.CellActor,
	start Vec3
):
	centre, inCell = cell.placeIn(p, start, a.achr)
	world.PlanHead(
		editorId = p.editorId.copy(),
		template = p.template.copy(),
		schedule = p.schedule,
		holds = not p.isPlacedByAlias() and (plugin.newGameHolds(p.conditions, a.location) ?? false),
		inCell,
		center = centre,
		radius = f32((p.location?.radius) ?? 0),
		sitting = p.inputOn("allow sitting"),
		sleeping = p.inputOn("allow sleeping"),
		eating = p.inputOn("allow eating"),
		idleMarkers = p.inputOn("allow idle markers"),
		special = p.inputOn("allow special furniture"),
		wandering = p.inputOn("allow wandering"),
		energy = p.inputs.get("energy") ?? 50.0
	)

# the race's height for the sex (DATA: after the skill boosts, the male's then the female's)
fn raceHeight(mut plugin esm.Esm, race i64, female bool) f32:
	r = plugin.recordOf(race) ?? return 1.0
	at = esm.dataOf(r.fields, "DATA") ?? return 1.0
	r.body.f32le(at + (20 if female else 16))

# the actor prepared: its body worn and toned, where it starts, its packages
fn prepareNpc(
	install skyrim.Install,
	mut plugin esm.Esm,
	names skyrim.Strings,
	cell esm.Cell,
	a sim.CellActor,
	skeletons hkx.Skeleton[],
	mut table TextureTable,
	mut body u8[]
) world.NpcHead ? str:
	npc = try plugin.npcOf(a.npc)
	look = install.npcLook(plugin, names, npc)
	worn = try install.npcBodyParts(plugin, npc)
	tones = Tones(skin = npc.skinTone ?? neutralTone, hair = plugin.hairColorOf(npc),
		faceTint = look.faceTint.copy())
	scale = npc.height * plugin.raceHeight(npc.race, npc.female)
	skeleton = 1 if npc.female else 0
	faces = install.faceShapes(try plugin.npcHeadParts(npc), worn)
	start = Vec3(0, 0, 0)
	heading = 0.0
	if a.achr is r: start, heading = r.placeOf()
	world.NpcHead(
		formId = a.npc,
		refId = (a.achr?.formId) ?? 0,
		editorId = npc.editorId.copy(),
		name = look.name.copy(),
		female = npc.female,
		look = install.prepareBody(worn, skeletons, skeleton, scale, tones, faces, npc.editorId,
			table, body),
		start,
		heading,
		plans = plugin.packagesOf(npc).map(plugin.planOf(it, cell, a, start))
	)

# The actors of the cell prepared, its textures laid in the table; one that cannot be is left out
# with a line saying why.
pub fn prepareNpcs(
	install skyrim.Install,
	mut plugin esm.Esm,
	cell esm.Cell,
	skeletons hkx.Skeleton[],
	mut table TextureTable,
	mut body u8[]
) world.NpcHead[]:
	names = install.readNames(plugin.pluginName()) ?? fail
	out = []
	for a in plugin.cellActors(cell.editorId) ?? []:
		match install.prepareNpc(plugin, names, cell, a, skeletons, table, body):
			n: out.push(n)
			error: eprint("actor {a.npc:08X} left out: {error}")
	out
