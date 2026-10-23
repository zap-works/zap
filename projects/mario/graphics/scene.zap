# A stage on the GPU: what does not move as one model (in the world's space) of every still batch
# laid one after the other by layer, each vertex naming its batch's material (a layer is then a
# draw for each run of one culling, its textures read by index: bindless), each
# billboard batch as one model drawn at all its places at once, and Mario's parts, each drawn
# with its texture and its material's state into a target of `samples` samples a pixel (the
# console smoothed its edges too) that is then shown on the screen. The layers go in the
# console's order: opaque surfaces, decals on them, cut-out ones, then the blended ones over all. The sky is drawn first, behind everything,
# as the console draws it: a window onto its picture that slides as the camera turns and tilts.

import engine
import n64
import stage
import game
import graphics.shaders

pub type DrawBatch:
	model engine.Model
	material n64.Material

# a billboard batch and the places it stands at
pub type BoardBatch:
	model engine.Model
	material n64.Material
	copies shaders.N64Copy[]

# a run of the still model's vertices of one layer and one culling: one draw
pub type StillRun:
	first i64
	count i64
	cullBack bool

pub type Scene:
	meshes DrawBatch[,]
	still engine.Model   # every still batch, by layer
	stillMaterials n64.Material[]   # per still batch, in the model's order
	stillByLayer i64[,]   # per layer: its still batches
	stillRuns StillRun[,]   # per layer: its runs
	stillProgram engine.Program
	textures engine.GpuTexture[]   # the stage's, whose handles stillParams reads
	stillParams shaders.StillParams   # the stage's textures and the still batches' materials, and the frame's view
	boards BoardBatch[]
	boardsByLayer i64[,]
	mirrors i64[]   # per texture: the axes its sampler mirrors (1 across, 2 down)
	program engine.Program
	sky engine.ScreenPass
	skyTexture i64   # the sky's texture among `textures`, -1 none
	rigMeshes i64[]
	things stage.Thing[]
	puppets stage.Puppet[]
	rigs stage.Rig[]
	poses Mat4[,]   # each puppet's parts this frame, in the world's space
	thingsOfMesh i64[,]   # per mesh: the things that draw it
	puppetsOfRig i64[,]   # per rig: the puppets posed with it
	thingShown bool[]   # this frame, by Mario's distance
	puppetShown bool[]
	shadows engine.Model[]   # this frame's shadows in layers 4, 5 and 6
	shadowVertices f32[,]   # what each holds, sent again only when it changes
	thingShadows CastShadow[]   # per thing and per puppet: its shadow (they stay where they are)
	puppetShadows CastShadow[]
	shadowMaterial n64.Material
	water engine.Model   # the moving water, made again each tick
	waterfall engine.Model
	waterMaterial n64.Material
	waterfallMaterial n64.Material
	samples i64
	drawn engine.RenderTarget   # `samples` samples a pixel, with depth
	resolved engine.RenderTarget   # its samples averaged
	show engine.ScreenPass

layerOrder = [0, 1, 3, 2, 4, 5, 6, 7]

