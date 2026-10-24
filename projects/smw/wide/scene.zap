# Super Mario World's widescreen on recomp.snes's wide drawing (console/wide.zap): a level is drawn
# wide, its layers' margins decoded from the level the cartridge keeps in work RAM (level.zap), its
# sprites spawned, kept and drawn across the margins by the cartridge's windows widened
# (sprites.zap, cartridge/patches.zap). Anything else, the title, the map, menus, a level the
# decode does not reproduce, is the native frame centred on black. Installed into the console by
# the program's setup line.

import recomp.snes.console

mut why = 1   # why the scene is centred: 1 not a level's registers, 2 a level narrower than the
              # picture (or one that does not scroll), 3 no level layer, 4 the decode does not
              # match the live tilemap

pub fn install():
	console.wideHooks = console.WideHooks(
		judge = judgeScene,
		sceneId = sceneId,
		marginPixel = marginPixel
	)

# the level mode and the level's number ($13BF), in the --wide-hashes lines
fn sceneId() i64:
	(i64(console.wram[0x1925]) << 8) | i64(console.wram[0x13BF])

# Line 0 ended: judges the frame that begins and where the native picture sits in the wide one,
# pinned inside the level at its edges.
fn judgeScene() console.SceneJudgement:
	why = 1
	levelLayers = []
	if console.wram[0x100] != 0x14 or not console.isPlainMode1():
		return console.SceneJudgement(why = why)
	readLevelLayers()
	why = 3
	if levelLayers.isEmpty or levelLayers[0].bg != 0: return console.SceneJudgement(why = why)
	terrain = levelLayers[0].copy()
	why = 4
	tx, ty = terrain.viewportTile()
	matches, decodable = console.viewportMatches(0, tx, ty, (x, y): terrain.decodeTile(x, y))
	if not console.viewportAgrees(matches, decodable):
		levelLayers = []
		return console.SceneJudgement(why = why)
	why = 2
	width = terrain.levelWidth()
	if console.wram[0x1411] == 0 or width < console.wideWidth:
		levelLayers = []
		return console.SceneJudgement(why = why)
	bias = console.edgeBias(terrain.camera, 0, width - 256, 1)
	console.SceneJudgement(on = true, why = 0, bias = bias)
