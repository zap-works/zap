# The cell's physics prepared beside its file (physics.bin): the world of its colliders with the
# clutter let settle first, so the game opens on bodies asleep where they rest; and the prepared
# files opened together.

import engine
import skyrim
import skyrim.esm
import skyrim.nif
import world
import engine.physics

settleSeconds f32 = 3.0

# the cell (with the player) and its physics as prepared
pub type PreparedCell:
	head world.CellHead
	file engine.Prepared
	physics CellWorld

pub fn physicsPath(cell str) str:
	"{world.preparedDir}/{cell.lower()}/physics.bin"

# the cell's world built from the install, settled, and written beside the cell
pub fn preparePhysics(install skyrim.Install, mut plugin esm.Esm, cell esm.Cell, id str):
	models {str: nif.Collider[]} = {}
	cw = install.cellWorld(plugin, cell, models)
	if esm.areaOf(cell.editorId) is area: cw.world.collideAreaLand(plugin, area)
	cw.world.step(settleSeconds)
	path = physicsPath(id)
	engine.writePreparedFile(path, "ZNSP", world.formatVersion, cw.toBytes(), []) ??
		fail("cannot write {path}: {error}")

# the prepared world of the cell, none when it is missing or of another version
pub fn readPhysics(id str) CellWorld?:
	file = try engine.readPreparedFile(physicsPath(id), "ZNSP", world.formatVersion)
	CellWorld.fromBytes(file.headOf())

# the cell `id` as prepared, none when a file is missing or of another version; what `load` leaves
# out is not read (the body without textures, an empty world without physics)
pub fn openPrepared(id str, load Load = Load()) PreparedCell?:
	head, file = try world.readCell(world.cellPath(id), load.textures)
	if not load.physics: return PreparedCell(head, file, CellWorld(world = havokWorld()))
	PreparedCell(head, file, try readPhysics(id))

# The cell `id` as prepared, preparing it from the default install first when it is missing or of
# another version (the tests that need it share one file, written whole).
pub fn openOrPrepare(id str, load Load = Load()) PreparedCell:
	if openPrepared(id, load) is cell: return cell
	prepareCell(skyrim.defaultInstall, id)
	openPrepared(id, load) ?? fail("the prepared {id} cannot be read")
