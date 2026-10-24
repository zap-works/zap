# A cell prepared once from the player's install into projects/skyrim/assets/prepared/<cell>/ and
# then only read: the engine's prepared file (engine/prepared.zap) under "ZNSK" and the format's
# version. Its head says what the body holds: the merged vertices (shaders.CellVertex, y up),
# their u32 indices in runs by how they are drawn, each texture's levels as the GPU takes them, the
# placed lights, the effects and the particle systems, and the cell's light, fog and image space.

import engine
import fs
import skyrim.esm
import skyrim.nif
import world.shaders

# the version of the files this code writes and reads: a file of another is prepared again
pub formatVersion = 34
pub preparedDir = "projects/skyrim/assets/prepared"

# how a run of triangles is drawn
pub type Kind:
	Opaque
	Tested   # texels under the cutout dropped
	Blended   # alpha over what is behind, after the rest, the depth not written
	Added   # light added to what is behind (Gamebryo's destination factor one)

# a run of indices of one kind and sidedness: one draw
pub type Run:
	kind Kind
	twoSided bool
	first i64
	count i64

pub type PreparedTexture:
	width i64
	height i64
	format engine.TextureFormat
	levels engine.Span[]   # level 0 first, each half the one before

# the cell's light and fog, in 0..1 colors
pub type CellLight:
	ambient Vec3[]   # from +x, -x, +y, -y, +z, -z (y up)
	sunColor Vec3
	sunToward Vec3
	fogNearColor Vec3
	fogFarColor Vec3
	fogNear f32
	fogFar f32
	fogPower f32
	fogMax f32

# a part of a spell's art: its triangles in the model's own space (Skyrim's z up), drawn where the
# game puts them as time goes
pub type SpellPart:
	kind Kind
	vertices shaders.CellVertex[]

# the art a spell shows, a magic effect's casting art or a projectile's model: its parts and the
# light it gives (its place is where it is drawn)
pub type SpellArt:
	form i64   # the ARTO or PROJ it is of
	parts SpellPart[]
	light shaders.PointLight?

# a part of a movable model: its triangles in the model's own space (Skyrim's z up), posed by the
# frame it hangs from (-1: it stays where it is)
pub type MovablePart:
	kind Kind
	twoSided bool
	frame i64
	vertices shaders.CellVertex[]

# A model the scene moves: a door whose model animates a node with its Open and Close sequences
# (the game plays them when the door is activated), left out of the cell's baked buffer. `place`
# takes the model's space to the cell's (y up); the sequences are the model's own, Open first.
pub type Movable:
	refId i64
	place Mat4
	frames nif.NodeFrame[]
	open nif.Sequence
	close nif.Sequence
	halfWidth f32   # the model's half extent along its x, for the doors the actors walk through
	parts MovablePart[]

pub type CellHead:
	cell str
	refs i64   # the references placed, the models they show, the parts drawn
	models i64
	parts i64
	vertices engine.Span   # shaders.CellVertex each
	indices engine.Span   # u32 each, in runs
	runs Run[]
	textures PreparedTexture[]
	lights shaders.PointLight[]
	billboards shaders.Billboard[]
	effects nif.Effect[]   # what the vertices' effects are and how they are animated
	surfaces nif.LitMaterial?[]   # the lit parts' materials, their looks taken when drawn (looks.zap)
	textureKeys {str: i64}   # the textures by their archive keys (a cube's by cubeKey)
	emitters Emitter[]
	spellArt SpellArt[]
	movables Movable[]   # the doors the scene poses, left out of the vertices above
	light CellLight
	emittance Emittance   # what its references' emittance source (XEMI) gives, emittance.zap
	imageSpace esm.ImageSpace
	focus Vec3   # where the camera starts looking: the fire pit, else the middle
	low Vec3   # the box the cell's vertices lie in
	high Vec3
	cast CastHead   # the player and the NPCs, their textures in the body too

pub fn cellPath(cell str) str:
	"{preparedDir}/{cell.lower()}/cell.bin"

pub fn writeCell(path str, head CellHead, body u8[]) ? fs.Error:
	try engine.writePreparedFile(path, "ZNSK", formatVersion, head.toBytes(), body)

# the prepared cell, none when it is missing or of another version; `body` false leaves the body
# unread
pub fn readCell(path str, body bool = true) (CellHead, engine.Prepared)?:
	file = try engine.readPreparedFile(path, "ZNSK", formatVersion, body)
	head = try CellHead.fromBytes(file.headOf())
	(head, file)
