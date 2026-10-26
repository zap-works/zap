# The declarations of a program's GPU files as its layout reads them (lower.zap, packer.zap): its
# structs and enums and its functions' signatures, in one list of nodes, each type in the
# shader's words (vec3, float, sampler2D, a struct's name). mc builds it from the parser's tree
# before its check (gpu.zap), as the packers it gives the parameter structs are code it checks.

pub kStruct = 2   # text the name; kids its members (kDecl)
pub kFunction = 4   # text the name, tname the result; kids the parameters (kDecl)
pub kDecl = 5   # a member or a parameter: tname, zname, arr, text
pub kEnum = 6   # text the name; kids its variants (kDecl, no type), each the number of its place

# where a variable of a stage's interface is
pub qIn = 1   # a vertex input, or a value the pixel stage receives
pub qOut = 2   # a value the vertex stage passes on, or one of the pixel stage's targets

# a node's index in its unit's nodes
pub type LayoutId = n32

pub type Node:
	kind i64
	text str
	tname str   # a declaration's type in the shader's own words (float, vec3, sampler2D, a struct's name)
	zname str   # that type as the Zap source writes it (Vec4, Mat4, Texture, an enum's name), its array apart
	arr i64   # its array length: -1 none, 0 unsized (a storage buffer's)
	kids LayoutId[]
	pos i64   # where it is: its file, line and column (posOf)

pub type Unit:
	nodes Node[]
	tops LayoutId[]
	structs str[]   # the struct names declared
	enums str[]   # the enum names declared

# A place in the sources, in one number a node carries as the tree is lowered: the file's
# number among the sources compiled, its line and its column.
lineSpan = 1_000_000
colSpan = 10_000

pub fn posOf(file i64, line i64, col i64) i64:
	(file * lineSpan + line) * colSpan + col.min(colSpan - 1)

# the names of the files being compiled, by number, for messages
mut sourceNames str[] = []

# A named error's message from its name and parts: mc's table (errorNames.zap), which mc's GPU
# code (gpu.zap) sets here, as this module cannot import its importer.
pub mut nameError fn(str, str[]) str = (name, parts): "{name}: {parts.join(", ")}"

pub fn compileError(name str, parts str[]) str:
	named = nameError
	named(name, parts)

# The error that ends a program's GPU compile: its place and its message. The GPU's code returns
# it, and mc's GPU code reports it as every other compile error and goes on to the next program.
pub type GpuError:
	file str
	line i64
	col i64
	message str

# the error that stops the GPU compile at a place (posOf)
pub fn stop(pos i64, msg str) GpuError:
	file = pos / colSpan / lineSpan
	GpuError(
		file = sourceNames[file].copy() if file < sourceNames.len else "shader",
		line = pos / colSpan % lineSpan,
		col = pos % colSpan,
		message = msg.copy()
	)

pub fn newNode(kind i64, move text str, move kids LayoutId[], pos i64) Node:
	Node(kind, text, tname = "", zname = "", arr = -1, kids, pos)
