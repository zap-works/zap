# A prepared game built for players: twice, as the cartridge draws it (<name>) and with the
# widescreen on by default (<name>-wide, console/wide.zap), for Windows (release) or as Android
# apps (releaseApps). Nothing of the game is in them but its code's translation, except an app,
# which carries the player's dump inside (zap build --assets): made on the player's machine from
# their own dump, kept out of the repository as the dump is.

import fs
import image

# the program and its widescreen built into dir; each finds the player's dump beside it
# (console/presets.zap)
pub fn release(game Game, dir str):
	copyBuilt(game.releaseBuilds(dir, "", "{exeSuffix()}", "342"), dir)
	print("released into {dir}: the program and its widescreen; beside them goes the player's dump as {fs.stem(game.romPath)}.sfc")

# The two as Android apps (<name>.apk, <name>-wide.apk) for `target` (android: a phone's arm64;
# android-x64: the emulator's), named `label`, their icon the game's own picture at frame
# `iconFrame` (gameIcon); each carries the player's dump, so the device needs nothing else.
pub fn releaseApps(game Game, dir str, target str, label str, iconFrame i64):
	assets = "build/{game.name}-assets"
	fs.deleteTree(assets) ?? fail("cannot empty {assets}: {error}")   # (a dump of another name left there)
	fs.createDir(assets) ?? fail("cannot make {assets}: {error}")
	dump = fs.readBytes(game.romPath) ?? fail("cannot read {game.romPath}: {error}")
	fs.writeBytes("{assets}/{fs.stem(game.romPath)}.sfc", dump) ??
		fail("cannot write into {assets}: {error}")
	icon = game.gameIcon(iconFrame)
	options = " --target {target} --assets {quoteArg(assets)} --icon {quoteArg(icon)} --label {quoteArg(label)}"
	copyBuilt(game.releaseBuilds(dir, options, ".apk", "screen"), dir)
	print("released into {dir}: {game.name}.apk and {game.name}-wide.apk, the dump inside each")

# The app's icon: the picture of a headless run at `frame` (when many games show their title), its
# middle square four times larger; the path of its PNG in build/.
fn gameIcon(game Game, frame i64) str:
	shot = "build/{game.name}-icon.png"
	run = "{zapPath()} run {quoteArg(game.entryPath())} --headless --frames {frame} --shot {quoteArg(shot)}"
	if Process.run(run) != 0: fail("cannot make the icon: {run} failed")
	picture = image.loadPng(shot)
	side = picture.height
	square = picture.crop((picture.width - side) / 2, 0, side, side)
	square.enlarge(4).savePng(shot) ?? fail("cannot write {shot}: {error}")
	shot

fn entryPath(game Game) str:
	"{game.recompDir}/{game.name}.zap"

# the files zap build wrote into build/, copied into dir
fn copyBuilt(names str[], dir str):
	for name in names:
		fs.writeBytes(
			"{dir}/{name}",
			fs.readBytes("build/{name}") ?? fail("no build/{name}: {error}")
		) ??
			fail("cannot write {dir}/{name}: {error}")

# The program and its widescreen (<name>-wide: presets --wide --wide-scenes all and --wide-width,
# a phone's `screen`; a game's own presets kept) built with the build's options into build/; the
# names of what they wrote (their stem and suffix)
fn releaseBuilds(game Game, dir str, options str, suffix str, wideWidth str) str[]:
	fs.createDir(dir) ?? fail("cannot make {dir}: {error}")
	wide = game.copy()
	wide.name = "{game.name}-wide"
	wide.presets = game.presets.copy()
	for word in ["--wide", "--wide-scenes", "all", "--wide-width", wideWidth.copy()]:
		wide.presets.push(word.copy())
	wide.writeEntry()
	built = []
	for g in [game.copy(), wide.copy()]:
		if Process.run("{zapPath()} build{options} {quoteArg(g.entryPath())}") != 0: exit(1)
		built.push("{g.name}{suffix}")
	built
