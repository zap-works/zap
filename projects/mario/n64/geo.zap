# Geo layouts: the trees the game draws a model or an area from. Each command makes a node (a
# group, a translation, a rotation, a display list in a layer, a switch among children...) or
# opens and closes the children of the last one; there is no length byte, so each command's size
# is known from its opcode and flags. Here a layout is walked once, as it stands when nothing
# moves: each display list with the transform of the nodes above it. Nodes the game's code runs
# (camera, water, effects) are passed over; a switch takes its first case, and of a model's levels of detail
# (render ranges) the one seen up close is kept.
#
# Matrices are the engine's (column vectors): the console's row-vector matrices composed as
# `local * parent` become `parent * local` here.

import math

# a display list to draw: where it is, its layer, its transform, whether it faces the camera
pub type GeoDraw:
	dl i64
	layer i64
	transform Mat4
	billboard bool

pub type GeoScene:
	draws GeoDraw[]
	background i64   # the sky's id (-1 a color or none)

# a node just made: its transform, whether it is drawn, whether it is a switch and its case
type GeoNode:
	transform Mat4
	billboard bool   # under a billboard node: faces the camera
	skipped bool
	switchCase i64   # -1: not a switch

# an open node, whose children follow
type GeoFrame:
	transform Mat4
	billboard bool
	skipped bool
	switchCase i64
	children i64

# the scene of the layout at `at` (a segmented address), its root transformed by `root`
pub fn walkGeo(s Segments, at0 i64, root Mat4) GeoScene:
	scene = GeoScene(draws = [], background = -1)
	frames = [
		GeoFrame(
			transform = root,
			billboard = false,
			skipped = false,
			switchCase = -1,
			children = 0
		)
	]
	last = GeoNode(transform = root, billboard = false, skipped = false, switchCase = -1)
	returns = []
	at = at0
	loop 100_000:
		op = s.u8At(at)
		p = s.u8At(at + 1)
		if op == 0x00:
			returns.push(at + 8)
			at = s.u32At(at + 4)
			continue
		if op == 0x01 or op == 0x03:
			if returns.isEmpty: return scene
			at = returns.pop() ?? 0
			continue
		if op == 0x02:
			if p == 1:
				returns.push(at + 8)
			at = s.u32At(at + 4)
			continue
		if op == 0x04:
			frames.push(
				GeoFrame(
					transform = last.transform,
					billboard = last.billboard,
					skipped = last.skipped,
					switchCase = last.switchCase,
					children = 0
				)
			)
			at += 4
			continue
		if op == 0x05:
			# back out: the last node at the outer level is the one whose children closed
			# (geo_layout.c keeps the last node of each depth)
			if frames.len > 1:
				closed = frames.pop() ?? frames[0]
				last = GeoNode(
					transform = closed.transform,
					billboard = closed.billboard,
					skipped = closed.skipped,
					switchCase = closed.switchCase
				)
			at += 4
			continue
		size = geoCommandSize(op, p)
		if size == 0:
			fail("geo layout: unknown command {op} at {at}")
		if makesNode(op):
			# the node is a child of the open one: drawn unless a switch picks another child
			n = frames.len - 1
			parent = frames[n].transform
			index = frames[n].children
			frames[n].children += 1
			skipped = frames[n].skipped or
				frames[n].switchCase >= 0 and index != frames[n].switchCase
			last = s.nodeOf(op, p, at, parent, frames[n].billboard, skipped, scene)
		at += size
	fail("geo layout: no end after 100000 commands")
	scene

