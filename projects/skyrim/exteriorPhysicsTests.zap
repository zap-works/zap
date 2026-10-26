# The player on the exterior's physics (game/travel.zap, esm/area.zap): the town's ground under
# him, from one cell of the loaded grid into the next.

import engine.physics
import fs
import skyrim.esm
import skyrim
import game

riverwood = esm.Area(0x3C, 5, -11)

test "the player stands on the town's ground and walks from one cell into the next":
	if not fs.exists(esm.defaultEsm()): return
	cell = game.openOrPrepare(riverwood.areaId(), game.Load(textures = false))
	start = Vec3(23259.771, -44476.164, -6.0)
	crossed = false
	for heading in [
		Vec3(0, -1, 0),
		Vec3(1, 0, 0),
		Vec3(0, 1, 0),
		Vec3(-1, 0, 0),
		Vec3(-0.7, 0.7, 0),
		Vec3(-0.7, -0.7, 0),
		Vec3(0.7, -0.7, 0),
		Vec3(0.7, 0.7, 0)
	]:
		c = start.playerController()
		loop 1500:
			c.walk(cell.physics.world, heading * 200.0, 1.0 / 60.0)
		x, y = c.feet.gridOf()
		if (x, y) != (riverwood.x, riverwood.y) and c.onFloor and (c.feet.z + 8.25).abs() < 400.0:
			crossed = true
	expect crossed
