# A frame's clears and draws (maxwell's FrameCommands) drawn through the engine: each render
# target a texture of a target set (the targets a draw writes together, by their addresses and
# formats), each draw its recorded program set's translation (the program table the translated
# program gives), its textures decoded from the TIC pool (or a target drawn earlier, read where it
# lies), its vertices converted to the Vec4s its Attributes hold, as a list of triangles. What a
# frame met and could not draw is counted in `skips` by reason.
#
# Left out for now: depth and stencil, blending, culling, instancing, textures of layers and
# shadow maps, primitives other than triangles and quads.

import engine
import image
import recomp.switch.maxwell
import recomp.switch.shaders

# the program table of a translated program (out/shaders/programs/programs.zap)
pub type ShaderTable:
	code fn(str) str?
	textures fn(str) shaders.TextureUse[]
	attributes fn(str) i64[]
	setParams fn(
		engine.Program,
		u32[],
		u32[],
		engine.Texture[],
		engine.TextureArray[],
		engine.ShadowMap[],
		engine.ShadowMapArray[]
	)

# a target set and the render targets it holds, by their addresses
type Targets:
	set engine.TargetSet
	addresses i64[]
	formats i64[]   # the render target formats, in the set's order

pub type Replayer:
	table ShaderTable
	programs {str: engine.Program} = {}
	sets {str: Targets} = {}
	textures {str: engine.GpuTexture} = {}
	blank engine.GpuTexture
	skips {str: i64} = {}   # what was not drawn, by reason
	trace bool = false   # each command printed as it is replayed (the program's --trace-render)

# the table of a program translated with no shaders: nothing to draw with
pub fn noShaders() ShaderTable:
	ShaderTable(
		code = _: none,
		textures = _: [],
		attributes = _: [],
		setParams = (_, _, _, _, _, _, _): pass
	)

pub fn newReplayer(table ShaderTable) Replayer:
	white = image.Image(1, 1, fill = image.Rgba8(255, 255, 255, 255))
	Replayer(table = table.copy(), blank = white.newTexture())

fn skip(mut rp Replayer, why str):
	rp.skips[why.copy()] = (rp.skips.get(why) ?? 0) + 1

# long: a table of the render target formats
fn formatOf(code i64) engine.TextureFormat?:
	match code:
		0xD5: .Rgba8
		0xD6: .Rgba8Srgb
		0xCF: .Bgra8
		0xD0: .Bgra8Srgb
		0xCA, 0xC0: .Rgba16Float
		0xDE: .Rg16Float
		0xE0: .R11G11B10Float
		0xD1: .Rgb10A2
		0xE5: .R32Float
		0xF3: .R8
		0xEA: .Rg8
		_: none

fn keyOf(targets maxwell.RenderTarget[]):
	targets.map("{.address:x}:{.format:x}:{.width}x{.height}").join(" ")

# the target set of these render targets, made the first time
fn setOf(mut rp Replayer, targets maxwell.RenderTarget[]) str?:
	key = keyOf(targets)
	if key in rp.sets: return key
	formats = []
	for t in targets:
		formats.push(formatOf(t.format) ?? return rp.skipped("render target format {t.format:x}"))
	first = targets[0]
	rp.sets[key.copy()] = Targets(
		set = engine.newTargetSet(first.width, first.height, formats, none),
		addresses = targets.map(.address),
		formats = targets.map(.format)
	)
	key

fn skipped<T>(mut rp Replayer, why str) T?:
	rp.skip(why)
	none

# the targets' addresses, for a note
pub fn targetAddresses(rp Replayer) str:
	parts = []
	for _, t in rp.sets:
		parts.push(t.addresses.map("{it:x}").join(","))
	parts.join(" ")

# The set and index of the target drawn at `address`, if a set holds one.
fn targetAt(rp Replayer, address i64) (str, i64)?:
	for key, t in rp.sets:
		if t.addresses.indexOf(address) is k: return (key.copy(), k)
	none

# The frame's commands drawn on the renderer, inside a frame the caller began.
pub fn replay(
	mut rp Replayer,
	mut r engine.Renderer,
	space maxwell.AddressSpace,
	frame maxwell.FrameCommand[]
):
	for command in frame:
		if rp.trace: eprint(command.traceLine())
		match command:
			Clear(target, color):
				if rp.targetAt(target.address) is (key, k):
					r.useTargetSet(rp.sets[key].set)
					r.clearColorTarget(k, color)
				elif rp.setOf([target]) is key:
					r.useTargetSet(rp.sets[key].set)
					r.clearColorTarget(0, color)
			Draw(d): rp.draw(r, space, d)

fn traceLine(command maxwell.FrameCommand):
	match command:
		Clear(target, color): "clear {target.address:x} ({target.format:x}) to {color}"
		Draw(d):
			targets = (0..d.targetCount).map("{d.targets[d.targetMap[it]].address:x}").join(",")
			base = 3 * shaders.bankWords
			bank3 = (base..base + 8).map(
				f32.fromBits(d.pixelConstants[it] if it < d.pixelConstants.len else 0)
			)
			"draw {d.programNames.join(" ")} into {targets}, topology {d.topology}, {d.count} from {d.first}, pixel bank 3 {bank3}"

# The picture of the target at `address` (the presented buffer), as RGBA8 rows; none when no set
# holds it.
pub fn pictureAt(rp Replayer, address i64) image.Image?:
	key, k = try rp.targetAt(address)
	t = rp.sets[key]
	bytes = t.set.readColor(k)
	w = t.set.width
	h = t.set.height
	if rp.trace:
		centre = ((h / 2) * w + w / 2) * 4
		lit = (0..w * h).count(bytes[it * 4] | bytes[it * 4 + 1] | bytes[it * 4 + 2] != 0)
		eprint("  read {address:x}: {w}x{h}, centre {bytes[centre..centre + 4]}, {lit} pixels not black")
	if bytes.len != w * h * 4: return none
	format = t.formats[k]
	for at in (0..w * h).map(it * 4):
		bytes.toRgb8(at, format)
		bytes[at + 3] = 255   # the screen shows no alpha
	image.fromBytes(w, h, bytes)

# the pixel at `at` of a 4-byte target format turned to R, G, B bytes in place
fn toRgb8(mut b u8[], at i64, format i64):
	match format:
		0xD1:   # A2B10G10R10
			v = i64(b.u32le(at))
			b[at] = (v & 0x3FF) >> 2
			b[at + 1] = ((v >> 10) & 0x3FF) >> 2
			b[at + 2] = ((v >> 20) & 0x3FF) >> 2
		0xCF, 0xD0:   # B8G8R8A8
			blue = b[at]
			b[at] = b[at + 2]
			b[at + 2] = blue
		_: pass
