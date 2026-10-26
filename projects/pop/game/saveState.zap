# The game's state as bytes (SDLPoP's seg000.c quick_process): what QUICKSAVE.SAV and a replay's
# savestate hold, in the order and with the widths of the C variables, so SDLPoP's files read here
# and these read there.

import dos.pop

pub quickVersion = "V1.16b4 "
# SDLPoP's sequence table lies 0x10C before v1.4's: its sequence addresses are these less that
seqShift = 0x10C
torchColorsSize = 25 * 30
superJumpSize = 5

fn pushChar(mut out u8[], c CharType):
	out.push(u8.wrap(c.frame))
	out.push(u8.wrap(c.x))
	out.push(u8.wrap(c.y))
	out.push(u8.wrap(c.direction & 0xFF))
	out.push(u8.wrap(c.currCol & 0xFF))
	out.push(u8.wrap(c.currRow & 0xFF))
	out.push(u8.wrap(c.action))
	out.push(u8.wrap(c.fallX & 0xFF))
	out.push(u8.wrap(c.fallY & 0xFF))
	out.push(u8.wrap(c.room))
	out.push(u8.wrap(c.repeat))
	out.push(u8.wrap(c.charid))
	out.push(u8.wrap(c.sword))
	out.push(u8.wrap(c.alive & 0xFF))
	out.pushU16le(c.currSeq - seqShift if c.currSeq != 0 else 0)

fn readChar(mut r Reader):
	c = CharType(
		frame = r.u8(),
		x = r.u8(),
		y = r.u8(),
		direction = r.i8(),
		currCol = r.i8(),
		currRow = r.i8(),
		action = r.u8(),
		fallX = r.i8(),
		fallY = r.i8(),
		room = r.u8(),
		repeat = r.u8(),
		charid = r.u8(),
		sword = r.u8(),
		alive = r.i8(),
		currSeq = r.u16()
	)
	if c.currSeq != 0: c.currSeq += seqShift
	c

fn pushBytes(mut out u8[], xs i64[]):
	for x in xs:
		out.push(u8.wrap(x & 0xFF))

fn readSigned(mut r Reader, n i64):
	xs i64[] = []
	loop n:
		xs.push(r.i8())
	xs

fn readBytes(mut r Reader, n i64):
	xs i64[] = []
	loop n:
		xs.push(r.u8())
	xs

# quick_process writing: the state, as the bytes of a savestate
pub fn savestate(g Game) u8[]:
	out u8[] = g.level.bytesOf()
	for v in [g.checkpoint, g.upsideDown, g.drawnRoom, g.currentLevel, g.nextLevel]:
		out.pushU16le(v)
	out.pushU16le(g.mobs.len)
	for i in 0..14:
		m = g.mobs[i] if i < g.mobs.len else Mob()
		out.push(u8.wrap(m.xh))
		out.push(u8.wrap(m.y))
		out.push(u8.wrap(m.room))
		out.push(u8.wrap(m.speed & 0xFF))
		out.push(u8.wrap(m.mobType))
		out.push(u8.wrap(m.row))
	out.pushU16le(g.trobs.len)
	for i in 0..30:
		t = g.trobs[i] if i < g.trobs.len else Trob()
		out.push(u8.wrap(t.tilepos))
		out.push(u8.wrap(t.room))
		out.push(u8.wrap(t.trobType & 0xFF))
	out.pushU16le(g.leveldoorOpen)
	out.pushChar(g.kid)
	for v in [
		g.hitpCurr,
		g.hitpMax,
		g.hitpBegLev,
		g.grabTimer,
		g.holdingSword,
		g.unitedWithShadow,
		g.haveSword
	]:
		out.pushU16le(v)
	for v in [g.kidSwordStrike, g.pickupObjType, g.offguard]:
		out.pushU16le(v)
	out.pushChar(g.guard)
	out.pushChar(g.char)
	out.pushChar(g.opp)
	for v in [
		g.guardhpCurr,
		g.guardhpMax,
		g.demoIndex,
		g.demoTime,
		g.currGuardColor,
		g.guardNoticeTimer,
		g.guardSkill,
		g.shadowInitialized,
		g.guardRefrac,
		g.justblocked,
		g.droppedout
	]:
		out.pushU16le(v)
	out.pushBytes(g.currRowCollRoom)
	out.pushBytes(g.currRowCollFlags)
	out.pushBytes(g.belowRowCollRoom)
	out.pushBytes(g.belowRowCollFlags)
	out.pushBytes(g.aboveRowCollRoom)
	out.pushBytes(g.aboveRowCollFlags)
	out.pushBytes([g.prevCollisionRow])
	for v in [
		g.flashColor,
		g.flashTime,
		g.needLevel1Music,
		g.isScreaming,
		g.isFeatherFall,
		g.lastLooseSound
	]:
		out.pushU16le(v)
	out.pushU32le(g.randomSeed)
	out.pushU16le(g.remMin)
	out.pushU16le(g.remTick)
	out.pushBytes(
		[
			g.controlX,
			g.controlY,
			g.controlShift,
			g.controlForward,
			g.controlBackward,
			g.controlUp,
			g.controlDown,
			g.controlShift2,
			g.ctrl1Forward,
			g.ctrl1Backward,
			g.ctrl1Up,
			g.ctrl1Down,
			g.ctrl1Shift2
		]
	)
	out.pushU32le(g.currTick)
	out.extend(zeros(torchColorsSize))
	out.extend(zeros(superJumpSize))
	out.pushU16le(g.isGuardNotice)
	out.pushU16le(g.canGuardSeeKid)
	out

