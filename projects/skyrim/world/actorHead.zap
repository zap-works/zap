# The actors as the cell's prepared file holds them: the player and the NPCs, each a body as the
# engine's skinned models take it (engine/gltf's Model, y up) with each part's material, posed by
# one of the skeletons (the male's, the female's) whose clips every body of it shares; the
# textures they read (laid in the file's body as the cell's are); the NPCs' packages, the
# furniture and idle markers they use and the navmesh they walk.

import engine
import engine.gltf
import skyrim.actor
import skyrim.hkx
import world.shaders

# how a part of the body is drawn: its textures (of the cast's), its lighting (its highlight, its
# soft, rim and back lighting with their maps), its cutout, and how the skin shader tones it
# (nif.toneFace, toneSkin, toneHair; 0 none)
pub type ActorMaterial:
	diffuse i64
	normalMap i64   # the surface's bends, its alpha the highlight's mask
	look shaders.Look
	cutout f32   # the alpha under which a texel is dropped (0..1)
	tone i64
	toneColor Vec3   # the skin's tone, the hair's color
	tintMap i64   # a face's FaceGen tint
	detailMap i64   # a face's detail

# the body's model as engine/gltf's Model holds it, but its images (whose type the file cannot
# hold): part k is drawn with materials[k]
pub type ActorBody:
	nodes gltf.Node[]
	order i64[]
	palette i64[]
	inverseBinds f32[]
	vertices f32[]
	parts gltf.Part[]
	clips gltf.Clip[]

# a body: its model (no clips: its skeleton's move it) and how it looks
pub type ActorHead:
	body ActorBody
	materials ActorMaterial[]
	skeleton i64   # the cast's skeleton that poses it
	scale f32   # its height over the skeleton's
	faces actor.FaceShape[] = []   # the head shapes the lip track and the blinks move

# a skeleton: its nodes with the clips every body of it moves by, and how each clip's motion
# carries the actor (the behavior's: where it moves and turns it, by clip; how fast, units a
# second, 0 for none); its bones and its ragdoll as its HKX file holds them
pub type SkeletonHead:
	rig ActorBody
	motions actor.Motion[]
	speeds f32[]
	bones hkx.Skeleton
	ragdoll hkx.Ragdoll?

# a package as the AI runs it: what it does (its template), when, where, whether its conditions
# hold at a new game, and what a sandbox may do there (its template's inputs)
pub type PlanHead:
	editorId str
	template str
	schedule actor.Schedule
	holds bool
	inCell bool   # its place is in the cell
	center Vec3   # its place (Skyrim's units, Z up)
	radius f32
	sitting bool
	sleeping bool
	eating bool
	idleMarkers bool
	special bool   # furniture of FurnitureSpecial
	wandering bool
	energy f32   # 0 to 100: how often a sandbox changes what it does

pub type NpcHead:
	formId i64
	refId i64   # its placed actor (ACHR), 0 for one its packages bring
	editorId str
	name str
	female bool
	look ActorHead
	start Vec3   # where the ACHR stands (Z up)
	heading f32   # radians from north (+y) toward east (+x)
	plans PlanHead[]   # in the order the game tries them

# a place an actor goes to sit, sleep, lean or play an idle: a furniture's marker or an idle
# marker, where the actor stands and the way it faces
pub type MarkerHead:
	refId i64
	kind str   # its animations' set: "chair", "bed", "leantable", "counter", "sweep"...
	special bool   # its furniture has FurnitureSpecial
	position Vec3
	heading f32
	entries i64   # the sides it is entered from (FNPR's: 1 the front, 2 behind, 4 right, 8 left)
	dwell f32   # an idle marker's time (IDLT, seconds), 0 for furniture

# what the AI reads of the plugin's game settings: a sandbox's dwell (fSandboxDurationBase game
# hours, times fSandboxDurationMultFurniture at a furniture, fSandboxDurationMultIdleMarker at an
# idle marker) and how fast a head turns to what it tracks (fHeadTrackSpeedMin degrees a second
# up to fHeadTrackSpeedMinAngle away, fHeadTrackSpeedMax from fHeadTrackSpeedMaxAngle)
pub type AiSettings:
	dwellBase f32
	dwellFurniture f32
	dwellIdleMarker f32
	trackSpeedMin f32
	trackSpeedMinAngle f32
	trackSpeedMax f32
	trackSpeedMaxAngle f32

# the clips of one kind of marker: the way in, the loop, the way out, and the events the graph is
# sent to enter it (one after the other) and to leave it
pub type MarkerClips:
	kind str
	enter str
	looping str
	leave str
	enterEvents str[]
	leaveEvent str

# a door the actors may open: its reference, its base record and where it stands (Skyrim's units,
# Z up); a load door (teleports) leads out of the cell and is left to the player
pub type DoorHead:
	refId i64
	base i64
	position Vec3
	heading f32
	teleports bool
	halfWidth f32 = 48.0   # half the leaf's extent along its x when closed, from its model

pub type CastHead:
	textures PreparedTexture[]
	skeletons SkeletonHead[]   # the male's, the female's
	player ActorHead
	start Vec3   # where the player's feet stand when the cell opens (Skyrim's units, Z up)
	heading f32   # the way the player faces then: radians from north (+y) toward east (+x)
	npcs NpcHead[]
	markers MarkerHead[]
	markerClips MarkerClips[]   # the clips each kind of marker is entered, looped and left by
	doors DoorHead[]
	navmesh engine.NavMesh   # the cell's floor (Skyrim's units, Z up)
	ai AiSettings

pub fn actorBodyOf(move m gltf.Model) ActorBody:
	ActorBody(nodes = m.nodes, order = m.order, palette = m.palette,
		inverseBinds = m.inverseBinds, vertices = m.vertices, parts = m.parts,
		clips = m.clips)

pub fn modelOf(move b ActorBody) gltf.Model:
	gltf.Model(nodes = b.nodes, order = b.order, palette = b.palette,
		inverseBinds = b.inverseBinds, vertices = b.vertices, parts = b.parts,
		images = [], clips = b.clips)
