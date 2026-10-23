# The Havok world as SkyrimSE.exe sets it up: its solver's settings and its solver deactivation
# classes (hkpSolverInfo's DeactivationInfo, built in hkpWorld's constructor from the gravity 9.81
# and hkpWorldCinfo's 0.02 m reference distance): the class of a body
# (hkpSolverInfo::DeactivationClass, as the model's bhkRigidBody and a skeleton's hkpRigidBody keep
# it: 1 off, 2 low, 3 medium, 4 high, 5 max) and what it does to a slow body.

import engine.physics
import skyrim.nif

# each class's inverse thresholds (linear, angular), the share of the velocity kept a sub-step and
# the share of the thresholds under which it is stopped: a table, one line a class
slowingTable (f32, f32, f32, f32)[] = [
	(10.1937, 10.3911, 0.968, 0.05),
	(5.99628, 6.11242, 0.952941, 0.02),
	(5.09684, 5.19556, 0.94, 0.0133333),
	(4.07747, 4.15644, 0.936, 0.01)
]

# the slowing of a class: none for off (and the invalid class 0)
pub fn slowingOf(class i64) physics.Slowing:
	if class < 2 or class > 5: return physics.Slowing(0.0, 0.0, 1.0, 0.0)
	inverseSpeed, inverseTurning, keep, rest = slowingTable[class - 2]
	physics.Slowing(1.0 / inverseSpeed, 1.0 / inverseTurning, keep, rest)

# Which biped parts of one ragdoll collide, as SkyrimSE.exe's bhkCollisionFilter sets them
# (0x14107cbd0, reference/exe/README.md, "Havok: the collision filter"): by part (OTHER 0, HEAD 1,
# BODY 2, SPINE1 3, SPINE2 4, LUPPERARM 5, LFOREARM 6, LHAND 7, LTHIGH 8, LCALF 9, LFOOT 10,
# RUPPERARM 11, RFOREARM 12, RHAND 13, RTHIGH 14, RCALF 15, RFOOT 16, TAIL 17, SHIELD 18, QUIVER 19,
# WEAPON 20, PONYTAIL 21, WING 22, PACK 23, CHAIN 24), the parts it collides with; the rest of a
# ragdoll does not touch itself. long: a table, one line a part
bipedCollisions (i64[])[] = [
	[],
	[6, 7, 12, 13, 17, 22],
	[6, 7, 12, 13, 22, 24],
	[6, 7, 12, 13, 22, 24],
	[6, 7, 12, 13, 17, 22, 24],
	[12, 13, 22],
	[1, 2, 3, 4, 8, 11, 12, 13, 14, 17, 22],
	[1, 2, 3, 4, 8, 9, 10, 11, 12, 13, 14, 15, 16, 22],
	[6, 7, 12, 13, 14, 15, 16, 18, 22, 24],
	[7, 13, 14, 15, 16, 18, 22, 24],
	[7, 13, 14, 15, 18, 22, 24],
	[6, 7, 22],
	[1, 2, 3, 4, 5, 6, 7, 8, 14, 17, 22],
	[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 14, 15, 16, 18, 22],
	[6, 7, 8, 9, 10, 12, 13, 18, 22, 24],
	[7, 8, 9, 10, 13, 18, 22, 24],
	[7, 8, 9, 13, 18, 22, 24],
	[1, 4, 6, 12, 22],
	[8, 9, 10, 13, 14, 15, 16, 22],
	[],
	[22],
	[22],
	[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 21],
	[],
	[2, 3, 4, 8, 9, 10, 14, 15, 16]
]

# Which collision layers do not collide, as SkyrimSE.exe's bhkCollisionFilter sets them
# (0x14107cbd0, reference/exe/README.md, "Havok: the collision filter"): by SkyrimLayer
# (nif.layerNames' order: 0 unidentified, 1 static, 4 clutter, 8 biped, 10 props, 30 char
# controller, 32 dead bip...), the layers it does not meet; every other pair collides.
# long: a table, one line a layer
layerMisses (i64[])[] = [
	[30],
	[18, 21],
	[18, 21],
	[18, 19, 21],
	[18, 21],
	[8, 18, 21],
	[8, 18, 19, 21],
	[18, 19, 21],
	[5, 6, 18, 19, 20, 21, 30, 32],
	[18, 21],
	[18, 21],
	[18, 19, 20, 21],
	[18, 19, 21],
	[18, 21],
	[18, 21],
	[18, 19, 20, 21],
	[18, 19, 20, 21],
	[18, 21],
	[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 19, 20, 26, 28, 30, 32, 34, 39, 41, 42, 43, 44, 45],
	[3, 6, 7, 8, 11, 12, 15, 16, 18, 26, 28, 30, 34, 36, 39, 40, 41, 42, 46],
	[8, 11, 15, 16, 18, 41],
	[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 26, 28, 32, 34, 39, 41, 42, 43, 44, 45],
	[],
	[],
	[],
	[],
	[18, 19, 21],
	[],
	[18, 19, 21],
	[],
	[0, 8, 18, 19, 32],
	[],
	[8, 18, 21, 30],
	[],
	[18, 19, 21],
	[],
	[19],
	[],
	[],
	[18, 19, 21],
	[19],
	[18, 19, 20, 21],
	[18, 19, 21],
	[18, 21],
	[18, 21],
	[18, 21],
	[19]
]

pub charControllerLayer = 30
pub deadBipLayer = 32

# the layer table as the physics takes it: a layer's bits of the layers it meets
fn layerPairs():
	all = -1
	out = []
	for misses in layerMisses:
		bits = all
		for layer in misses:
			bits &= ~(1 << layer)
		out.push(bits)
	out

# the table as the physics takes it: a part's bits
fn bipedPairs():
	out = []
	for parts in bipedCollisions:
		bits = 0
		for part in parts:
			bits |= 1 << part
		out.push(bits)
	out

# an empty world of Skyrim's units and its solver settings (hkpWorldCinfo as the game fills it:
# tau, damping, iterations, micro steps)
pub fn havokWorld() physics.World:
	w = physics.worldOf(nif.havokScale)
	w.solver = physics.Solver(
		tau = 0.6,
		damping = 1.0,
		iterations = 4,
		microSteps = 1
	)
	w.partPairs = bipedPairs()
	w.layerPairs = layerPairs()
	w
