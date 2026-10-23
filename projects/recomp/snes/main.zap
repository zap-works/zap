# recomp.snes: a SNES cartridge recompiled into a native Zap program. The ROM's 65816 code is
# translated ahead of time into Zap functions (snes/), written as a program beside a copy of
# nothing of the game: the program reads the ROM at its start and runs it on the SNES written in
# Zap (console/, cpu/: PPU, DMA and HDMA, joypads, the SPC700 and its DSP, timed as Mesen 2 times
# them). Run from the repository root:
#
#   zap run projects/recomp/snes/main.zap <rom.sfc> [--out <dir>] [--tables <dir>] [--name <name>] [--mesen N [--route file]] [--build | --release <dir> | --android <dir> [--target android-x64] [--icon-frame N] [--label name]]
#
# writes <dir>/<name>.zap (the name the ROM file's by default) and its module game/; `zap run
# <dir>/<name>.zap` plays it (its options in console/screen.zap: --headless, --frames, --route,
# --hashes, --shot...). --tables names a dir of per-bank cfg files (snes/cfg.zap) whose entries
# and dispatch targets seed the flow; without them the flow starts at the cartridge's vectors
# and follows the calls it can see, and a jump through memory it never saw stops the program at
# run time (the console says where). --mesen N plays N frames of the game in Mesen 2 (mesen/), notes
# where those jumps went and prepares again until no new target shows; --route gives it buttons.
# --build builds the program too (build/<name>.exe). The dump is yours: nothing of it goes into
# the repository (.gitignore: projects/recomp/snes/rom/, recomp/).

import fs
import image
import recomp.snes.mesen
import recomp.snes.snes
import recomp.snes.cartridge

named = [
	"--out",
	"--tables",
	"--name",
	"--mesen",
	"--route",
	"--release",
	"--android",
	"--target",
	"--icon-frame",
	"--label"
].map(args.option(it) ?? "")
paths = args.filter(not .startsWith("--") and not (it in named))
if paths.isEmpty:
	fail("recomp.snes: which ROM? zap run projects/recomp/snes/main.zap <rom.sfc> --out <dir>")
romPath = paths[0]
out = args.option("--out") ?? "projects/recomp/snes/out/{fs.stem(romPath)}"
name = args.option("--name") ?? fs.stem(romPath).replace(" ", "_")
rom = cartridge.readRom(romPath) ?? fail("cannot read {romPath}: {error}")
header = cartridge.readHeader(rom)
print("{romPath}: \"{header.title}\", {"HiROM" if header.hirom else "LoROM"}, {rom.len / 1024} KB{", fast" if header.fast else ""}{", {header.sramBytes / 1024} KB of battery RAM" if header.sramBytes > 0 else ""}")
game = snes.Game(
	name = name.copy(),
	romPath = romPath.copy(),
	recompDir = out.copy(),
	tablesDir = args.option("--tables") ?? ""
)
game.prepareGame()
if i64.parse(args.option("--mesen") ?? "") is frames: game.resolveInMesen(frames)
print("written: {out}/{name}.zap (zap run {out}/{name}.zap)")
if args.option("--release") is dir:
	game.release(dir)
elif args.option("--android") is dir:
	game.releaseApps(dir)
elif args.hasFlag("--build"):
	exit(Process.run("{zapPath()} build {out}/{name}.zap"))

# --release dir: the program built twice into dir, as the cartridge draws it (<name>.exe) and with
# the widescreen on by default (<name>-wide.exe, any scene, console/wide.zap); each finds the
# player's dump beside it (console/presets.zap). Nothing of the game is in them but its code's
# translation: the dump stays the player's.
fn release(game snes.Game, dir str):
	copyBuilt(game.releaseBuilds(dir, "", "{exeSuffix()}", "342"), dir)
	print("released into {dir}: the program and its widescreen; beside them goes the player's dump as {fs.stem(game.romPath)}.sfc")

