# The cell's models the scene poses as time goes instead of baking them into its one buffer: a
# door whose model animates a node with its Open and Close sequences (as the game plays them when
# the door is activated, TESObjectDOOR::Activate 0x140283210 through 0x1401d9590, or sets its
# state at the load with 0x1401d9eb0). Each part keeps its triangles in the model's space and the
# frame of the node it hangs from, which the scene moves.

import world

# whether the model animates a node with an Open and a Close sequence
pub fn isMovable(m ModelParts) bool:
	m.sequences.any(.name == "Open") and m.sequences.any(.name == "Close") and
		m.partFrames.any(it >= 0)

# the model of the reference `refId` placed by `place`, as the scene poses it
pub fn movableOf(m ModelParts, refId i64, place Mat4) world.Movable:
	parts = []
	reach = 0.0
	for k in 0..m.parts.len:
		one = newCellBuild()
		one.addPart(m, k, Mat4(1.0))
		for v in one.vertices:
			reach = reach.max(v.position.x.abs())
		indices, runs = one.runsOf()
		for run in runs:
			parts.push(world.MovablePart(
				kind = run.kind,
				twoSided = run.twoSided,
				frame = m.partFrames[k],
				vertices = indices[
					run.first..run.first + run.count
				].map(one.vertices[it].copy())
			))
	world.Movable(
		refId,
		place,
		frames = m.frames.map(.copy()),
		open = (m.sequences.find(.name == "Open") ?? fail("no Open sequence")).copy(),
		close = (m.sequences.find(.name == "Close") ?? fail("no Close sequence")).copy(),
		halfWidth = reach,
		parts
	)
