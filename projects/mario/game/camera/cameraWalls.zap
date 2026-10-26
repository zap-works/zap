# Camera helpers: C-button movement, floor height and walls that hide Mario (camera.c).

# handle_c_button_movement: C-down zooms out (again: further, then back), C-left and C-right
# turn the camera an eighth of a turn (C-up's first person view is not ported)
fn handleCButtonMovement(mut c Camera, ctl Controls):
	if (ctl.cPressed & cButtonUp) != 0 and (c.movementFlags & camMoveZoomedOut) != 0:
		c.movementFlags &= ~camMoveZoomedOut
	if (ctl.cPressed & cButtonDown) != 0:
		if (c.movementFlags & camMoveZoomedOut) != 0:
			c.movementFlags |= camMoveAlreadyZoomedOut
			c.zoomAmount = c.zoomDist + 400.0
		else:
			c.movementFlags |= camMoveZoomedOut
			c.zoomAmount = c.zoomDist + 400.0
	cSideYaw = 0x1000
	if (ctl.cPressed & cButtonRight) != 0:
		if (c.movementFlags & camMoveRotateLeft) != 0:
			c.movementFlags &= ~camMoveRotateLeft
		else:
			c.movementFlags |= camMoveRotateRight
			c.cSideButtonYaw = -cSideYaw
	if (ctl.cPressed & cButtonLeft) != 0:
		if (c.movementFlags & camMoveRotateRight) != 0:
			c.movementFlags &= ~camMoveRotateRight
		else:
			c.movementFlags |= camMoveRotateLeft
			c.cSideButtonYaw = cSideYaw

# calc_y_to_curr_floor: how far the floor (or the water over it) is below Mario, scaled and held
# within bounds, for the camera's place and for its focus
fn calcYToCurrFloor(
	c Camera,
	m Mario,
	s Surfaces,
	posMul f32,
	posBound f32,
	focMul f32,
	focBound f32
):
	floorHeight = c.currFloorHeight
	if (m.camAction & actFlagMetalWater) == 0:
		waterHeight = s.waterLevel(m.camPos.x, m.camPos.z)
		if floorHeight < waterHeight:
			floorHeight = waterHeight
	# (on a pole the bound is wider: Mario's pole actions are not ported)
	posOff = (floorHeight - m.camPos.y) * posMul
	if posOff > posBound:
		posOff = posBound
	if posOff < -posBound:
		posOff = -posBound
	focOff = (floorHeight - m.camPos.y) * focMul
	if focOff > focBound:
		focOff = focBound
	if focOff < -focBound:
		focOff = -focBound
	(posOff, focOff)

# rotate_camera_around_walls: 8 steps from Mario back to the camera, looking for walls; 3 when one
# hides Mario (with the yaw to turn toward around it), 1 when one is only near the camera
fn rotateCameraAroundWalls(
	mut c Camera,
	m Mario,
	s Surfaces,
	cPos Vec3,
	yawRange i64
):
	mp = m.camPos
	_, _, yawFromMario = mp.vec3fGetDistAndAngle(cPos)
	c.statusFlags &= ~camFlagCamNearWall
	checkDist = 0.0
	# @bug the coarse radius grows to 250, past the wall query's limit of 200
	coarseRadius = 150.0
	fineRadius = 100.0
	status = 0
	avoidYaw = 0
	step = 0
	while step < 8:
		x = mp.x + (cPos.x - mp.x) * checkDist
		y = mp.y + (cPos.y - mp.y) * checkDist
		z = mp.z + (cPos.z - mp.z) * checkDist
		coarse = s.findWallCollisions(x, y, z, 100.0, coarseRadius, true)
		coarseRadius = cameraApproachF32Symmetric(coarseRadius, 250.0, 30.0)
		if coarse.numCollisions != 0:
			if step >= 5:
				c.statusFlags |= camFlagCamNearWall
				if status <= 0:
					status = 1
					n = s.all[coarse.wall].normal
					wallYaw i64 = i16.wrap(atan2s(n.z, n.x) + 0x4000)
					avoidYaw = i16.wrap(calcAvoidYaw(yawFromMario, wallYaw) + 0x8000)
			fine = s.findWallCollisions(x, y, z, 100.0, fineRadius, true)
			fineRadius = cameraApproachF32Symmetric(fineRadius, 200.0, 20.0)
			if fine.numCollisions != 0:
				wall = s.all[fine.wall]
				horWallNorm = atan2s(wall.normal.z, wall.normal.x)
				wallYaw = i16.wrap(horWallNorm + 0x4000)
				# a wall that would hide Mario, tall enough to
				if mp.isRangeBehindSurface(cPos, wall, yawRange, surfaceWallMisc) == 0 and
					mp.isBehindSurface(wall) == 1 and
					not wall.isSurfWithinBoundingBox(-1.0, 150.0, -1.0):
					avoidYaw = i16.wrap(calcAvoidYaw(yawFromMario, wallYaw) + 0x8000)
					avoidYaw = cameraApproachS16Symmetric(avoidYaw, horWallNorm, yawRange)
					status = 3
					step = 8
		checkDist += 0.125
		step += 1
	(status, avoidYaw)

