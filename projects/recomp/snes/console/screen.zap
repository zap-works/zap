# The player's side: each frame shown in a window at an integer zoom, joypad 1 read from the keys
# (the arrows; Z is B, X is A, A is Y, S is X, Q and W the shoulders, Enter Start, Backspace
# Select) and a game pad (its buttons by their place, as the SNES pad has them) or from a route, the frames paced to the SNES's 60.1 a second. From the command line:
# `--frames N` ends after N frames (`--hash` printing the last one's hashes, `--shot x.png` saving
# its picture, `--memory prefix` its memories); `--hashes out.txt` writes every frame's line as tools/oracle.lua does in Mesen 2;
# `--route path` plays a route; `--wide` draws the picture 342 pixels wide (`--wide-width 308` for
# 308, wide.zap), `--wide-hashes out.txt` writing each frame's wide picture's hash, whether it was drawn wide
# and the level; `--shots-at f,f --shots-dir dir` saving those frames' pictures; `--headless`
# opens no window; `--fps N` (with --wide) shows N pictures a second, those between the
# cartridge's frames interpolated (interpolate.zap); `--uncapped` runs unpaced; the sound is heard unless `--mute`, and `--wav out.wav` writes it; `--ports` prints each access to the
# APU's ports and each frame's start with its master cycle, as tools/oracle.lua's ports mode prints Mesen 2's.
# F5 saves the state beside the dump (<stem>.state, savestate.zap), F7 loads it; `--save-at N
# file` (any number) saves it at frame N's end, `--load file` starts from one, --frames counting
# from its frame.

import digest
import engine
import engine.audio
import image
import recomp.touch

mut displays engine.PixelWindow[] = []
mut overlay = touch.newOverlay(touch.snesLayout(), ["save state", "load state", "resume"])   # a phone's controls over the picture
mut frameLimit = -1
mut paced = false
mut shownPerFrame = 1   # pictures shown for each of the cartridge's frames (--fps, interpolate.zap)
mut started f64 = 0.0
mut hashesPath = ""
mut hashLines str[] = []
mut wideHashPath = ""
mut wideHashLines str[] = []
mut savesAt (i64, str)[] = []   # --save-at N file, as many as given: the frames whose end saves the state
mut shotFrames i64[] = []   # --shots-at: the frames whose picture is saved, as DIR/FRAME.png (--shots-dir)
portLogging = args.hasFlag("--ports")

# `--writes 211B-2120`: each write to those B bus registers, the CPU's or a DMA's, and each frame's
# end, from frame `--writes-from` on, as tools/oracle.lua's writes mode lists Mesen 2's
writesRange = (args.option("--writes") ?? "").split("-")
writesFrom = u32(i64.parse("0x{writesRange[0]}") ?? 0x1_0000) if writesRange.len == 2 else 0x1_0000
writesTo = u32(i64.parse("0x{writesRange[1]}") ?? 0) if writesRange.len == 2 else 0
writesFromFrame = i64.parse(args.option("--writes-from") ?? "") ?? 0
mut sound = audio.FrameSound(rate = sampleRate, wavPath = args.option("--wav") ?? "")

mut framesPerSecond = 60.0988
startZoom = 3

pub fn openScreen():
	frameLimit = i64.parse(args.option("--frames") ?? "") ?? -1
	hashesPath = args.option("--hashes") ?? ""
	wideHashPath = args.option("--wide-hashes") ?? ""
	setupWide()
	for word in (args.option("--shots-at") ?? "").split(","):
		if i64.parse(word) is frame: shotFrames.push(frame)
	if args.option("--route") is path: route = loadRoute(path)
	if args.option("--polls") is path: polls = loadRoute(path)
	if args.option("--load") is path: requestLoad(path)
	for k in 0..args.len - 2:
		if args[k] == "--save-at": savesAt.push((i64.parse(args[k + 1]) ?? -1, args[k + 2].copy()))
	started = clockSeconds()
	if not args.hasFlag("--headless") and not args.hasFlag("--mute"): sound.hear()
	makesSound = sound.isWanted()
	shownPerFrame = presentsPerFrame(i64.parse(presetOption("--fps") ?? "") ?? 60)
	if args.hasFlag("--headless"): return
	paced = not args.hasFlag("--uncapped")
	if route.isEmpty and polls.isEmpty: keepBattery()
	if makesSound: startVolume()

	displays.push(
		engine.openPixelWindow(
			"{cartridgeHeader.title} (Zap)",
			wideWidth,
			screenHeight,
			startZoom,
			pictureImage()
		)
	)
	displays[0].setFrameRate(framesPerSecond)

