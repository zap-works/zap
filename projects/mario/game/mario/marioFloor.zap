# Mario floor queries: the floor class, slipperiness, slope and the floor around him (mario.c).

# mario_get_floor_class
fn marioGetFloorClass(m Mario, s Surfaces):
	floorClass = classVerySlippery if (terrainType & 7) == terrainSlide else classDefault
	if m.floor >= 0:
		t = s.all[m.floor].kind
		if t in [surfaceNotSlippery, surfaceHardNotSlippery, surfaceSwitch]:
			floorClass = classNotSlippery
		elif t in [
			surfaceSlippery,
			surfaceNoiseSlippery,
			surfaceHardSlippery,
			surfaceNoCamColSlippery
		]:
			floorClass = classSlippery
		elif t in [
			surfaceVerySlippery,
			surfaceIce,
			surfaceHardVerySlippery,
			surfaceNoiseVerySlippery73,
			surfaceNoiseVerySlippery74,
			surfaceNoiseVerySlippery,
			surfaceNoCamColVerySlippery
		]:
			floorClass = classVerySlippery
	# crawling keeps him from sliding on some steeper floors
	if m.action == actCrawling and s.all[m.floor].normal.y > 0.5 and floorClass == classDefault:
		floorClass = classNotSlippery
	floorClass

fn floorNormalY(m Mario, s Surfaces):
	s.all[m.floor].normal.y

# mario_facing_downhill
fn marioFacingDownhill(m Mario, turnYaw bool):
	faceAngleYaw = m.faceYaw
	if turnYaw and m.forwardVel < 0.0:
		faceAngleYaw = i16.wrap(faceAngleYaw + 0x8000)
	faceAngleYaw = i16.wrap(m.floorAngle - faceAngleYaw)
	-0x4000 < faceAngleYaw and faceAngleYaw < 0x4000

# mario_floor_is_slippery
fn marioFloorIsSlippery(m Mario, s Surfaces):
	m.onSlideTerrainSlope(s) or m.floorNormalAtMost(s, [0.9848077, 0.9396926, 0.7880108, 0.0])

# mario_floor_is_slope
fn marioFloorIsSlope(m Mario, s Surfaces):
	m.onSlideTerrainSlope(s) or
		m.floorNormalAtMost(s, [0.9961947, 0.9848077, 0.9659258, 0.9396926])

# mario_floor_is_steep (which, as the game's, does not look at a slide terrain)
fn marioFloorIsSteep(m Mario, s Surfaces):
	not m.marioFacingDownhill(false) and
		m.floorNormalAtMost(s, [0.9659258, 0.9396926, 0.8660254, 0.8660254])

# a floor that is not flat on a slide terrain (the first test of the two above)
fn onSlideTerrainSlope(m Mario, s Surfaces):
	(terrainType & 7) == terrainSlide and m.floorNormalY(s) < 0.9998477

# The floor's normal at most its class's limit: the switch of the three above, its cases as
# `limits` (very slippery, slippery, default, not slippery).
fn floorNormalAtMost(m Mario, s Surfaces, limits f32[4]):
	floorClass = m.marioGetFloorClass(s)
	normY = limits[2]
	if floorClass == classVerySlippery:
		normY = limits[0]
	elif floorClass == classSlippery:
		normY = limits[1]
	elif floorClass == classNotSlippery:
		normY = limits[3]
	m.floorNormalY(s) <= normY

# find_floor_height_relative_polar
fn findFloorHeightRelativePolar(m Mario, s Surfaces, angleFromMario i64, distFromMario f32):
	y = sins(m.faceYaw + angleFromMario) * distFromMario
	x = coss(m.faceYaw + angleFromMario) * distFromMario
	floorY, _ = s.findFloor(m.pos.x + y, m.pos.y + 100.0, m.pos.z + x)
	floorY

# find_floor_slope: the pitch of the floor ahead (or behind) him, from points 5 units away
fn findFloorSlope(m Mario, s Surfaces, yawOffset i64):
	x = sins(m.faceYaw + yawOffset) * 5.0
	z = coss(m.faceYaw + yawOffset) * 5.0
	forwardFloorY, _ = s.findFloor(m.pos.x + x, m.pos.y + 100.0, m.pos.z + z)
	backwardFloorY, _ = s.findFloor(m.pos.x - x, m.pos.y + 100.0, m.pos.z - z)
	forwardYDelta = forwardFloorY - m.pos.y
	backwardYDelta = m.pos.y - backwardFloorY
	if forwardYDelta * forwardYDelta < backwardYDelta * backwardYDelta:
		return atan2s(5.0, forwardYDelta)
	atan2s(5.0, backwardYDelta)

# ---------- after the action ----------