# --android dir: the same two as Android apps (<name>.apk, <name>-wide.apk, a phone's arm64, or
# with --target android-x64 the emulator's x86-64), named --label (the game's name by default),
# their icon the game's own picture (gameIcon), each carrying the player's dump inside (zap build
# --assets), so the device needs nothing else: made on the player's machine from their own dump,
# kept out of the repository as the dump is.
fn releaseApps(game snes.Game, dir str):
	assets = "build/{game.name}-assets"
	fs.deleteTree(assets) ?? fail("cannot empty {assets}: {error}")   # (a dump of another name left there)
	fs.createDir(assets) ?? fail("cannot make {assets}: {error}")
	dump = fs.readBytes(game.romPath) ?? fail("cannot read {game.romPath}: {error}")
	fs.writeBytes("{assets}/{fs.stem(game.romPath)}.sfc", dump) ??
		fail("cannot write into {assets}: {error}")
	target = args.option("--target") ?? "android"
	icon = game.gameIcon()
	label = args.option("--label") ?? game.name
	options = " --target {target} --assets {assets} --icon {icon} --label {quoteArg(label)}"
	copyBuilt(game.releaseBuilds(dir, options, ".apk", "screen"), dir)
	print("released into {dir}: {game.name}.apk and {game.name}-wide.apk, the dump inside each")

# The app's icon: the picture of a headless run at frame --icon-frame (900 by default, when many
# games show their title), its middle square four times larger; the path of its PNG in build/.
fn gameIcon(game snes.Game) str:
	frame = i64.parse(args.option("--icon-frame") ?? "") ?? 900
	shot = "build/{game.name}-icon.png"
	run = "{zapPath()} run {game.recompDir}/{game.name}.zap --headless --frames {frame} --shot {shot}"
	if Process.run(run) != 0: fail("cannot make the icon: {run} failed")
	picture = image.loadPng(shot)
	side = picture.height
	square = picture.crop((picture.width - side) / 2, 0, side, side)
	square.enlarge(4).savePng(shot) ?? fail("cannot write {shot}: {error}")
	shot

# the files zap build wrote into build/, copied into dir
fn copyBuilt(names str[], dir str):
	for name in names:
		fs.writeBytes(
			"{dir}/{name}",
			fs.readBytes("build/{name}") ?? fail("no build/{name}: {error}")
		) ??
			fail("cannot write {dir}/{name}: {error}")

# The program and its widescreen (<name>-wide: presets --wide --wide-scenes all and --wide-width,
# a phone's `screen`) built with the build's options into build/; the names of what they wrote
# (their stem and suffix)
fn releaseBuilds(game snes.Game, dir str, options str, suffix str, wideWidth str) str[]:
	fs.createDir(dir) ?? fail("cannot make {dir}: {error}")
	wide = game.copy()
	wide.name = "{game.name}-wide"
	wide.presets = ["--wide", "--wide-scenes", "all", "--wide-width", wideWidth.copy()]
	wide.writeEntry()
	built = []
	for g in [game.copy(), wide.copy()]:
		if Process.run("{zapPath()} build{options} {g.recompDir}/{g.name}.zap") != 0: exit(1)
		built.push("{g.name}{suffix}")
	built

# --mesen N: the jumps through memory the flow could not resolve are watched in Mesen 2 over N
# frames of the game (with --route's buttons, else none), their targets added to the tables as
# played.cfg (tools/oracle.lua's played mode), and the program prepared again; over once a round
# leaves the list of jumps as it was.
fn resolveInMesen(mut game snes.Game, frames i64):
	if game.tablesDir.isEmpty:
		game.tablesDir = "{game.recompDir}/tables"
		fs.createDir(game.tablesDir) ?? fail("cannot make {game.tablesDir}: {error}")
	played = "{game.tablesDir}/played.cfg"
	jumps = "{game.recompDir}/jumps.txt"
	lastJumps = ""
	for round in 1..=8:
		if (fs.readFile(jumps) ?? "") == lastJumps: return
		lastJumps = fs.readFile(jumps) ?? ""
		before = (fs.readFile(played) ?? "").lines().filter(.startsWith("indirect_dispatch")).len
		mesen.runOracle(
			"played",
			game.romPath,
			frames,
			played,
			args.option("--route") ?? "",
			{"SNESRECOMP_JUMPS": fs.join(currentDir(), jumps)}
		)
		after = (fs.readFile(played) ?? "").lines().filter(.startsWith("indirect_dispatch")).len
		print("Mesen round {round}: {after} jumps through memory resolved ({after - before} new)")
		game.prepareGame()
