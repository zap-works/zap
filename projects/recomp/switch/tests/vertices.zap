# Vertex attributes read as Vec4s, and the vertex numbers a draw reads.

import recomp.switch.cpu
import recomp.switch.maxwell
import recomp.switch.render
import recomp.switch.shaders

fn attribute(size i64, kind i64):
	maxwell.VertexAttribute(
		index = 0,
		stream = 0,
		offset = 0,
		size,
		kind,
		constant = false,
		bgra = false
	)

test "floats, unorm bytes and packed formats as Vec4":
	b = []
	b.pushU32le(f32(1.5).toBits())
	b.pushU32le(f32(-2.0).toBits())
	expect attribute(0x04, 7).attributeValue(b, 0) == Vec4(1.5, -2.0, 0.0, 1.0)
	expect attribute(0x0A, 2).attributeValue([255, 0, 255, 0], 0) ==
		Vec4(1.0, 0.0, 1.0, 0.0)
	expect attribute(0x18, 1).attributeValue([0x81, 0x7F], 0) ==
		Vec4(-1.0, 1.0, 0.0, 1.0)
	expect attribute(0x30, 2).attributeValue([0xFF, 0x03, 0, 0xC0], 0) ==
		Vec4(1.0, 0.0, 0.0, 1.0)
	expect attribute(0x1B, 7).attributeValue([0, 0x3C], 0) == Vec4(1.0, 0.0, 0.0, 1.0)
	expect render.attributeBytes(0x0A) == 4 and render.attributeBytes(0x31) == 4

# a draw of two vertices from the second, indexed or not, with nothing bound
fn drawOf(indexed bool):
	maxwell.DrawCall(
		topology = 4,
		indexed,
		first = 1,
		count = 2,
		baseVertex = 10,
		firstInstance = 0,
		index = maxwell.IndexBuffer(address = 0, end = 8, format = 1),
		inlineIndices = [],
		attributes = [],
		streams = [],
		programs = [],
		constantBuffers = [],
		samplerPool = maxwell.Pool(address = 0, highest = 0),
		texturePool = maxwell.Pool(address = 0, highest = 0),
		textureBufferSlot = 0,
		targets = [],
		targetCount = 0,
		targetMap = [],
		zeta = maxwell.ZetaBuffer(enabled = false, address = 0, format = 0, layout = 0, layerSize = 0, width = 0, height = 0, depth = 0),
		viewports = [],
		scissors = [],
		blend = [],
		blendConstant = Vec4(0.0, 0.0, 0.0, 0.0),
		depth = maxwell.DepthState(testEnabled = false, writeEnabled = false, function = 0),
		cull = maxwell.CullState(enabled = false, frontFace = 0, face = 0),
		depthMode = 0,
		clipControl = 0,
		yControl = 0
	)

test "a draw's vertex numbers from shorts of its index buffer":
	d = drawOf(true)
	expect d.vertexNumbers([5, 0, 6, 0, 7, 0]) == [16, 17]
	d.indexed = false
	expect d.vertexNumbers([]) == [1, 2]

test "a stage's constant buffers at their banks' words":
	cpu.memory = cpu.Memory(bytes = zeros(0x1000), base = 0x10_0000)
	space = maxwell.AddressSpace()
	space.map(0x2000_0000, 0x1000, 0x10_0000, 0)
	bytes = []
	bytes.pushU32le(7)
	bytes.pushU32le(9)
	space.write(0x2000_0100, bytes)
	d = drawOf(false)
	d.constantBuffers = [
		maxwell.BoundConstantBuffer(kind = 4, slot = 2, address = 0x2000_0100, size = 8),
		maxwell.BoundConstantBuffer(kind = 0, slot = 0, address = 0x2000_0000, size = 4)
	]
	words = space.constantWords(d, 4)
	expect words.len == 3 * shaders.bankWords
	expect words[2 * shaders.bankWords] == 7 and words[2 * shaders.bankWords + 1] == 9
	expect words[0] == 0