# the stage made into the GPU's; its things, puppets and rigs move into the scene
pub fn newScene(mut st stage.Stage, samples i64) Scene:
	mirrors = st.mirrorsOf()
	textures = st.newSceneTextures(mirrors)
	meshes = st.newSceneMeshes()
	stillVertices, stillMaterials, materials, stillByLayer, stillRuns = newSceneStill(
		st,
		textures,
		mirrors
	)
	boards, boardsByLayer = st.newSceneBoards()
	program = engine.newProgram(shader(shaders.n64Vertex, shaders.n64Pixel))
	stillProgram = engine.newProgram(shader(shaders.stillVertex, shaders.stillPixel))
	stillParams = shaders.StillParams(
		projection = Mat4(1.0),
		view = Mat4(1.0),
		model = Mat4(1.0),
		textures = textures.map(.texture()),
		materials = move materials)
	sky = engine.newScreenPass(shader(shaders.skyPixel))
	skyTexture = st.sky
	show = engine.newScreenPass(shader(shaders.showPixel))
	water = engine.newDynamicModel()
	waterfall = engine.newDynamicModel()
	shadows = (0..3).map(_: engine.newDynamicModel())
	thingShadows = st.things.map(t:
		st.ground.shadowOf(t.x, t.y + t.behavior.graphLift, t.z, t.shadow)
	)
	puppetShadows = st.puppets.map(pp:
		st.ground.shadowOf(pp.x, pp.y + pp.behavior.graphLift, pp.z, pp.shadow)
	)
	thingsOfMesh i64[,] = fill(meshes.len, [])
	for k, thing in st.things:
		thingsOfMesh[thing.mesh].push(k)
	puppetsOfRig i64[,] = fill(st.rigs.len, [])
	for k, puppet in st.puppets:
		puppetsOfRig[puppet.rig].push(k)
	Scene(
		things = move st.things,
		puppets = move st.puppets,
		rigs = move st.rigs,
		poses = [],
		thingsOfMesh,
		puppetsOfRig,
		thingShown = [],
		puppetShown = [],
		shadows,
		shadowVertices = [[], [], []],
		thingShadows,
		puppetShadows,
		shadowMaterial = st.shadowMaterial,
		water,
		waterfall,
		waterMaterial = st.waterMaterial,
		waterfallMaterial = st.waterfallMaterial,
		meshes,
		still = engine.newModel(stillVertices),
		stillMaterials,
		stillByLayer,
		stillRuns,
		stillProgram,
		textures,
		stillParams,
		boards,
		boardsByLayer,
		rigMeshes = move st.rigMeshes,
		mirrors,
		program,
		sky,
		skyTexture,
		samples, drawn = engine.newMultisampleTarget(1, 1, samples), resolved = engine.newRenderTarget(
			1,
			1,
			true,
			false
		), show)

fn newSceneTextures(st stage.Stage, mirrors i64[]):
	textures = []
	for i, t in st.textures:
		textures.push(
			engine.newTexture(
				t,
				engine.Sampling(
					smooth = true,
					mipmaps = false,
					repeat = true,
					mirror = mirrors[i],
					anisotropy = false
				)
			)
		)
	textures

fn newSceneMeshes(st stage.Stage):
	meshes = []
	for mesh in st.meshes:
		meshes.push(
			mesh
				.filter(not .vertices.isEmpty)
				.map(b:
					DrawBatch(
						model = engine.newModel(verticesOf(b.vertices)),
						material = b.material
					)
				)
		)
	meshes

fn newSceneStill(st stage.Stage, textures engine.GpuTexture[], mirrors i64[]) (
	shaders.StillVertex[],
	n64.Material[],
	shaders.StillMaterial[],
	i64[,],
	StillRun[,]
):
	# the still batches laid by layer (each layer's in the stage's order), their runs of one culling
	stillVertices = []
	stillMaterials = []
	materials = []
	stillByLayer = []
	stillRuns = []
	for layer in 0..8:
		runs StillRun[] = []
		batches = []
		for b in st.still:
			if b.vertices.isEmpty or (b.material.layer & 7) != layer: continue
			first = stillVertices.len
			addStillVertices(stillVertices, b.vertices, i32(materials.len))
			count = stillVertices.len - first
			n = runs.len
			if n > 0 and runs[n - 1].cullBack == b.material.cullBack:
				runs[n - 1].count += count
			else:
				runs.push(StillRun(first, count, cullBack = b.material.cullBack))
			batches.push(stillMaterials.len)
			stillMaterials.push(b.material)
			materials.push(b.material.stillMaterialOf(textures, mirrors))
		stillByLayer.push(batches)
		stillRuns.push(runs)
	(stillVertices, stillMaterials, materials, stillByLayer, stillRuns)

fn newSceneBoards(st stage.Stage):
	boardsByLayer i64[,] = fill(8, [])
	boards = []
	for g in st.billboards:
		boardsByLayer[g.batch.material.layer & 7].push(boards.len)
		copies = []
		for i in 0..g.anchors.len / 5:
			a = g.anchors[i * 5..i * 5 + 5]
			copies.push(shaders.N64Copy(place = Vec4(a), scale = a[4]))
		boards.push(
			BoardBatch(
				model = engine.newModel(verticesOf(g.batch.vertices)),
				material = g.batch.material,
				copies
			)
		)
	(boards, boardsByLayer)

