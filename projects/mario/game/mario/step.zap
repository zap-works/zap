# Mario's steps (mario_step.c): on the ground in four quarter steps along the floor, each
# scaled by how level it is; through the air in four quarter steps, then gravity. Each quarter
# step pushes him out of the walls, finds the floor and the ceiling there and tells what met him.

# step results (sm64.h)
groundStepLeftGround = 0
groundStepNone = 1
groundStepHitWall = 2   # also GROUND_STEP_HIT_WALL_STOP_QSTEPS
groundStepHitWallContinueQsteps = 3
airStepCheckLedgeGrab = 0x1
airStepCheckHang = 0x2
airStepNone = 0
airStepLanded = 1
airStepHitWall = 2
airStepGrabbedLedge = 3
airStepGrabbedCeiling = 4
airStepHitLavaWall = 6

# the speeds of moving quicksand by its force's upper byte
movingSandSpeeds = [12, 8, 4, 0]

# mario_bonk_reflection: turned off the wall he hit (mirrored about its normal), or back around
fn marioBonkReflection(mut m Mario, s Surfaces, negateSpeed bool):
	if m.wall >= 0:
		n = s.all[m.wall].normal
		wallAngle = atan2s(n.z, n.x)
		m.faceYaw = i16.wrap(wallAngle - i16.wrap(m.faceYaw - wallAngle))
	if negateSpeed:
		m.marioSetForwardVel(-m.forwardVel)
	else:
		m.faceYaw = i16.wrap(m.faceYaw + 0x8000)

# mario_update_quicksand: how deep he sinks, by the floor (true when it kills him)
fn marioUpdateQuicksand(mut m Mario, s Surfaces, sinkingSpeed f32):
	if (m.action & actFlagRidingShell) != 0:
		m.quicksandDepth = 0.0
		return false
	if m.quicksandDepth < 1.1:
		m.quicksandDepth = 1.1
	t = s.all[m.floor].kind
	if t == surfaceShallowQuicksand:
		m.quicksandDepth += sinkingSpeed
		if m.quicksandDepth >= 10.0:
			m.quicksandDepth = 10.0
	elif t == surfaceShallowMovingQuicksand:
		m.quicksandDepth += sinkingSpeed
		if m.quicksandDepth >= 25.0:
			m.quicksandDepth = 25.0
	elif t == surfaceQuicksand or t == surfaceMovingQuicksand:
		m.quicksandDepth += sinkingSpeed
		if m.quicksandDepth >= 60.0:
			m.quicksandDepth = 60.0
	elif t == surfaceDeepQuicksand or t == surfaceDeepMovingQuicksand:
		m.quicksandDepth += sinkingSpeed
		if m.quicksandDepth >= 160.0: return m.dropAndSetMarioAction(s, actQuicksandDeath, 0)
	elif t == surfaceInstantQuicksand or t == surfaceInstantMovingQuicksand:
		return m.dropAndSetMarioAction(s, actQuicksandDeath, 0)
	else:
		m.quicksandDepth = 0.0
	false

# mario_push_off_steep_floor
fn marioPushOffSteepFloor(mut m Mario, s Surfaces, action i64, actionArg i64) bool:
	floorDYaw i64 = i16.wrap(m.floorAngle - m.faceYaw)
	if floorDYaw > -0x4000 and floorDYaw < 0x4000:
		m.forwardVel = 16.0
		m.faceYaw = m.floorAngle
	else:
		m.forwardVel = -16.0
		m.faceYaw = i16.wrap(m.floorAngle + 0x8000)
	m.setMarioAction(s, action, actionArg)

# mario_update_moving_sand: flowing quicksand carries him along
fn marioUpdateMovingSand(mut m Mario, s Surfaces):
	f = s.all[m.floor]
	t = f.kind
	if t in [
		surfaceDeepMovingQuicksand,
		surfaceShallowMovingQuicksand,
		surfaceMovingQuicksand,
		surfaceInstantMovingQuicksand
	]:
		pushAngle i64 = i16.wrap(f.force << 8)
		pushSpeed = f32(movingSandSpeeds[f.force.bits(8, 2)])
		m.vel.x += pushSpeed * sins(pushAngle)
		m.vel.z += pushSpeed * coss(pushAngle)
		return true
	false

# mario_update_windy_ground: the wind pushes him
fn marioUpdateWindyGround(mut m Mario, s Surfaces):
	f = s.all[m.floor]
	if f.kind != surfaceHorizontalWind: return false
	pushAngle i64 = i16.wrap(f.force << 8)
	pushSpeed = 0.0
	if (m.action & actFlagMoving) != 0:
		pushDYaw i64 = i16.wrap(m.faceYaw - pushAngle)
		pushSpeed = -m.forwardVel * 0.5 if m.forwardVel > 0.0 else -8.0
		if pushDYaw > -0x4000 and pushDYaw < 0x4000:
			pushSpeed *= -1.0
		pushSpeed *= coss(pushDYaw)
	else:
		pushSpeed = 3.2 + f32(m.ticks % 4)
	m.vel.x += pushSpeed * sins(pushAngle)
	m.vel.z += pushSpeed * coss(pushAngle)
	true

