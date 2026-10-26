# Prints the sky's records: a weather's fields, a climate's, a region's weathers, and the sky at an
# hour. Run from the repository root:
#
#   zap run projects/skyrim/weatherInfo.zap --weathers          every weather
#   zap run projects/skyrim/weatherInfo.zap --fields 0x81A      a record's fields (tag, size)
#   zap run projects/skyrim/weatherInfo.zap --weather 0x81A      a weather's colors, fog, clouds
#   zap run projects/skyrim/weatherInfo.zap --climate 0x3C       a world's climate and its weathers
#   zap run projects/skyrim/weatherInfo.zap --region WeatherPineForest    a region's weathers
#   zap run projects/skyrim/weatherInfo.zap --sky 0x81A --hour 12   the sky's colors at an hour
#   zap run projects/skyrim/weatherInfo.zap --install D:/Data ...  another install

import skyrim
import skyrim.esm
import world

tamriel = 0x3C

fn rgb(c esm.Color):
	"{c.r} {c.g} {c.b}"

fn rgbList(cs esm.Color[]):
	cs.map(.rgb()).join(" | ")

fn formList(xs i64[]):
	xs.map("{it:08X}").join(" ")

fn numbers(xs f32[]):
	xs.map("{it}").join(" ")

fn showColors(w esm.Weather):
	for k in 0..esm.colorKinds.len:
		cells = (0..esm.timesOfDay).map(w.colors[k * esm.timesOfDay + it])
		print("  {esm.colorKinds[k]:<16} {rgbList(cells)}")

fn showWeather(mut plugin esm.Esm, form i64):
	w = plugin.weatherOf(form) ?? fail("no weather {form:08X}")
	print("{w.editorId} {form:08X}: wind {w.windSpeed}, transition {w.transDelta}, flags {w.flags}, sun glare {w.sunGlare}, sun damage {w.sunDamage}")
	print("  precipitation {w.precipitationBegin} to {w.precipitationEnd} ({w.precipitation:08X}); thunder {w.thunderBegin} {w.thunderEnd} every {w.thunderFrequency}")
	if plugin.precipitationOf(w.precipitation) is p:
		print("  {p.editorId}: gravity {p.gravity}, size {p.sizeX} x {p.sizeY}, cells {p.columns} x {p.rows}, snow {p.snow}, box {p.boxSize}, density {p.density}, spin {p.rotationVelocity}, range {p.rotationRange}, {p.texture}")
	f = w.fog
	print("  fog day {f.dayNear} {f.dayFar} night {f.nightNear} {f.nightFar} power {f.dayPower} {f.nightPower} max {f.dayMax} {f.nightMax}")
	w.showColors()
	print("  image spaces {formList(w.imageSpaces)}")
	for k, l in w.layers:
		print("  cloud {k}: {l.texture} speed {l.speedX} {l.speedY} alpha {numbers(l.alpha)} enabled {l.enabled}")
	for t in 0..esm.timesOfDay:
		face = (0..6).map(w.ambient[t * 6 + it])
		print("  ambient cube {t}: {rgbList(face)} specular {w.ambientSpecular[t].rgb()} fresnel {w.ambientFresnel[t]}")

fn showClimate(mut plugin esm.Esm, world i64):
	id = plugin.worldClimate(world) ?? fail("no climate for world {world:08X}")
	c = plugin.climateOf(id) ?? fail("no climate {id:08X}")
	print("climate {id:08X}: sunrise {c.sunriseBegin} to {c.sunriseEnd}, sunset {c.sunsetBegin} to {c.sunsetEnd}, volatility {c.volatility}, moon phase {c.phaseLength} days, masser {c.masser}, secunda {c.secunda}")
	print("  sun {c.sunTexture}, glare {c.glareTexture}")
	for w in c.weathers:
		print("  weather {w.weather:08X} chance {w.chance} global {w.global:08X}")