# The axes each texture is mirrored along by every material that repeats it: those its sampler
# mirrors, filtered across the mirror's edge as the console does (one also repeated plainly is
# mirrored by the shader instead).
fn mirrorsOf(st stage.Stage):
	mirrored = zeros(st.textures.len)
	plain = zeros(st.textures.len)
	materials = [st.waterMaterial, st.waterfallMaterial, st.shadowMaterial]
	for mesh in st.meshes:
		for b in mesh:
			materials.push(b.material)
	for b in st.still:
		materials.push(b.material)
	for g in st.billboards:
		materials.push(g.batch.material)
	for m in materials:
		if m.texture < 0: continue
		for (axis, wrap) in [(1, m.wrapS), (2, m.wrapT)]:
			if wrap == 1:
				mirrored[m.texture] |= axis
			elif wrap == 0:
				plain[m.texture] |= axis
	(0..mirrored.len).map(mirrored[it] & (3 - plain[it]))

# the moving textures as they stand `frames` frames after the level began
fn moveTextures(mut sc Scene, st stage.Stage, frames i64):
	water = []
	for w in st.water:
		w.quad.quadVertices(w.y, frames, water)
	sc.water.fillModel(verticesOf(water))
	fall = []
	st.waterfall.trisVertices(stage.waterfallAlpha, frames, fall)
	sc.waterfall.fillModel(verticesOf(fall))

# a still batch's vertices (n64.vertexFloats floats each) added as the still stages', naming its
# material
fn addStillVertices(mut into shaders.StillVertex[], f f32[], material i32):
	n = n64.vertexFloats
	for i in 0..f.len / n:
		k = i * n
		into.push(shaders.StillVertex(
			position = Vec3(f, k),
			colorOrNormal = Vec3(f, k + 3),
			uvAlpha = Vec3(f, k + 6), material))

# a still batch's material as the still stages read it: what drawBatch sets for it (a material
# without a texture names the first, which its combiner does not read)
fn stillMaterialOf(
	m n64.Material,
	textures engine.GpuTexture[],
	mirrors i64[]
):
	size = Vec2(1.0 / 32.0, 1.0 / 32.0)
	if m.texture >= 0:
		t = textures[m.texture]
		size = Vec2(1.0 / f32(t.width), 1.0 / f32(t.height))
	mirror = mirrors[m.texture] if m.texture >= 0 else 0
	prim = colorOf(m.prim)
	env = colorOf(m.env)
	ambient = rgbOf(m.ambient) if m.lit else Vec3(0.0, 0.0, 0.0)
	diffuse = rgbOf(m.diffuse) if m.lit else Vec3(0.0, 0.0, 0.0)
	direction = directionOf(m.direction) if m.lit else Vec3(0.0, 0.0, 0.0)
	color = combinerOf(m.colorSel)
	alpha = combinerOf(m.alphaSel)
	shaders.StillMaterial(
		prim = Vec4(prim.r, prim.g, prim.b, prim.a),
		env = Vec4(env.r, env.g, env.b, env.a),
		ambient = ambient.withW(0.0),
		diffuse = diffuse.withW(0.0),
		lightDirection = direction.withW(0.0),
		texelSize = size,
		texture = i32(m.texture.max(0)),
		lit = 1 if m.lit else 0,
		alphaCut = 0.3 if m.layer == 4 else 0.0,
		wrapS = wrapOf(0 if m.wrapS == 1 and (mirror & 1) != 0 else m.wrapS),
		wrapT = wrapOf(0 if m.wrapT == 1 and (mirror & 2) != 0 else m.wrapT),
		colorA = color.a, colorB = color.b, colorC = color.c, colorD = color.d, alphaA = alpha.a, alphaB = alpha.b, alphaC = alpha.c, alphaD = alpha.d, unused = 0)

# the console's vertices (n64.vertexFloats floats each) as the shader's
fn verticesOf(f f32[]):
	out = []
	n = n64.vertexFloats
	for i in 0..f.len / n:
		k = i * n
		out.push(shaders.N64Vertex(
			position = Vec3(f, k),
			colorOrNormal = Vec3(f, k + 3),
			uvAlpha = Vec3(f, k + 6)))
	out

# What Mario's distance shows this frame, and each shown puppet's parts posed in the world.
fn placeObjects(mut sc Scene, frames i64, mario Mat4):
	mx, my, mz = mario.m[12], mario.m[13], mario.m[14]
	sc.thingShown.clear()
	for t in sc.things:
		sc.thingShown.push(t.behavior.isShownNear(t.x, t.y, t.z, mx, my, mz))
	sc.puppetShown.clear()
	sc.poses.clear()
	for pp in sc.puppets:
		shown = pp.behavior.isShownNear(pp.x, pp.y, pp.z, mx, my, mz)
		sc.puppetShown.push(shown)
		parts = []
		if shown:
			a = pp.animation
			for part in n64.pose(
				sc.rigs[pp.rig].nodes,
				a,
				a.frameAfter(a.startFrame + pp.first, frames)
			):
				parts.push(pp.transform @ part)
		sc.poses.push(parts)

