# Mario animation playback: choosing, setting and advancing an animation (mario.c).

import n64

fn animOf(anims {i64: n64.Animation}, id i64) ref n64.Animation:
	anims.get(id) ?? fail("Mario's animation {id} was not read")

# the animation `id` becomes his, its header's numbers kept (curAnim)
fn takeAnimation(mut m Mario, anims {i64: n64.Animation}, id i64):
	a = animOf(anims, id)
	m.anim = id
	m.animFlags = a.flags
	m.animStart = a.startFrame
	m.animLoopStart = a.loopStart
	m.animLoopEnd = a.loopEnd

# set_mario_animation: from the frame before its first (the drawing steps onto it)
fn setMarioAnimation(mut m Mario, anims {i64: n64.Animation}, id i64):
	if m.anim != id:
		m.takeAnimation(anims, id)
		m.animAccel = 0
		if (m.animFlags & animFlagFrozen) != 0:
			m.animFrame = m.animStart
		elif (m.animFlags & animFlagForward) != 0:
			m.animFrame = m.animStart + 1
		else:
			m.animFrame = m.animStart - 1
	m.animFrame

# set_mario_anim_with_accel: played `accel` frames a frame (0x10000 one)
fn setMarioAnimWithAccel(mut m Mario, anims {i64: n64.Animation}, id i64, accel i64):
	if m.anim != id:
		m.takeAnimation(anims, id)
		if (m.animFlags & animFlagFrozen) != 0:
			m.animAssist = m.animStart << 16
		elif (m.animFlags & animFlagForward) != 0:
			m.animAssist = (m.animStart << 16) + accel
		else:
			m.animAssist = (m.animStart << 16) - accel
		m.animFrame = i16.wrap(m.animAssist >> 16)
	m.animAccel = accel
	m.animFrame

# set_anim_to_frame: the animation moved so that the next step lands on `animFrame`
fn setAnimToFrame(mut m Mario, animFrame i64):
	if m.animAccel != 0:
		if (m.animFlags & animFlagForward) != 0:
			m.animAssist = (animFrame << 16) + m.animAccel
		else:
			m.animAssist = (animFrame << 16) - m.animAccel
	else:
		if (m.animFlags & animFlagForward) != 0:
			m.animFrame = animFrame + 1
		else:
			m.animFrame = animFrame - 1

# is_anim_at_end
fn isAnimAtEnd(m Mario):
	m.animFrame + 1 == m.animLoopEnd

# is_anim_past_end
fn isAnimPastEnd(m Mario):
	m.animFrame >= m.animLoopEnd - 2

# is_anim_past_frame: whether the last step of the animation went over `animFrame`
fn isAnimPastFrame(m Mario, animFrame i64):
	acceleratedFrame = animFrame << 16
	if m.animAccel != 0:
		if (m.animFlags & animFlagForward) != 0:
			return m.animAssist > acceleratedFrame and
				acceleratedFrame >= m.animAssist - m.animAccel
		return m.animAssist < acceleratedFrame and acceleratedFrame <= m.animAssist + m.animAccel
	if (m.animFlags & animFlagForward) != 0: return m.animFrame == animFrame + 1
	m.animFrame + 1 == animFrame

# a 32-bit value whose upper 16 bits are replaced (SET_HIGH_S16_OF_32)
fn withHigh16(v i64, high i64) i64:
	i32.wrap((high << 16) | (v & 0xFFFF))

# geo_update_animation_frame: the frame after this one, on by its speed, around its loop or
# held at its end
fn advanceAnimation(mut m Mario):
	if m.anim < 0 or (m.animFlags & animFlagFrozen) != 0: return
	result = 0
	if (m.animFlags & animFlagForward) != 0:
		result = m.animAssist - m.animAccel if m.animAccel != 0 else (m.animFrame - 1) << 16
		if i16.wrap(result >> 16) < m.animLoopStart:
			result = withHigh16(
				result,
				m.animLoopStart if (m.animFlags & animFlagNoLoop) != 0 else m.animLoopEnd - 1
			)
	else:
		result = m.animAssist + m.animAccel if m.animAccel != 0 else (m.animFrame + 1) << 16
		if i16.wrap(result >> 16) >= m.animLoopEnd:
			result = withHigh16(
				result,
				m.animLoopEnd - 1 if (m.animFlags & animFlagNoLoop) != 0 else m.animLoopStart
			)
	m.animAssist = i32.wrap(result)
	m.animFrame = i16.wrap(result >> 16)
