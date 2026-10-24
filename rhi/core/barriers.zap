# What each texture drawn into is used for, from which every barrier between its uses follows. A
# pass declares the targets it writes (beginPass: its color and depth, each cleared or kept), a
# resolve its source and destination, a compute stage the buffers it writes (its program's
# `written`); every other texture rests, readable by any shader stage. The textures a use takes
# out of rest stay held until the next one (a pass, a resolve, a compute stage, the frame's end),
# which puts back those it does not take itself: a target drawn by two passes in a row stays a
# target. Each backend turns the transitions into its barriers: Vulkan's stages, access and image
# layouts, Direct3D 12's resource states.

pub useRead = 0   # at rest: read by shaders
pub useColor = 1   # a pass's color target
pub useDepth = 2   # a pass's depth target
pub useResolveFrom = 3   # a resolve's multisampled source
pub useResolveInto = 4   # a resolve's destination
pub useNone = 5   # the screen before the frame's first pass into it: what it holds is not kept
pub useCopyFrom = 6   # copied out (read back)

# a texture (or the screen) wanted for a use; `discard` when what it holds is not kept (a pass
# clears it)
pub type TextureUse:
	texture i64
	use i64
	discard bool = false

# A texture (or the screen) moved from one use to the next: the same use when the writes of the
# one before must be done before the next one's.
pub type Transition:
	texture i64
	from i64
	to i64
	discard bool

# what a pass into the color targets (textures, or the screen) and the depth target (a texture or
# none) takes
pub fn passUses(colors i64[], depth i64, clearColor bool, clearDepth bool) TextureUse[]:
	uses = []
	for color in colors:
		uses.push(TextureUse(texture = color, use = useColor, discard = clearColor))
	if depth >= 0:
		uses.push(TextureUse(texture = depth, use = useDepth, discard = clearDepth))
	uses

# what a resolve from a multisampled texture into a plain one takes
pub fn resolveUses(from i64, into i64) TextureUse[]:
	[
		TextureUse(texture = from, use = useResolveFrom),
		TextureUse(texture = into, use = useResolveInto)
	]

# The transitions that take the textures to their uses, after those held by the use before and
# not taken now go back to rest; the textures taken become the held ones. (The screen is never
# held: it stays a target until the frame's end presents it.)
pub fn takeTextures(mut s DeviceState, uses TextureUse[]) Transition[]:
	moves = []
	for id in s.held:
		if s.textures[id].live and not taken(uses, id):
			moves.push(
				Transition(texture = id, from = s.textures[id].use, to = useRead, discard = false)
			)
			s.textures[id].use = useRead
	s.held.clear()
	for u in uses:
		if u.texture == screenTarget:
			from = useColor if s.pass.screenTouched else useNone
			moves.push(Transition(texture = u.texture, from, to = u.use, discard = u.discard))
		else:
			moves.push(
				Transition(
					texture = u.texture,
					from = s.textures[u.texture].use,
					to = u.use,
					discard = u.discard
				)
			)
			s.textures[u.texture].use = u.use
			s.held.push(u.texture)
	moves

# the held textures back to rest (before a compute stage, at the frame's end)
pub fn restTextures(mut s DeviceState) Transition[]:
	s.takeTextures([])

fn taken(uses TextureUse[], id i64):
	for u in uses:
		if u.texture == id: return true
	false
