# Camera math: pitch clamp, distances, rotation and approach functions (camera.c).

# clamp_pitch: `to` set again about `from` at the same distance, its pitch held within bounds
fn clampPitch(from Vec3, to Vec3, maxPitch i64, minPitch i64):
	dist, pitch0, yaw = from.vec3fGetDistAndAngle(to)
	pitch = pitch0
	if pitch > maxPitch:
		pitch = maxPitch
	if pitch < minPitch:
		pitch = minPitch
	from.vec3fSetDistAndAngle(dist, pitch, yaw)

# ---------- camera.c's arithmetic ----------

# is_within_100_units_of_mario
fn isWithin100UnitsOfMario(m Mario, pos Vec3):
	m.camPos.calcAbsDist(pos) < 100.0

# offset_rotated: `to` turned by the pitch (its z flipped) and the yaw, added to `from`
fn offsetRotated(from Vec3, to Vec3, pitch i64, yaw i64):
	pitchedZ = -(to.z * coss(pitch) - to.y * sins(pitch))
	pitchedY = to.z * sins(pitch) + to.y * coss(pitch)
	pitchedX = to.x
	Vec3(
		from.x + pitchedZ * sins(yaw) + pitchedX * coss(yaw),
		from.y + pitchedY,
		from.z + pitchedZ * coss(yaw) - pitchedX * sins(yaw)
	)

# calculate_yaw
fn calculateYaw(from Vec3, to Vec3):
	atan2s(to.z - from.z, to.x - from.x)

# calc_abs_dist
fn calcAbsDist(a Vec3, b Vec3):
	dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
	(dx * dx + dy * dy + dz * dz).sqrt()

# calc_hor_dist
fn calcHorDist(a Vec3, b Vec3):
	dx, dz = b.x - a.x, b.z - a.z
	(dx * dx + dz * dz).sqrt()

# rotate_in_xz
fn rotateInXz(v Vec3, yaw i64):
	Vec3(v.z * sins(yaw) + v.x * coss(yaw), v.y, v.z * coss(yaw) - v.x * sins(yaw))

# scale_along_line
fn scaleAlongLine(from Vec3, to Vec3, scale f32):
	Vec3(
		(to.x - from.x) * scale + from.x,
		(to.y - from.y) * scale + from.y,
		(to.z - from.z) * scale + from.z
	)

# approach_f32_asymptotic_bool: a share of the way to the target (at most all of it)
fn approachF32Asymptotic(current f32, target f32, multiplier0 f32):
	multiplier = multiplier0
	if multiplier > 1.0:
		multiplier = 1.0
	current + (target - current) * multiplier

# set_or_approach_f32_asymptotic: approached while smooth movement is on, set otherwise
fn setOrApproachF32Asymptotic(c Camera, dst f32, goal f32, scale f32):
	approachF32Asymptotic(dst, goal, scale) if (c.statusFlags & camFlagSmoothMovement) != 0
		else goal

# approach_s16_asymptotic_bool: a 1/divisor share of the way, in 16 bits
fn approachS16Asymptotic(current i64, target i64, divisor i64) i64:
	if divisor == 0: return target
	temp i64 = i16.wrap(current - target)
	temp = i16.wrap(temp - temp / divisor)
	i16.wrap(temp + target)

# camera_approach_s16_symmetric_bool: by `increment` toward the target, in 16 bits
fn cameraApproachS16Symmetric(current i64, target i64, increment0 i64) i64:
	dist i64 = i16.wrap(target - current)
	increment = -increment0 if increment0 < 0 else increment0
	if dist > 0:
		dist = i16.wrap(dist - increment)
		return i16.wrap(target - dist) if dist >= 0 else target
	dist = i16.wrap(dist + increment)
	i16.wrap(target - dist) if dist <= 0 else target

# set_or_approach_s16_symmetric
fn setOrApproachS16Symmetric(c Camera, current i64, target i64, increment i64):
	cameraApproachS16Symmetric(current, target, increment) if (
		c.statusFlags & camFlagSmoothMovement
	) !=
		0
		else target

# camera_approach_f32_symmetric_bool
fn cameraApproachF32Symmetric(current f32, target f32, increment0 f32):
	dist = target - current
	increment = increment0
	if increment < 0.0:
		increment = -1.0 * increment
	if dist > 0.0:
		dist -= increment
		return target - dist if dist > 0.0 else target
	dist += increment
	target - dist if dist < 0.0 else target
