# The display list as a player keeps it from frame to frame (SWF specification v19, chapter 3, and
# Ruffle's core/src/display_object/movie_clip.rs): a tree of nodes, the root the main timeline,
# each sprite at its own frame, playing or stopped. A step to the next frame applies that frame's
# commands; a jump to any other frame makes the children what the timeline shows there, keeping
# those placed by the same PlaceObject (so their state lives on), as Flash's goto does. A node made
# by script (attachMovie, duplicateMovieClip) is the timeline's no more, and one whose transform a
# script set keeps it. What changed is noted (`created`, `entered`, `removed`) for the script
# machine (avm1) to make objects for and run the code of.

# an object of the display list
pub type Node:
	placed Placed   # its depth, character, transform, name, clip depth and visibility
	parent Handle<Node>? = none   # none: the root
	owner i64   # the character whose timeline placed it (0 the main one), -1 a script
	frame i64 = -1   # a sprite's frame shown, 0 the first; -1 before its first
	playing bool = true
	children Handle<Node>[] = []   # by depth
	scripted bool = false   # its transform set by script, which the timeline then leaves
	dynamic bool = false   # made or moved in depth by script: the timeline never removes it
	text str = ""   # a text field's text, HTML when html
	html bool = false
	textColor Vec4? = none   # a text field's color set by script
	format TextOverride? = none   # what a script's setTextFormat set over a text field's runs
	bounds Rect? = none   # a text field's bounds as autoSize made them
	shrink bool = false   # Scaleform's textAutoSize "shrink": the text made smaller to fit the field
	scroll i64 = 1   # a text field's first line shown (1 is the top)
	field EditText? = none   # the field MovieClip.createTextField made, which no tag defines

# a frame a node showed
pub type Shown:
	node Handle<Node>
	frame i64

# the display list of a scene's movie: a removed node leaves the pool, and its handle names nothing
pub type Stage:
	nodes Pool<Node>
	root Handle<Node>
	created Handle<Node>[] = []   # nodes made since the machine last took them, parents first
	entered Shown[] = []   # each frame shown, in order
	removed Handle<Node>[] = []

# the text field a node is: the one a script made, else its character's
pub fn fieldOf(st Stage, scene Scene, n Handle<Node>) EditText?:
	if st.nodes[n].field is own: return own.copy()
	(try scene.movie.editTexts.get(st.nodes[n].placed.character)).copy()

# the timeline a character plays: 0 the main one, else a sprite's; none for other characters
pub fn timelineOf(scene Scene, character i64) ref Timeline?:
	if character == 0: return scene.movie.timeline
	sp = try scene.movie.sprites.get(character)
	sp.timeline

# a stage at the movie's first frame
pub fn newStage(scene Scene) Stage:
	placed = Placed(
		depth = 0,
		character = 0,
		matrix = Affine(),
		color = ColorTransform(),
		ratio = -1,
		name = "", clipDepth = 0, blend = 0, visible = true, placedAt = 0)
	nodes = Pool<Node>()
	root = nodes.add(Node(placed, owner = -1))
	st = Stage(nodes, root)
	st.created.push(root)
	st.showFrame(scene, root, 0)
	st

# the frames of a node's timeline, 1 for what has none
pub fn frameCount(st Stage, scene Scene, n Handle<Node>) i64:
	t = scene.timelineOf(st.nodes[n].placed.character) ?? return 1
	t.frameCount.max(t.frames.len).max(1)

# the node's next frame shown when it plays: the first after the last
pub fn stepFrame(mut st Stage, scene Scene, n Handle<Node>):
	count = st.frameCount(scene, n)
	if count <= 1 and st.nodes[n].frame >= 0: return
	st.showFrame(scene, n, (st.nodes[n].frame + 1) % count)

# the node shows frame f (0 the first) of its timeline, its children made what that frame shows
pub fn showFrame(mut st Stage, scene Scene, n Handle<Node>, f i64):
	t = scene.timelineOf(st.nodes[n].placed.character) ?? return
	if f == st.nodes[n].frame + 1:
		if f < t.frames.len:
			for c in t.frames[f].commands:
				match c:
					Place(p): st.applyPlace(scene, n, p, f)
					Remove(depth):
						if st.timelineChild(n, depth) is gone: st.removeNode(gone)
	elif f != st.nodes[n].frame:
		st.reconcile(scene, n, t.displayList(f))
	st.nodes[n].frame = f
	st.entered.push(Shown(node = n, frame = f))

fn applyPlace(mut st Stage, scene Scene, n Handle<Node>, p Placement, f i64):
	at = st.timelineChild(n, p.depth)
	if at is c and p.moves:
		if not st.nodes[c].scripted: st.nodes[c].placed.moveTo(p)
		return
	if p.character < 0: return
	if at is c: st.removeNode(c)
	st.addChild(scene, n, p.placedOf(f), st.nodes[n].placed.character)

