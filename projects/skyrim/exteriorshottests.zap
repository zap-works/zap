# A headless shot outside the inn, through the game's own main.zap (a process of its own: the
# town's prepared files are read whole), and what the town takes of the machine: a game of it on
# a 4 GB card and 16 GB of memory.
#   limit: 1200 s

import fs
import image
import skyrim.esm

riverwood = esm.Area(0x3C, 5, -11)

# the budget, in MB: the card's memory the town may hold (a quarter is the desktop's), what it
# stages through host-visible memory, and the process's most memory
deviceBudget = 3000
hostBudget = 512
processBudget = 2500

# the largest number right after `label` on the lines of `text` that have it
fn megabytesAfter(text str, label str):
	most = -1
	for line in text.lines():
		if line.indexOf(label) is at:
			digits = line[at + label.len..].split(" ")[0]
			most = most.max(i64.parse(digits) ?? -1)
	if most < 0: fail("no number after {label}")
	most

test "a headless shot outside the inn shows the town, not an empty frame, within the memory budget":
	if not fs.exists(esm.defaultEsm()): return
	shot = "build/skyrim-riverwood.png"
	ran = Process.output(
		"{zapPath()} run projects/skyrim/main.zap --cell {riverwood.areaId()} --free --at 23259,-44476,-8 --eye 128 --look -48,-5 --frames 4 --step 16 --bare --shot {shot}",
		vars = [runAssignment("gpumemory,memstats")]
	)
	if ran.code != 0: fail(ran.out)
	img = image.loadPng(shot)
	lit = 0
	for p in img.cells:
		if i64(p.r) + i64(p.g) + p.b > 30: lit += 1
	expect lit * 100 > img.cells.len * 30
	expect ran.out.megabytesAfter("device peak ") <= deviceBudget
	expect ran.out.megabytesAfter("host peak ") <= hostBudget
	expect ran.out.megabytesAfter("peak=") <= processBudget
