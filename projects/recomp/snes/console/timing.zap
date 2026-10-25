# Time, as the recompiled 65816 drives it. The API the CPU's side calls:
#
#   console.loadRom(path)            the cartridge, once at the start
#   console.hooks = Hooks(nmi = .., irq = .., irqAllowed = ..)
#                                    the handlers the hardware enters, and the I flag it asks
#   console.read8/read16(addr u32), console.write8/write16(addr u32, v)
#                                    the 24-bit address space with no time taken (memory.zap)
#   console.fetch/idle/cpuRead/cpuWrite  the CPU's bus cycles, each as long as Mesen 2 makes it
#                                    (bus.zap): the hardware runs through them
#   console.catchUp()                at an instruction's start once `cycles` reaches eventDue:
#                                    enters the interrupt the last cycles saw
#   console.waitForInterrupt()       WAI
#   console.runFrame(step)           a frame of idle cycles: step(line) runs at the start of each
#                                    line until the next vertical blank begins
#
# A frame is 262 lines of 1,364 master cycles (line 240 of every other frame 1,360). Each line
# refreshes the DRAM at 538 less the line's start modulo 8 (the CPU stalls 40 cycles), asks for its
# HDMA at 1104 (lines 0-224: the next line's writes) and ends: lines 1 to 224 are drawn, a write to
# the PPU mid-line drawing the line up to its dot first. Line 0 asks for the HDMA's tables at 12
# past its start modulo 8; line 225 starts the vertical blank: the frame is done (screen.zap shows
# and hashes it), the joypads are read and the NMI flag rises, which the NMI 4200 allows follows
# 6 cycles later. The H/V timer (4207-420A) raises the IRQ at its dot; hooks.irq() is entered while
# the flag is up (4211 read clears it) and the I flag is clear. All as Mesen 2 times them.

pub cyclesPerLine = 1364
resetCycles = 186   # the master cycles before the first instruction: Mesen's start-up
pub mut linesPerFrame = 262   # 312 on a PAL console (setRegion)
pub vblankLine = 225
hdmaInitAt = 12
refreshAt = 538
hdmaAt = 1104
nmiDelay = 6
shortLine = 240
never i64 = 0x7FFF_FFFF_FFFF_FFFF

pub mut cycles i64 = 0
pub mut line = 0
pub mut frameCount = 0
mut lineStart i64 = 0
mut clock i64 = 0      # the hardware's now: an event's time while it runs, else cycles
mut phase = 0          # the line's next event: 0 the HDMA's tables, 1 the refresh, 2 the HDMA, 3 its end
mut irqAt i64 = -1     # when the H/V timer fires on this line, -1 not on it
mut lineEventAt i64 = 0   # the line's next event
pub mut eventDue = never  # from when an instruction's start may have an interrupt to enter
pub mut pollsEach = false # every instruction's start polls (cpu's --steps)

# What the CPU's side gives the hardware.
pub type Hooks:
	nmi fn() = noHandler
	irq fn() = noHandler
	irqAllowed fn() bool = irqMasked   # the I flag clear

fn noHandler():
	pass

fn irqMasked():
	false

pub mut hooks = Hooks()

# the dot (a quarter of the line's master cycles) the hardware is at
# the PPU's odd-frame flag (213F bit 7, the short line): it flips as line 0 begins, while
# frameCount counts at the vertical blank's start
fn isOddFrame():
	(frameCount & 1 == 1) == (line < vblankLine)

# the dot the beam is at: 4 master cycles a dot, but dots 323 and 327 last 6 (Mesen 2's GetCycle)
pub fn dot() i64:
	h = clock - lineStart
	if h <= 1292: return h >> 2
	if h <= 1310: return (h - 2) >> 2
	(h - 4) >> 2

fn phaseAt():
	match phase:
		0: lineStart + hdmaInitAt + (lineStart & 7)
		1: lineStart + refreshAt - (lineStart & 7)
		2: lineStart + hdmaAt
		_: lineStart + lineLength()

# the line's length: line 240 of the frames Mesen calls odd is short when not interlaced
fn lineLength():
	if line == shortLine and isOddFrame() and ppuRegs[0x33] & 1 == 0: return cyclesPerLine - 4
	cyclesPerLine

# Runs the hardware's events up to `cycles`, each at its time; a refresh's stall moves `cycles` on.
pub fn advance():
	while true:
		at = lineEventAt
		if irqAt >= 0 and irqAt <= at and irqAt <= cycles:
			clock = irqAt
			irqAt = -1
			raiseIrq()
			continue
		if at > cycles: break
		clock = at
		runPhase()
		lineEventAt = phaseAt()
	clock = cycles

