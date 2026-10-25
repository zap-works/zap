# A NEC DSP run by a rewrite of its firmware in Zap (dsp1.zap) instead of the player's dump: the
# rewrite runs a part at a time, each from a wait on RQM or a read of DR to the next, counting the
# chip's cycles as the firmware spends them; what the 65816 sees of the chip (DR, SR, RQM) changes
# at the cycle the firmware's instruction would change it, as the 65816's accesses reach it.

import recomp.snes.cartridge

pub mut necRewritten = false
mut rwChip = ""
mut rwEvents RewriteEvent[] = []
mut rwNextEvent = 0
mut rwWaitAt i64 = -1      # the cycle a wait on RQM begins (the loop's first test)
mut rwWakeAt i64 = -1      # the cycle a part that reads DR mid-way begins
mut rwClearedAt i64 = 0    # the cycle the 65816 last took RQM down
mut rwT i64 = 0            # the cycle of the instruction the running part is at

eventDr = 0       # DR written, RQM up
eventRqm = 1      # DR read with RQM raised
eventSr = 2       # SR written

type RewriteEvent:
	at i64
	kind i64
	value i64

# The chip `chip` ("dsp1b") run by its rewrite, mapped as loadNec maps it.
pub fn rewriteNec(chip str):
	necSt01x = false
	necRam = zeros(0x100)
	necRate = 7_600_000.0
	necRegisterMask = 0x1000 if cartridge.hirom else 0x4000
	necMapped = true
	necRewritten = true
	mapMemory()
	rwChip = chip.copy()
	rwEvents = []
	rwNextEvent = 0
	rwWaitAt = -1
	rwWakeAt = 1   # the firmware's first loop finds RQM down at cycle 0
	rwClearedAt = 0
	nSR = 0
	nDR = 0
	nCycles = 0
	dsp1PowerOn()

# the rewrite's place in its firmware, its variables and the events the 65816 has not seen yet
fn rewriteFields(mut f StateFile):
	dPart = f.dsp1Part(dPart)
	dA = f.int(dA)
	dB = f.int(dB)
	dK = f.int(dK)
	dL = f.int(dL)
	dTR = f.int(dTR)
	f.intList(dResults)
	f.intList(dGaps)
	dWide = f.int(dWide)
	dSquares = f.int(dSquares)
	dDp = f.int(dDp)
	dTransposed = f.isSet(dTransposed)
	f.events(rwEvents)
	rwNextEvent = f.int(rwNextEvent)
	rwWaitAt = f.int(rwWaitAt)
	rwWakeAt = f.int(rwWakeAt)
	rwClearedAt = f.int(rwClearedAt)
	rwT = f.int(rwT)

fn rewriteRun(target i64):
	loop:
		while rwNextEvent < rwEvents.len and rwEvents[rwNextEvent].at < target:
			rwEvents[rwNextEvent].applyEvent()
			rwNextEvent += 1
		if rwNextEvent == rwEvents.len and rwNextEvent > 0:
			rwEvents.clear()
			rwNextEvent = 0
		start = partStart()
		if start < 0 or start >= target: break
		rwWaitAt = -1
		rwWakeAt = -1
		rwT = start
		dsp1Part()
	nCycles = target

# the cycle the next part's first instruction runs at, -1 while it waits on the 65816
fn partStart():
	if rwWakeAt >= 0: return rwWakeAt
	if rwWaitAt < 0 or not rwEvents.isEmpty or nSR & srRqm != 0: return -1
	(rwWaitAt if rwWaitAt > rwClearedAt else rwClearedAt) + 1

fn applyEvent(e RewriteEvent):
	match e.kind:
		0:
			nDR = e.value
			nSR |= srRqm
		1: nSR |= srRqm
		_: nSR = (nSR & 0x907C) | (e.value & ~0x907C & 0xFFFF)

fn noteEvent(kind i64, value i64):
	rwEvents.push(RewriteEvent(at = rwT, kind, value = value & 0xFFFF))
	rwT += 1

# an instruction writing DR for the 65816 (RQM up)
fn drOut(v i64):
	noteEvent(eventDr, v)

# an instruction reading what the 65816 wrote into DR, RQM raised for the next transfer
fn drIn():
	v = nDR
	noteEvent(eventRqm, 0)
	v

# an instruction reading DR without a transfer
fn drPeek():
	rwT += 1
	nDR

fn srOut(v i64):
	noteEvent(eventSr, v)

fn spend(instructions i64):
	rwT += instructions

# the part ends in the firmware's loop on RQM: the next runs once the 65816 has taken it down
fn waitRqm():
	rwWaitAt = rwT

# the part ends before an instruction that reads DR: the next part starts with it
fn wakeHere():
	rwWakeAt = rwT
