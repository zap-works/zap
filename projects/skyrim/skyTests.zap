# The exterior sky from SkyrimClear and SkyrimClimate, read from Skyrim.esm (skipped quietly
# without the game's files): the colors at given hours against the executable's blend, the fog,
# the sun's path, the clouds, and how one weather gives way to the next.

import fs
import skyrim.esm
import game
import math
import world

tamriel = 0x3C
skyrimClear = 0x81A

# the weathers' and the climate's records
fn records() (esm.Weather, esm.Climate)?:
	if not fs.exists(esm.defaultEsm()):
		eprint("skipped: no {esm.defaultEsm()}")
		return none
	plugin = esm.openEsm(esm.defaultEsm()) ?? fail
	clear = plugin.weatherOf(skyrimClear) ?? fail("no SkyrimClear")
	climate = plugin.climateOf(plugin.worldClimate(tamriel) ?? fail("no climate")) ??
		fail("no climate")
	(clear, climate)

fn skyAt(w esm.Weather, c esm.Climate, hour f32):
	world.skyAt(w, none, c, world.SkyTime(hour, share = 1.0, extension = 0.5))

fn rgb(c esm.Color):
	Vec3(f32(c.r), f32(c.g), f32(c.b)) / 255.0

fn near(a Vec3, b Vec3):
	(a - b).length() < 0.0001

test "the climate and the weather read as the plugin holds them":
	clear, c = records() ?? return
	expect c.sunriseBegin == 5.5 and c.sunriseEnd == 10.0 and c.sunsetBegin == 16.0 and
		c.sunsetEnd == 20.5
	expect c.volatility == 50 and c.sunTexture == "Sky\\Sun.dds" and
		c.glareTexture == "Sky\\SunGlare.dds"
	expect c.colorHours(0.5) == Vec4(5.0, 10.0, 16.0, 21.0)
	expect clear.editorId == "SkyrimClear" and clear.transDelta == 125 and clear.sunGlare == 191
	expect clear.layers.len == 12 and clear.layers[0].texture == "Sky\\SkyrimCloudsUpper04.dds"
	expect clear.fog.dayFar == 80000.0 and clear.fog.nightFar == 40000.0 and
		clear.fog.dayMax == 0.85

test "the sky's colors at each time of day are the weather's, and between them the executable's blend":
	clear, c = records() ?? return
	day = skyAt(clear, c, 12.0)
	night = skyAt(clear, c, 2.0)
	for k in 0..esm.colorKinds.len:
		expect day.colors[k].near(clear.colors[k * 4 + 1].rgb())
		expect night.colors[k].near(clear.colors[k * 4 + 3].rgb())
	# the sunrise begins at 5.0 (5.5 less the half hour) and ends at 10.0: at its middle, 7.5, it is the
	# sunrise colors whole, a quarter of the way from there to the day, they are 3/4 sunrise and 1/4 day
	mid = skyAt(clear, c, 7.5)
	expect mid.colors[0].near(clear.colors[0].rgb())
	late = skyAt(clear, c, 8.75)
	expect late.colors[0].near(clear.colors[0].rgb() * 0.5 + clear.colors[1].rgb() * 0.5)
	# before the middle the sunrise shades into the night
	early = skyAt(clear, c, 6.25)
	expect early.colors[0].near(clear.colors[0].rgb() * 0.5 + clear.colors[3].rgb() * 0.5)
	# the sunset's middle is 18.5
	dusk = skyAt(clear, c, 18.5)
	expect dusk.colors[4].near(clear.colors[4 * 4 + 2].rgb())

test "the ambient cube and the fog follow the hour":
	clear, c = records() ?? return
	day = skyAt(clear, c, 13.0)
	for u in 0..6:
		expect day.ambient[u].near(clear.ambient[6 + u].rgb())
	expect day.fogFar == 80000.0 and day.fogNear == 0.0 and day.fogPower == 0.4 and
		day.fogMax == 0.85
	night = skyAt(clear, c, 23.0)
	expect night.fogFar == 40000.0 and night.ambient[4].near(clear.ambient[18 + 4].rgb())
	# a quarter into the sunrise ramp (5.0 to 10.0), 1.25 hours: the fog is a quarter day
	dawn = skyAt(clear, c, 6.25)
	expect (dawn.fogFar - (0.75 * 40000.0 + 0.25 * 80000.0)).abs() < 0.01