# the node a command makes, its display list (if any) noted as a draw
fn nodeOf(
	s Segments,
	op i64,
	p i64,
	at i64,
	parent Mat4,
	parentBillboard bool,
	skipped bool,
	mut scene GeoScene
):
	transform = parent
	switchCase = -1
	dl = 0
	layer = p & 0x0F
	billboard = parentBillboard
	if op == 0x10:
		layout = p.bits(4, 3)
		if layout == 0:
			transform = parent @ s.vecAt(at + 4).rotateZxyTranslate(s.vecAt(at + 10))
		elif layout == 1:
			transform = parent @ s.vecAt(at + 2).rotateZxyTranslate(zero())
		elif layout == 2:
			transform = parent @ zero().rotateZxyTranslate(s.vecAt(at + 2))
		else:
			transform = parent @
				zero().rotateZxyTranslate(Vec3(0.0, f32(s.s16At(at + 2)), 0.0))
		if (p & 0x80) != 0:
			dl = s.u32At(at + [16, 8, 8, 4][layout])
	elif op == 0x11 or op == 0x14:
		transform = parent @ s.vecAt(at + 2).rotateZxyTranslate(zero())
		if (p & 0x80) != 0:
			dl = s.u32At(at + 8)
		billboard = billboard or op == 0x14
	elif op == 0x12:
		transform = parent @ zero().rotateZxyTranslate(s.vecAt(at + 2))
		if (p & 0x80) != 0:
			dl = s.u32At(at + 8)
	elif op == 0x13:
		layer = p
		transform = parent @ s.vecAt(at + 2).rotateZxyTranslate(zero())
		dl = s.u32At(at + 8)
	elif op == 0x15:
		layer = p
		dl = s.u32At(at + 4)
	elif op == 0x1D:
		k = f32(s.u32At(at + 4)) / 65536.0
		transform = parent @ Mat4.scaling(Vec3(k, k, k))
		if (p & 0x80) != 0:
			dl = s.u32At(at + 8)
	elif op == 0x0E:
		switchCase = s.s16At(at + 2).max(0)
	elif op == 0x0D:
		# a level of detail: drawn from `min` to `max` away; the closest is the one kept
		if s.s16At(at + 4) > 0:
			return GeoNode(transform, billboard, skipped = true, switchCase = -1)
	elif op == 0x19 and s.u32At(at + 4) != 0 and not skipped:
		scene.background = s.s16At(at + 2)
	if dl != 0 and not skipped:
		scene.draws.push((dl, layer, transform, billboard))
	GeoNode(transform, billboard, skipped, switchCase)

# ---------- rigs: the tree kept, for models that move ----------

# A node of a model kept as a tree: its parent (an index, -1 the root), its transform from the
# parent (an animated part's is made each frame from its offset and the animation's values),
# and the display list it draws.
pub type RigNode:
	kind i64   # the command that made it
	parent i64
	local Mat4
	animated bool
	offset Vec3
	dl i64   # 0 none
	layer i64
	billboard bool

# an open node of the rig being read
type RigFrame:
	node i64   # its index, -1 the root
	skipped bool
	switchCase i64
	children i64

# The nodes of the layout at `at` in the order the game draws them (parents first): what a
# switch does not pick is left out, so the animated parts are in the order their values come.
pub fn walkRig(s Segments, at0 i64) RigNode[]:
	nodes = []
	frames = [RigFrame(node = -1, skipped = false, switchCase = -1, children = 0)]
	last = RigFrame(node = -1, skipped = false, switchCase = -1, children = 0)
	returns = []
	at = at0
	loop 100_000:
		op = s.u8At(at)
		p = s.u8At(at + 1)
		if op == 0x00:
			returns.push(at + 8)
			at = s.u32At(at + 4)
			continue
		if op == 0x01 or op == 0x03:
			if returns.isEmpty: return nodes
			at = returns.pop() ?? 0
			continue
		if op == 0x02:
			if p == 1:
				returns.push(at + 8)
			at = s.u32At(at + 4)
			continue
		if op == 0x04:
			frames.push(RigFrame(..last, children = 0))
			at += 4
			continue
		if op == 0x05:
			# back out: the last node at the outer level is the one whose children closed
			# (geo_layout.c keeps the last node of each depth)
			if frames.len > 1:
				last = frames.pop() ?? last
			at += 4
			continue
		size = geoCommandSize(op, p)
		if size == 0:
			fail("geo layout: unknown command {op} at {at}")
		if makesNode(op):
			n = frames.len - 1
			index = frames[n].children
			frames[n].children += 1
			skipped = frames[n].skipped or
				frames[n].switchCase >= 0 and index != frames[n].switchCase
			if op == 0x0D and s.s16At(at + 4) > 0:
				skipped = true   # a level of detail seen from afar
			node = -1
			if not skipped:
				nodes.push(s.rigNodeOf(op, p, at, frames[n].node))
				node = nodes.len - 1
			last = RigFrame(
				node,
				skipped,
				switchCase = s.s16At(at + 2).max(0) if op == 0x0E else -1,
				children = 0
			)
		at += size
	fail("geo layout: no end after 100000 commands")
	nodes

