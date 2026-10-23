# A level's collision data (TERRAIN): a stream of signed 16-bit words. First the vertices, then
# groups of triangles by surface type (some types carry a parameter per triangle), then the
# special objects the level places with its ground (trees, doors), then its water boxes. The
# macro objects (MACRO_OBJECTS) are a list of their own: a preset, a turn, a place, a parameter.
# The presets (which model and behavior an object is) are tables in the game's code.

pub type Surface:
	kind i64
	a i64   # vertex indices
	b i64
	c i64
	param i64

pub type Placed:
	preset i64
	model i64   # the model id the preset gives (0 none)
	behavior i64   # its behavior script (segment 0x13), 0 unknown
	x i64
	y i64
	z i64
	yaw i64   # degrees
	param i64

pub type WaterBox:
	id i64
	x1 i64
	z1 i64
	x2 i64
	z2 i64
	y i64

pub type Collision:
	vertices i64[]   # x, y, z for each
	surfaces Surface[]
	specials Placed[]
	water WaterBox[]

# the preset tables in the US cartridge (the code's data): special objects, macro objects
specialPresets = 0xE_D350
macroPresets = 0xE_C7E0

# the types whose triangles carry a parameter (a force: flowing water, wind, quicksand)
fn hasParam(kind i64):
	kind in [0x0004, 0x000E, 0x0024, 0x0025, 0x0027, 0x002C, 0x002D, 0x0040]

# the collision data at `at` (a segmented address)
pub fn readCollision(s Segments, rom Rom, at0 i64) Collision:
	col = Collision(vertices = [], surfaces = [], specials = [], water = [])
	at = at0
	loop 100_000:
		word = s.s16At(at)
		at += 2
		if word == 0x0040:
			n = s.s16At(at)
			at += 2
			loop n * 3:
				col.vertices.push(s.s16At(at))
				at += 2
		elif word == 0x0041:
			continue
		elif word == 0x0042:
			return col
		elif word == 0x0043:
			n = s.s16At(at)
			at += 2
			loop n:
				preset = s.s16At(at)
				model, extra, behavior = rom.specialPreset(preset)
				yaw = 0
				param = 0
				if extra >= 1:
					yaw = s.s16At(at + 8) * 360 / 256
				if extra >= 2:
					param = s.s16At(at + 10)
				col.specials.push(
					Placed(
						preset,
						model,
						behavior,
						x = s.s16At(at + 2),
						y = s.s16At(at + 4),
						z = s.s16At(at + 6),
						yaw,
						param
					)
				)
				at += 8 + extra * 2
		elif word == 0x0044:
			n = s.s16At(at)
			at += 2
			loop n:
				col.water.push(
					WaterBox(
						id = s.s16At(at),
						x1 = s.s16At(at + 2),
						z1 = s.s16At(at + 4),
						x2 = s.s16At(at + 6),
						z2 = s.s16At(at + 8),
						y = s.s16At(at + 10)
					)
				)
				at += 12
		else:
			kind = word
			n = s.s16At(at)
			at += 2
			withParam = hasParam(kind)
			loop n:
				col.surfaces.push(
					Surface(
						kind,
						a = s.s16At(at),
						b = s.s16At(at + 2),
						c = s.s16At(at + 4),
						param = s.s16At(at + 6) if withParam else 0
					)
				)
				at += 8 if withParam else 6
	fail("collision data: no end")
	col

# A special object's preset: its model and how many words follow its place (0 none, 1 a turn,
# 2 a turn and a parameter, 3 three words), from the table {id, type, default parameter, model,
# behavior} ending with id 0xFF.
fn specialPreset(rom Rom, preset i64) (i64, i64, i64):
	at = specialPresets
	while at + 8 <= rom.bytes.len and rom.bytes[at] != 0xFF:
		if rom.bytes[at] == preset:
			kind = i64(rom.bytes[at + 1])
			extra = [0, 1, 2, 3, 1][kind.min(4)]
			return (rom.bytes[at + 3], extra, rom.bytes.u32be(at + 4))
		at += 8
	(0, 0, 0)

# the macro objects of the list at `at`: records of five words ending with 0x001E
pub fn readMacroObjects(s Segments, rom Rom, at0 i64) Placed[]:
	out = []
	at = at0
	loop 10_000:
		w0 = s.u16At(at)
		if w0 == 0x001E or w0 == 0: return out
		preset = (w0 & 0x1FF) - 31
		yaw = w0.bits(9, 7) << 1   # 256ths of a turn
		entry = macroPresets + preset * 8
		known = entry + 8 <= rom.bytes.len and preset >= 0
		model = rom.bytes.i16be(entry + 4) if known else 0
		behavior = rom.bytes.u32be(entry) if known else 0
		out.push(Placed(
			preset,
			model,
			behavior,
			x = s.s16At(at + 2),
			y = s.s16At(at + 4),
			z = s.s16At(at + 6),
			yaw = yaw * 360 / 256,
			param = s.u16At(at + 8)))
		at += 10
	out