test "the sun crosses from the east between its windows, high at noon, its light never under 14 degrees":
	_, c = records() ?? return
	# the windows are an hour either side of 7.75 and of 18.25
	expect c.sunTrack(6.75) == 1.0 and (c.sunTrack(19.25) + 1.0).abs() < 0.0001
	expect (c.sunTrack(13.0)).abs() < 0.0001
	expect c.daylightAt(6.0) == 0.0 and c.daylightAt(13.0) == 1.0
	expect (c.daylightAt(7.75) - 0.5).abs() < 0.0001 and
		(c.daylightAt(18.25) - 0.5).abs() < 0.0001
	rise = world.sunDiscToward(c.sunTrack(6.75))
	expect rise.x > 0.99 and rise.z.abs() < 0.0001
	noon = world.sunDiscToward(0.0)
	expect noon.z > 0.99
	for k in 0..21:
		light = world.sunLightToward(-1.0 + f32(k) * 0.1)
		expect light.z >= 100.0 / (Vec3(400.0, 25.0, 100.0)).length() - 0.0001
	# the night carries the track on from the sunset's end to the next sunrise's start
	expect (c.sunTrack(0.0) - c.sunTrack(24.0)).abs() < 0.0001
	expect c.sunTrack(1.0) > c.sunTrack(0.0)

test "the stars are out at night, gone by day, fading across the twilights":
	_, c = records() ?? return
	expect c.starsAlphaAt(2.0) == 1.0 and c.starsAlphaAt(12.0) == 0.0
	# the stars fade out from 5.0 to 7.5 and in from 18.5 to 21.0
	expect (c.starsAlphaAt(6.25) - 0.5).abs() < 0.0001
	expect (c.starsAlphaAt(19.75) - 0.5).abs() < 0.0001

test "a cloud layer scrolls by its byte, 127 standing still":
	expect (world.cloudSpeed(127.0)).abs() < 0.0001
	expect (world.cloudSpeed(254.0) - 0.1).abs() < 0.0001 and
		(world.cloudSpeed(0.0) + 0.1).abs() < 0.0001
	clear, c = records() ?? return
	sky = skyAt(clear, c, 12.0)
	expect sky.clouds.len == clear.layers.len
	expect (sky.clouds[0].alpha - clear.layers[0].alpha[1]).abs() < 0.0001
	expect sky.clouds[11].color.near(clear.layers[11].colors[1].rgb())
	expect (sky.clouds[0].scroll.x - world.cloudSpeed(clear.layers[0].speedX)).abs() < 0.00001

test "a transition mixes two weathers by its share, the colors adding up":
	clear, c = records() ?? return
	plugin = esm.openEsm(esm.defaultEsm()) ?? fail
	overcast = plugin.weatherOf(
		plugin.formByEditorId("WTHR", "SkyrimOvercastRain") ?? fail("no SkyrimOvercastRain")
	) ?? fail("not a weather")
	half = world.skyAt(
		overcast,
		clear.copy(),
		c,
		world.SkyTime(hour = 12.0, share = 0.25, extension = 0.5)
	)
	for k in 0..esm.colorKinds.len:
		want = overcast.colors[k * 4 + 1].rgb() * 0.25 + clear.colors[k * 4 + 1].rgb() * 0.75
		expect half.colors[k].near(want)
	expect (half.fogFar - (0.25 * overcast.fog.dayFar + 0.75 * clear.fog.dayFar)).abs() < 0.01
	expect half.imageWeights.len == 4 and (half.imageWeights.sum() - 1.0).abs() < 0.0001
	# a flash lights the sunlight up to the weather's lightning color, but only while no weather gives way
	storm = plugin.weatherOf(
		plugin.formByEditorId("WTHR", "SkyrimStormRain") ?? fail("no storm")
	) ??
		fail("not a weather")
	flashed = world.skyAt(
		storm,
		none,
		c,
		world.SkyTime(hour = 12.0, share = 1.0, extension = 0.5, flash = 0.5)
	)
	steady = skyAt(storm, c, 12.0)
	top = storm.lightning.rgb()
	expect top.x > 0.0
	expect (flashed.colors[4].x - (steady.colors[4].x + 0.5).clamp(0.0, top.x)).abs() < 0.0001
	expect flashed.colors[9] == steady.colors[9]

