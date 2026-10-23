# A model's collision as the physics reads it: each rigid body a node points to (through its
# bhkCollisionObject) flattened into one Collider in the model's space, the node's transform, the
# T body's own and the Havok scale applied, its shapes walked down to their leaves: meshes and
# hulls as triangles, and boxes, spheres, capsules and hulls kept as primitives too. The engine's
# physics (hull.zap) makes the triangles of the convex leaves.

import engine.physics
import math

pub type Motion:
	Fixed
	Keyframed
	Dynamic

# a convex leaf a simulation tests directly, in the model's space
pub type Primitive:
	BoxPrimitive(center Vec3, halfAxes Mat3)   # each column a half extent along a side
	SpherePrimitive(center Vec3, radius f32)
	CapsulePrimitive(a Vec3, b Vec3, radius f32)
	HullPrimitive(points Vec3[], radius f32)   # the hull of the points, grown by the shell radius

pub type Collider:
	node str   # the name of the node it hangs from
	transform Mat4   # the body's space, in Havok units, to the model's
	layer i64   # SkyrimLayer: layerNames
	motion Motion
	mass f32
	friction f32
	restitution f32
	center Vec3   # the center of mass
	kinds str[]   # each leaf's kind: box, sphere, capsule, convex, mesh
	leafEnds i64[]   # the triangles after each leaf: leaf k's are leafEnds[k - 1]..leafEnds[k]
	positions Vec3[]
	indices u32[]   # three per triangle
	materials i64[]   # the Havok material of each triangle
	primitives Primitive[]
	body RigidBody
	block i64   # the body's block, which constraints name
	constraints Constraint[]   # those the body lists, in their bodies' spaces (Havok units)

pub layerNames = [
	"unidentified", "static", "anim static", "transparent", "clutter", "weapon", "projectile",
	"spell", "biped", "trees", "props", "water", "trigger", "terrain", "trap", "noncollidable",
	"cloud trap", "ground", "portal", "debris small", "debris large", "acoustic space",
	"actor zone", "projectile zone", "gas trap", "shell casing", "transparent small",
	"invisible wall", "transparent small anim", "ward", "char controller", "stair helper",
	"dead bip", "biped no cc", "avoid box", "collision box", "camera sphere", "door detection",
	"cone projectile", "camera pick", "item pick", "line of sight", "path pick", "custom pick 1",
	"custom pick 2", "spell explosion", "dropping pick", "dead actor zone", "falling trap trigger",
	"nav cut", "critter", "spell trigger", "living and dead actors", "detection", "trap trigger"
]

layerAnimStatic = 2
fixedLayers = [1, 9, 13, 17]   # static, trees, terrain, ground

# how a body moves: keyframed when animated, fixed when it is the scene's or has no mass, else
# simulated
fn motionOf(b RigidBody):
	if b.motionSystem == motionKeyframed or b.layer == layerAnimStatic: return Motion.Keyframed
	if b.motionSystem == motionFixed or b.mass == 0.0 or b.layer in fixedLayers: return .Fixed
	.Dynamic

pub fn colliderPositions(colliders Collider[]) Vec3[]:
	colliders.flatMap(.positions.copy())

pub fn partPositions(parts Part[]) Vec3[]:
	parts.flatMap(.positions.copy())

# how the collision's box sits on the drawn parts' box, against the drawn box's diagonal
pub type BoundsFit:
	ratio f32   # the collision's diagonal over the drawn one
	offset f32   # how far apart the two centers are
	overflow f32   # how far the collision reaches past the drawn box at most, along any axis

pub fn collisionFit(colliders Collider[], parts Part[]) BoundsFit:
	clo, chi = colliderPositions(colliders).boundsOf()
	dlo, dhi = partPositions(parts).boundsOf()
	size = (dhi - dlo).length().max(1.0)
	past = (dlo - clo).max(chi - dhi).max(Vec3(0, 0, 0))
	BoundsFit(
		ratio = (chi - clo).length() / size,
		offset = ((clo + chi) - (dlo + dhi)).length() * 0.5 / size,
		overflow = past.x.max(past.y).max(past.z) / size
	)

