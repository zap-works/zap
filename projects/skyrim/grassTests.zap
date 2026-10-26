# The grass of Riverwood (game/grassPlace.zap, game/grass.zap) and the water types (esm/water.zap)
# read from Skyrim.esm; skipped quietly without the game's files.

import fs
import skyrim.esm
import game

tamriel = 0x3C
riverwood02 = 5, -11

fn plugin() esm.Esm?:
	if not fs.exists(esm.defaultEsm()):
		eprint("skipped: no {esm.defaultEsm()}")
		return none
	esm.openEsm(esm.defaultEsm()) ?? fail

# the executable's twister, as an independent transcription of its code draws (0x140ce4460,
# 0x140ce44e0): the first words, and those after the first regeneration
test "the twister draws as the executable's does":
	t = game.seededTwister(12_345)
	first = [t.nextBelow(0xffff_ffff), t.nextBelow(0xffff_ffff), t.nextBelow(0xffff_ffff)]
	expect first == [4_142_182_111, 460_351_632, 2_723_093_241]
	loop 620:
		t.nextBelow(0xffff_ffff)
	around = [t.nextBelow(0xffff_ffff), t.nextBelow(0xffff_ffff), t.nextBelow(0xffff_ffff)]
	expect around == [3_102_332_379, 4_170_408_829, 3_674_951_461]
	loop 873:
		t.nextBelow(0xffff_ffff)
	expect t.nextBelow(0xffff_ffff) == 2_196_837_435
	# Riverwood02's seed is its x times its y, as an unsigned number: -55
	cell = game.seededTwister(u32.wrap(5 * -11))
	expect [cell.nextBelow(0x7fff), cell.nextBelow(0x7fff), cell.nextBelow(0x7fff)] ==
		[22_179, 27_503, 32_692]
	expect [cell.nextBelow(0xffff_ffff), cell.nextBelow(0xffff_ffff)] == [77_130_549, 2_778_393_610]
	small = game.seededTwister(0)
	expect [
		small.nextBelow(100),
		small.nextBelow(100),
		small.nextBelow(100),
		small.nextBelow(100)
	] ==
		[64, 95, 92, 37]

test "half floats: the known values, and every finite half comes back from its float":
	expect game.halfOf(1.0) == 0x3c00 and game.halfOf(-2.0) == 0xc000 and game.halfOf(0.0) == 0
	expect game.halfOf(65504.0) == 0x7bff and game.halfOf(1.0 / 3.0) == 0x3555
	expect game.halfOf(100000.0) == 0x7c00 and game.halfOf(-0.0) == 0x8000
	expect game.halfValue(0x3c00) == 1.0 and game.halfValue(0xc000) == -2.0
	expect game.halfValue(0x0001) == 5.9604645e-8
	for h in 0..65536:
		if (h & 0x7c00) == 0x7c00: continue
		expect game.halfOf(game.halfValue(h)) == h
	# a position's rounding at the size the cells' blocks reach: 16 units from 16384 to 32768
	expect game.halfValue(game.halfOf(21_890.0)) == 21_888.0
	expect game.halfValue(game.halfOf(-45_060.0)) == -45_056.0

test "the slope cosines: the table at 0, 45, 90 and 180 degrees":
	table = game.cosineTable()
	expect table.len == 512 and table[0] == 1.0
	expect (table[64] - 0.70710678).abs() < 0.0001 and table[128].abs() < 0.0001
	expect (table[256] + 1.0).abs() < 0.0001

test "a cell's plants are the same every time, inside the cell, on its land, in the slopes allowed":
	p = plugin() ?? return
	x, y = riverwood02
	lands = p.landsAround(tamriel, x, y)
	cosines = game.cosineTable()
	found {i64: game.Plant[]} = {}
	p.plantsOfCell(tamriel, x, y, lands, cosines, found)
	again {i64: game.Plant[]} = {}
	p.plantsOfCell(tamriel, x, y, lands, cosines, again)
	expect found.len == 2 and again.len == 2
	total = 0
	for form, plants in found:
		other = again.get(form) ?? fail("no kind {form:X}")
		expect plants.len == other.len and plants.len > 100
		for k, plant in plants:
			expect plant.place == other[k].place and plant.rows == other[k].rows
			expect plant.place.x >= 20_400.0 and plant.place.x <= 24_700.0
			expect plant.place.y >= -45_100.0 and plant.place.y <= -40_900.0
			s = lands.surfaceAt(plant.place.x, plant.place.y) ?? fail("no land under a plant")
			expect (s.height - plant.place.z).abs() < 6.0
			expect s.normal.z > 0.7
			expect plant.shade > 0.0 and plant.shade < 1.0
			expect plant.rows.len == 9 and plant.rows[8] > 0.7
		total += plants.len
	print("{total} plants in Riverwood02")
	fieldGrass = found.get(0x1_35BE) ?? fail("no FieldGrass01")
	flowers = found.get(0x10_98CA) ?? fail("no FieldGrass02")
	expect fieldGrass.len == 1865 and flowers.len == 582

test "the water types read: the river's flow map type, its colors and its flags":
	p = plugin() ?? return
	w = p.waterTypeOf(0x100_1232) ?? fail("no RiverWaterFlow")
	expect w.editorId == "RiverWaterFlow" and (w.flags & esm.flagFlowMap) != 0
	expect w.normals[3] == "data\\Textures\\Water\\RiverFlow.dds"
	expect (w.shallow.x - 0.1490196).abs() < 0.001 and w.refractionMagnitude == 40.0
	expect w.windSpeed.len == 3 and w.uvScale == [1667.0, 4855.0, 580.0]
	x, y = riverwood02
	water = p.cellWaterAt(tamriel, x, y) ?? fail("Riverwood02 has water")
	expect water.height == -250.0 and water.waterType == 0x100_1232
	distant = p.worldLodWater(tamriel) ?? fail("no LOD water")
	expect distant.waterType != 0