fn rigNodeOf(s Segments, op i64, p i64, at i64, parent i64):
	local = Mat4(1.0)
	dl = 0
	layer = p & 0x0F
	animated = false
	offset = zero()
	if op == 0x10:
		layout = p.bits(4, 3)
		if layout == 0:
			local = s.vecAt(at + 4).rotateZxyTranslate(s.vecAt(at + 10))
		elif layout == 1:
			local = s.vecAt(at + 2).rotateZxyTranslate(zero())
		elif layout == 2:
			local = zero().rotateZxyTranslate(s.vecAt(at + 2))
		else:
			local = zero().rotateZxyTranslate(Vec3(0.0, f32(s.s16At(at + 2)), 0.0))
		if (p & 0x80) != 0:
			dl = s.u32At(at + [16, 8, 8, 4][layout])
	elif op == 0x11 or op == 0x14:
		local = s.vecAt(at + 2).rotateZxyTranslate(zero())
		if (p & 0x80) != 0:
			dl = s.u32At(at + 8)
	elif op == 0x12:
		local = zero().rotateZxyTranslate(s.vecAt(at + 2))
		if (p & 0x80) != 0:
			dl = s.u32At(at + 8)
	elif op == 0x13:
		layer = p
		animated = true
		offset = s.vecAt(at + 2)
		local = offset.rotateZxyTranslate(zero())
		dl = s.u32At(at + 8)
	elif op == 0x15:
		layer = p
		dl = s.u32At(at + 4)
	elif op == 0x1D:
		k = f32(s.u32At(at + 4)) / 65536.0
		local = Mat4.scaling(Vec3(k, k, k))
		if (p & 0x80) != 0:
			dl = s.u32At(at + 8)
	RigNode(kind = op, parent, local, animated, offset, dl, layer, billboard = op == 0x14)

# the game's sine table (gSineTable): 4096 steps a turn, a quarter more for the cosines
sineTable = makeSines()

fn makeSines():
	# a half turn and a whole one are exactly 0 in the table, not the f64 sine's 1e-16
	(0..0x1400).map(i:
		f32(0.0 if i == 2048 or i == 4096 else (i * pi * 2.0 / 4096.0).sin())
	)

# sins and coss: the sine and cosine of an angle of 65536 units a turn, as the game looks them up
pub fn sins(a i64) f32:
	sineTable[(a & 0xFFFF) >> 4]

pub fn coss(a i64) f32:
	sineTable[((a & 0xFFFF) >> 4) + 0x400]

