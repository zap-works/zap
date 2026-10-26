# Camera height, pan ahead, the behind-Mario mode and Lakitu flight (camera.c).

# approach_camera_height: the camera's height toward `goal` by `inc` (set at once while smooth
# movement is off)
fn approachCameraHeight(mut c Camera, goal f32, inc f32):
	if (c.statusFlags & camFlagSmoothMovement) != 0:
		if c.cPos.y < goal:
			c.cPos.y += inc
			if c.cPos.y > goal:
				c.cPos.y = goal
		else:
			c.cPos.y -= inc
			if c.cPos.y < goal:
				c.cPos.y = goal
	else:
		c.cPos.y = goal

# pan_ahead_of_player: the focus moved to the side Mario faces, up to about 30% of the camera's
# distance to him
fn panAheadOfPlayer(mut c Camera, m Mario):
	dist, _, yaw0 = c.cPos.vec3fGetDistAndAngle(m.camPos)
	yaw = yaw0
	pan = Vec3(0.0, 0.0, sins(0xC00) * dist)
	pan = pan.rotateInXz(m.camFaceYaw)
	yaw = i16.wrap(-yaw)
	pan = pan.rotateInXz(yaw)
	pan.z = 0.0
	# long jumping or on a pole (below its top): the other way
	if m.camAction == actLongJump or
		(m.camAction != actTopOfPole and (m.camAction & actFlagOnPole) != 0):
		pan.x = -pan.x
	if (c.statusFlags & camFlagSleeping) != 0:
		c.panDistance = approachF32Asymptotic(c.panDistance, 0.0, 0.025)
	else:
		c.panDistance = approachF32Asymptotic(c.panDistance, pan.x, 0.025)
	pan.x = c.panDistance
	yaw = i16.wrap(-yaw)
	pan = pan.rotateInXz(yaw)
	c.cFocus += pan

# ---------- behind Mario (on the water's surface) ----------

# mode_behind_mario: behind him and level with his pitch, over the water's surface while he swims
# at it
fn modeBehindMario(mut c Camera, m Mario, s Surfaces):
	c.movementFlags &= ~camMovingIntoMode
	yaw, pos = c.updateBehindMarioCamera(m, c.cPos)
	newPos = pos
	c.cPos.x = newPos.x
	c.cPos.z = newPos.z
	if c.mode == cameraModeWaterSurface:
		floor, _ = s.findFloor(c.cPos.x, c.cPos.y, c.cPos.z, forCamera = true)
		newPos.y = f32(m.waterLevel + 120)
		floorHeight = floor + 120.0
		if newPos.y < floorHeight:
			newPos.y = floorHeight
	c.approachCameraHeight(newPos.y, 50.0)
	waterHeight = s.waterLevel(c.cPos.x, c.cPos.z) + 100.0
	if c.cPos.y <= waterHeight:
		c.movementFlags |= camMoveSubmerged
	else:
		c.movementFlags &= ~camMoveSubmerged
	c.cPos = s.resolveGeometryCollisions(c.cPos)
	# not too far away
	distCamToFocus, camPitch, camYaw = c.cFocus.vec3fGetDistAndAngle(c.cPos)
	if distCamToFocus > 800.0:
		c.cPos = c.cFocus.vec3fSetDistAndAngle(800.0, camPitch, camYaw)
	c.panAheadOfPlayer(m)
	yaw