test "a weather gives way to the next after its time, over its transition":
	s = world.WeatherState(current = 1, last = 0, changedAt = 10.0)
	entries = [
		esm.RegionWeather(weather = 1, chance = 30, global = 0),
		esm.RegionWeather(weather = 2, chance = 0, global = 0),
		esm.RegionWeather(weather = 3, chance = 70, global = 0)
	]
	chances = entries.map(.chance)
	# the pick lays 30 then 70 end to end
	expect world.pickWeather(entries, chances, 29) == 1 and
		world.pickWeather(entries, chances, 30) == 3
	expect world.pickWeather(entries, chances, 130) == 3 and
		world.pickWeather(entries, [0, 0, 0], 5) == none
	# volatility 50 lasts 1 + 205 * 22 / 255 = 18.69 hours; before that the weather stays
	expect (world.weatherHours(50) - 18.686275).abs() < 0.0001
	still = s.stepWeather(20.0, 50, 125, entries, chances, 99, false, 0.0)
	expect still == s
	# after that the roll picks 3: it comes in with 1 as the last one, its share growing over the
	# transition's hours (125 / 255 * 0.24 + 0.01 = 0.1277)
	moved = s.stepWeather(29.0 - 24.0, 50, 125, entries, chances, 99, false, 0.0)
	expect moved.current == 3 and moved.last == 1 and moved.changedAt == 5.0
	expect (world.transitionHours(125) - 0.127647).abs() < 0.0001
	expect (moved.shareAt(5.0638, 125) - 0.5).abs() < 0.001
	done = moved.stepWeather(5.2, 50, 125, entries, chances, 99, false, 0.0)
	expect done.current == 3 and done.last == 0 and done.shareAt(5.2, 125) == 1.0
	# entering a region that lists the current weather keeps it by the time it has left
	entered = s.stepWeather(11.0, 50, 125, entries, chances, 99, true, 0.5)
	expect entered.current == 1
	switched = s.stepWeather(11.0, 50, 125, entries, chances, 99, true, 0.01)
	expect switched.current == 3 and switched.last == 1

test "Riverwood lies in WeatherPineForest, whose weathers and chances are the plugin's":
	if not fs.exists(esm.defaultEsm()):
		eprint("skipped: no {esm.defaultEsm()}")
		return
	plugin = esm.openEsm(esm.defaultEsm()) ?? fail
	pine = plugin.formByEditorId("REGN", "WeatherPineForest") ?? fail("no region")
	found = plugin.weatherRegionsAt(tamriel, 22528.0, -43008.0)
	expect found.len >= 1 and found[0] == pine
	region = plugin.regionOf(pine) ?? fail("not a region")
	expect region.priority == 52 and region.weathers.len == 7
	chances = plugin.weatherChances(region.weathers)
	expect chances == [35, 35, 10, 5, 5, 5, 5]
	# the clear and the cloudy weathers are the likeliest, a roll of 0 to 34 giving the first
	expect world.pickWeather(region.weathers, chances, 34) == region.weathers[0].weather
	expect world.pickWeather(region.weathers, chances, 35) == region.weathers[1].weather
	expect world.pickWeather(region.weathers, chances, 99) == region.weathers[6].weather
	# far from every region of the world, none gives weather
	expect plugin.weatherRegionsAt(tamriel, 1.0e9, 1.0e9).isEmpty