# calc_avoid_yaw: along the wall, the way that turns further into it (the caller turns it around)
fn calcAvoidYaw(yawFromMario i64, wallYaw i64):
	yawDiff i64 = i16.wrap(wallYaw - yawFromMario + 0x4000)
	wallYaw if yawDiff < 0 else i16.wrap(wallYaw + 0x8000)

# collide_with_walls: `pos` pushed out of the last wall that met it, once for every wall kept;
# the count of walls that met it
fn collideWithWalls(s Surfaces, pos0 Vec3, offsetY f32, radius f32):
	pos = pos0
	w = s.findWallCollisions(pos.x, pos.y, pos.z, offsetY, radius, true)
	if w.numCollisions != 0:
		wall = s.all[w.wall]
		loop w.numWalls:
			newPos = pos
			offset = wall.normal.x * newPos.x + wall.normal.y * newPos.y +
				wall.normal.z * newPos.z + wall.offset
			offsetAbsolute = offset if offset >= 0.0 else -offset
			if offsetAbsolute < radius:
				newPos.x += wall.normal.x * (radius - offset)
				newPos.z += wall.normal.z * (radius - offset)
				pos = newPos
	(pos, w.numCollisions)

# is_behind_surface: whether `pos` is behind the surface's plane through its first vertex (the
# normal taken from its vertices)
fn isBehindSurface(pos Vec3, f Surface):
	normX = f32((f.y2 - f.y1) * (f.z3 - f.z2) - (f.y3 - f.y2) * (f.z2 - f.z1))
	normY = f32((f.z2 - f.z1) * (f.x3 - f.x2) - (f.z3 - f.z2) * (f.x2 - f.x1))
	normZ = f32((f.x2 - f.x1) * (f.y3 - f.y2) - (f.x3 - f.x2) * (f.y2 - f.y1))
	dirX = f32(f.x1) - pos.x
	dirY = f32(f.y1) - pos.y
	dirZ = f32(f.z1) - pos.z
	1 if dirX * normX + dirY * normY + dirZ * normZ < 0.0 else 0

# is_range_behind_surface: whether `to`, turned by `range` either way about `from`, is behind the
# surface both times (or just `to`, when the range is 0); a surface of the type `surfType` counts
# as behind
fn isRangeBehindSurface(from Vec3, to Vec3, f Surface, range i64, surfType i64):
	if surfType != -1 and f.kind == surfType: return 1
	if range == 0: return to.isBehindSurface(f)
	checkDist, checkPitch, checkYaw = from.vec3fGetDistAndAngle(to)
	leftBehind = isBehindSurface(
		from.vec3fSetDistAndAngle(checkDist, checkPitch, i16.wrap(checkYaw + range)),
		f
	)
	rightBehind = isBehindSurface(
		from.vec3fSetDistAndAngle(checkDist, checkPitch, i16.wrap(checkYaw - range)),
		f
	)
	leftBehind * rightBehind

# is_surf_within_bounding_box: whether the surface's spans are under the bounds given (-1 ignores one)
fn isSurfWithinBoundingBox(f Surface, xMax f32, yMax f32, zMax f32):
	sx = [f.x1, f.x2, f.x3]
	sy = [f.y1, f.y2, f.y3]
	sz = [f.z1, f.z2, f.z3]
	dxMax = 0
	dyMax = 0
	dzMax = 0
	for i in 0..3:
		j = 0 if i + 1 >= 3 else i + 1
		dx = (sx[i] - sx[j]).abs()
		if dx > dxMax:
			dxMax = i16.wrap(dx)
		dy = (sy[i] - sy[j]).abs()
		if dy > dyMax:
			dyMax = i16.wrap(dy)
		dz = (sz[i] - sz[j]).abs()
		if dz > dzMax:
			dzMax = i16.wrap(dz)
	smaller = false
	if yMax != -1.0 and f32(dyMax) < yMax:
		smaller = true
	if xMax != -1.0 and zMax != -1.0 and f32(dxMax) < xMax and f32(dzMax) < zMax:
		smaller = true
	smaller