# update_behind_mario_camera: the focus on Mario, the camera turned toward his back and his pitch
# (the C buttons turn it about); its yaw and place
fn updateBehindMarioCamera(mut c Camera, m Mario, pos Vec3):
	goalPitch i64 = i16.wrap(-m.camFacePitch)
	marioYaw i64 = i16.wrap(m.camFaceYaw + 0x8000)
	goalYawOff = 0
	pitchInc = 32
	maxDist f32 = 800.0
	focYOff f32 = 125.0
	# (Mario's camera, closer: not ported)
	if (m.camAction & (actFlagSwimming | actFlagMetalWater)) == 0:
		pitchInc = 128
	c.cFocus = m.camPos
	c.cFocus.y += focYOff
	dist0, pitch0, yaw0 = c.cFocus.vec3fGetDistAndAngle(pos)
	dist = dist0
	pitch = pitch0
	yaw = yaw0
	if dist > maxDist:
		dist = maxDist
	absPitch i64 = i16.wrap(pitch.abs())
	# further from level, slower
	yawSpeed = 32 - absPitch / 0x200
	if yawSpeed < 1:
		yawSpeed = 1
	if yawSpeed > 32:
		yawSpeed = 32
	if c.cSideButtonYaw != 0:
		c.cSideButtonYaw = cameraApproachS16Symmetric(c.cSideButtonYaw, 0, 1)
		yawSpeed = 8
	if c.behindMarioSoundTimer != 0:
		goalPitch = 0
		c.behindMarioSoundTimer = cameraApproachS16Symmetric(c.behindMarioSoundTimer, 0, 1)
		pitchInc = 0x800
	# the C buttons turn it the other way (airplane controls)
	if (c.cButtonsPressed & cButtonLeft) != 0:
		if dist < maxDist:
			dist = cameraApproachF32Symmetric(dist, maxDist, 5.0)
		goalYawOff = -0x3FF8
		c.cSideButtonYaw = 30
		yawSpeed = 2
	if (c.cButtonsPressed & cButtonRight) != 0:
		if dist < maxDist:
			dist = cameraApproachF32Symmetric(dist, maxDist, 5.0)
		goalYawOff = 0x3FF8
		c.cSideButtonYaw = 30
		yawSpeed = 2
	if (c.cButtonsPressed & cButtonDown) != 0:
		if dist < maxDist:
			dist = cameraApproachF32Symmetric(dist, maxDist, 5.0)
		goalPitch = -0x3000
		c.behindMarioSoundTimer = 30
		pitchInc = 0x800
	if (c.cButtonsPressed & cButtonUp) != 0:
		if dist < maxDist:
			dist = cameraApproachF32Symmetric(dist, maxDist, 5.0)
		goalPitch = 0x3000
		c.behindMarioSoundTimer = 30
		pitchInc = 0x800
	yaw = approachS16Asymptotic(yaw, i16.wrap(marioYaw + goalYawOff), yawSpeed)
	pitch = cameraApproachS16Symmetric(pitch, goalPitch, pitchInc)
	if dist < 300.0:
		dist = 300.0
	(yaw, c.cFocus.vec3fSetDistAndAngle(dist, pitch, yaw))

# resolve_geometry_collisions: `pos` out of the walls, between the floor and the ceiling there
fn resolveGeometryCollisions(s Surfaces, pos0 Vec3):
	pos = pos0
	w = s.findWallCollisions(pos.x, pos.y, pos.z, 0.0, 100.0, true)
	pos.x = w.x
	pos.z = w.z
	floor, _ = s.findFloor(pos.x, pos.y + 50.0, pos.z, forCamera = true)
	ceil, _ = s.findCeiling(pos.x, pos.y - 50.0, pos.z, forCamera = true)
	floorY = floor
	ceilY = ceil
	if floorY != floorLowerLimit and ceilY == ceilingLimit:
		floorY += 125.0
		if pos.y < floorY:
			pos.y = floorY
	if floorY == floorLowerLimit and ceilY != ceilingLimit:
		ceilY -= 125.0
		if pos.y > ceilY:
			pos.y = ceilY
	if floorY != floorLowerLimit and ceilY != ceilingLimit:
		floorY += 125.0
		ceilY -= 125.0
		if pos.y <= floorY and pos.y < ceilY:
			pos.y = floorY
		if pos.y > floorY and pos.y >= ceilY:
			pos.y = ceilY
		if pos.y <= floorY and pos.y >= ceilY:
			pos.y = (floorY + ceilY) * 0.5
	pos

# ---------- Lakitu ----------

# update_lakitu: Lakitu flies toward the camera's place and focus (all at once while smooth
# movement is off), kept 100 units over the floor, his pitch held within about 87 degrees
fn updateLakitu(mut c Camera, m Mario, s Surfaces):
	newPos, newFoc, newYaw = c.nextLakituState(m, s)
	c.yaw = c.setOrApproachS16Symmetric(c.yaw, newYaw, c.yawSpeed)
	c.oldPosition = newPos
	c.oldFocus = newFoc
	c.lakituYaw = c.yaw
	c.lakituNextYaw = c.nextYaw
	c.goalPos = c.cPos
	c.goalFocus = c.cFocus
	c.curPos.x = c.setOrApproachF32Asymptotic(c.curPos.x, newPos.x, c.posHSpeed)
	c.curPos.y = c.setOrApproachF32Asymptotic(c.curPos.y, newPos.y, c.posVSpeed)
	c.curPos.z = c.setOrApproachF32Asymptotic(c.curPos.z, newPos.z, c.posHSpeed)
	c.curFocus.x = c.setOrApproachF32Asymptotic(c.curFocus.x, newFoc.x, c.focHSpeed)
	c.curFocus.y = c.setOrApproachF32Asymptotic(c.curFocus.y, newFoc.y, c.focVSpeed)
	c.curFocus.z = c.setOrApproachF32Asymptotic(c.curFocus.z, newFoc.z, c.focHSpeed)
	# Lakitu's speeds back to normal
	c.focHSpeed = c.setOrApproachF32Asymptotic(c.focHSpeed, 0.8, 0.05)
	c.focVSpeed = c.setOrApproachF32Asymptotic(c.focVSpeed, 0.3, 0.05)
	c.posHSpeed = c.setOrApproachF32Asymptotic(c.posHSpeed, 0.3, 0.05)
	c.posVSpeed = c.setOrApproachF32Asymptotic(c.posVSpeed, 0.3, 0.05)
	# smooth movement on unless it was blocked this frame
	if (c.statusFlags & camFlagBlockSmoothMovement) != 0:
		c.statusFlags &= ~camFlagBlockSmoothMovement
	else:
		c.statusFlags |= camFlagSmoothMovement
	c.pos = c.curPos
	c.focus = c.curFocus
	# (shakes: none is ported, nor the one a dive starts)
	if c.mode != cameraModeCUp and c.cutscene == 0:
		floor, _ = s.findFloor(c.pos.x, c.pos.y + 20.0, c.pos.z, forCamera = true)
		if floor != floorLowerLimit:
			distToFloor = floor + 100.0
			if c.pos.y < distToFloor:
				c.pos.y = distToFloor
	c.transitionMarioPos = m.camPos
	c.focus = c.pos.clampPitch(c.focus, 0x3E00, -0x3E00)
	c.lakituMode = c.mode
	c.lakituDefMode = c.defMode

