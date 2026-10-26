# Masser and Secunda as SkyrimSE.exe 1.7.104 places them: Moon::Update 0x14040e0f0 turns each moon's
# angle by its speed as the hours pass and fades it in as it climbs and out as it sets, the quad is
# built in Moon::Init 0x14040d930 (a square of half-width iMasserSize 512 units out of the eye, a
# part of the moons' root rotated by the angle about x and by the z offset about z), and
# Sky::UpdateMoonPhase 0x14040d370 picks the texture by the days passed. Plain numbers; the drawing
# is skyDraw.zap. Axes are the game's (x east, y north, z up).

import skyrim.esm

# how far from the eye a moon's quad stands (the moon node's translation, 0x14040d930)
moonDistance f32 = 512.0
# the moons' angle starts here when first updated (0x14040e0f0), whose last time is then this
# (the largest float: a moon never updated)
moonStartAngle f32 = 90.0
pub moonNever f32 = 3.4028235e38

# the textures by phase, in the executable's order: Data/Textures/Sky/<moon>_<phase>.dds
pub moonPhases = [
	"full",
	"three_wan",
	"half_wan",
	"one_wan",
	"new",
	"one_wax",
	"half_wax",
	"three_wax"
]

# a moon's settings: its fMasserAngleFadeStart ..., iMasserSize (GMSTs, these the executable's
# defaults in reference/exe/gmst-*.md)
pub type MoonSettings:
	name str   # "masser" or "secunda": the texture's prefix
	fadeStart f32
	fadeEnd f32
	earlyFade f32
	speed f32
	zOffset f32
	size f32

pub fn masserDefaults() MoonSettings:
	MoonSettings("masser", 55.0, 45.0, 0.5, 0.25, 35.0, 94.0)

pub fn secundaDefaults() MoonSettings:
	MoonSettings("secunda", 55.0, 40.0, 0.5, 0.3, 50.0, 40.0)

# a moon's settings from the plugin's GMSTs (keys lowercase, as esm.gameSettings gives them), the
# defaults where it sets none
pub fn moonSettings(name str, defaults MoonSettings, settings {str: f64}) MoonSettings:
	key = name.lower()
	MoonSettings(
		name = name.lower(),
		fadeStart = f32(settings.get("f{key}anglefadestart") ?? f64(defaults.fadeStart)),
		fadeEnd = f32(settings.get("f{key}anglefadeend") ?? f64(defaults.fadeEnd)),
		earlyFade = f32(settings.get("f{key}angleshadowearlyfade") ?? f64(defaults.earlyFade)),
		speed = f32(settings.get("f{key}speed") ?? f64(defaults.speed)),
		zOffset = f32(settings.get("f{key}zoffset") ?? f64(defaults.zOffset)),
		size = f32(settings.get("i{key}size") ?? f64(defaults.size))
	)

# the angle in degrees a moon is at after the hour goes from `last` to `hour`: it turns
# speed * 60 degrees an hour, a day wrapped when the hour went round, and the angle held in 0..360
# (a moon not yet updated starts at 90 and counts its hours from midnight)
pub fn moonAngleAfter(angle f32, last f32, hour f32, speed f32) f32:
	start = angle
	since = last
	if last == moonNever:
		start = moonStartAngle
		since = 0.0
	dt = hour - since
	if dt < 0.0: dt += 24.0
	turned = speed * 60.0 * dt + start
	while turned < 0.0:
		turned += 360.0
	while turned >= 360.0:
		turned -= 360.0
	turned

# The angle of a moon `hours` after the game's first update, where it stood at 90 degrees (the
# frames' steps added up)
pub fn moonAngleAt(settings MoonSettings, hours f32) f32:
	(moonStartAngle + settings.speed * 60.0 * hours) % 360.0

# The share of the fade at `angle` between a start `a` and an end `b`: 0 below the horizon (over 180),
# rising from 0 at b to 1 at a, held to 180 - a, falling to 0 at 180 - b (Moon::Update's piecewise
# blend, the moon's with the fade settings, the shadow's with the end and the end less the early
# fade)
pub fn moonFadeBetween(angle f32, a f32, b f32) f32:
	if angle > 180.0: return 0.0
	top = 180.0 - a
	last = 180.0 - b
	if a < angle or angle < b:
		if angle < top or last < angle:
			if angle <= a or top <= angle: return 0.0
			return 1.0
		return (last - angle) / (last - top)
	(angle - b) / (a - b)

# the moon's alpha
pub fn moonAlpha(s MoonSettings, angle f32) f32:
	moonFadeBetween(angle, s.fadeStart, s.fadeEnd)

# the alpha of its shadow (the mask that hides the stars behind it), held under the stars' alpha
pub fn moonShadowAlpha(s MoonSettings, angle f32, starsAlpha f32) f32:
	moonFadeBetween(angle, s.fadeEnd, s.fadeEnd - s.earlyFade).min(starsAlpha)

# The place of a moon's quad: its center `moonDistance` out and the quad's right and up, the columns
# of the matrix 0x14040e0f0 stores in the moon's node (the quad, at (0, 512, 0), turned to face -y
# with its y up, rides on it): its middle column is the center's direction.
pub type MoonPlace:
	center Vec3
	right Vec3
	up Vec3

pub fn moonPlaceAt(angle f32, zOffset f32) MoonPlace:
	a = angle.radians()
	z = zOffset.radians()
	sa = a.sin()
	ca = a.cos()
	sz = z.sin()
	cz = z.cos()
	MoonPlace(
		center = Vec3(sz, cz * ca, cz * sa) * moonDistance,
		right = Vec3(cz, -sz * ca, -sa * sz),
		up = Vec3(0.0, -sa, ca)
	)

# the phase the moons show on a day (Sky::UpdateMoonPhase: the day modulo eight phases' length, over
# the phase length), none when the climate gives no phase length
pub fn moonPhaseOn(day i64, phaseLength i64) i64:
	if phaseLength <= 0: return 0
	(day % (phaseLength * 8)) / phaseLength

# the texture of a moon at a phase, as the archive names it
pub fn moonTexture(name str, phase i64) str:
	"Sky\\{name}_{moonPhases[phase]}.dds"

# a moon as the sky draws it this frame
pub type MoonShown:
	texture str
	place MoonPlace
	half f32
	alpha f32
	shadowAlpha f32

# the moons the climate has, `hours` after the game began, on `day`
pub fn moonsAt(
	climate esm.Climate,
	masser MoonSettings,
	secunda MoonSettings,
	hours f32,
	day i64,
	starsAlpha f32
) MoonShown[]:
	out = []
	phase = moonPhaseOn(day, climate.phaseLength)
	for k in 0..2:
		present = climate.masser if k == 0 else climate.secunda
		if not present: continue
		s = masser if k == 0 else secunda
		angle = s.moonAngleAt(hours)
		out.push(
			MoonShown(
				texture = moonTexture(s.name, phase),
				place = moonPlaceAt(angle, s.zOffset),
				half = s.size,
				alpha = s.moonAlpha(angle),
				shadowAlpha = s.moonShadowAlpha(angle, starsAlpha)
			)
		)
	out