# quick_process reading: the state set from a savestate's bytes; false when they are too short
# (a savestate of a build without the torch colours or the super high jump lacks those fields)
pub fn loadSavestate(mut g Game, b u8[]) bool:
	if b.len < 2305 + 120: return false
	r = Reader(d = b)
	g.level = pop.levelOf(r.bytes(2305))
	g.checkpoint = r.u16()
	g.upsideDown = r.u16()
	g.drawnRoom = r.u16()
	g.currentLevel = r.u16()
	g.nextLevel = r.u16()
	mobCount = r.i16()
	g.mobs = []
	for i in 0..14:
		m = Mob(
			xh = r.u8(),
			y = r.u8(),
			room = r.u8(),
			speed = r.i8(),
			mobType = r.u8(),
			row = r.u8()
		)
		if i < mobCount: g.mobs.push(m)
	trobCount = r.i16()
	g.trobs = []
	for i in 0..30:
		t = Trob(tilepos = r.u8(), room = r.u8(), trobType = r.i8())
		if i < trobCount: g.trobs.push(t)
	g.leveldoorOpen = r.u16()
	g.kid = r.readChar()
	g.hitpCurr = r.u16()
	g.hitpMax = r.u16()
	g.hitpBegLev = r.u16()
	g.grabTimer = r.u16()
	g.holdingSword = r.u16()
	g.unitedWithShadow = r.i16()
	g.haveSword = r.u16()
	g.kidSwordStrike = r.u16()
	g.pickupObjType = r.i16()
	g.offguard = r.u16()
	g.guard = r.readChar()
	g.char = r.readChar()
	g.opp = r.readChar()
	g.guardhpCurr = r.u16()
	g.guardhpMax = r.u16()
	g.demoIndex = r.u16()
	g.demoTime = r.i16()
	g.currGuardColor = r.u16()
	g.guardNoticeTimer = r.i16()
	g.guardSkill = r.u16()
	g.shadowInitialized = r.u16()
	g.guardRefrac = r.u16()
	g.justblocked = r.u16()
	g.droppedout = r.u16()
	g.currRowCollRoom = r.readSigned(10)
	g.currRowCollFlags = r.readBytes(10)
	g.belowRowCollRoom = r.readSigned(10)
	g.belowRowCollFlags = r.readBytes(10)
	g.aboveRowCollRoom = r.readSigned(10)
	g.aboveRowCollFlags = r.readBytes(10)
	g.prevCollisionRow = r.i8()
	g.flashColor = r.u16()
	g.flashTime = r.u16()
	g.needLevel1Music = r.u16()
	g.isScreaming = r.u16()
	g.isFeatherFall = r.u16()
	g.lastLooseSound = r.u16()
	g.randomSeed = r.u32()
	g.remMin = r.i16()
	g.remTick = r.u16()
	g.controlX = r.i8()
	g.controlY = r.i8()
	g.controlShift = r.i8()
	g.controlForward = r.i8()
	g.controlBackward = r.i8()
	g.controlUp = r.i8()
	g.controlDown = r.i8()
	g.controlShift2 = r.i8()
	g.ctrl1Forward = r.i8()
	g.ctrl1Backward = r.i8()
	g.ctrl1Up = r.i8()
	g.ctrl1Down = r.i8()
	g.ctrl1Shift2 = r.i8()
	g.currTick = r.u32()
	# the torch colours and the super high jump's fields lie there in some builds, in others not
	r.skip((b.len - r.at - 4).max(0))
	g.isGuardNotice = r.u16()
	g.canGuardSeeKid = r.i16()
	true
