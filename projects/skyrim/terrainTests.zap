# The land of Riverwood (Tamriel's cells around Riverwood02) read from Skyrim.esm, and the terrain
# built from it; skipped quietly without the game's files.

import fs
import engine.physics
import skyrim
import skyrim.esm
import game

tamriel = 0x3C
riverwood02 = 5, -11
inn = "RiverwoodSleepingGiantInn"
innDoor = 0x1_3419   # the Sleeping Giant Inn's front door, whose teleport leads outside

fn plugin() esm.Esm?:
	if not fs.exists(esm.defaultEsm()):
		eprint("skipped: no {esm.defaultEsm()}")
		return none
	esm.openEsm(esm.defaultEsm()) ?? fail

test "Riverwood02's land reads: 33 x 33 heights, four quadrants of textures, layers by quadrant":
	p = plugin() ?? return
	x, y = riverwood02
	l = p.landOf(tamriel, x, y) ?? fail("no land at Riverwood02")
	expect l.formId == 0xA712 and l.heights.len == 33 * 33 and l.normals.len == 33 * 33
	expect (l.heights.min() ?? 0.0) == -448.0 and (l.heights.max() ?? 0.0) == -8.0
	expect l.heights[0] == -168.0 and l.heights[32] == -72.0 and l.heights[32 * 33] == -328.0
	expect l.base == [0xC16, 0xC16, 0x7_99BB, 0xC16]
	expect l.layers.filter(.quadrant == 0).len == 5 and l.layers.len == 21
	grass = p.landTexture(0x1_342A) ?? fail("no LFieldGrass02")
	expect grass.editorId == "LFieldGrass02" and grass.diffuse == "Landscape\\FieldGrass02.dds"
	expect grass.normal == "Landscape\\FieldGrass02_N.dds" and grass.grass.len == 2
	expect p.landOf(tamriel, 5, 300) == none

test "the normals agree with the heights' slopes, and neighbouring cells share their edge":
	p = plugin() ?? return
	x, y = riverwood02
	l = p.landOf(tamriel, x, y) ?? fail("no land")
	east = p.landOf(tamriel, x + 1, y) ?? fail("no land")
	north = p.landOf(tamriel, x, y + 1) ?? fail("no land")
	for k in 0..33:
		expect l.heights[k * 33 + 32] == east.heights[k * 33]
		expect l.heights[32 * 33 + k] == north.heights[k]
	agreeing = 0
	for r in 1..32:
		for c in 1..32:
			dx = (l.heights[r * 33 + c + 1] - l.heights[r * 33 + c - 1]) / 256.0
			dy = (l.heights[(r + 1) * 33 + c] - l.heights[(r - 1) * 33 + c]) / 256.0
			slope = Vec3(-dx, -dy, 1.0).normalized()
			if slope @ l.normals[r * 33 + c] > 0.95: agreeing += 1
	print("{agreeing} of {31 * 31} normals within 18 degrees of the slope")
	expect agreeing > 31 * 31 * 9 / 10

test "the world's land defaults read":
	p = plugin() ?? return
	w = p.worldLand(tamriel) ?? fail("no Tamriel")
	expect w.defaultHeight < -1000.0 and w.waterHeight < 0.0

# the install, the plugin and the nine cells around Riverwood02 as terrain
fn riverwoodTerrain() (esm.Esm, game.Terrain)?:
	p = try plugin()
	install = skyrim.openInstall(skyrim.defaultInstall) ?? fail
	(p, install.terrainOf(p, tamriel, 4, -12, 6, -10))

test "the terrain of the nine cells: vertices, textures, and the ground where the front door leads":
	p, t = riverwoodTerrain() ?? return
	expect t.grids.len == 9 and t.vertices.len == 9 * 4 * 17 * 17
	expect t.indices.len == 9 * 4 * 16 * 16 * 6 and t.textures.len > 10
	for v in t.vertices:
		expect v.weights.x >= 0.0 and v.normal.length() > 0.99
	records = p.cellRecords(inn) ?? fail("no inn")
	door = records.find(.formId == innDoor) ?? fail("no door")
	at = esm.dataOf(door.fields, "XTEL") ?? fail("no teleport")
	x = door.body.f32le(at + 4)
	y = door.body.f32le(at + 8)
	z = door.body.f32le(at + 12)
	ground = t.heightAt(x, y) ?? fail("no ground at the arrival")
	print("arrival ({x}, {y}, {z}), ground {ground}")
	# the door stands on the inn's foundation, above the ground its steps start from
	expect (z - ground) > 50.0 and (z - ground) < 120.0

test "the trees of Riverwood02 stand on the terrain's ground":
	p, t = riverwoodTerrain() ?? return
	x, y = riverwood02
	trees = p.placedOfKind(tamriel, x, y, "TREE")
	expect trees.len > 40
	near = 0
	for tree in trees:
		ground = t.heightAt(tree.x, tree.y) ?? fail("no ground under a tree")
		if (tree.z - ground).abs() < 25.0: near += 1
	print("{near} of {trees.len} trees within 25 units of the ground")
	expect near * 10 > trees.len * 8

test "the player walks on the terrain and stands on its ground":
	_, t = riverwoodTerrain() ?? return
	w = game.havokWorld()
	w.collideTerrain(t)
	x = 5.0 * 4096.0 + 2000.0
	y = -11.0 * 4096.0 + 2100.0
	ground = t.heightAt(x, y) ?? fail("no ground")
	c = physics.characterOf(Vec3(x, y, ground + 60.0), 15.0, 128.0, 20.0, f32(45.0).radians())
	loop 120:
		c.walk(w, Vec3(0.0, 0.0, 0.0), 1.0 / 60.0)
	expect c.onFloor and c.feet.z.isClose(ground, 1.0)
	loop 120:
		c.walk(w, Vec3(150.0, 0.0, 0.0), 1.0 / 60.0)
	now = t.heightAt(c.feet.x, c.feet.y) ?? fail("no ground")
	print("walked to {c.feet}, ground {now}")
	expect c.feet.x > x + 100.0 and c.onFloor and c.feet.z.isClose(now, 6.0)
