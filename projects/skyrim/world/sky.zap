# The exterior's sky as SkyrimSE.exe 1.7.104 works it out each frame, from the weathers and the hour:
# the sky's 17 colors (Sky::UpdateColors 0x140412df0 with Sky::FillColorBlend 0x140416760 and
# Sky::SetColor 0x140414cf0), the weather's ambient cube (the DALC blend, 0x140416490), the fog by
# day and night (0x140413a30), the sun's place and light (Sun::Update 0x14041bd90), the stars
# (Stars::Update 0x14041a4b0), the clouds' colors, alphas and scrolling (Clouds::Update 0x14040c220),
# the image space of the hour (0x1404158d0), and how a weather gives way to the next
# (Sky::UpdateWeather 0x140412810, the weighted pick 0x14030a3c0).
#
# Everything here is plain numbers: the reading of the records is skyrim/esm/weather.zap, the
# drawing is skyDraw.zap. Axes are the game's (x east, y north, z up).

import skyrim.esm

# the sky's colors are bytes of a texel scale: 1 / 255 (0x141b5bdc8)
byteScale f32 = 1.0 / 255.0

# the weights the four colors of a blend take: the current weather at the first and the second time
# of day, then the last weather's at the same two
pub type SkyBlend:
	first i64
	second i64
	weights Vec4

# FillColorBlend: the times of day the hour falls between, and how far the current weather has
# come in (`share`, 1 when it has no predecessor) times how near the hour is to each time
pub fn blendOf(hours Vec4, hour f32, share f32) SkyBlend:
	first, second, near = hours.timeShares(hour)
	SkyBlend(
		first,
		second,
		weights = Vec4(
			near * share,
			(1.0 - near) * share,
			(1.0 - share) * near,
			(1.0 - share) * (1.0 - near)
		)
	)

fn byteColor(c esm.Color):
	Vec3(f32(c.r), f32(c.g), f32(c.b)) * byteScale

# the four colors times their weights, summed in the executable's order and then scaled from bytes
# (SetColor 0x140414cf0)
pub fn weightedBytes(a esm.Color, b esm.Color, c esm.Color, d esm.Color, w Vec4) Vec3:
	Vec3(
		(f32(a.r) * w.x + f32(b.r) * w.y + f32(c.r) * w.z + f32(d.r) * w.w) * byteScale,
		(f32(a.g) * w.x + f32(b.g) * w.y + f32(c.g) * w.z + f32(d.g) * w.w) * byteScale,
		(f32(a.b) * w.x + f32(b.b) * w.y + f32(c.b) * w.z + f32(d.b) * w.w) * byteScale
	)

# SetColor's last step: with a flash the flash (held to 1) is added and each channel held between 0
# and the weather's lightning color, without one each is held under 1
pub fn flashed(sum Vec3, lightning esm.Color, flash f32) Vec3:
	if flash > 0.0:
		lit = sum + Vec3(1.0, 1.0, 1.0) * flash.min(1.0)
		top = lightning.byteColor()
		return Vec3(lit.x.clamp(0.0, top.x), lit.y.clamp(0.0, top.y), lit.z.clamp(0.0, top.z))
	sum.min(Vec3(1.0, 1.0, 1.0))

# a weather's color of this layer or kind at the two times, none when the weather lacks it
fn noColor():
	esm.Color(r = 0, g = 0, b = 0)

# SetColor: the weather's color of this kind blended over the two times of day and the two weathers
fn blendedColor(
	current esm.Weather,
	last esm.Weather?,
	kind i64,
	b SkyBlend,
	flash f32
):
	at = esm.timesOfDay
	third = noColor()
	fourth = noColor()
	if last is l:
		third = l.colors[kind * at + b.first].copy()
		fourth = l.colors[kind * at + b.second].copy()
	sum = weightedBytes(
		current.colors[kind * at + b.first],
		current.colors[kind * at + b.second],
		third,
		fourth,
		b.weights
	)
	sum.flashed(current.lightning, flash)

