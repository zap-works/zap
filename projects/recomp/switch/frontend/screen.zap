# The player's side of a recompiled Switch program: the guest run a sixtieth of a second of its
# time at a turn, the last picture it presented (Kernel.frame, vi's) shown in a window, and the
# pad read into Kernel.pad. From the command line: `--frames N` ends after N turns, `--shot x.png`
# saves the last picture then; a scripted run (engine.isHeadless) opens no window and reads no
# real input.

import engine
import image
import recomp.switch.controls
import recomp.switch.horizon

screenWidth = 1280
screenHeight = 720

# a turn: a sixtieth of a second of the guest's counter
turnTicks = 19_200_000 / 60

# the instructions a turn may run at most (the guest's clock moves with them, threads.zap)
turnSteps = 20_000_000

# the picture shown while the guest has presented none
fn blank() image.Image:
	image.fromBytes(screenWidth, screenHeight, fill(screenWidth * screenHeight * 4, u8(0)))

# Runs the process turn by turn until it ends, is closed, or `--frames` turns ran; why it ended.
pub fn play(mut k horizon.Kernel) str:
	frames = i64.parse(args.option("--frames") ?? "") ?? -1
	shot = args.option("--shot") ?? ""
	scripted = engine.isHeadless()
	k.audio.sound.wavPath = args.option("--wav") ?? ""
	if not scripted and not args.hasFlag("--mute"): k.audio.sound.hear()
	window = engine.openPixelWindow("Switch", screenWidth, screenHeight, 1, blank())
	turns = 0
	why = ""
	while frames < 0 or turns < frames:
		if not scripted: k.pad = controls.fromGamePad()
		why = k.runFor(turnTicks, turnSteps)
		turns += 1
		picture = k.frame?.copy() ?? blank()
		if not window.show(picture): return "the window was closed"
		if k.exited or why == "every thread waits": break
	k.audio.sound.saveWav()
	if shot != "":
		(k.frame?.copy() ?? blank()).savePng(shot) ?? fail("cannot write {shot}: {error}")
	why
