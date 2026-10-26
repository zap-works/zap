# Mario per-frame upkeep: squish, submerged camera preset, health, hitbox and the object copy (mario.c).

# squish_mario_model: the count of frames he stays squashed (the drawing's scale is not ported)
fn squishMarioModel(mut m Mario):
	if m.squishTimer != 0xFF and m.squishTimer != 0:
		m.squishTimer -= 1

# set_submerged_cam_preset_and_spawn_bubbles: deep under the water the camera goes behind him,
# near its surface it comes back to the surface's (the bubbles are not ported)
fn setSubmergedCamPresetAndSpawnBubbles(m Mario, mut cam Camera):
	if (m.action & actGroupMask) != actGroupSubmerged: return
	heightBelowWater = f32(m.waterLevel - 80) - m.pos.y
	camPreset = cam.mode
	if (m.action & actFlagMetalWater) != 0:
		if camPreset != cameraModeClose:
			cam.setCameraMode(cameraModeClose, 1)
	else:
		if heightBelowWater > 800.0 and camPreset != cameraModeBehindMario:
			cam.setCameraMode(cameraModeBehindMario, 1)
		if heightBelowWater < 400.0 and camPreset != cameraModeWaterSurface:
			cam.setCameraMode(cameraModeWaterSurface, 1)

# update_mario_health: hurt and healed 0x40 a frame while the counters run; otherwise the poison
# gas hurts, and the water too unless he swims at its surface, where he heals (the alarm near
# drowning is not ported)
fn updateMarioHealth(mut m Mario, s Surfaces):
	if m.health < 0x100: return
	if (m.healCounter | m.hurtCounter) == 0:
		if (m.input & inputInPoisonGas) != 0 and (m.action & actFlagIntangible) == 0:
			if (m.flags & marioMetalCap) == 0:
				m.health -= 4
		elif (m.action & actFlagSwimming) != 0 and (m.action & actFlagIntangible) == 0:
			terrainIsSnow = (terrainType & 7) == terrainSnow
			if m.pos.y >= f32(m.waterLevel - 140) and not terrainIsSnow:
				m.health += 0x1A
			else:
				m.health -= 3 if terrainIsSnow else 1
	if m.healCounter > 0:
		m.health += 0x40
		m.healCounter -= 1
	if m.hurtCounter > 0:
		m.health -= 0x40
		m.hurtCounter -= 1
	if m.health >= 0x881:
		m.health = 0x880
	if m.health < 0x100:
		m.health = 0xFF

# mario_update_hitbox_and_cap_model: his object's height, shorter while he crouches or crawls
# (the caps' looks and the flicker while invincible are not ported)
fn marioUpdateHitboxAndCapModel(m Mario, mut objs Objects):
	objs.all[0].hitboxHeight = 160.0
	if (m.action & actFlagShortHitbox) != 0:
		objs.all[0].hitboxHeight = 100.0

# copy_mario_state_to_object: his object takes his place
fn copyMarioStateToObject(m Mario, mut objs Objects):
	objs.all[0].pos = m.pos

# ---------- animation ----------