fn runPhase():
	match phase:
		0:
			phase = 1
			askHdmaInit()
		1:
			phase = 2 if line < vblankLine else 3
			cycles += 40
		2:
			phase = 3
			askHdma()
		_: endLine()

fn endLine():
	if line == 0: judgeScene()
	if line < vblankLine:
		drawTo(screenWidth - 1)
		evaluateSprites(line)
		stepMosaic()
	blankWrites.clear()
	if line == 0: startOutput()
	lineStart += lineLength()
	line += 1
	clock = lineStart
	phase = 1
	drawnTo = 0
	startFetch()
	if line == linesPerFrame:
		line = 0
		phase = 0
		nmiFlag = false
		rangeOver = false
		timeOver = false
	elif line == vblankLine:
		if not isBlanked(): oamInternal = oamAddress << 1
		frameCount += 1
		frameDone()
		clearBorders()
		vblankRegisters()
	scheduleIrq()

# The H/V timer's flag on this line, as 4200 and 4207-420A set it: 14 + 4 HTIME master cycles in
# (on line VTIME when V is on too), or 10 into line VTIME (6 into line 0), as Mesen 2's counters
# reach it.
fn scheduleIrq():
	irqAt = -1
	h = nmitimen & 0x10 != 0
	v = nmitimen & 0x20 != 0
	if not h and not v or v and line != vTime or h and hTime > 339: return
	at = lineStart + (hTime * 4 + 14 if h else 6 if line == 0 else 10)
	if at >= clock: irqAt = at

# the time from which an instruction's start polls: while an interrupt is wanted or a save state
# waits for it
fn updateDue():
	eventDue = 0 if isInterruptWanted() or stateArmed else never

# whether an instruction's start polls for the interrupts
pub fn isInterruptWanted() bool:
	needNmi or irqFlag and nmitimen & 0x30 != 0 or pollsEach

# At an instruction's start: the NMI or the IRQ the last cycles saw entered.
pub fn catchUp():
	advance()
	takeInterrupt()

fn takeInterrupt():
	if needNmi:
		needNmi = false
		updateDue()
		hooks.nmi()
	elif irqSeen: hooks.irq()

# WAI, after its fetch: an interrupt the fetch saw is entered at once, the CPU still halted (Mesen 2's
# order); then the CPU idles until a cycle sees an interrupt (a masked IRQ too, unentered) and
# idles once more, and the interrupt is entered.
pub fn waitForInterrupt():
	waiOver = false
	halted = true
	takeInterrupt()
	if halted: haltedSteps()
	takeInterrupt()

# the halted CPU's idle cycles, until one after a cycle that saw an interrupt
pub fn haltedSteps():
	rounds = 0
	while true:
		over = waiOver
		idle()
		if over: break
		rounds += 1
		if rounds > 3 * linesPerFrame * 230:
			fail("WAI with no interrupt that can come (4200 = 0x{nmitimen:02X})")
	halted = false

# Runs to the start of the next vertical blank, step(line) at the start of each line, the CPU
# idle between, its interrupts entered.
pub fn runFrame(step fn(i64)):
	target = frameCount + 1
	while frameCount < target:
		step(line)
		at = line
		while line == at and frameCount < target:
			idle()
			catchUp()

fn timingFields(mut f StateFile):
	cycles = f.int(cycles)
	line = f.int(line)
	frameCount = f.int(frameCount)
	lineStart = f.int(lineStart)
	clock = f.int(clock)
	phase = f.int(phase)
	irqAt = f.int(irqAt)
	lineEventAt = f.int(lineEventAt)

# The console as it powers on: memories cleared, registers zero, line 0 of frame 0.
pub fn powerOn():
	memoryPowerOn()
	vram = zeros(0x8000)
	cgram = zeros(256)
	oam = zeros(544)
	ppuRegs = zeros(0x40)
	ppuRegs[0] = 0x80
	dmaPowerOn()
	cpuLinesPowerOn()
	nmitimen = 0
	nmiFlag = false
	irqFlag = false
	spcPowerOn()
	mode7PowerOn()
	outputPowerOn()
	for bg in 0..4:
		hScroll[bg] = 0
		vScroll[bg] = 0
	fixedColor = 0
	cycles = resetCycles
	line = 0
	lineStart = 0
	clock = 0
	phase = 0
	irqAt = -1
	lineEventAt = phaseAt()
	frameCount = 0
	updateDue()
	drawnTo = 0
	startFetch()
	mosaicCounter = 0
	evaluateSprites(0)
