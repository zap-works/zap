# What a game project's entry files share (projects/dkc, projects/smw): its dump checked against
# the cartridge it was made for, prepared, the program built and run.

import digest
import fs

# the cartridge a game project was made for: its name, its size and its SHA-256
pub type Dump:
	title str
	bytes i64
	sha256 str

	# what is wrong with `rom` for this cartridge, or none
	fn problem(rom u8[]) str?:
		if rom.len != bytes:
			return "it is {rom.len} bytes, not {bytes / 1024} KB (a dump with a copier's header?)"
		sha = digest.sha256(rom).map("{it:02x}").join("")
		if sha != sha256: return "its SHA-256 is {sha}, not {sha256}"
		none

# Prepares the game from its dump; stops the program with the reason when it is not the cartridge.
pub fn prepareDump(game Game, dump Dump):
	rom = fs.readBytes(game.romPath) ?? fail("no ROM at {game.romPath}: {error}")
	if dump.problem(rom) is why: fail("{game.romPath} is not {dump.title}: {why}")
	game.prepareGame()

# A game project's main: prepares the game when its program is not written yet, builds the program
# when it is not built, and runs it with this program's arguments; with `--android <dir>
# [--target t]` it releases the game's apps (releaseApps), named `label`, instead.
pub fn playMain(game Game, dump Dump, label str):
	if not fs.exists(game.entryPath()):
		print("{dump.title} prepares itself from {game.romPath} (once)...")
		game.prepareDump(dump)
	if args.option("--android") is dir:
		game.releaseApps(dir, args.option("--target") ?? "android", label, 900)
		exit(0)
	exe = "build/{game.name}{exeSuffix()}"
	if not fs.exists(exe):
		print("building {exe}...")
		if Process.run("{zapPath()} build {quoteArg(game.entryPath())}") != 0: exit(1)
	exit(Process.run("{exe} {args.join(" ")}"))