# The shadows of what is shown and of Mario, each in the layer it asks for.
fn castShadows(mut sc Scene, st stage.Stage, mario Mat4):
	byLayer f32[,] = [[], [], []]
	for k in 0..sc.things.len:
		if sc.thingShown[k]:
			addShadow(byLayer, sc.thingShadows[k])
	for k in 0..sc.puppets.len:
		if sc.puppetShown[k]:
			addShadow(byLayer, sc.puppetShadows[k])
	addShadow(byLayer, st.ground.shadowOf(mario.m[12], mario.m[13], mario.m[14], st.marioShadow))
	for i in 0..3:
		if byLayer[i] == sc.shadowVertices[i]: continue
		sc.shadows[i].fillModel(verticesOf(byLayer[i]))
		sc.shadowVertices[i] = move byLayer[i]

# a shadow cast: the layer it is drawn in (-1 none) and its vertices
type CastShadow:
	layer i64
	vertices f32[]

fn shadowOf(ground game.Surfaces, x f32, y f32, z f32, sh n64.GeoShadow):
	verts = []
	layer = ground.castShadow(x, y, z, sh.kind, sh.solidity, f32(sh.scale), verts) if sh.kind >= 0
		else -1
	CastShadow(layer, vertices = verts)

fn addShadow(mut byLayer f32[,], c CastShadow):
	if c.layer >= 4:
		byLayer[c.layer - 4].extend(c.vertices)

# The scene as seen from a camera looking along `forward` with `projection`, on a screen of
# w x h pixels: the sky, then each layer of every instance and of Mario (his parts placed by
# `marioParts`, in his model's space, and his model by `mario`), then the picture shown.
pub fn drawScene(
	mut r engine.Renderer,
	mut sc Scene,
	st stage.Stage,
	frames i64,
	projection Mat4,
	view Mat4,
	forward Vec3,
	w i64,
	h i64,
	mario Mat4,
	marioParts Mat4[]):
		sc.moveTextures(st, frames)
		sc.placeObjects(frames, mario)
		sc.castShadows(st, mario)
		if sc.drawn.width != w or sc.drawn.height != h:
			sc.drawn = engine.newMultisampleTarget(w, h, sc.samples) if sc.samples > 1
				else engine.newDepthTarget(w, h)
			sc.resolved = engine.newRenderTarget(
				w if sc.samples > 1 else 1,
				h if sc.samples > 1 else 1,
				true,
				false
			)
		if sc.samples <= 1:
			# one sample a pixel: straight onto the screen, with a depth of its own
			r.useScreenWithDepth(sc.drawn)
			r.clearTarget(engine.black)
			r.drawSky(sc, forward)
			r.drawLayers(sc, projection, view, mario, marioParts)
			r.setBlending(true)
			return
		r.useTarget(sc.drawn)
		r.clearTarget(engine.black)
		r.drawSky(sc, forward)
		r.drawLayers(sc, projection, view, mario, marioParts)
		sc.drawn.resolveTarget(sc.resolved)
		r.useScreen()
		r.setDepth(false, false, false)
		r.setBlending(false)
		r.drawScreenPass(sc.show, shaders.ShowParams(picture = sc.resolved.colorTexture()))
		r.setBlending(true)