fn havokBlock(n Nif, i i64) HavokShape?:
	if i < 0 or i >= n.blocks.len: return none
	match n.blocks[i]:
		HavokBlock(shape): shape.copy()
		_: none

# how long the unit x of `m` comes out: the scale of a transform scaled alike on every axis
fn scaleOf(m Mat4):
	m.applyDirection(Vec3(1, 0, 0)).length()

# triangles in the shape's space added to the collider moved by `place`, all of one material
fn addTriangles(mut c Collider, place Mat4, positions Vec3[], indices u32[], material i64):
	base = u32(c.positions.len)
	for p in positions:
		c.positions.push(place.applyPoint(p))
	for k in indices:
		c.indices.push(base + k)
	loop indices.len / 3:
		c.materials.push(material)

# the triangles added since the last leaf make one of this kind
fn endLeaf(mut c Collider, kind str):
	c.kinds.push(kind.copy())
	c.leafEnds.push(c.indices.len / 3)

fn addMesh(mut c Collider, place Mat4, mesh HavokMesh):
	base = c.indices.len / 3
	c.addTriangles(place, mesh.positions, mesh.indices, 0)
	for t in 0..mesh.materials.len.min(c.materials.len - base):
		c.materials[base + t] = mesh.materials[t]
	c.endLeaf("mesh")

fn addBox(mut c Collider, place Mat4, half Vec3, material i64):
	positions, indices = half.boxTriangles()
	c.addTriangles(place, positions, indices, material)
	axes = Mat3(
		place.applyDirection(Vec3(half.x, 0, 0)),
		place.applyDirection(Vec3(0, half.y, 0)),
		place.applyDirection(Vec3(0, 0, half.z))
	)
	c.primitives.push(.BoxPrimitive(place.applyPoint(Vec3(0, 0, 0)), axes))
	c.endLeaf("box")

fn addRound(mut c Collider, place Mat4, a Vec3, b Vec3, radius f32, material i64):
	positions, indices = a.roundTriangles(b, radius)
	c.addTriangles(place, positions, indices, material)
	r = radius * place.scaleOf()
	if a == b:
		c.primitives.push(.SpherePrimitive(place.applyPoint(a), r))
		c.endLeaf("sphere")
	else:
		c.primitives.push(.CapsulePrimitive(place.applyPoint(a), place.applyPoint(b), r))
		c.endLeaf("capsule")

# the NiTriStripsData blocks of a bhkNiTriStripsShape, whose vertices are the model's units
fn addStrips(mut c Collider, n Nif, place Mat4, material i64, data i64[]):
	unscaled = place @ Mat4.scaling(Vec3(1.0, 1.0, 1.0) / havokScale)
	for d in data:
		g = n.dataBlock(d)
		c.addTriangles(unscaled, g.positions, g.indices, material)
	c.endLeaf("mesh")

# shape block i and its children, `place` taking their space (Havok units) to the model's
fn addShape(mut c Collider, n Nif, i i64, place Mat4, depth i64):
	if depth > 16: return
	shape = n.havokBlock(i) ?? return
	match shape:
		BoxShape(material, radius, half): c.addBox(place, half + radius, material)
		SphereShape(material, radius):
			c.addRound(place, Vec3(0, 0, 0), Vec3(0, 0, 0), radius, material)
		CapsuleShape(material, radius, a, b): c.addRound(place, a, b, radius, material)
		ConvexShape(material, radius, vertices, planes):
			positions, indices = physics.hullTriangles(vertices, planes, radius)
			c.addTriangles(place, positions, indices, material)
			c.primitives.push(
				.HullPrimitive(vertices.map(place.applyPoint(it)), radius * place.scaleOf())
			)
			c.endLeaf("convex")
		MultiSphereShape(material, spheres):
			for s in spheres:
				c.addRound(place, s.xyz, s.xyz, s.w, material)
		TransformShape(child, transform): c.addShape(n, child, place @ transform, depth + 1)
		ListShape(children):
			for child in children:
				c.addShape(n, child, place, depth + 1)
		MoppShape(child): c.addShape(n, child, place, depth + 1)
		CompressedShape(data): c.addShape(n, data, place, depth + 1)
		PackedShape(data): c.addShape(n, data, place, depth + 1)
		StripsShape(material, data): c.addStrips(n, place, material, data)
		MeshData(mesh): c.addMesh(place, mesh)
	return

