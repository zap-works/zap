# The textures a cell's parts name, read from the install once each and laid in the body as the
# GPU takes them: BC1, BC3, BC4, BC5 and BC7 levels as they are (or, prepared for ASTC, Android's,
# transcoded: engine.astcLevels), any other format (or a block texture not a multiple of 4 across)
# decoded to RGBA. A texture no archive has, or that cannot be read, is drawn with a flat one.

import engine
import fs
import image
import image.dds
import skyrim
import skyrim.nif
import world

# the flat textures, first in every cell: a gray diffuse, a normal map facing out with no highlight
pub flatDiffuse = 0
pub flatNormal = 1

# the blocks the game's BC textures are prepared as (prepare.zap's --textures)
mut blockTarget = engine.BlockTarget.Bc

pub fn prepareTexturesAs(target engine.BlockTarget):
	blockTarget = target

pub type TextureTable:
	textures world.PreparedTexture[]
	byKey {str: i64} = {}   # an archive key -> its texture
	missing str[] = []
	cache TextureCache = TextureCache()   # where laid-out and baked textures are kept
	mipSkip i64 = 0   # the top levels of an archive texture left out (iTexMipMapSkip)

	# the table's keys by index, one `index key` line each (diagnostics: main.zap --ids)
	pub fn writeNames(path str):
		lines = []
		for k, v in byKey:
			lines.push("{v} {k}")
		fs.writeFile(path, lines.join("\n")) ?? fail("cannot write {path}")

	# the index of a flat 4 x 4 texture of this RGBA pixel, made the first time under `key`
	pub mut fn flatIndex(key str, pixel u8[], mut body u8[]) i64:
		if byKey.get(key) is k: return k
		textures.push(flat(body, pixel))
		byKey[key.copy()] = textures.len - 1
		textures.len - 1

	# The index of the texture at `path`, read and laid in the body the first time; `fallback` for
	# no path or a texture that cannot be had.
	pub mut fn textureIndex(i skyrim.Install,
		path str,
		fallback i64,
		mut body u8[]
	) i64:
		if path.isEmpty: return fallback
		key = nif.textureKey(path)
		if byKey.get(key) is k: return k
		kept = cache.layoutKey(
			i,
			"texture skip {mipSkip}{" astc" if blockTarget == .Astc else ""}",
			key
		)
		index = fallback
		if readKept(kept, body) is t:
			textures.push(t)
			index = textures.len - 1
		else:
			match i.installTexture(key):
				d:
					textures.push(d.laidOut(body, mipSkip))
					index = textures.len - 1
					keep(kept, textures[index], body)
				error: missing.push(error)
		byKey[key] = index
		index

	# The index of the cube map at `path` laid as one texture for a cube sample (shaders.cubeColor):
	# its six faces side by side, each level of the strip the faces' levels side by side; `fallback`
	# when it cannot be had.
	pub mut fn cubeIndex(i skyrim.Install, path str, fallback i64, mut body u8[]) i64:
		if path.isEmpty: return fallback
		key = world.cubeKey(path)
		if byKey.get(key) is k: return k
		kept = cache.layoutKey(i, "cube", nif.textureKey(path))
		index = fallback
		if readKept(kept, body) is t:
			textures.push(t)
			index = textures.len - 1
		else:
			match i.installTexture(nif.textureKey(path)):
				d:
					if d.stripOfFaces(body) is strip:
						textures.push(strip)
						index = textures.len - 1
						keep(kept, textures[index], body)
				error: missing.push(error)
		byKey[key] = index
		index

	# The index of the texture kept under `kept` (bakeKey), read back under `key` the first time;
	# none when none is kept
	pub mut fn keptIndex(key str, kept str, mut body u8[]) i64?:
		if byKey.get(key) is k: return k
		t = try readKept(kept, body)
		textures.push(t)
		byKey[key.copy()] = textures.len - 1
		textures.len - 1

	# The index of an image made here (not read from the archives) under `key`, laid in the body as
	# RGBA with its levels, each half the one before, the first time.
	pub mut fn imageIndex(key str, img image.Image, mut body u8[]) i64:
		if byKey.get(key) is k: return k
		levels = [body.append(img.cells.bytes())]
		level = img.copy()
		while level.width > 1 or level.height > 1:
			level = level.resize((level.width / 2).max(1), (level.height / 2).max(1))
			levels.push(body.append(level.cells.bytes()))
		textures.push(world.PreparedTexture(width = img.width, height = img.height, format = .Rgba8,
			levels))
		byKey[key.copy()] = textures.len - 1
		textures.len - 1

fn flat(mut body u8[], pixel u8[]):
	bytes = []
	loop 16:
		bytes.extend(pixel)
	world.PreparedTexture(width = 4, height = 4, format = .Rgba8, levels = [body.append(bytes)])

pub fn newTextureTable(mut body u8[]) TextureTable:
	diffuse = flat(body, [160, 160, 160, 255])
	normal = flat(body, [128, 128, 255, 0])
	TextureTable(
		textures = [diffuse, normal],
		mipSkip = i64(skyrim.readIniSettings().iniNumber("iTexMipMapSkip:Display").max(0.0))
	)

fn kept(f dds.Format) engine.TextureFormat?:
	match f:
		Bc1: .Bc1
		Bc3: .Bc3
		Bc4: .Bc4
		Bc5: .Bc5
		Bc7: .Bc7
		_: none

# a cube map's six faces as one RGBA texture, side by side
fn stripOfFaces(d dds.Dds, mut body u8[]) world.PreparedTexture?:
	faces = []
	for f in 0..6:
		faces.push(try d.face(f))
	levels = []
	for k in 0..d.levels:
		across = dds.levelDim(d.width, k)
		strip = image.Image(across * 6, dds.levelDim(d.height, k), fill = image.Rgba8(0, 0, 0, 255))
		for f in 0..6:
			strip.paste(faces[f].decodeLevel(k), f * across, 0)
		levels.push(body.append(strip.cells.bytes()))
	world.PreparedTexture(width = d.width * 6, height = d.height, format = .Rgba8, levels)

# the top levels left out, as many as asked while the texture stays 4 texels across and a level remains
fn laidOut(d dds.Dds, mut body u8[], skip i64):
	first = 0
	while first < skip and first + 1 < d.levels and dds.levelDim(d.width, first + 1) >= 4 and
		dds.levelDim(d.height, first + 1) >= 4:
		first += 1
	width = dds.levelDim(d.width, first)
	height = dds.levelDim(d.height, first)
	levels = []
	if d.format.kept() is format:
		if width % 4 == 0 and height % 4 == 0 and blockTarget == .Astc:
			astc = format.astcFormatOf()
			for level in engine.astcLevels((first..d.levels).map(d.decodeLevel(it)), astc):
				levels.push(body.append(level))
			return world.PreparedTexture(width, height, format = astc, levels)
		if width % 4 == 0 and height % 4 == 0:
			for k in first..d.levels:
				levels.push(body.append(d.levelBytes(k)))
			return world.PreparedTexture(width, height, format, levels)
	for k in first..d.levels:
		levels.push(body.append(d.decodeLevel(k).cells.bytes()))
	world.PreparedTexture(width, height, format = .Rgba8, levels)
