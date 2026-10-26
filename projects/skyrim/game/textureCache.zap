# The textures a prepare made, kept under projects/skyrim/assets/prepared/cache/ by a key of all
# they are made from: the game's file each reads (its archive with the archive's size and time, or
# the extracted file's time), the sources of the code that lays it out or bakes it (fs.zapStamp)
# and a baked one's inputs. A prepare reads back each texture whose key is unchanged instead of
# decoding or baking it again; the cache is only ever a copy (deleting the dir costs one slow
# prepare).

import engine
import fs
import skyrim
import world

cacheDir = "{world.preparedDir}/cache"

# the code a texture read from the archives is laid out by, and the code a baked one comes from
layoutSources = ["std/image", "projects/skyrim/game/textures.zap"]
bakeSources = ["std/image", "projects/skyrim/skyrim/actor", "projects/skyrim/game/cast.zap"]

# the stamps of the code, "" when nothing is kept (a table made outside a prepare)
pub type TextureCache:
	layout str = ""
	bake str = ""

pub fn newTextureCache() TextureCache:
	TextureCache(layout = fs.zapStamp(layoutSources), bake = fs.zapStamp(bakeSources))

# what a kept file holds: the whole key (two keys may share a file name) and the texture, its
# levels' spans in the file's body
type Entry:
	key str
	texture world.PreparedTexture

fn entryPath(key str):
	"{cacheDir}/{key.hash():016x}.bin"

# the key of the texture with this archive key laid out (`how` tells a cube's strip from a plain
# one), "" when nothing is kept
pub fn layoutKey(c TextureCache, i skyrim.Install, how str, key str) str:
	if c.layout.isEmpty: return ""
	"{how} {key} {i.installStamp(key)} {c.layout}"

# the key of a texture baked from `inputs` and the game's files with these archive keys
pub fn bakeKey(c TextureCache, i skyrim.Install, keys str[], inputs str) str:
	if c.bake.isEmpty: return ""
	stamps = keys.map("{it} {i.installStamp(it)}").join(" ")
	"bake {stamps} {inputs} {c.bake}"

# the texture kept under key with its levels appended to body, none when none is
pub fn readKept(key str, mut body u8[]) world.PreparedTexture?:
	if key.isEmpty: return none
	file = try engine.readPreparedFile(entryPath(key), "ZNSC", world.formatVersion)
	e = try Entry.fromBytes(file.headOf())
	if e.key != key: return none
	kept = file.bodyOf()
	levels = []
	for s in e.texture.levels:
		levels.push(body.append(kept.bytesAt(s)))
	world.PreparedTexture(width = e.texture.width, height = e.texture.height,
		format = e.texture.format, levels)

# the texture, whose levels lie in body, kept under key (nothing for an empty key)
pub fn keep(key str, t world.PreparedTexture, body u8[]):
	if key.isEmpty: return
	own u8[] = []
	levels = []
	for s in t.levels:
		levels.push(own.append(body.bytesAt(s)))
	texture = world.PreparedTexture(width = t.width, height = t.height, format = t.format, levels)
	e = Entry(key = key.copy(), texture)
	path = entryPath(key)
	engine.writePreparedFile(path, "ZNSC", world.formatVersion, e.toBytes(), own) ??
		fail("cannot write {path}: {error}")
