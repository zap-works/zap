# The player's side of a recompiled Switch program: the guest run a sixtieth of a second of its
# time at a turn, the last picture it presented (Kernel.frame, or the buffer vi was given, read
# from guest memory, scaled to the screen) shown in a window, and the pad read into Kernel.pad.
# A window shows the touch controls over the picture (touch.zap's Pro Controller layout, kept in
# the file `--touch-layout` names, touch-layout.txt by default); a game pad once pressed replaces
# them, and the fingers on no control are Kernel.touches. From the command line: `--frames N`
# ends after N turns, `--shot x.png` saves the last picture then; a scripted run
# (engine.isHeadless) opens no window and reads no real input.

import engine
import engine.audio
import image
import recomp.switch.controls
import recomp.switch.horizon
import recomp.switch.maxwell
import recomp.switch.render
import recomp.touch

screenWidth = 1280
screenHeight = 720

# a turn: a sixtieth of a second of the guest's counter
turnTicks = 19_200_000 / 60

# the instructions a turn may run at most (the guest's clock moves with them, threads.zap)
turnSteps = 20_000_000

# The menu of the touch controls: bigger, smaller, moving them, back to the game.
touchMenu = ["bigger controls", "smaller controls", "move controls", "resume"]

# the picture shown while the guest has presented none
fn blank() image.Image:
	image.fromBytes(screenWidth, screenHeight, fill(screenWidth * screenHeight * 4, u8(0)))

# the last picture presented at the screen's size, blank before the first
fn lastPicture(k horizon.Kernel) image.Image:
	picture = k.frame?.copy() ?? k.screenPicture() ?? return blank()
	if picture.width == screenWidth and picture.height == screenHeight: return picture
	picture.resize(screenWidth, screenHeight)

# The picture shown with the controls over it, the program waiting while their menu is open;
# false once the window is closed.
fn showWithControls(
	mut window engine.PixelWindow,
	mut overlay touch.Overlay,
	picture image.Image
) bool:
	loop:
		overlay.compose(picture, window.screenSize())
		if not window.show(overlay.frame): return false
		if overlay.takeChoice() is chosen:
			if chosen == 0: overlay.resize(1.15)
			if chosen == 1: overlay.resize(1.0 / 1.15)
			if chosen == 2: overlay.toggleEditing()
		if not overlay.isMenuOpen(): return true

# Runs the process turn by turn until it ends, is closed, or `--frames` turns ran; why it ended.
# With a program table (`table`), the frames are drawn by the renderer (rendered.zap).
pub fn play(mut k horizon.Kernel, table render.ShaderTable? = none) str:
	frames = i64.parse(args.option("--frames") ?? "") ?? -1
	shot = args.option("--shot") ?? ""
	scripted = engine.isHeadless()
	k.audio.sound.wavPath = args.option("--wav") ?? ""
	if not scripted and not args.hasFlag("--mute"): k.audio.sound.hear()
	window = engine.openPixelWindow("Switch", screenWidth, screenHeight, 1, blank())
	overlay = touch.newOverlay(controls.proLayout(), touchMenu)
	overlay.withSettings(args.option("--touch-layout") ?? "touch-layout.txt")
	rendering = table != none
	k.gpu.renders = rendering
	rp = render.newReplayer(table ?? render.noShaders())
	turns = 0
	why = ""
	picture = blank()
	shown = -1   # the presented frame the picture is of, rebuilt only when a new one comes
	while frames < 0 or turns < frames:
		why = k.runFor(turnTicks, turnSteps)
		turns += 1
		if k.display.presented != shown or k.frame != none:
			if rendering and k.display.presented != shown:
				k.frame = renderedPicture(rp, window, k)
			picture = k.lastPicture()
			shown = k.display.presented
		if scripted:
			if not window.show(picture): return "the window was closed"
		else:
			if not showWithControls(window, overlay, picture): return "the window was closed"
			k.pad = controls.fromGamePad() if overlay.hasGamePad()
				else controls.fromOverlay(overlay)
			k.touches = controls.touchPoints(overlay)
		if k.exited or why.startsWith("every thread waits"): break
	for reason, n in rp.skips:
		k.gpu.note("not drawn {n} times: {reason}")
	k.audio.sound.saveWav()
	if shot != "":
		k.lastPicture().savePng(shot) ??
			fail("cannot write {shot}: {error}")
	why