# One layer of clouds this frame: its color, its alpha, and its scrolling
pub type CloudState:
	texture str
	color Vec3
	alpha f32
	scroll Vec2   # the speed: its texture offset grows by it times cloudStep and the seconds

# when the sky is: the game hour, how far the current weather has come in over the last (Sky+0x1b8,
# 1 once whole), fDaytimeColorExtension and the lightning's flash (Sky+0x1c8)
pub type SkyTime:
	hour f32
	share f32
	extension f32
	flash f32 = 0.0

# the sky this frame
pub type Sky:
	colors Vec3[]   # esm.colorKinds, 0..1
	ambient Vec3[]   # +x -x +y -y +z -z, the weather's DALC blend
	ambientSpecular Vec3
	ambientFresnel f32
	fogNear f32
	fogFar f32
	fogPower f32
	fogMax f32
	sunToward Vec3   # toward the sun, the light's direction
	sunPlace Vec3   # where the sun's disc stands from the eye
	daylight f32   # the sun's alpha: 0 at night, 1 by day
	glare f32   # the glare's alpha
	starsAlpha f32
	clouds CloudState[]
	imageSpaces i64[]   # the forms of the image spaces blended (IMSP of the hour)
	imageWeights f32[]   # and the weight of each
	moons MoonShown[] = []   # the moons the climate has, set by the clock (moons.zap)
	precipitation PrecipitationNow[] = []   # what falls now, set by the clock (precipitation.zap)

# One of the ambient cube's colors (a face or the specular tint) at the two times of day of the
# current weather and, when there is one, of the last (0x140416490): each byte scaled, then times
# its weight, the current pair added first, the last pair added in front of it
pub fn mixedFace(
	first esm.Color,
	second esm.Color,
	lastFirst esm.Color?,
	lastSecond esm.Color?,
	w Vec4
) Vec3:
	sum = second.byteColor() * w.y + first.byteColor() * w.x
	if lastFirst is a and lastSecond is b: sum = a.byteColor() * w.z + b.byteColor() * w.w + sum
	sum

# the ambient fresnel the same way
pub fn mixedFresnel(first f32, second f32, lastFirst f32?, lastSecond f32?, w Vec4) f32:
	sum = second * w.y + first * w.x
	if lastFirst is a and lastSecond is b: sum = b * w.w + a * w.z + sum
	sum

# the DALC blend of the six faces and the specular tint
fn ambientBlend(current esm.Weather, last esm.Weather?, b SkyBlend):
	w = b.weights
	faces = []
	for u in 0..7:
		lastFirst = none
		lastSecond = none
		if last is l:
			lastFirst = l.ambientAt(b.first, u).copy()
			lastSecond = l.ambientAt(b.second, u).copy()
		faces.push(
			mixedFace(
				current.ambientAt(b.first, u),
				current.ambientAt(b.second, u),
				lastFirst,
				lastSecond,
				w
			)
		)
	lastFirst = none
	lastSecond = none
	if last is l:
		lastFirst = l.ambientFresnel[b.first]
		lastSecond = l.ambientFresnel[b.second]
	fresnel = mixedFresnel(
		current.ambientFresnel[b.first],
		current.ambientFresnel[b.second],
		lastFirst,
		lastSecond,
		w
	)
	(faces[..6].copy(), faces[6], fresnel)

# the color of a DALC face u (0..5) or its specular tint (6) at a time of day
fn ambientAt(w esm.Weather, time i64, u i64):
	if u == 6: return w.ambientSpecular[time]
	w.ambient[time * 6 + u]

# how far the hour is into the day (0 night, 1 day): the ramp over the sunrise, then the sunset
# (the fog's, 0x140413a30; the hours are the colors' widened ones)
pub fn dayShare(h Vec4, hour f32) f32:
	if h.x < hour and hour < h.y: return (hour - h.x) / (h.y - h.x)
	if hour >= h.y and hour <= h.z: return 1.0
	if hour > h.z and hour < h.w: return (h.w - hour) / (h.w - h.z)
	0.0

