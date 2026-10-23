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
	game.releaseApps(
		dir,
		args.option("--target") ?? "android",
		args.option("--label") ?? name,
		i64.parse(args.option("--icon-frame") ?? "") ?? 900
	)
elif args.hasFlag("--build"):
	exit(Process.run("{zapPath()} build {quoteArg("{out}/{name}.zap")}"))

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