# The console's mtxf_rotate_xyz_and_translate (rotations in the game's angle units, 0x10000 a
# turn): about x first, then y, then z; written as its rows, as rotateZxyTranslate is.
pub fn rotateXyzTranslate(t Vec3, r Vec3) Mat4:
	ax, ay, az = i64(r.x), i64(r.y), i64(r.z)
	sx, cx = sins(ax), coss(ax)
	sy, cy = sins(ay), coss(ay)
	sz, cz = sins(az), coss(az)
	m f32[16]
	m[0] = cy * cz
	m[1] = cy * sz
	m[2] = -sy
	m[4] = sx * sy * cz - cx * sz
	m[5] = sx * sy * sz + cx * cz
	m[6] = sx * cy
	m[8] = cx * sy * cz + sx * sz
	m[9] = cx * sy * sz - sx * cz
	m[10] = cx * cy
	m[12] = t.x
	m[13] = t.y
	m[14] = t.z
	m[15] = 1.0
	Mat4(m)

# a model's shadow (GEO_SHADOW): its kind (shadow.h's SHADOW_*), its alpha and its width
pub type GeoShadow:
	kind i64
	solidity i64
	scale i64

# the first shadow a geo layout casts, its jumps followed; none when it casts none
pub fn geoShadow(s Segments, at0 i64) GeoShadow?:
	returns = []
	at = at0
	loop 10_000:
		if not s.holds(at, 8): return none
		op = s.u8At(at)
		p = s.u8At(at + 1)
		if op == 0x16:
			return GeoShadow(
				kind = s.s16At(at + 2),
				solidity = s.s16At(at + 4),
				scale = s.s16At(at + 6)
			)
		if op == 0x00 or op == 0x02:
			if op == 0x00 or p == 1:
				returns.push(at + 8)
			at = s.u32At(at + 4)
			continue
		if op == 0x01 or op == 0x03:
			if returns.isEmpty: return none
			at = returns.pop() ?? 0
			continue
		if op == 0x04 or op == 0x05:
			at += 4
			continue
		size = geoCommandSize(op, p)
		if size == 0: return none
		at += size
	none

# the bytes a command takes (0: not a command)
fn geoCommandSize(op i64, p i64):
	hasDl = 4 if (p & 0x80) != 0 else 0
	if op in [0x06, 0x07, 0x09, 0x0B, 0x0C, 0x17, 0x1B, 0x20]: return 4
	if op in [0x0D, 0x0E, 0x15, 0x16, 0x18, 0x19, 0x1A, 0x1E]: return 8
	if op in [0x11, 0x12, 0x14, 0x1D]: return 8 + hasDl
	if op in [0x13, 0x1C, 0x08]: return 0x0C
	if op == 0x0A: return 0x0C if p != 0 else 8
	if op == 0x0F: return 0x14
	if op == 0x10: return [0x10, 8, 8, 4][p.bits(4, 3)] + hasDl
	0x10 if op == 0x1F else 0

# whether a command makes a node (the others jump, return, open or close, or set flags)
fn makesNode(op i64):
	op >= 0x08 and op <= 0x20 and op != 0x1A and op != 0x1E and op != 0x1F

fn vecAt(s Segments, at i64):
	Vec3(f32(s.s16At(at)), f32(s.s16At(at + 2)), f32(s.s16At(at + 4)))

fn zero():
	Vec3(0.0, 0.0, 0.0)

# The console's mtxf_rotate_zxy_and_translate (rotations in degrees), written as its rows are
# (row-major), which is this column-major matrix of the same transform.
pub fn rotateZxyTranslate(t Vec3, r Vec3) Mat4:
	k = pi / 180.0
	sx, cx = (r.x * k).sin(), (r.x * k).cos()
	sy, cy = (r.y * k).sin(), (r.y * k).cos()
	sz, cz = (r.z * k).sin(), (r.z * k).cos()
	m f32[16]
	m[0] = cy * cz + sx * sy * sz
	m[1] = cx * sz
	m[2] = -sy * cz + sx * cy * sz
	m[4] = -cy * sz + sx * sy * cz
	m[5] = cx * cz
	m[6] = sy * sz + sx * cy * cz
	m[8] = cx * sy
	m[9] = -sx
	m[10] = cx * cy
	m[12] = t.x
	m[13] = t.y
	m[14] = t.z
	m[15] = 1.0
	Mat4(m)