# stationary_ground_step: standing; held on the floor unless sand or wind moves him
fn stationaryGroundStep(mut m Mario, s Surfaces):
	stepResult = groundStepNone
	m.marioSetForwardVel(0.0)
	movedBySand = m.marioUpdateMovingSand(s)
	movedByWind = m.marioUpdateWindyGround(s)
	if movedBySand or movedByWind:
		stepResult = m.performGroundStep(s)
	else:
		m.pos.y = m.floorHeight
		m.drawUpright()
	stepResult

# the model at his place, upright, facing his yaw (gfx.pos copied, vec3s_set of gfx.angle)
fn drawUpright(mut m Mario):
	m.drawYaw = m.faceYaw
	m.drawPitch = 0
	m.drawRoll = 0
	m.drawLift = 0.0

# perform_ground_quarter_step
fn performGroundQuarterStep(mut m Mario, s Surfaces, nextPos0 Vec3):
	nextPos = nextPos0
	s.resolveAndReturnWallCollisions(nextPos, 30.0, 24.0)
	upperWall = s.resolveAndReturnWallCollisions(nextPos, 60.0, 50.0)
	floorHeight, floor = s.findFloor(nextPos.x, nextPos.y, nextPos.z)
	ceilHeight, _ = s.vec3fFindCeil(nextPos, floorHeight)
	m.wall = upperWall
	if floor < 0: return groundStepHitWall
	# (riding a shell over water: not ported)
	if nextPos.y > floorHeight + 100.0:
		if nextPos.y + 160.0 >= ceilHeight: return groundStepHitWall
		m.pos = nextPos
		m.floor = floor
		m.floorHeight = floorHeight
		return groundStepLeftGround
	if floorHeight + 160.0 >= ceilHeight: return groundStepHitWall
	m.pos = Vec3(nextPos.x, floorHeight, nextPos.z)
	m.floor = floor
	m.floorHeight = floorHeight
	if upperWall >= 0:
		n = s.all[upperWall].normal
		wallDYaw i64 = i16.wrap(atan2s(n.z, n.x) - m.faceYaw)
		if wallDYaw >= 0x2AAA and wallDYaw <= 0x5555: return groundStepNone
		if wallDYaw <= -0x2AAA and wallDYaw >= -0x5555: return groundStepNone
		return groundStepHitWallContinueQsteps
	groundStepNone

# perform_ground_step
fn performGroundStep(mut m Mario, s Surfaces):
	stepResult = groundStepNone
	loop 4:
		normalY = s.all[m.floor].normal.y
		intendedX = m.pos.x + normalY * (m.vel.x / 4.0)
		intendedZ = m.pos.z + normalY * (m.vel.z / 4.0)
		stepResult = m.performGroundQuarterStep(s, Vec3(intendedX, m.pos.y, intendedZ))
		if stepResult == groundStepLeftGround or stepResult == groundStepHitWall: break
	m.drawUpright()
	if stepResult == groundStepHitWallContinueQsteps:
		stepResult = groundStepHitWall
	stepResult

# check_ledge_grab: a wall that pushed him back, with a floor over 100 units above him behind it
fn checkLedgeGrab(mut m Mario, s Surfaces, wall i64, intendedPos Vec3, nextPos Vec3):
	if m.vel.y > 0.0: return false
	displacementX = nextPos.x - intendedPos.x
	displacementZ = nextPos.z - intendedPos.z
	if displacementX * m.vel.x + displacementZ * m.vel.z > 0.0: return false
	n = s.all[wall].normal
	ledgeX = nextPos.x - n.x * 60.0
	ledgeZ = nextPos.z - n.z * 60.0
	ledgeY, ledgeFloor = s.findFloor(ledgeX, nextPos.y + 160.0, ledgeZ)
	if ledgeY - nextPos.y <= 100.0: return false
	m.pos = Vec3(ledgeX, ledgeY, ledgeZ)
	m.floor = ledgeFloor
	m.floorHeight = ledgeY
	ln = s.all[ledgeFloor].normal
	m.floorAngle = atan2s(ln.z, ln.x)
	m.facePitch = 0
	m.faceYaw = i16.wrap(atan2s(n.z, n.x) + 0x8000)
	true

