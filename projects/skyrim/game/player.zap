# The player as the game starts him: the plugin's Player (a Nord man) in the prisoner's tunic and
# footwraps, at the character creation's middle weight, prepared with the cell (world/actorHead.zap):
# his body on the skeleton with the clips he moves by, standing inside the cell's load door.

import skyrim
import skyrim.esm
import skyrim.hkx
import skyrim.actor
import engine.physics
import world

pub playerId = 0x7
pub prisonerOutfit = [0x3_C9FE, 0x3_CA00]   # ClothesPrisonerTunic, ClothesPrisonerShoes
startWeight f32 = 0.5
inside f32 = 100.0   # how far into the cell from its load door the player starts

# the clips the player moves by, the clip generators' and the HKX files' name
pub idleClip = "mt_idle"
pub walkClip = "mt_walkforward"
pub runClip = "mt_runforward"
pub playerClips = [idleClip, walkClip, runClip]

# the player's worn models read, or why they cannot be
pub fn playerParts(install skyrim.Install, mut plugin esm.Esm) actor.BodyPart[] ? str:
	out = []
	for w in try plugin.actorModels(playerId, prisonerOutfit):
		out.push(try install.readBodyPart(w.slot, w.key, startWeight))
	out

# the archive keys of the player's worn models, both ends of each weighted pair
pub fn playerModelKeys(mut plugin esm.Esm) str[] ? str:
	out = []
	for w in try plugin.actorModels(playerId, prisonerOutfit):
		out.extend(w.key.weightedKeys())
	out

# the player's character controller standing at `feet`: Skyrim's capsule, 15 units round and 128
# tall, stepping 20 units, walking slopes up to 45 degrees, on the char controller layer (which
# does not meet the biped and the dead: it walks over a ragdoll without moving it)
pub fn playerController(feet Vec3) physics.Character:
	c = feet.characterOf(15.0, 128.0, 20.0, f32(45.0).radians())
	c.layer = charControllerLayer
	c

# Skyrim's fov (the console's `fov`, fDefaultWorldFOV) is the width of a 16:9 frame's view in
# degrees, whatever the window's shape: other shapes keep its height and see more or less at the
# sides (measured against the game's own pictures, README.md)
pub defaultFov f32 = 65.0

# the view's height in radians, bottom to top, for a fov in Skyrim's convention
pub fn fovY(fov f32) f32:
	2.0 * ((fov.radians() * 0.5).tan() * 9.0 / 16.0).atan()

# Where the player starts and the way he faces: inside the cell's first load door, facing
# `focus` (Z up); at the focus without a door.
pub fn startOf(mut plugin esm.Esm, cell esm.Cell, focus Vec3) (Vec3, f32):
	if esm.areaOf(cell.editorId) is area: return plugin.exteriorStartOf(cell, area)
	for r in cell.refs:
		if r.disabled or not r.teleports: continue
		if (plugin.baseRecord(r.base) ?? continue).kind != "DOOR": continue
		toward = Vec3(focus.x - r.position.x, focus.y - r.position.y, 0).normalized()
		return (r.position + toward * inside, toward.x.atan2(toward.y))
	(focus, 0.0)

# An exterior area's start (a game opened in it, not arriving through a door): the load door
# nearest the middle of the area's own cell, facing north.
fn exteriorStartOf(mut plugin esm.Esm, cell esm.Cell, area esm.Area) (Vec3, f32):
	middle = Vec3((f32(area.x) + 0.5) * esm.cellSize, (f32(area.y) + 0.5) * esm.cellSize, 0.0)
	best = Vec3(middle.x, middle.y, 0.0)
	away = 1.0e12
	for r in cell.refs:
		if r.disabled or not r.teleports: continue
		if (plugin.baseRecord(r.base) ?? continue).kind != "DOOR": continue
		d = Vec2(r.position.x - middle.x, r.position.y - middle.y).length()
		if d < away:
			away = d
			best = r.position
	(best, 0.0)

# The player prepared with the cell, his textures laid in the table: his skin toned by his
# record's skin tone, his hair by its color, his face (made by the character creation, not baked)
# as its texture is.
pub fn preparePlayer(
	install skyrim.Install,
	mut plugin esm.Esm,
	skeletons hkx.Skeleton[],
	mut table TextureTable,
	mut body u8[]
) world.ActorHead:
	worn = install.playerParts(plugin) ?? fail
	npc = plugin.npcOf(playerId) ?? fail
	tones = Tones(skin = npc.skinTone ?? neutralTone, hair = plugin.hairColorOf(npc), faceTint = "")
	install.prepareBody(worn, skeletons, 0, 1.0, tones, [], "the player", table, body)