# The biped part of each node's rigid body by the node's name: the low five bits of the body's
# filter flags (HavokFilter's part number), the index into the game's biped parts (OTHER 0, HEAD 1,
# BODY 2... reference/exe/README.md, "Havok: the collision filter").
pub fn bipedParts(n Nif) {str: i64}:
	out {str: i64} = {}
	for b in n.blocks:
		match b:
			NodeBlock(node):
				i = n.bodyBlockOf(node.av.collision) ?? continue
				out[node.av.name.copy()] = n.bodyAt(i).filterFlags & 0x1f
			_: continue
	out

# the block of the body behind collision object i, none when there is none
fn bodyBlockOf(n Nif, collision i64) i64?:
	if collision < 0 or collision >= n.blocks.len: return none
	match n.blocks[collision]:
		CollisionBlock(_, b):
			if b < 0 or b >= n.blocks.len: return none
			match n.blocks[b]:
				BodyBlock: b
				_: none
		_: none

fn bodyAt(n Nif, i i64):
	match n.blocks[i]:
		BodyBlock(body): body.copy()
		_: fail("block {i} is not a body")

# the constraint blocks the body lists
fn constraintsOf(n Nif, body RigidBody):
	out = []
	for i in body.constraints:
		if i < 0 or i >= n.blocks.len: continue
		match n.blocks[i]:
			ConstraintBlock(c): out.push(c.copy())
			_: continue
	out

# the collider of the body behind collision object i, on a node of the transform `world`
fn colliderOf(n Nif, collision i64, node str, world Mat4) Collider?:
	block = try n.bodyBlockOf(collision)
	body = n.bodyAt(block)
	constraints = n.constraintsOf(body)
	place = world @ Mat4.scaling(Vec3(havokScale, havokScale, havokScale))
	if body.moves:
		place = place @ Mat4.translation(body.translation) @ Mat4.rotationOf(body.rotation)
	c = Collider(
		node = node.copy(),
		transform = place,
		layer = body.layer,
		motion = body.motionOf(),
		mass = body.mass,
		friction = body.friction,
		restitution = body.restitution,
		center = place.applyPoint(body.center),
		kinds = [],
		leafEnds = [],
		positions = [],
		indices = [],
		materials = [],
		primitives = [],
		body = body.copy(),
		block,
		constraints
	)
	c.addShape(n, body.shape, place, 0)
	c

# block i and what is under it, under the transform `parent`; `seen` stops a damaged file's loops
fn addColliders(n Nif, i i64, parent Mat4, mut seen bool[], mut out Collider[]):
	if i < 0 or i >= n.blocks.len or seen[i]: return
	seen[i] = true
	match n.blocks[i]:
		NodeBlock(node):
			world = parent @ node.av.transform
			if n.colliderOf(node.av.collision, node.av.name, world) is c: out.push(c)
			for child in node.children:
				n.addColliders(child, world, seen, out)
		ShapeBlock(shape):
			world = parent @ shape.av.transform
			if n.colliderOf(shape.av.collision, shape.av.name, world) is c: out.push(c)
		_: return

# the colliders of a model's rigid bodies, from its roots (placed as drawModel places them),
# hidden nodes' included
pub fn collisionShapes(n Nif) Collider[]:
	out = []
	seen = fill(n.blocks.len, false)
	for r in n.rootBlocks():
		n.addColliders(r, n.rootParent(r), seen, out)
	out