# perform_air_quarter_step
fn performAirQuarterStep(mut m Mario, s Surfaces, intendedPos Vec3, stepArg i64):
	nextPos = intendedPos
	upperWall = s.resolveAndReturnWallCollisions(nextPos, 150.0, 50.0)
	lowerWall = s.resolveAndReturnWallCollisions(nextPos, 30.0, 50.0)
	floorHeight, floor = s.findFloor(nextPos.x, nextPos.y, nextPos.z)
	ceilHeight, _ = s.vec3fFindCeil(nextPos, floorHeight)
	m.wall = -1
	if floor < 0:
		if nextPos.y <= m.floorHeight:
			m.pos.y = m.floorHeight
			return airStepLanded
		m.pos.y = nextPos.y
		return airStepHitWall
	if nextPos.y <= floorHeight:
		if ceilHeight - floorHeight > 160.0:
			m.pos.x = nextPos.x
			m.pos.z = nextPos.z
			m.floor = floor
			m.floorHeight = floorHeight
		m.pos.y = floorHeight
		return airStepLanded
	if nextPos.y + 160.0 > ceilHeight:
		if m.vel.y >= 0.0:
			m.vel.y = 0.0
			# (the ceiling he stood under, not this one: the game's ceiling hang upwarp)
			if (stepArg & airStepCheckHang) != 0 and m.ceil >= 0 and
				s.all[m.ceil].kind == surfaceHangable:
				return airStepGrabbedCeiling
			return airStepNone
		if nextPos.y <= m.floorHeight:
			m.pos.y = m.floorHeight
			return airStepLanded
		m.pos.y = nextPos.y
		return airStepHitWall
	if (stepArg & airStepCheckLedgeGrab) != 0 and upperWall < 0 and lowerWall >= 0:
		if m.checkLedgeGrab(s, lowerWall, intendedPos, nextPos): return airStepGrabbedLedge
		m.pos = nextPos
		m.floor = floor
		m.floorHeight = floorHeight
		return airStepNone
	m.pos = nextPos
	m.floor = floor
	m.floorHeight = floorHeight
	if upperWall >= 0 or lowerWall >= 0:
		m.wall = upperWall if upperWall >= 0 else lowerWall
		w = s.all[m.wall]
		wallDYaw i64 = i16.wrap(atan2s(w.normal.z, w.normal.x) - m.faceYaw)
		if w.kind == surfaceBurning: return airStepHitLavaWall
		if wallDYaw < -0x6000 or wallDYaw > 0x6000:
			m.flags |= marioAirWallHit
			return airStepHitWall
	airStepNone

# should_strengthen_gravity_for_jump_ascent: A let go while rising fast cuts a jump short
fn shouldStrengthenGravityForJumpAscent(m Mario):
	if (m.flags & marioJumpHeightControl) == 0: return false
	if (m.action & (actFlagIntangible | actFlagInvulnerable)) != 0: return false
	if (m.input & inputADown) == 0 and m.vel.y > 20.0:
		return (m.action & actFlagControlJumpHeight) != 0
	false

# apply_gravity (twirling, the cannon, lava boosts, wind, metal and the wing cap are not ported)
fn applyGravity(mut m Mario):
	if m.action == actLongJump or m.action == actSlideKick:
		m.vel.y -= 2.0
		if m.vel.y < -75.0:
			m.vel.y = -75.0
	elif m.shouldStrengthenGravityForJumpAscent():
		m.vel.y /= 4.0
	else:
		m.vel.y -= 4.0
		if m.vel.y < -75.0:
			m.vel.y = -75.0

# apply_vertical_wind
fn applyVerticalWind(mut m Mario, s Surfaces):
	if m.action == actGroundPound: return
	offsetY = m.pos.y + 1500.0
	if s.all[m.floor].kind == surfaceVerticalWind and -3000.0 < offsetY and offsetY < 2000.0:
		maxVelY = 50.0
		if offsetY >= 0.0:
			maxVelY = 10000.0 / (offsetY + 200.0)
		if m.vel.y < maxVelY:
			m.vel.y += maxVelY / 8.0
			if m.vel.y > maxVelY:
				m.vel.y = maxVelY

# perform_air_step
fn performAirStep(mut m Mario, s Surfaces, stepArg i64):
	stepResult = airStepNone
	m.wall = -1
	loop 4:
		intendedPos = Vec3(
			m.pos.x + m.vel.x / 4.0,
			m.pos.y + m.vel.y / 4.0,
			m.pos.z + m.vel.z / 4.0
		)
		quarterStepResult = m.performAirQuarterStep(s, intendedPos, stepArg)
		if quarterStepResult != airStepNone:
			stepResult = quarterStepResult
		if quarterStepResult in [
			airStepLanded,
			airStepGrabbedLedge,
			airStepGrabbedCeiling,
			airStepHitLavaWall
		]:
			break
	if m.vel.y >= 0.0:
		m.peakHeight = m.pos.y
	if m.action != actFlying:
		m.applyGravity()
	m.applyVerticalWind(s)
	m.drawUpright()
	stepResult
