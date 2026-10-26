# The kinds of block, what each is like (solid, see-through) and the texture of each of its faces.
# The world module: blocks, the world they make, its meshes, and what moves through it.

pub air = 0
pub grass = 1
pub dirt = 2
pub stone = 3
pub sand = 4
pub log = 5
pub leaves = 6
pub planks = 7
pub brick = 8
pub glass = 9
pub water = 10
pub snow = 11
pub coal = 12
pub iron = 13
pub gravel = 14
pub tallGrass = 15   # a plant: two crossed quads, not a cube
pub blockKinds = 16

blockNames = [
	"air",
	"grass",
	"dirt",
	"stone",
	"sand",
	"log",
	"leaves",
	"planks",
	"brick",
	"glass",
	"water",
	"snow",
	"coal ore",
	"iron ore",
	"gravel",
	"tall grass"
]

# the images of the faces, one texture layer each, in layer order (assets/blocks/<name>.png, its
# color, and <name>_surface.png, its normal, roughness and occlusion; makeTextures.zap makes them)
pub tileNames = [
	"grass_top",
	"dirt_grass",
	"dirt",
	"stone",
	"sand",
	"trunk_side",
	"trunk_top",
	"leaves_transparent",
	"wood",
	"brick_red",
	"glass", "water", "snow", "dirt_snow", "stone_coal", "stone_iron", "gravel_stone", "tall_grass"]

# per kind, the layers of its top, its sides and its bottom
topLayers = [0, 0, 2, 3, 4, 6, 7, 8, 9, 10, 11, 12, 14, 15, 16, 17]
sideLayers = [0, 1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 13, 14, 15, 16, 17]
bottomLayers = [0, 2, 2, 3, 4, 6, 7, 8, 9, 10, 11, 2, 14, 15, 16, 17]

pub fn blockName(b i64) ref str:
	blockNames[b]

# whether a body stands on it and cannot pass through it
pub fn isSolid(b i64) bool:
	b != air and b != water and b != tallGrass

# whether it hides the faces behind it (leaves and glass are seen through, water too)
pub fn isOpaque(b i64) bool:
	b != air and b != water and b != leaves and b != glass and b != tallGrass

# the texture layer of a face of a block: dy 1 its top, -1 its bottom, 0 a side
pub fn faceLayer(b i64, dy i64) i64:
	topLayers[b] if dy > 0 else bottomLayers[b] if dy < 0 else sideLayers[b]