# the picture as the player sees it: the native 256 pixels, or with --wide the wide picture
fn pictureImage():
	colorsImage(pictureColors())

fn colorsImage(colors u16[]):
	engine.bgr555Image(colors, wideWidth, screenHeight)

# The hash of the frame as tools/oracle.lua takes Mesen 2's: FNV-1a over each pixel's blue,
# green and red bytes, the output's rows from the top (output.zap).
pub fn screenHash() u32:
	hashOf(outputColors())

# the same hash of any picture's colours (BGR555)
fn hashOf(colors u16[]) u32:
	bytes = colorBytes(colors)
	for i in 0..bytes.len / 3:
		red = bytes[3 * i]
		bytes[3 * i] = bytes[3 * i + 2]
		bytes[3 * i + 2] = red
	digest.fnv1a(bytes)

# the output's colours as red, green and blue bytes
fn screenBytes() u8[]:
	colorBytes(outputColors())

fn colorBytes(colors u16[]) u8[]:
	bytes = fill(colors.len * 3, u8(0))
	for i in 0..colors.len:
		c = rgb(i64(colors[i]))
		bytes[3 * i] = (c >> 16) & 0xFF
		bytes[3 * i + 1] = (c >> 8) & 0xFF
		bytes[3 * i + 2] = c & 0xFF
	bytes

# the hash of the game's variables: FNV-1a over the first 8 KB of work RAM
pub fn wramHash() u32:
	digest.fnv1a(wram[..0x2000].copy())

fn hashLine():
	"{frameCount} {screenHash():08x} {wramHash():08x}"

# A frame is done (the vertical blank began): hashed, shown, the buttons taken, the pace kept.
fn frameDone():
	if portLogging or writesFrom <= writesTo and frameCount >= writesFromFrame:
		eprint("F {frameCount} {clock}")
	spcRunTo(clock)
	if makesSound:
		sound.pushFrame(soundSamples)
		soundSamples.clear()
	if not route.isEmpty: buttons = routeButtons(frameCount, buttons)
	if not polls.isEmpty: buttons = pollButtons(buttons)
	if not hashesPath.isEmpty: hashLines.push(hashLine())
	if not wideHashPath.isEmpty:
		wideHashLines.push("{frameCount} {hashOf(pictureColors()):08x} {1 if wideOn else 0} {wideHooks.sceneId():010x} {wideWhy}")
	if frameCount in shotFrames:
		dir = args.option("--shots-dir") ?? "build"
		pictureImage().savePng("{dir}/{frameCount}.png") ?? eprint("cannot save the shot: {error}")
		if shownPerFrame > 1 and wideOn:
			noteFrameEnd()
			final = pictureColors()
			colorsImage(interpolatedColors(0.5)).savePng("{dir}/{frameCount}-half.png") ??
				eprint("cannot save the shot: {error}")
			wideFrame = final
	for (frame, path) in savesAt:
		if frame == frameCount: requestSave(path)
	armState()
	saveChangedBattery()
	if frameLimit >= 0 and frameCount - framesFrom >= frameLimit: finish()
	noteFrameEnd()
	if displays.isEmpty:
		rotateFrame()
		return
	if shownPerFrame > 1 and wideOn:
		final = pictureColors()
		for step in 1..shownPerFrame:
			displays[0].present(interpolatedColors(f64(step) / f64(shownPerFrame)))
			keepPace(f64(frameCount - 1) + f64(step) / f64(shownPerFrame))
		displays[0].present(final)
	else:
		displays[0].present(pictureColors())
	keepPace(f64(frameCount))
	rotateFrame()