test "the hour's image space is the weather's by the sky's weights":
	clear, c = records() ?? return
	plugin = esm.openEsm(esm.defaultEsm()) ?? fail
	day = skyAt(clear, c, 13.0)
	expect day.imageSpaces[0] == clear.imageSpaces[1] and day.imageWeights[0] == 1.0
	space = plugin.imageSpaceOf(clear.imageSpaces[1]) ?? fail("no image space")
	mixed = esm.mixedSpaces([space.copy()], [1.0])
	expect mixed.sunlightScale == space.sunlightScale and mixed.white == space.white
	# a half and a half of two spaces is their mean
	night = plugin.imageSpaceOf(clear.imageSpaces[3]) ?? fail("no image space")
	both = esm.mixedSpaces([space.copy(), night.copy()], [0.5, 0.5])
	expect (both.saturation - (space.saturation + night.saturation) * 0.5).abs() < 0.00001

test "a clock at Riverwood starts on one of the region's weathers and brings others as hours pass":
	if not fs.exists(esm.defaultEsm()):
		eprint("skipped: no {esm.defaultEsm()}")
		return
	plugin = esm.openEsm(esm.defaultEsm()) ?? fail
	clock = plugin.openSkyClock(tamriel, 22528.0, -43008.0, 8.0, 7) ?? fail("no clock")
	expect clock.entries.len == 7 and clock.weathers.len == 7
	listed = clock.entries.map(.weather)
	first = clock.state.current
	expect first in listed and clock.state.last == 0
	# a weather lasts 18.7 hours at this volatility: nothing changes before that
	hour f32 = 8.0
	while hour < 26.0:
		hour += 0.25
		clock.advance(hour % 24.0)
	expect clock.state.current == first
	# over the following days the weather changes, each change a transition from the one before
	changes = 0
	seen = first
	loop 800:
		hour += 0.25
		clock.advance(hour % 24.0)
		sky = clock.skyAt(hour % 24.0, 0.0)
		expect sky.fogFar > 0.0 and sky.imageWeights.sum() > 0.999 and
			sky.imageWeights.sum() < 1.001
		if clock.state.current != seen:
			expect clock.state.last == seen and clock.state.current in listed
			seen = clock.state.current
			changes += 1
	expect changes >= 2

test "a moon climbs from its fade end to its fade start, holds, and sets as it rose":
	m = world.masserDefaults()
	expect m.moonAlpha(44.0) == 0.0 and m.moonAlpha(45.0) == 0.0
	expect near(Vec3(m.moonAlpha(50.0), 0.0, 0.0), Vec3(0.5, 0.0, 0.0))
	expect m.moonAlpha(55.0) == 1.0
	expect m.moonAlpha(90.0) == 1.0 and m.moonAlpha(124.0) == 1.0
	expect near(Vec3(m.moonAlpha(130.0), 0.0, 0.0), Vec3(0.5, 0.0, 0.0))
	expect m.moonAlpha(135.0) == 0.0 and m.moonAlpha(200.0) == 0.0
	# the shadow's fade ends half a degree below the moon's end
	expect m.moonShadowAlpha(90.0, 0.3) == 0.3
	expect m.moonShadowAlpha(45.25, 1.0) > 0.4 and m.moonShadowAlpha(44.0, 1.0) == 0.0
test "the moons turn speed times 60 degrees an hour from 90 and the phase changes every phase length":
	m = world.masserDefaults()
	expect m.moonAngleAt(0.0) == 90.0 and m.moonAngleAt(4.0) == 150.0
	expect near(Vec3(m.moonAngleAt(24.0), 0.0, 0.0), Vec3(90.0, 0.0, 0.0))
	expect world.moonAngleAfter(350.0, 23.5, 0.5, 0.25) == 5.0
	expect world.moonPhaseOn(0, 3) == 0 and world.moonPhaseOn(2, 3) == 0 and
		world.moonPhaseOn(3, 3) == 1
	expect world.moonPhaseOn(23, 3) == 7 and world.moonPhaseOn(24, 3) == 0
	expect world.moonTexture("masser", 4) == "Sky\\masser_new.dds"
	# overhead at 90 degrees, the quad's up toward the south, its center at 512 out
	place = world.moonPlaceAt(90.0, 0.0)
	expect place.center.near(Vec3(0.0, 0.0, 512.0)) and place.up.near(Vec3(0.0, -1.0, 0.0))
