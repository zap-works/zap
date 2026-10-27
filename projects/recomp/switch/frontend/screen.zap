# The player's side of a recompiled Switch program: the guest run a sixtieth of a second of its
# time at a turn, the last picture it presented (Kernel.frame, or the buffer vi was given, read
# from guest memory, scaled to the screen) shown in a window, and the pad read into Kernel.pad.
# A window shows the touch controls over the picture (touch.zap's Pro Controller layout, kept in
# the file `--touch-layout` names, touch-layout.txt by default); a game pad once pressed replaces
# them, and the fingers on no control are Kernel.touches. From the command line: `--frames N`
# ends after N turns, `--shot x.png` saves the frame the window shows then (the controls over the
# last picture, which `--shot-picture x.png` saves bare); a scripted run (engine.isHeadless) opens
# no window and reads no real input.

import engine
import engine.audio
import image
import recomp.switch.controls
import recomp.switch.cpu
import recomp.switch.cpu.core
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

# The menu of the touch controls: all bigger or smaller, the last one moved alone bigger or smaller,
# more or less opaque, moving them, back to the game.
touchMenu = [
	"bigger controls",
	"smaller controls",
	"this one bigger",
	"this one smaller",
	"more opaque",
	"less opaque",
	"move controls",
	"resume"
]

# a step of size, and of opacity
sizeStep = 1.15
opacityStep = 0.1

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
			if chosen == 0: overlay.resize(sizeStep)
			if chosen == 1: overlay.resize(1.0 / sizeStep)
			if chosen == 2: overlay.resizePicked(sizeStep)
			if chosen == 3: overlay.resizePicked(1.0 / sizeStep)
			if chosen == 4: overlay.fade(opacityStep)
			if chosen == 5: overlay.fade(-opacityStep)
			if chosen == 6: overlay.toggleEditing()
		if not overlay.isMenuOpen(): return true

# Runs the process turn by turn until it ends, is closed, or `--frames` turns ran; why it ended.
# `--profile f` writes the blocks the run entered, as tools/run.zap's does.
# With a program table (`table`), the frames are drawn by the renderer (rendered.zap).
pub fn play(mut k horizon.Kernel, table render.ShaderTable? = none) str:
	frames = i64.parse(args.option("--frames") ?? "") ?? -1
	profile = args.option("--profile") ?? ""
	cpu.recording = profile != ""
	shot = args.option("--shot") ?? ""
	shotPicture = args.option("--shot-picture") ?? ""
	scripted = engine.isHeadless()
	k.audio.sound.wavPath = args.option("--wav") ?? ""
	if not scripted and not args.hasFlag("--mute"): k.audio.sound.hear()
	window = engine.openPixelWindow("Switch", screenWidth, screenHeight, 1, blank())
	overlay = touch.newOverlay(controls.proLayout(), touchMenu)
	overlay.withSettings(args.option("--touch-layout") ?? "touch-layout.txt")
	rendering = table != none
	k.gpu.renders = rendering
	rp = render.newReplayer(table ?? render.noShaders())
	rp.trace = args.hasFlag("--trace-render")
	turns = 0
	why = ""
	picture = blank()
	shown = -1   # the presented frame the picture is of, rebuilt only when a new one comes
	checkFrom = cpu.lockstepFrom()
	samples {i64: i64} = {}   # --calls: where each thread stood at every turn's end, by pc
	while frames < 0 or turns < frames:
		if turns == checkFrom: cpu.lockstep = true
		if cpu.lockstep: eprint("lockstep: turn {turns}")
		why = k.runFor(turnTicks, turnSteps)
		turns += 1
		if args.hasFlag("--calls"):
			# the log so far, kept out of memory and safe from a stop
			for line in k.log:
				print(line)
			k.log.clear()
			print("turn {turns}")
			for t in k.threads:
				if t.started and not t.exited and t.waiting == .Nothing:
					samples[t.c.pc] = (samples.get(t.c.pc) ?? 0) + 1
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
	# --calls: where each live thread stands, to read its frames beside the log's call chains
	if args.hasFlag("--calls"):
		for pc in samples.keys().sortedBy(-samples[it])[..20.min(samples.len)]:
			eprint("sample {pc:x} x{samples[pc]}")
		for t in k.threads.filter(.started and not .exited):
			c = t.c
			eprint("thread t{t.id} pc {c.pc:x} regs {(0..33).map("{c.x[it]:x}").join(" ")}")
			eprint("trail {(0..c.trail.len).map(c.trail[(c.trailAt + it) % len]).map("{it:x}").join(" ")}")
			# each frame of the x29 chain: the 0xc0 bytes below the frame pointer (the locals) and the
			# saved x29, x30 at it
			fp = i64(c.x[29])
			loop 8:
				if fp < core.memory.base or fp + 16 > core.memory.end: break
				words = core.memory.read(fp - 0xc0, 0xd0)
				eprint("frame fp {fp:x}: {words.map("{it:02x}").join("")}")
				next = i64(core.memory.load(fp, 3))
				if next <= fp: break
				fp = next
	if profile != "": eprint(cpu.writeProfile(profile))
	if shot != "":
		overlay.compose(k.lastPicture(), window.screenSize())
		overlay.frame.savePng(shot) ?? fail("cannot write {shot}: {error}")
	if shotPicture != "":
		k.lastPicture().savePng(shotPicture) ?? fail("cannot write {shotPicture}: {error}")
	why