# the fog one weather gives at this share of the day: near, far, power, max
fn fogOf(w esm.Weather, day f32):
	f = w.fog
	night = 1.0 - day
	Vec4(
		night * f.nightNear + day * f.dayNear,
		night * f.nightFar + day * f.dayFar,
		night * f.nightPower + day * f.dayPower,
		night * f.nightMax + day * f.dayMax
	)

# the fog: the current weather's, with the last one's blended in by the share
fn fogBlend(current esm.Weather, last esm.Weather?, t SkyTime, hours Vec4):
	day = hours.dayShare(t.hour)
	cur = current.fogOf(day)
	if last is l: return cur * t.share + l.fogOf(day) * (1.0 - t.share)
	cur

# the sun's path by the hour (Sun::Update, full mode): it crosses from east to west between a
# window an hour either side of the middle of the climate's sunrise and of its sunset
sunWindow f32 = 1.0   # half of DAT_14209e948 (2.0)
sunReach f32 = 400.0   # DAT_14209e960
sunTilt f32 = 25.0   # DAT_14209e978
sunLight f32 = 100.0   # DAT_14209e990: how high the light stands, whatever the disc does

# the sun's windows: where it rises (A..B) and sets (C..D)
fn sunWindows(c esm.Climate):
	rise = (c.sunriseBegin + c.sunriseEnd) * 0.5
	set = (c.sunsetBegin + c.sunsetEnd) * 0.5
	Vec4(rise - sunWindow, rise + sunWindow, set - sunWindow, set + sunWindow)

# the sun's alpha: 0 before its sunrise window, rising across it, 1 by day, falling across its sunset
pub fn daylightAt(c esm.Climate, hour f32) f32:
	w = c.sunWindows()
	if hour < w.x or hour > w.w: return 0.0
	if hour <= w.x or w.y <= hour:
		if w.z < hour and hour < w.w: return 1.0 - (hour - w.z) / (w.w - w.z)
		return 1.0
	(hour - w.x) / (w.y - w.x)

# the sun's place along its path, +1 at the start of its sunrise window, -1 at the end of its sunset
# one (it carries on from there through the night back to +1)
pub fn sunTrack(c esm.Climate, hour f32) f32:
	w = c.sunWindows()
	night = 24.0 - (w.w - w.x)
	if hour <= w.x: return 2.0 * ((hour + 24.0 - w.w) / night) - 1.0
	if w.w <= hour: return 2.0 * ((hour - w.w) / night) - 1.0
	1.0 - 2.0 * ((hour - w.x) / (w.w - w.x))

# toward the sun where its light comes from (the light stands at least sunLight over the reach)
pub fn sunLightToward(track f32) Vec3:
	Vec3(sunReach * track, sunTilt, sunLight).normalized()

# the sun's disc from the viewer: (reach * track, tilt, reach * (1 - |track|)), 400 units out at the
# horizon and at noon and 283 half way between
pub fn sunDiscPlace(track f32) Vec3:
	Vec3(sunReach * track, sunTilt, sunReach * (1.0 - track.abs()))

# toward the sun's disc
pub fn sunDiscToward(track f32) Vec3:
	sunDiscPlace(track).normalized()

# the stars' alpha: fading out across the sunrise, gone by day, fading in across the sunset
# (Stars::Update): the hours are the climate's, the first and last widened by half an hour
pub fn starsAlphaAt(c esm.Climate, hour f32) f32:
	begin = (c.sunriseBegin - 0.5).max(0.0)
	over = (c.sunsetEnd + 0.5).min(23.99)
	rise = c.sunriseEnd - (c.sunriseEnd - begin) * 0.5
	set = over - (over - c.sunsetBegin) * 0.5
	if begin < hour and hour < rise: return (rise - hour) / (rise - begin)
	if hour >= rise and hour <= set: return 0.0
	if set < hour and hour < over: return (hour - set) / (over - set)
	1.0

