# The art of the player's spells prepared with the cell: for each spell the player casts at a new
# game (its record's and its race's), each effect's casting art (an ARTO's model, what shows on the
# hand) and projectile (a PROJ's model, what flies), their parts as lists of triangles in the
# model's own space, which the scene draws where the game puts them as time goes (world/scene.zap),
# and the light the effect gives the hand (MGEF's light). Only what the engine draws of an effect
# model is kept: its meshes under an effect shader or lit; a billboard and the particle systems
# (whose birth rates are the controller sequences' blends, which the loader does not play) are not.

import skyrim
import skyrim.esm
import game.sim
import world
import world.shaders

# the spells the actors of a new game cast by hand: those of the player's record and of its race
fn playerSpellForms(mut plugin esm.Esm):
	r = plugin.recordOf(sim.playerBase) ?? return []
	out i64[] = []
	for id in [sim.playerBase, r.formOf("RNAM") ?? 0]:
		if plugin.recordOf(id) is rec:
			for form in esm.formsOf(rec.body, rec.fields, "SPLO"):
				if form not in out: out.push(form)
	out

# the parts the model adds to the build, taken back out of it again: the build is as it was
fn partsOf(mut build CellBuild, m ModelParts):
	low = build.low
	high = build.high
	emitters = build.emitters.len
	billboards = build.billboards.len
	build.placeModel(m, Mat4(1.0))
	out = []
	for state, list in build.byState:
		if list.isEmpty: continue
		triangles = []
		for k in 0..list.len / 3:
			corners = (0..3).map(build.vertices[list[k * 3 + it]].copy())
			if corners.any(.billboard >= 0): continue
			triangles.extend(corners)
		if not triangles.isEmpty:
			out.push(world.SpellPart(kind = kinds[state / 2], vertices = triangles))
	build.vertices = []
	for k in 0..build.byState.len:
		build.byState[k] = []
	build.parts = 0
	build.emitters = build.emitters[..emitters].copy()
	build.billboards = build.billboards[..billboards].copy()
	build.low = low
	build.high = high
	out

# the model of the record (an ARTO's or a PROJ's) as art, none when the record has no model
fn artOf(
	install skyrim.Install,
	mut plugin esm.Esm,
	form i64,
	light shaders.PointLight?,
	mut models {str: ModelParts},
	mut build CellBuild,
	mut table TextureTable,
	mut body u8[]
) world.SpellArt?:
	r = try plugin.recordOf(form)
	path = esm.textOf(r.body, r.fields, "MODL")
	if path.isEmpty: return none
	key = install.loadModel(path, models, build, table, body)
	parts = build.partsOf(models[key])
	if parts.isEmpty and light == none: return none
	world.SpellArt(form, parts, light)

# The art of the spells the player casts at a new game, none when the plugin gives no spell.
pub fn prepareSpellArt(
	install skyrim.Install,
	mut plugin esm.Esm,
	mut models {str: ModelParts},
	mut build CellBuild,
	mut table TextureTable,
	mut body u8[]
) world.SpellArt[]:
	names = install.readNames("Skyrim.esm") ?? return []
	w = sim.newWorld()
	for form in plugin.playerSpellForms():
		w.learnSpell(plugin, names, form)
	out world.SpellArt[] = []
	for m in w.magicEffects.values():
		light shaders.PointLight? = none
		if plugin.baseRecord(m.light) is b:
			if b.light is l: light = l.lightAt(Vec3(0.0, 0.0, 0.0), 0.0, 0.0, 1.0)
		for form in [m.castingArt, m.projectile]:
			if form == 0 or out.any(.form == form): continue
			if install.artOf(plugin, form, light if form == m.castingArt else none, models, build,
				table, body) is art:
				out.push(art)
	out
