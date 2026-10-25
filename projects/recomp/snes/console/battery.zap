# The cartridge's battery RAM kept between a player's runs, as an emulator keeps its .srm: read
# from `<dump's stem>.srm` beside the dump when the run starts, written there when the game has
# changed it (looked at every half second). Runs compared with Mesen 2 (a route, polls, headless)
# start from cleared RAM and keep nothing.

import fs

mut loadedRom = ""   # the dump the run plays
mut sramChanged = false   # written since it was last kept
mut sramFile = ""   # where it is kept; "" for a run that keeps nothing

fn keepBattery():
	if sramLen == 0 or loadedRom.isEmpty: return
	sramFile = besideDump("srm")
	if fs.readBytes(sramFile) is saved and saved.len == sramLen:
		memoryMap.bytes.place(sramAt, saved)

# the file of that name beside the dump, of another extension (the battery's, the save state's)
fn besideDump(extension str):
	fs.join(fs.dirOf(loadedRom), "{fs.stem(loadedRom)}.{extension}")

fn saveChangedBattery():
	if sramFile.isEmpty or not sramChanged or frameCount % 30 != 0: return
	sramChanged = false
	fs.writeBytes(sramFile, sramCopy()) ??
		eprint("cannot keep the battery RAM in {sramFile}: {error}")