# a cloud layer's scroll speed (Clouds::Update): a byte, 127 standing still
pub fn cloudSpeed(b f32) f32:
	b * 0.2 * (1.0 / 254.0) - 0.1

# the layers' scroll step: a tenth of the seconds that pass (0x141b5bde4); a layer's offset grows by
# its speed times it each frame
pub cloudStep f32 = 0.1

fn cloudAlphaOf(w esm.Weather, k i64, time i64) f32:
	if k >= w.layers.len or not w.layers[k].enabled: return 0.0
	w.layers[k].alpha[time]

fn cloudColorOf(w esm.Weather, k i64, time i64):
	if k >= w.layers.len: return Vec3(0.0, 0.0, 0.0)
	w.layers[k].colors[time].byteColor()

fn cloudsOf(current esm.Weather, last esm.Weather?, t SkyTime, b SkyBlend):
	out = []
	for k, layer in current.layers:
		third = noColor()
		fourth = noColor()
		if last is l and k < l.layers.len:
			third = l.layers[k].colors[b.first].copy()
			fourth = l.layers[k].colors[b.second].copy()
		sum = layer.colors[b.first].weightedBytes(layer.colors[b.second], third, fourth, b.weights)
		# the lightning's flash lights the first layer while no weather gives way
		flash = t.flash if last == none and k == 0 else 0.0
		alpha = current.cloudAlphaOf(k, b.first) * b.weights.x +
			current.cloudAlphaOf(k, b.second) * b.weights.y
		speed = Vec2(cloudSpeed(layer.speedX), cloudSpeed(layer.speedY)) * t.share
		if last is l:
			alpha = alpha + l.cloudAlphaOf(k, b.first) * b.weights.z +
				l.cloudAlphaOf(k, b.second) * b.weights.w
			if k < l.layers.len:
				speed = speed +
					Vec2(cloudSpeed(l.layers[k].speedX), cloudSpeed(l.layers[k].speedY)) *
					(1.0 - t.share)
		out.push(
			CloudState(
				texture = layer.texture.copy(),
				color = sum.flashed(current.lightning, flash),
				alpha,
				scroll = speed
			)
		)
	out

# the image spaces of the hour, each with its weight (0x1404158d0): the current weather's at the
# two times and the last one's
fn imageSpacesOf(current esm.Weather, last esm.Weather?, b SkyBlend):
	forms = [current.imageSpaces[b.first], current.imageSpaces[b.second]]
	weights = [b.weights.x, b.weights.y]
	if last is l:
		forms.push(l.imageSpaces[b.first])
		forms.push(l.imageSpaces[b.second])
		weights.push(b.weights.z)
		weights.push(b.weights.w)
	(forms, weights)

# the sky this frame
pub fn skyAt(current esm.Weather, last esm.Weather?, climate esm.Climate, t SkyTime) Sky:
	hours = climate.colorHours(t.extension)
	b = hours.blendOf(t.hour, t.share if last != none else 1.0)
	colors = []
	for k in 0..esm.colorKinds.len:
		# the flash lights the sun's and the ambient light while no weather gives way
		flash = 0.0
		if last == none:
			if k == esm.sunlightColor: flash = t.flash
			if k == esm.ambientColor: flash = t.flash * 0.3
		colors.push(current.blendedColor(last, k, b, flash))
	faces, tint, fresnel = current.ambientBlend(last, b)
	fog = current.fogBlend(last, t, hours)
	track = climate.sunTrack(t.hour)
	daylight = climate.daylightAt(t.hour)
	glareNow = f32(current.sunGlare) * byteScale * t.share * daylight
	glareLast = 0.0
	if last is l: glareLast = f32(l.sunGlare) * byteScale * (1.0 - t.share) * daylight
	forms, weights = current.imageSpacesOf(last, b)
	Sky(
		colors,
		ambient = faces,
		ambientSpecular = tint,
		ambientFresnel = fresnel,
		fogNear = fog.x,
		fogFar = fog.y,
		fogPower = fog.z,
		fogMax = fog.w,
		sunToward = sunLightToward(track),
		sunPlace = sunDiscPlace(track),
		daylight,
		glare = glareNow + glareLast,
		starsAlpha = climate.starsAlphaAt(t.hour),
		clouds = current.cloudsOf(last, t, b),
		imageSpaces = forms,
		imageWeights = weights
	)

