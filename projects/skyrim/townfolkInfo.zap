# Prints Riverwood's people by the hour: the town's cells and doors, then for each dweller its cell
# at a few hours of a new game's first day.
#
#   zap run projects/skyrim/townfolkInfo.zap

import skyrim
import skyrim.esm
import game
import skyrim.actor

riverwood = esm.Area(0x3C, 5, -11)
nowhere = game.Spot(cell = "-", at = Vec3(0.0, 0.0, 0.0))

install = skyrim.openInstall(skyrim.defaultInstall) ?? fail("no install")
plugin = esm.openEsm(install.installPlugin("Skyrim.esm")) ?? fail("no plugin")
town = plugin.townAround(riverwood)
print("cells: {town.cells.join(", ")}")
for d in town.doors:
	print("door {d.refId:08X} in {d.spot.cell} to {d.to}")
for d in town.dwellers:
	hours = [0.0, 6.0, 9.0, 12.0, 18.0, 21.0].map(f32(it)).map((d.spotAt(it, 0) ?? nowhere).cell)
	print("{d.editorId} {d.npc:08X} home {(d.home ?? nowhere).cell}: {hours.join(" | ")}")
for name in args.positional():
	for d in town.dwellers.filter(.editorId == name):
		for p in d.plans:
			where = p.spot ?? nowhere
			print("  {p.editorId} holds {p.holds} {p.schedule.scheduleText()} {where.cell} {where.at.x:.0}")