fn showRegion(mut plugin esm.Esm, name str):
	form = plugin.formByEditorId("REGN", name) ?? fail("no region {name}")
	r = plugin.regionOf(form) ?? fail("not a region")
	print("region {form:08X} in world {r.world:08X}")
	for w in r.weathers:
		print("  weather {w.weather:08X} chance {w.chance}")

fn showFields(mut plugin esm.Esm, form i64):
	r = plugin.recordOf(form) ?? fail("no record {form:08X}")
	print("{r.kind} {form:08X}")
	for f in r.fields:
		print("  {f.tag} {f.size}")

fn showSky(mut plugin esm.Esm, form i64, hour f32):
	w = plugin.weatherOf(form) ?? fail("no weather {form:08X}")
	climateId = plugin.worldClimate(tamriel) ?? fail("no climate")
	c = plugin.climateOf(climateId) ?? fail("no climate")
	sky = w.skyAt(none, c, world.SkyTime(hour, share = 1.0, extension = 0.5))
	for k in 0..esm.colorKinds.len:
		print("  {esm.colorKinds[k]:<16} {sky.colors[k] * 255.0}")
	print("  fog {sky.fogNear} {sky.fogFar} power {sky.fogPower} max {sky.fogMax}")
	print("  sun toward {sky.sunToward}, in the sky {sky.sunPlace}, daylight {sky.daylight}, glare {sky.glare}, stars {sky.starsAlpha}")

fn listWeathers(mut plugin esm.Esm):
	for form in plugin.formsOfKind("WTHR"):
		w = plugin.weatherOf(form) ?? continue
		print("{form:08X} {w.editorId} flags {w.flags} transition {w.transDelta} layers {w.layers.len}")

fn listRegions(mut plugin esm.Esm):
	for form in plugin.formsOfKind("REGN"):
		r = plugin.recordOf(form) ?? continue
		id = esm.textOf(r.body, r.fields, "EDID")
		tags = r.fields.map(.tag).join(" ")
		print("{form:08X} {id} {tags}")

fn showAt(mut plugin esm.Esm, text str):
	parts = text.split(",").map(f32.parse(it) ?? fail("--at is x,y in game units"))
	for form in plugin.weatherRegionsAt(tamriel, parts[0], parts[1]):
		r = plugin.regionOf(form) ?? continue
		rec = plugin.recordOf(form) ?? continue
		id = esm.textOf(rec.body, rec.fields, "EDID")
		print("{form:08X} {id} priority {r.priority}")
		for w in r.weathers:
			print("  weather {w.weather:08X} chance {w.chance}")

args.options(
	[
		skyrim.installOption,
		ArgOption("--at", true, "the weather regions holding a game position x,y"),
		ArgOption("--regions", false, "every region"),
		ArgOption("--weathers", false, "every weather"),
		ArgOption("--fields", true, "a record's fields"),
		ArgOption("--weather", true, "a weather's data"),
		ArgOption("--climate", true, "a world's climate"),
		ArgOption("--region", true, "a region's weathers, by editor id"),
		ArgOption("--sky", true, "the sky of a weather at --hour"),
		ArgOption("--hour", true, "the game hour (12)")
	]
)
dir = skyrim.installDir()
mut plugin = esm.openEsm(esm.pluginPath(dir, "Skyrim.esm")) ?? fail("cannot open Skyrim.esm")
if args.option("--at") is v: plugin.showAt(v)
if args.hasFlag("--regions"): plugin.listRegions()
if args.hasFlag("--weathers"): plugin.listWeathers()
if args.option("--fields") is v: plugin.showFields(i64.parse(v) ?? fail("not a form id"))
if args.option("--weather") is v: plugin.showWeather(i64.parse(v) ?? fail("not a form id"))
if args.option("--climate") is v: plugin.showClimate(i64.parse(v) ?? fail("not a form id"))
if args.option("--region") is v: plugin.showRegion(v)
if args.option("--sky") is v:
	showSky(
		plugin,
		i64.parse(v) ?? fail("not a form id"),
		f32.parse(args.option("--hour") ?? "") ?? 12.0
	)
