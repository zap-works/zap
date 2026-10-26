# Prints the land of an exterior cell as the plugins hold it: its heights, texture layers and
# colors; or finds the cells of a location. Run from the repository root:
#
#   zap run projects/skyrim/terrainInfo.zap --cell 5,-2          the land of Tamriel's cell (x, y)
#   zap run projects/skyrim/terrainInfo.zap --ground 23259,-44476   the heights around a game position
#   zap run projects/skyrim/terrainInfo.zap --find Riverwood     the cells whose location is named
#                                                               so, scanning x -20..40, y -40..20
#   zap run projects/skyrim/terrainInfo.zap --water 5,-11        the cell's water: height, type, shader values
#   zap run projects/skyrim/terrainInfo.zap --survey 3,-13,7,-9  which of the cells have water
#   zap run projects/skyrim/terrainInfo.zap --plants 5,-11       the grass the game plants in the cell, by kind
#   zap run projects/skyrim/terrainInfo.zap --grass 0x1035be     one GRAS: model, density, slopes, ranges
#   zap run projects/skyrim/terrainInfo.zap --record 0x1001232   any record's fields
#   zap run projects/skyrim/terrainInfo.zap --world 0x3C ...     another world (default Tamriel)
#   zap run projects/skyrim/terrainInfo.zap --install D:/Data ...  another install

import skyrim
import skyrim.esm
import game

tamriel = 0x3C

fn textureLine(mut plugin esm.Esm, form i64):
	if form == 0: return "none"
	t = plugin.landTexture(form) ?? return "{form:08X} (no LTEX)"
	"{form:08X} {t.editorId}: {t.diffuse}, {t.normal}, grass {t.grass.len}"

fn printLand(mut plugin esm.Esm, l esm.Land):
	lo = l.heights.min()
	hi = l.heights.max()
	print("land {l.formId:08X} of cell ({l.x}, {l.y}): flags {l.flags}, heights {lo} to {hi}, corners SW {l.heights[0]} SE {l.heights[32]} NW {l.heights[32 * 33]} NE {l.heights[33 * 33 - 1]}")
	print("center height {l.heights[16 * 33 + 16]}, center normal {l.normals[16 * 33 + 16]}, center color {l.colors[16 * 33 + 16]}")
	for q in 0..4:
		print("quadrant {q} base {plugin.textureLine(l.base[q])}")
		for layer in l.layers.filter(.quadrant == q):
			covered = layer.opacity.filter(it > 0.0).len
			print("  layer {layer.order} {plugin.textureLine(layer.texture)}: {covered} vertices, up to {layer.opacity.max()}")

fn findLocation(mut plugin esm.Esm, world i64, name str):
	want = name.lower()
	for y in -40..20:
		for x in -20..40:
			c = plugin.exteriorCell(world, x, y) ?? continue
			r = plugin.recordOf(c.location) ?? continue
			id = esm.textOf(r.body, r.fields, "EDID")
			if (id.lower().indexOf(want) ?? -1) >= 0:
				print("({x}, {y}) {c.editorId} {c.formId:08X} {id}")

fn dumpRecord(r esm.Record):
	print("{r.kind} {r.formId:08X} flags {r.flags:X}")
	for f in r.fields:
		note = ""
		if f.size <= 4 and f.size > 0: note = " = {r.body.u32le(f.at)} / {r.body.f32le(f.at)}"
		text = r.body.cStringAt(f.at)
		if f.size > 4 and text.len > 3 and text.len == f.size - 1: note = " \"{text}\""
		print("  {f.tag} {f.size}{note}")

fn showType(w esm.WaterType):
	print("water type {w.formId:08X} {w.editorId}: flags {w.flags} alpha {w.alpha}")
	print("  normals {w.normals}")
	print("  colors shallow {w.shallow} deep {w.deep} reflection {w.reflection}")
	print("  sun specular power {w.sunSpecularPower}, reflection {w.reflectionAmount}, fresnel {w.fresnelAmount}")
	print("  fog above {w.aboveFogNear} to {w.aboveFogFar} x {w.aboveFogAmount}, below {w.underwaterFogNear} to {w.underwaterFogFar} x {w.underwaterFogAmount}")
	print("  refraction {w.refractionMagnitude}, specular {w.specularPower} radius {w.specularRadius} brightness {w.specularBrightness}")
	print("  noise falloff {w.noiseFalloff}, wind {w.windDirection} at {w.windSpeed}, scales {w.uvScale}, amplitudes {w.amplitude}")
	print("  magnitudes reflection {w.reflectionMagnitude} sparkle {w.sunSparkleMagnitude} sun {w.sunSpecularMagnitude}, sparkle power {w.sunSparklePower}")
	print("  depth factors {w.depthReflections} {w.depthRefraction} {w.depthNormals} {w.depthSpecular}, flow scale {w.flowmapScale}")