test "the climate gives both moons and a phase length of three days":
	_, c = records() ?? return
	expect c.masser and c.secunda and c.phaseLength == 3
	moons = c.moonsAt(world.masserDefaults(), world.secundaDefaults(), 4.0, 0, 1.0)
	expect moons.len == 2 and moons[0].texture == "Sky\\masser_full.dds" and moons[0].half == 94.0
	expect moons[1].half == 40.0
test "rain shows once its weather is past the begin byte and the last weather's stops at its end":
	expect world.currentAmount(0.5, 153, 1.0) == 0.0
	expect near(Vec3(world.currentAmount(1.0, 153, 1.0), 0.0, 0.0), Vec3(1.0, 0.0, 0.0))
	expect near(Vec3(world.currentAmount(0.8, 153, 2.0), 0.0, 0.0), Vec3(1.0, 0.0, 0.0))
	expect world.lastAmount(0.0, 103, 1.0) == 1.0 and world.lastAmount(0.5, 103, 1.0) == 0.0
	expect near(
		Vec3(world.lastAmount(0.2, 103, 1.0), 0.0, 0.0),
		Vec3(1.0 - 0.2 / (103.0 / 255.0 + 0.001), 0.0, 0.0)
	)
test "the rain's and the snow's particles are read from their SPGD records":
	if not fs.exists(esm.defaultEsm()):
		eprint("skipped: no {esm.defaultEsm()}")
		return
	plugin = esm.openEsm(esm.defaultEsm()) ?? fail
	rain = plugin.weatherOf(0xC_821F) ?? fail("no SkyrimOvercastRain")
	spec = plugin.precipitationOf(rain.precipitation) ?? fail("no rain particles")
	expect spec.editorId == "RainParticles" and spec.gravity == 675.0 and spec.boxSize == 1300.0 and
		not spec.snow and spec.columns == 4 and spec.rows == 2
	snow = plugin.weatherOf(0x4_D7FB) ?? fail("no SkyrimOvercastSnow")
	flakes = plugin.precipitationOf(snow.precipitation) ?? fail("no snow particles")
	expect flakes.snow and flakes.density == 3.0 and flakes.rotationVelocity == 100.0

test "the sun's cascades split the view as the executable's practical scheme does":
	fractions = world.splitFractions(3, 8000.0)
	expect near(Vec3(fractions[0], fractions[1], fractions[2]), Vec3(0.15625, 0.578125, 1.0))
	ends = world.sliceEnds(50.0, 200000.0, 3)
	expect near(Vec3(ends[0], ends[1], ends[2]), Vec3(801.34393, 2893.154, 8100.0))
	starts = world.sliceStarts(ends)
	expect starts[0] == 0.0 and
		near(Vec3(starts[1], starts[2], 0.0), Vec3(601.34393, 2693.154, 0.0))
test "a cascade's map holds the slice it was fitted to and puts what is toward the sun in front":
	view = Mat4.lookAlong(Vec3(0.0, 300.0, 0.0), Vec3(0.0, 0.0, -1.0))
	toward = Vec3(0.8, 0.5, 0.2).normalized()
	fit = view.fitSun(1.0, 1.0, 50.0, 200000.0, toward)
	expect fit.cascades.len == 3
	# a point of the first slice and a point beyond the second, both in their cascades' maps
	inside = fit.cascades[0].projection @ Vec4(0.0, 300.0, -400.0, 1.0)
	expect inside.x.abs() < 1.0 and inside.y.abs() < 1.0 and inside.z.abs() < 1.0
	far = fit.cascades[2].projection @ Vec4(300.0, 300.0, -5000.0, 1.0)
	expect far.x.abs() < 1.0 and far.y.abs() < 1.0 and far.z.abs() < 1.0
	# a point nearer the sun has the smaller depth
	nearer = fit.cascades[1].projection @
		(Vec4(0.0, 300.0, -1500.0, 1.0) + (toward * 500.0).withW(0.0))
	level = fit.cascades[1].projection @ Vec4(0.0, 300.0, -1500.0, 1.0)
	expect nearer.z < level.z