# The children made what the list says, those placed by the same PlaceObject kept with their name
# and their visibility, which a script may have set and a goto leaves (Ruffle's goto_frame applies
# a PlaceObject's transform to a kept clip, its visibility only when the tag carries one).
fn reconcile(mut st Stage, scene Scene, n Handle<Node>, list Placed[]):
	for c in st.nodes[n].children.copy():
		if st.nodes[c].dynamic: continue
		was = st.nodes[c].placed
		keep = list.any(.depth == was.depth and .character == was.character and
			.placedAt == was.placedAt)
		if not keep: st.removeNode(c)
	for p in list:
		if st.timelineChild(n, p.depth) is c:
			if not st.nodes[c].scripted:
				name = st.nodes[c].placed.name.copy()
				visible = st.nodes[c].placed.visible
				st.nodes[c].placed = p.copy()
				st.nodes[c].placed.name = name
				st.nodes[c].placed.visible = visible
		else:
			st.addChild(scene, n, p.copy(), st.nodes[n].placed.character)

# how many clips hold the node, 0 for the root
pub fn depthOf(st Stage, n Handle<Node>) i64:
	k = 0
	at = n
	while st.nodes[at].parent is up:
		at = up
		k += 1
	k

# the child of n at this depth that its timeline placed
fn timelineChild(st Stage, n Handle<Node>, depth i64) Handle<Node>?:
	for c in st.nodes[n].children:
		if st.nodes[c].placed.depth == depth and not st.nodes[c].dynamic: return c
	none

# the child of n at this depth, whoever placed it
pub fn childAtDepth(st Stage, n Handle<Node>, depth i64) Handle<Node>?:
	for c in st.nodes[n].children:
		if st.nodes[c].placed.depth == depth: return c
	none

# the child of n with this instance name
pub fn childNamed(st Stage, n Handle<Node>, name str) Handle<Node>?:
	for c in st.nodes[n].children:
		if st.nodes[c].placed.name == name: return c
	none

# A new child of n placed as `placed` says (owner the character whose timeline places it, -1 a
# script), a text field with its own text, a sprite at its first frame.
pub fn addChild(
	mut st Stage,
	scene Scene,
	n Handle<Node>,
	move placed Placed,
	owner i64
) Handle<Node>:
	character = placed.character
	node = Node(placed, parent = n, owner, dynamic = owner < 0)
	if scene.movie.editTexts.get(character) is t:
		node.text = t.text.copy()
		node.html = t.html
	id = st.nodes.add(node)
	st.insertChild(n, id)
	st.created.push(id)
	if scene.timelineOf(character) != none: st.showFrame(scene, id, 0)
	id

fn insertChild(mut st Stage, n Handle<Node>, id Handle<Node>):
	depth = st.nodes[id].placed.depth
	kids = st.nodes[n].children.copy()
	at = kids.len
	for k, c in kids:
		if st.nodes[c].placed.depth > depth:
			at = k
			break
	st.nodes[n].children.insert(at, id)

# the node and what it holds taken off the stage
pub fn removeNode(mut st Stage, n Handle<Node>):
	if n not in st.nodes: return
	if st.nodes[n].parent is p: st.nodes[p].children = st.nodes[p].children.filter(it != n)
	st.dropNode(n)

fn dropNode(mut st Stage, n Handle<Node>):
	st.removed.push(n)
	gone = st.nodes.remove(n) ?? return
	for c in gone.children:
		st.dropNode(c)

# the node put at another depth of its parent, trading places with one there
pub fn swapDepth(mut st Stage, n Handle<Node>, depth i64):
	p = st.nodes[n].parent ?? return
	if st.childAtDepth(p, depth) is other:
		st.nodes[other].placed.depth = st.nodes[n].placed.depth
		st.nodes[other].dynamic = true
	st.nodes[n].placed.depth = depth
	st.nodes[n].dynamic = true
	kids = st.nodes[p].children.copy()
	st.nodes[p].children = kids.sortedBy(st.nodes[it].placed.depth)

# the node at a path of instance names from the root ("HUDMovieBaseInstance.Health")
pub fn nodeAt(st Stage, path str) Handle<Node>?:
	n = st.root
	for name in path.split("."):
		n = try st.childNamed(n, name)
	n

# the node's path of names from the root, "_level0" for the root, empty for a node removed
pub fn pathOf(st Stage, n Handle<Node>) str:
	if n not in st.nodes: return ""
	up = st.nodes[n].parent ?? return "_level0"
	"{st.pathOf(up)}.{st.nodes[n].placed.name}"

# the node's matrix on the stage (twips): its parents' composed with its own
pub fn stageMatrix(st Stage, n Handle<Node>) Affine:
	m = st.nodes[n].placed.matrix
	p = st.nodes[n].parent
	while p is up:
		m = st.nodes[up].placed.matrix.times(m)
		p = st.nodes[up].parent
	m

# the nodes that play, parents before their children, in depth order
pub fn playOrder(st Stage) Handle<Node>[]:
	out = []
	st.collectOrder(st.root, out)
	out

fn collectOrder(st Stage, n Handle<Node>, mut out Handle<Node>[]):
	out.push(n)
	for c in st.nodes[n].children:
		st.collectOrder(c, out)