fn drawLayers(
	mut r engine.Renderer,
	mut sc Scene,
	projection Mat4,
	view Mat4,
	mario Mat4,
	marioParts Mat4[]
):
	p = sc.program
	unset = shaders.Combiner(a = 0, b = 0, c = 0, d = 0)
	params = shaders.N64Params(
		projection,
		view,
		model = Mat4(1.0),
		lit = false,
		alphaCut = 0.0,
		wrapS = 0,
		wrapT = 0,
		color = unset,
		alpha = unset, prim = engine.black, env = engine.black,
		ambient = Vec3(0.0, 0.0, 0.0),
		diffuse = Vec3(0.0, 0.0, 0.0),
		lightDirection = Vec3(0.0, 0.0, 0.0),
		texelSize = Vec2(0.0, 0.0),
		billboard = .None, anchor = Vec3(0.0, 0.0, 0.0), texel = engine.Texture(
			id = -1,
			width = 0,
			height = 0
	))
	sc.stillParams.projection = projection
	sc.stillParams.view = view
	sc.stillProgram.setParams(sc.stillParams)
	for layer in layerOrder:
		params.model = Mat4(1.0)
		r.drawStill(sc, layer)
		# the parameters as the still batches leave them (what a later batch without a texture
		# or a light keeps of theirs)
		for i in sc.stillByLayer[layer]:
			sc.applyMaterial(params, sc.stillMaterials[i], .None)
		for i in sc.boardsByLayer[layer]:
			r.drawBatch(sc, params, sc.boards[i].material, .AboutCopy)
			r.drawInstances(p, sc.boards[i].model, sc.boards[i].copies)
		# what Mario's distance hides or shows, and what moves: a batch's material set once for
		# every object that draws it
		for mesh in 0..sc.thingsOfMesh.len:
			if sc.thingsOfMesh[mesh].isEmpty: continue
			for b in sc.meshes[mesh]:
				if b.material.layer == layer:
					r.drawShown(sc, params, b, sc.thingsOfMesh[mesh], sc.thingShown, -1)
		for rig in 0..sc.puppetsOfRig.len:
			nodeMeshes = sc.rigs[rig].meshes
			for i, nodeMeshe in nodeMeshes:
				if nodeMeshe < 0: continue
				for b in sc.meshes[nodeMeshe]:
					if b.material.layer == layer:
						r.drawShown(sc, params, b, sc.puppetsOfRig[rig], sc.puppetShown, i)
		if layer >= 4 and layer <= 6:
			m = sc.shadowMaterial
			m.layer = layer
			params.model = Mat4(1.0)
			r.drawBatch(sc, params, m, .None)
			r.drawModel(p, sc.shadows[layer - 4])
		# the moving textures in the area's order: the waterfall, then the water regions
		params.model = Mat4(1.0)
		if layer == sc.waterfallMaterial.layer:
			r.drawBatch(sc, params, sc.waterfallMaterial, .None)
			r.drawModel(p, sc.waterfall)
		if layer == sc.waterMaterial.layer:
			r.drawBatch(sc, params, sc.waterMaterial, .None)
			r.drawModel(p, sc.water)
		for i in 0..sc.rigMeshes.len.min(marioParts.len):
			mesh = sc.rigMeshes[i]
			if mesh < 0: continue
			placed = false
			for b in sc.meshes[mesh]:
				if b.material.layer != layer: continue
				if not placed:
					params.model = mario @ marioParts[i]
					placed = true
				drawBatch(
					r,
					sc,
					params,
					b.material,
					.AboutAnchor if b.material.billboard else .None
				)
				r.drawModel(p, b.model)
	r.setBlending(true)
	r.setDecal(false)

# a layer's still batches: a draw for each run of one culling, in the layer's state
fn drawStill(mut r engine.Renderer, sc Scene, layer i64):
	blended = layer >= 5
	decal = layer == 2 or layer == 6
	for run in sc.stillRuns[layer]:
		r.setDepth(true, not blended and not decal, run.cullBack)
		r.setBlending(blended)
		r.setDecal(decal)
		r.drawModelRange(sc.stillProgram, sc.still, run.first, run.count)

# a batch drawn for each of `objects` shown, placed by the thing's transform (part -1) or by the
# puppet's posed part
fn drawShown(
	mut r engine.Renderer,
	sc Scene,
	mut params shaders.N64Params,
	b DrawBatch,
	objects i64[],
	shown bool[],
	part i64
):
	p = sc.program
	set = false
	for k in objects:
		if not shown[k]: continue
		params.model = sc.things[k].transform if part < 0 else sc.poses[k][part]
		if not set:
			r.drawBatch(sc, params, b.material, .AboutAnchor if b.material.billboard else .None)
			set = true
		else:
			p.setParams(params)
		r.drawModel(p, b.model)

# the state and the parameters of a material, placed as `billboard` says, set for the draws
# that follow (the model's matrix as the caller left it)
fn drawBatch(
	mut r engine.Renderer,
	sc Scene,
	mut params shaders.N64Params,
	m n64.Material,
	billboard shaders.Billboard
):
	blended = m.layer >= 5
	decal = m.layer == 2 or m.layer == 6
	r.setDepth(true, not blended and not decal, m.cullBack)
	r.setBlending(blended)
	r.setDecal(decal)
	sc.applyMaterial(params, m, billboard)
	sc.program.setParams(params)