fn showGrass(g esm.Grass):
	print("grass {g.formId:08X} {g.editorId}: {g.model}")
	print("  density {g.density} %, slope {g.minSlope} to {g.maxSlope} degrees, water state {g.waterState} at {g.waterDistance}")
	print("  position range {g.positionRange}, height range {g.heightRange}, color range {g.colorRange}, wave period {g.wavePeriod}, flags {g.flags}")

fn cellOf(text str):
	parts = text.split(",")
	(i64.parse(parts[0]) ?? fail("a cell is x,y"), i64.parse(parts[1]) ?? fail("a cell is x,y"))

fn printWater(mut plugin esm.Esm, world i64, x i64, y i64):
	match plugin.cellWaterAt(world, x, y):
		w:
			print("({x}, {y}): water at {w.height}")
			showType(plugin.waterTypeOf(w.waterType) ?? fail("no water type {w.waterType:X}"))
		none: print("({x}, {y}): no water")

fn printPlants(mut plugin esm.Esm, world i64, x i64, y i64):
	lands = plugin.landsAround(world, x, y)
	found {i64: game.Plant[]} = {}
	plugin.plantsOfCell(world, x, y, lands, game.cosineTable(), found)
	for form in found.keys().sorted():
		g = plugin.grassOf(form) ?? continue
		plants = found.get(form) ?? []
		print("{g.editorId} ({g.model}): {plants.len} plants")

dir = skyrim.declareWithInstall(
	[
		ArgOption("--water", true, "a cell x,y: its water and the type's shader values"),
		ArgOption("--survey", true, "a range of cells x0,y0,x1,y1: which have water"),
		ArgOption("--plants", true, "a cell x,y: the grass planted there, by kind"),
		ArgOption("--grass", true, "a GRAS record's form id"),
		ArgOption("--record", true, "a record's form id: its fields"),
		ArgOption("--cell", true, "the cell's x,y"),
		ArgOption("--ground", true, "x,y of a game position: the heights around it"),
		ArgOption("--find", true, "a part of a location's editor id"),
		ArgOption("--world", true, "the world's form id (Tamriel)")
	]
)
world = i64.parse(args.option("--world") ?? "0x3C") ?? tamriel
plugin = esm.openEsm(esm.pluginPath(dir, "Skyrim.esm")) ?? fail
if args.option("--find") is name: plugin.findLocation(world, name)
if args.option("--record") is text:
	dumpRecord(plugin.recordOf(i64.parse(text) ?? fail("a form id")) ?? fail("no such record"))
if args.option("--grass") is text:
	showGrass(plugin.grassOf(i64.parse(text) ?? fail("a form id")) ?? fail("no such GRAS"))
if args.option("--water") is text:
	x, y = cellOf(text)
	plugin.printWater(world, x, y)
if args.option("--plants") is text:
	x, y = cellOf(text)
	plugin.printPlants(world, x, y)
if args.option("--survey") is text:
	r = text.split(",").map(i64.parse(it) ?? fail("a range is x0,y0,x1,y1"))
	for y in r[1]..=r[3]:
		for x in r[0]..=r[2]:
			if plugin.cellWaterAt(world, x, y) is w:
				print("({x}, {y}): water at {w.height}, type {w.waterType:X}")
if args.option("--cell") is xy:
	parts = xy.split(",")
	x = i64.parse(parts[0]) ?? fail("a cell is x,y")
	y = i64.parse(parts[1]) ?? fail("a cell is x,y")
	l = plugin.landOf(world, x, y) ?? fail("no land at ({x}, {y})")
	plugin.printLand(l)
if args.option("--ground") is xy:
	parts = xy.split(",")
	px = f32.parse(parts[0]) ?? fail("a position is x,y")
	py = f32.parse(parts[1]) ?? fail("a position is x,y")
	cx, cy = Vec3(px, py, 0.0).gridOf()
	l = plugin.landOf(world, cx, cy) ?? fail("no land under ({px}, {py})")
	col = i64((px - f32(cx) * esm.cellSize) / esm.vertexStep)
	row = i64((py - f32(cy) * esm.cellSize) / esm.vertexStep)
	print("cell ({cx}, {cy}), vertex column {col}, row {row}; heights from row {row + 3} down to {row - 3}, columns {col - 3}..{col + 3}")
	for r in 0..7:
		rr = row + 3 - r
		line = []
		for c in 0..7:
			cc = col - 3 + c
			line.push(
				"{l.heights[rr * 33 + cc]:.0}" if rr >= 0 and rr < 33 and cc >= 0 and cc < 33
				else "-"
			)
		print(line.join(" "))