# sleeps until the time the frame (counted in the cartridge's frames) is due
fn keepPace(due f64):
	if not paced: return
	wait = started + due / framesPerSecond - clockSeconds()
	if wait > 0.0: sleepMs(i64(wait * 1000.0))
	if wait < -0.25: started -= wait   # far behind (the program waited): the pace starts again from now

# The picture shown; on a phone with its controls over it, the program waiting while their menu is
# open.
fn present(mut d engine.PixelWindow, colors u16[]):
	picture = colorsImage(colors)
	if not engine.hasTouchScreen():
		if not d.show(picture): finish()
	else:
		fitWideToScreen(d.screenSize())
		loop:
			overlay.compose(picture, d.screenSize())
			frame = overlay.frame.copy()   # (show is taken to change the overlay it is lent)
			if not d.show(frame): finish()
			if overlay.takeChoice() is chosen:
				if chosen == 0: requestSave(besideDump("state"))
				if chosen == 1: requestLoad(besideDump("state"))
			if overlay.takeLevel() is v: setVolume(v)
			if not overlay.isMenuOpen(): break
	if route.isEmpty and polls.isEmpty: buttons = keyButtons()
	if engine.isKeyPressed(.F(5)): requestSave(besideDump("state"))
	if engine.isKeyPressed(.F(7)): requestLoad(besideDump("state"))

fn keyButtons():
	keys (engine.Key, u16)[] = [
		(.Char('Z'), buttonB),
		(.Char('A'), buttonY),
		(.Backspace, buttonSelect),
		(.Enter, buttonStart),
		(.Up, buttonUp),
		(.Down, buttonDown),
		(.Left, buttonLeft),
		(.Right, buttonRight),
		(.Char('X'), buttonA),
		(.Char('S'), buttonX),
		(.Char('Q'), buttonL),
		(.Char('W'), buttonR)
	]
	pad (engine.PadButton, u16)[] = [
		(.South, buttonB),
		(.East, buttonA),
		(.West, buttonY),
		(.North, buttonX),
		(.LeftShoulder, buttonL),
		(.RightShoulder, buttonR),
		(.LeftTrigger, buttonL),   # a pad's triggers hold the shoulders too
		(.RightTrigger, buttonR),
		(.Start, buttonStart),
		(.Select, buttonSelect),
		(.Up, buttonUp),
		(.Down, buttonDown),
		(.Left, buttonLeft),
		(.Right, buttonRight)
	]
	held u16 = 0
	for (key, bit) in keys:
		if key.isKeyDown(): held |= bit
	for (button, bit) in pad:
		if button.isPadDown() or overlay.isDown(button): held |= bit
	held

# the end of a run: the hashes written, the last frame's printed and saved when asked
fn finish():
	sound.saveWav()
	if not hashesPath.isEmpty: writeLines(hashesPath, hashLines)
	if not wideHashPath.isEmpty: writeLines(wideHashPath, wideHashLines)
	if args.hasFlag("--hash"): print("frame {hashLine()}")
	if args.option("--shot") is path:
		pictureImage().savePng(path) ?? eprint("cannot write {path}: {error}")
	if args.option("--memory") is prefix: dumpMemory(prefix)
	exit(0)

fn writeLines(path str, lines str[]):
	fs.writeFile(path, "{lines.join("\n")}\n") ?? eprint("cannot write {path}: {error}")

# The console's memories as Mesen 2 shows them, a file each: prefix-wram.bin, -vram.bin,
# -cgram.bin (16-bit words, little-endian), -oam.bin and -screen.bin (the output's red, green and
# blue bytes, as the hash reads it).
fn dumpMemory(prefix str):
	files = [
		("wram", wram.copy()),
		("vram", wordBytes(vram)),
		("cgram", wordBytes(cgram)),
		("oam", oam.copy()),
		("screen", screenBytes())
	]
	for (name, bytes) in files:
		path = "{prefix}-{name}.bin"
		fs.writeBytes(path, bytes) ?? eprint("cannot write {path}: {error}")

fn wordBytes(words u16[]) u8[]:
	out = fill(words.len * 2, u8(0))
	for i in 0..words.len:
		w = words[i]
		out[2 * i] = u8.wrap(w)
		out[2 * i + 1] = u8.wrap(w >> 8)
	out