# the parameters of a material, placed as `billboard` says (a texture and a light are kept from
# before by a material without them)
fn applyMaterial(
	sc Scene,
	mut params shaders.N64Params,
	m n64.Material,
	billboard shaders.Billboard
):
	size = Vec2(1.0 / 32.0, 1.0 / 32.0)
	if m.texture >= 0:
		t = sc.stillParams.textures[m.texture]
		params.texel = t
		size = Vec2(1.0 / f32(t.width), 1.0 / f32(t.height))
	# a mirror the sampler makes is a plain repeat to the shader
	mirror = sc.mirrors[m.texture] if m.texture >= 0 else 0
	params.lit = m.lit
	params.alphaCut = 0.3 if m.layer == 4 else 0.0
	params.wrapS = wrapOf(0 if m.wrapS == 1 and (mirror & 1) != 0 else m.wrapS)
	params.wrapT = wrapOf(0 if m.wrapT == 1 and (mirror & 2) != 0 else m.wrapT)
	params.color = combinerOf(m.colorSel)
	params.alpha = combinerOf(m.alphaSel)
	params.prim = colorOf(m.prim)
	params.env = colorOf(m.env)
	if m.lit:
		params.ambient = rgbOf(m.ambient)
		params.diffuse = rgbOf(m.diffuse)
		params.lightDirection = directionOf(m.direction)
	params.texelSize = size
	params.billboard = billboard
	params.anchor = Vec3(f32(m.anchorX), f32(m.anchorY), f32(m.anchorZ))

# a tile's wrap (0 repeat, 1 mirror, 2 clamp) as the shader's Wrap's number
fn wrapOf(w i64):
	i32(w) if w == 1 or w == 2 else 0

# the combiner's four codes (a byte each, f3d.zap's) as the shader's inputs
fn combinerOf(codes i64):
	shaders.Combiner(
		a = sourceOf(codes & 0xFF),
		b = sourceOf(codes.bits(8, 8)),
		c = sourceOf(codes.bits(16, 8)),
		d = sourceOf(codes.bits(24, 8))
	)

# one of the combiner's codes as its input (1 the texel to 9 the environment's alpha, else zero)
fn sourceOf(code i64):
	i32(code) if code >= 1 and code <= 9 else 0

# The sky's window, as skybox.c places it: 360 degrees of turn span the picture's 1280 units
# across and the screen shows 320 of them; the tilt moves it 4 units a degree, 240 units shown
# (the picture is 960 tall, its horizon 600 up).
fn drawSky(mut r engine.Renderer, sc Scene, forward Vec3):
	if sc.skyTexture < 0: return
	# the yaw as atan2s(dz, dx) gives it, 0..0x10000; the window's left edge 1280 less its share
	yaw = (f64(forward.x).atan2(f64(forward.z)) / (2.0 * pi) % 1.0 + 1.0) % 1.0
	turn = 1280.0 - yaw * 1280.0
	tilt = f64(forward.y).clamp(-1.0, 1.0)
	pitch = tilt.atan2((1.0 - tilt * tilt).sqrt()).degrees()
	top = (600.0 + 4.0 * pitch).clamp(240.0, 960.0)
	r.setDepth(false, false, false)
	r.setBlending(false)
	r.drawScreenPass(sc.sky, shaders.SkyParams(
		window = Vec2(f32(turn), f32(top)),
		sky = sc.stillParams.textures[sc.skyTexture]
	))

# an RGBA8888 word as a color
fn colorOf(c i64):
	Vec4(
		f32(c.bits(24, 8)) / 255.0,
		f32(c.bits(16, 8)) / 255.0,
		f32(c.bits(8, 8)) / 255.0,
		f32(c & 0xFF) / 255.0
	)

fn rgbOf(c i64):
	Vec3(
		f32(c.bits(16, 8)) / 255.0,
		f32(c.bits(8, 8)) / 255.0,
		f32(c & 0xFF) / 255.0
	)

# three signed bytes as a direction
fn directionOf(d i64):
	Vec3(signed(d.bits(16, 8)), signed(d.bits(8, 8)), signed(d & 0xFF)).normalized()

fn signed(v i64):
	f32(v - 256 if v >= 128 else v)
