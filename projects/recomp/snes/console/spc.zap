# The SPC700, the sound CPU: 64 KB of RAM, the 64-byte boot ROM at FFC0, three timers and the four
# ports to the 65816 (2140-2143), run an instruction at a time in the order of its bus cycles
# (spcOps.zap), timed as Mesen 2 runs it: a bus cycle is 2 ticks of a 2.05056 MHz clock (64 ticks
# a sample at Mesen's 32,040 Hz, to the console's 21,477,270 master cycles a second), the timers
# step on its ticks (8 kHz: every 256, 64 kHz: every 32) and the DSP makes a sample every 64
# (dsp.zap).
#
# The CPU's side brings it up to date when it touches a port (spcRunTo): Mesen then has run the
# SPC700's bus cycles up to the tick the access lands on (`caughtUp`). An instruction that crosses
# that tick runs whole here, so one that reads or writes a port past it is undone and runs again at
# the next catch-up. A CPU write reaches the SPC700's next bus cycle when it lands in the first half
# of an SPC700 cycle, else the one after (Mesen's latch, which a step with no bus cycle applies too).

pub sampleRate = 32_040
mut spcTicksPerMaster = (sampleRate * 64) / ntscMasterRate
longestInstruction = 24   # DIV's 12 bus cycles, in ticks
ticksPerSample = 64

# the program status word: carry, zero, interrupts on, half carry, break, direct page 1, overflow,
# negative
type Psw bits u8:
	c bool = 0
	z bool = 1
	i bool = 2
	h bool = 3
	b bool = 4
	p bool = 5
	v bool = 6
	n bool = 7

# the boot ROM, as fullsnes lists it: clears the zero page, shows 0xAA 0xBB on ports 0 and 1, takes
# blocks of bytes through the ports and jumps to the address the last one names
iplRom u8[] = [
	0xCD, 0xEF, 0xBD, 0xE8, 0x00, 0xC6, 0x1D, 0xD0, 0xFC, 0x8F, 0xAA, 0xF4, 0x8F, 0xBB, 0xF5, 0x78,
	0xCC, 0xF4, 0xD0, 0xFB, 0x2F, 0x19, 0xEB, 0xF4, 0xD0, 0xFC, 0x7E, 0xF4, 0xD0, 0x0B, 0xE4, 0xF5,
	0xCB, 0xF4, 0xD7, 0x00, 0xFC, 0xD0, 0xF3, 0xAB, 0x01, 0x10, 0xEF, 0x7E, 0xF4, 0x10, 0xEB, 0xBA,
	0xF6, 0xDA, 0x00, 0xBA, 0xF4, 0xC4, 0xF4, 0xDD, 0x5D, 0xD0, 0xDB, 0x1F, 0x00, 0x00, 0xC0, 0xFF
]

# A timer: its 8 or 64 kHz clock falls every `period` ticks; each fall while it is on steps its
# divider, which at the target (0 is 256) steps the 4-bit output that F0-FF read and clear.
type SpcTimer:
	period i64
	on bool = false
	target i64 = 0
	steps i64 = 0
	output i64 = 15
	countedTo i64 = 0   # the tick its falls are counted up to

# The SPC700's registers and the state an undone instruction puts back.
type SpcState:
	a i64 = 0
	x i64 = 0
	y i64 = 0
	sp i64 = 0xFF
	pc i64 = 0xFFC0
	psw Psw = Psw(0)
	tick i64 = 4   # Mesen's power-on reads the reset vector: two bus cycles
	zeroStepAt i64 = -1   # the tick of the bus cycle a step with none followed last
	dspAddress i64 = 0
	romOn bool = true
	ramWritable bool = true
	timersCount bool = true   # F0's timer bits
	outPorts i64[4] = [0, 0, 0, 0]
	auxPorts i64[2] = [0, 0]
	timers SpcTimer[3] = [SpcTimer(period = 256), SpcTimer(period = 256), SpcTimer(period = 32)]

# A CPU write to a port: Mesen's SPC700 tick when it landed, and whether it shows a bus cycle late.
type PortWrite:
	port i64
	value i64
	from i64
	late bool

