# The distant land, objects and trees around Riverwood (game/lod.zap, game/lodTrees.zap) read from
# the install's archives; skipped quietly without the game's files.

import fs
import skyrim
import skyrim.esm
import game

riverwood = Vec2(23259.771, -44476.164)
tamriel = "tamriel"

fn install() skyrim.Install?:
	if not fs.exists(esm.defaultEsm()):
		eprint("skipped: no {esm.defaultEsm()}")
		return none
	skyrim.openInstall(skyrim.defaultInstall) ?? fail

test "the blocks around the eye: the smallest next to it, the biggest far, none overlapping":
	blocks = riverwood.lodBlocks(1.5, 250000.0)
	expect blocks.filter(.level == 4 and .x == 4 and .y == -12).len == 1
	expect blocks.filter(.level == 32).len > 0
	for b in blocks:
		expect b.level in [4, 8, 16, 32] and b.x % b.level == 0 and b.y % b.level == 0
	cells {i64: i64} = {}
	for b in blocks:
		for y in b.y..b.y + b.level:
			for x in b.x..b.x + b.level:
				cells[y * 4096 + x] = cells.get(y * 4096 + x) ?? 0 + 1
	for count in cells.values():
		expect count == 1
	print("{blocks.len} blocks over {cells.len} cells")

test "a block splits while the eye is within 1.5 times its half diagonal, and not beyond":
	near = game.LodBlock(32, 0, -32)
	expect near.splits(Vec2(0.0, -2000.0), 1.5)
	expect not near.splits(Vec2(300000.0, 0.0), 1.5)
	expect not game.LodBlock(4, 4, -12).splits(riverwood, 1.5)
	# a level 8 block's reach is 1.5 x 0.5 x 8 x 4096 x sqrt 2 = 34750 units
	expect game.LodBlock(8, 8, -16).splits(Vec2(65536.0 + 34000.0, -50000.0), 1.5)
	expect not game.LodBlock(8, 8, -16).splits(Vec2(65536.0 + 35500.0, -50000.0), 1.5)

test "the tree list and a block's trees read: 34 kinds, 107 trees in 15 groups inside the block":
	i = install() ?? return
	lst = i.installRead("meshes/terrain/tamriel/trees/tamriel.lst") ?? fail("no tree list")
	kinds = game.treeKinds(lst)
	expect kinds.len == 34
	for k in kinds:
		expect k.width > 100.0 and k.height > 100.0 and k.left < k.right and k.top < k.bottom
		expect k.left > -0.01 and k.right < 1.01 and k.top > -0.01 and k.bottom < 1.01
	btt = i.installRead(game.lodKey(tamriel, "btt", game.LodBlock(4, 4, -12))) ?? fail("no block")
	trees = game.treeInstances(btt)
	expect trees.len == 107
	for t in trees:
		expect t.kind < kinds.len and t.scale > 0.3 and t.scale < 3.0
		expect t.place.x >= 16384.0 and t.place.x <= 32768.0
		expect t.place.y >= -49152.0 and t.place.y <= -32768.0

# how far under the near land the distant land's vertices over it lie on average, with this drop
fn meanSink(i skyrim.Install, near game.Terrain, drop str):
	settings = skyrim.readIniSettings()
	settings.values["flodlanddropamount:lod"] = drop.copy()
	lod = i.lodOf(tamriel, riverwood, game.loadedAround(5, -11, 5), settings)
	total = 0.0
	count = 0.0
	for v in lod.vertices:
		if v.maps.w < 0.5 or (v.position.x - 22528.0).abs() > 10239.0 or
			(-v.position.z + 43008.0).abs() > 10239.0:
			continue
		ground = near.heightAt(v.position.x, -v.position.z) ?? continue
		total += ground - v.position.y
		count += 1.0
	expect count > 50.0
	total / count

test "the distant land under the loaded cells sinks by fLODLandDropAmount":
	i = install() ?? return
	plugin = esm.openEsm(esm.defaultEsm()) ?? fail
	near = i.terrainOf(plugin, 0x3C, 3, -13, 7, -9)
	sunk = i.meanSink(near, "230.0")
	level = i.meanSink(near, "0.0")
	print("the distant land is {level} units under the near land, {sunk} sunk")
	expect (sunk - level - 230.0).abs() < 0.5

test "the distant trees stand outside the loaded cells, eight vertices and twelve indices each":
	i = install() ?? return
	settings = skyrim.readIniSettings()
	area = game.loadedAround(5, -11, 5)
	trees = i.treesOf(tamriel, riverwood, area, settings)
	every = i.treesOf(tamriel, riverwood, game.loadedAround(5, -11, 0), settings)
	print("{trees.count} trees outside the loaded cells, {every.count} with them")
	expect trees.count > 1000 and every.count > trees.count
	expect trees.vertices.len == trees.count * 8 and trees.indices.len == trees.count * 12