# next_lakitu_state: Lakitu's next place and focus (the camera's, unless a transition from the last
# mode flies him there over its frames) and his yaw
fn nextLakituState(mut c Camera, m Mario, s Surfaces):
	curPos = c.cPos
	curFoc = c.cFocus
	newPos = curPos
	newFoc = curFoc
	yaw = c.nextYaw
	distTimer = f32(c.framesLeft)
	angleTimer i64 = i16.wrap(c.framesLeft)
	if (c.statusFlags & camFlagStartTransition) != 0:
		# from where the camera would have moved: last frame's state carried along with Mario
		startPos = c.oldPosition + m.camPos - c.transitionMarioPos
		startFoc = c.oldFocus + m.camPos - c.transitionMarioPos
		focDist, focPitch, focYaw = curFoc.vec3fGetDistAndAngle(startFoc)
		c.transFocDist = focDist
		c.transFocPitch = focPitch
		c.transFocYaw = focYaw
		posDist, posPitch, posYaw = curFoc.vec3fGetDistAndAngle(startPos)
		c.transPosDist = posDist
		c.transPosPitch = posPitch
		c.transPosYaw = posYaw
		c.statusFlags &= ~camFlagStartTransition
	if c.framesLeft > 0:
		goalDist, goalPitch, goalYaw = curFoc.vec3fGetDistAndAngle(curPos)
		distVelocity = (goalDist - c.transPosDist).abs() / distTimer
		pitchVelocity i64 = i16.wrap((goalPitch - c.transPosPitch).abs() / angleTimer)
		yawVelocity i64 = i16.wrap((goalYaw - c.transPosYaw).abs() / angleTimer)
		c.transPosDist = cameraApproachF32Symmetric(c.transPosDist, goalDist, distVelocity)
		c.transPosYaw = cameraApproachS16Symmetric(c.transPosYaw, goalYaw, yawVelocity)
		c.transPosPitch = cameraApproachS16Symmetric(c.transPosPitch, goalPitch, pitchVelocity)
		nextPos = curFoc.vec3fSetDistAndAngle(c.transPosDist, c.transPosPitch, c.transPosYaw)
		_, focGoalPitch, focGoalYaw = curPos.vec3fGetDistAndAngle(curFoc)
		focPitchVelocity i64 = i16.wrap(c.transFocPitch / i16.wrap(c.framesLeft))
		focYawVelocity i64 = i16.wrap(c.transFocYaw / i16.wrap(c.framesLeft))
		focDistVelocity = c.transFocDist / f32(c.framesLeft)
		c.transFocPitch = cameraApproachS16Symmetric(
			c.transFocPitch,
			focGoalPitch,
			focPitchVelocity
		)
		c.transFocYaw = cameraApproachS16Symmetric(c.transFocYaw, focGoalYaw, focYawVelocity)
		c.transFocDist = cameraApproachF32Symmetric(c.transFocDist, 0.0, focDistVelocity)
		nextFoc = curFoc.vec3fSetDistAndAngle(c.transFocDist, c.transFocPitch, c.transFocYaw)
		newFoc = nextFoc
		newPos = nextPos
		if c.cutscene != 0 or (c.movementFlags & camMoveCUpMode) == 0:
			floor, _ = s.findFloor(newPos.x, newPos.y, newPos.z)
			if floor != floorLowerLimit:
				above = floor + 125.0
				if above > newPos.y:
					newPos.y = above
			w = s.findWallCollisions(newPos.x, newPos.y, newPos.z, 0.0, 100.0, false)
			newPos.x = w.x
			newPos.z = w.z
		c.framesLeft -= 1
		yaw = newFoc.calculateYaw(newPos)
	else:
		c.transPosDist = 0.0
		c.transPosPitch = 0
		c.transPosYaw = 0
		c.statusFlags &= ~camFlagTransitionOutOfCUp
	c.transitionMarioPos = m.camPos
	(newPos, newFoc, yaw)