pub mut spcRam u8[] = zeros(0x1_0000)
mut spc = SpcState()
mut caughtUp i64 = 0   # Mesen's SPC700 tick at the CPU's last access
mut cpuPorts i64[4] = [0, 0, 0, 0]   # what the SPC700 reads at F4-F7
mut portWrites PortWrite[] = []   # the CPU's writes the SPC700 has not surely seen yet
mut careful = false   # this instruction may cross caughtUp: its writes can be undone
mut undone = false
mut ramUndo (i64, u8)[] = []
mut dspWrites (i64, i64)[] = []   # a careful instruction's DSP writes, made when it ends
mut dspTick i64 = ticksPerSample   # the tick of the DSP's next sample

# the SPC700 and what stands between it and the CPU; its instruction's undo lists are empty
# between two
fn spcFields(mut f StateFile):
	f.byteList(spcRam)
	f.spcState(spc)
	caughtUp = f.int(caughtUp)
	for k in 0..4:
		cpuPorts[k] = f.int(cpuPorts[k])
	f.portWrites(portWrites)
	dspTick = f.int(dspTick)

fn spcPowerOn():
	spcRam = zeros(0x1_0000)
	spc = SpcState()
	caughtUp = 0
	cpuPorts = [0, 0, 0, 0]
	portWrites.clear()
	dspTick = ticksPerSample
	dspPowerOn()

# ---------- the 65816's side ----------

# 2140-2143 read: the port as the SPC700 left it when the read lands
fn apuPortRead(port i64) u8:
	spcRunTo(cycles)
	if portLogging: eprint("R {cycles + 4} {port} {spc.outPorts[port]:02x}")
	u8(spc.outPorts[port])

# 2140-2143 written: kept for the SPC700's reads from the tick it sees it
fn apuPortWrite(port i64, v u8):
	at = cycles
	if portLogging: eprint("W {at} {port} {v:02x}")
	spcRunTo(at)
	if latestWrite(port) == v: return
	late = at * spcTicksPerMaster - caughtUp > 1.0
	portWrites.push(PortWrite(port, value = v, from = caughtUp, late))

fn latestWrite(port i64):
	for k in portWrites.len - 1..-1 step -1:
		if portWrites[k].port == port: return portWrites[k].value
	cpuPorts[port]

# Runs the SPC700 up to the master cycle `at`: every bus cycle Mesen would have run by then.
pub fn spcRunTo(at i64):
	target = i64(at * spcTicksPerMaster)
	caughtUp = caughtUp.max(target & ~1)
	while spc.tick < caughtUp:
		if not spcStep(): break
	dspRunTo(spc.tick)
	settlePortWrites()

# the writes every later read sees folded into the ports
fn settlePortWrites():
	while not portWrites.isEmpty and spc.tick >= portWrites[0].from + 2:
		w = portWrites.remove(0)
		cpuPorts[w.port] = w.value

# One instruction; false when it was undone (it touched a port past caughtUp).
fn spcStep():
	if spc.tick >= dspTick: dspRunTo(spc.tick)
	careful = spc.tick + longestInstruction > caughtUp
	if not careful:
		runInstruction()
		return true
	saved = spc
	runInstruction()
	careful = false
	if undone:
		spc = saved
		for k in ramUndo.len - 1..-1 step -1:
			addr, old = ramUndo[k]
			spcRam[addr] = old
		ramUndo.clear()
		dspWrites.clear()
		undone = false
		return false
	ramUndo.clear()
	for (reg, v) in dspWrites:
		dspWrite(reg, v)
	dspWrites.clear()
	true

# whether a port access at this tick lies past what the CPU has seen: the instruction is undone
fn isPastCaughtUp():
	if careful and spc.tick > caughtUp: undone = true
	undone

# ---------- the bus ----------

fn spcIdle():
	spc.tick += 2

fn spcRead(addr i64) i64:
	spc.tick += 2
	if addr >= 0xFFC0 and spc.romOn: return iplRom[addr & 0x3F]
	if addr & 0xFFF0 != 0xF0: return spcRam[addr]
	ioRead(addr)