# How a weather gives way. The sky keeps the weather it shows, the one before and the hour the
# current one came in; the next is picked when the current has lasted its time or the player's
# region changes.
pub type WeatherState:
	current i64
	last i64   # 0 when none
	changedAt f32   # Sky+0x1b4: the game hour the current weather came in

# game hours a transition takes: 0.01 to 0.25 by the weather's transition byte (0x14209e708,
# 0x14209e720)
pub fn transitionHours(transDelta i64) f32:
	f32(transDelta) * byteScale * (0.25 - 0.01) + 0.01

# hours since the weather came in, the day wrapping
fn sinceChange(s WeatherState, hour f32) f32:
	(24.0 if hour < s.changedAt else 0.0) + hour - s.changedAt

# the weather's share (Sky+0x1b8): how far it has come in over the last one
pub fn shareAt(s WeatherState, hour f32, transDelta i64) f32:
	if s.last == 0: return 1.0
	s.sinceChange(hour) / transitionHours(transDelta)

# how long a weather lasts, in game hours: 1 to 23 by the climate's volatility (0x140412810)
pub fn weatherHours(volatility i64) f32:
	f32((255 - volatility) * 22) * byteScale + 1.0

# The weighted pick (0x14030a3c0): the entries' chances laid end to end, the roll falling on one.
# A chance is a whole number, or its global's value cut to one.
pub fn pickWeather(entries esm.RegionWeather[], chances i64[], roll i64) i64?:
	total = chances.sum()
	if total == 0: return none
	at = roll % total
	passed = 0
	for k, e in entries:
		if chances[k] == 0: continue
		if passed <= at and at <= passed + chances[k] - 1: return e.weather
		passed += chances[k]
	none

# whether a region's list gives the weather a chance
fn listed(entries esm.RegionWeather[], chances i64[], weather i64):
	for k, e in entries:
		if e.weather == weather and chances[k] != 0: return true
	false

# What the sky does when time passes (Sky::UpdateWeather): once the current weather has lasted
# `weatherHours` the region's list is rolled for the next; entering a region that lists the current
# weather keeps it with the chance its remaining time gives (`keep`, 0..1, drawn by the caller).
# A weather that differs becomes current with the old one as the last, and the transition starts;
# one that has come in whole drops the last.
pub fn stepWeather(
	s WeatherState,
	hour f32,
	volatility i64,
	transDelta i64,
	entries esm.RegionWeather[],
	chances i64[],
	roll i64,
	enteredRegion bool,
	keep f32
) WeatherState:
	next = s
	elapsed = s.sinceChange(hour)
	lasts = weatherHours(volatility)
	picked = pickWeather(entries, chances, roll)
	chosen = s.current
	if enteredRegion:
		if picked is p:
			chosen = p
			if p != s.current and listed(entries, chances, s.current) and elapsed / lasts < keep:
				chosen = s.current
	elif elapsed > lasts:
		if picked is p: chosen = p
	if chosen != s.current:
		next = WeatherState(current = chosen, last = s.current, changedAt = hour)
	if next.last != 0 and next.shareAt(hour, transDelta) > 1.0:
		next = WeatherState(..next, last = 0)
	next