fn spcWrite(addr i64, v i64):
	spc.tick += 2
	if undone: return
	if careful: ramUndo.push((addr, spcRam[addr]))
	if spc.ramWritable: spcRam[addr] = v & 0xFF
	if addr & 0xFFF0 == 0xF0: ioWrite(addr, v & 0xFF)

fn ioRead(addr i64):
	match addr:
		0xF2: spc.dspAddress
		0xF3:
			dspRunTo(spc.tick)
			dspRead(spc.dspAddress & 0x7F)
		0xF4..0xF8: 0 if isPastCaughtUp() else portIn(addr - 0xF4)
		0xF8, 0xF9: spc.auxPorts[addr - 0xF8]
		0xFD..0x100: timerRead(addr - 0xFD)
		_: 0

fn ioWrite(addr i64, v i64):
	match addr:
		0xF0:
			if not spc.psw.p: testWrite(v)
		0xF1: controlWrite(v)
		0xF2: spc.dspAddress = v
		0xF3:
			if spc.dspAddress < 0x80: dspWriteAt(spc.dspAddress, v)
		0xF4..0xF8:
			if not isPastCaughtUp(): spc.outPorts[addr - 0xF4] = v
		0xF8, 0xF9: spc.auxPorts[addr - 0xF8] = v
		0xFA..0xFD:
			runTimers()
			spc.timers[addr - 0xFA].target = v
		_: pass

fn dspWriteAt(reg i64, v i64):
	if careful:
		dspWrites.push((reg, v))
		return
	dspRunTo(spc.tick)
	dspWrite(reg, v)

# a CPU port as the SPC700 reads it at this tick
fn portIn(port i64):
	v = cpuPorts[port]
	for w in portWrites:
		if w.port == port and w.isSeen(): v = w.value
	v

fn isSeen(w PortWrite):
	t = spc.tick
	t >= w.from + 4 or t == w.from + 2 and (not w.late or spc.zeroStepAt == w.from)

# F0, the test register: Mesen runs only the normal wait states (bits 4-7 clear)
fn testWrite(v i64):
	if v & 0xF0 != 0: fail("the SPC700's wait states (F0 = 0x{v:02X}) are not run")
	runTimers()
	counting = v & 0x08 != 0 and v & 0x01 == 0
	if spc.timersCount and not counting:
		# the clocks forced low: a timer whose clock was high takes its fall now
		for k in 0..3:
			if (spc.tick / (spc.timers[k].period / 2)) & 1 == 1: spc.timers[k].stepTimer()
	spc.timersCount = counting
	spc.ramWritable = v & 0x02 != 0

# F1: the timers on or off (on from off restarts one), the CPU's ports cleared, the boot ROM mapped
fn controlWrite(v i64):
	if v & 0x30 != 0 and isPastCaughtUp(): return
	runTimers()
	for k in 0..3:
		on = v & (1 << k) != 0
		if on and not spc.timers[k].on:
			spc.timers[k].steps = 0
			spc.timers[k].output = 0
		spc.timers[k].on = on
	for (bit, first) in [(0x10, 0), (0x20, 2)]:
		if v & bit == 0: continue
		for port in first..first + 2:
			cpuPorts[port] = 0
			portWrites = portWrites.filter(.port != port or .from >= spc.tick)
	spc.romOn = v & 0x80 != 0

fn timerRead(k i64):
	runTimers()
	v = spc.timers[k].output & 0x0F
	spc.timers[k].output = 0
	v

fn runTimers():
	for k in 0..3:
		spc.timers[k].runTimer(spc.tick, spc.timersCount)

# the falls of its clock from where it was counted up to `tick`
fn runTimer(mut t SpcTimer, tick i64, counting bool):
	falls = tick / t.period - t.countedTo / t.period
	t.countedTo = tick
	if not counting: return
	loop falls:
		t.stepTimer()

fn stepTimer(mut t SpcTimer):
	if not t.on: return
	t.steps = (t.steps + 1) & 0xFF
	if t.steps == t.target:
		t.steps = 0
		t.output = (t.output + 1) & 0xFF

# the DSP's samples due by `tick`
fn dspRunTo(tick i64):
	while dspTick <= tick:
		dspSample()
		dspTick += ticksPerSample
