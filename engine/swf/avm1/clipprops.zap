# long: the display properties' table and their reads and writes, one arm each
#
# A node's display properties as ActionScript sees them (SWF specification v19, GetProperty's
# indices; Ruffle's core/src/avm1/object/stage_object.rs): the place in pixels, the scales in
# percent and the rotation in degrees taken from its matrix and put back into it, the alpha in
# percent, the size of its bounds in its parent, its frames from 1. A script that sets one of the
# transform's takes it from the timeline. The names are not case sensitive.

import engine.swf

displayNames = ["_x", "_y", "_xscale", "_yscale", "_currentframe", "_totalframes", "_alpha",
	"_visible", "_width", "_height", "_rotation", "_target", "_framesloaded", "_name",
	"_droptarget", "_url", "_highquality", "_focusrect", "_soundbuftime", "_quality", "_xmouse",
	"_ymouse"]

# the index of a display property by name (GetProperty's), none for other names
pub fn displayIndex(name str) i64?:
	if not name.startsWith("_"): return none
	key = name.lower()
	for k, d in displayNames:
		if d == key: return k
	none

# a clip's member that is no property of its object: _root, _parent, _global, a child by
# instance name, a display property
fn clipMember(prog Program, mut m Machine, n Handle<swf.Node>, name str) Value?:
	match name:
		"_root", "_level0": return .Obj(m.objectOfNode(prog, m.stage.root))
		"_parent": return prog.parentOf(m, n)
		"_global": return .Obj(m.globals)
		_: pass
	if m.stage.childNamed(n, name) is c:
		if prog.scene.movie.shapes.get(m.stage.nodes[c].placed.character) == none:
			return .Obj(m.objectOfNode(prog, c))
	prog.displayProperty(m, n, name)

# the display property of a node by name
pub fn displayProperty(prog Program, mut m Machine, n Handle<swf.Node>, name str) Value?:
	index = try displayIndex(name)
	prog.displayByIndex(m, n, index)

fn displayByIndex(prog Program, mut m Machine, n Handle<swf.Node>, index i64):
	node = m.stage.nodes.get(n) ?? return Value.Undefined
	t = node.placed.matrix
	match index:
		0: .Num(f64(t.tx) / 20.0)
		1: .Num(f64(t.ty) / 20.0)
		2: .Num(f64(Vec2(t.a, t.b).length()) * 100.0)
		3: .Num(f64(Vec2(t.c, t.d).length()) * 100.0)
		4: .Num(f64(node.frame + 1))
		5, 12: .Num(f64(m.stage.frameCount(prog.scene, n)))
		6: .Num(f64(node.placed.color.mul.w) * 100.0)
		7: .Bool(node.placed.visible)
		8: .Num(f64(prog.boundsSize(m, n).x) / 20.0)
		9: .Num(f64(prog.boundsSize(m, n).y) / 20.0)
		10: .Num(f64(t.b).atan2(f64(t.a)).degrees())
		11: prog.targetPathOf(m, .Obj(m.objectOfNode(prog, n)))
		13: .Str(node.placed.name.copy())
		14, 15: .Str("")
		16: .Num(1.0)
		17: .Bool(true)
		18: .Num(5.0)
		19: .Str("HIGH")
		_: prog.mouseIn(m, n, index == 20)

# the pointer in the node's own space, pixels
fn mouseIn(prog Program, m Machine, n Handle<swf.Node>, x bool):
	local = m.stage.stageMatrix(n).inverse().apply(m.mouse * 20.0)
	Value.Num(f64(local.x if x else local.y) / 20.0)

# the size of the node's bounds in its parent's space, twips
fn boundsSize(prog Program, m Machine, n Handle<swf.Node>):
	b = prog.parentBounds(m, n) ?? return Vec2(0.0, 0.0)
	Vec2(b.xmax - b.xmin, b.ymax - b.ymin)

# the node's bounds in its parent's space, twips
pub fn parentBounds(prog Program, m Machine, n Handle<swf.Node>) swf.Rect?:
	prog.scene.boundsOf(m.stage, n, m.stage.nodes[n].placed.matrix)

# GetProperty: a target's display property by index
fn getPropertyOp(prog Program, mut m Machine, mut a Activation) () ? Thrown:
	index = i64(try prog.popNumber(m, a))
	which = a.pop()
	n = prog.nodeOfTarget(m, a, which) ?? return a.push(.Undefined)
	a.push(prog.displayByIndex(m, n, index) if index >= 0 and index < displayNames.len
		else .Undefined)

# SetProperty: a target's display property by index
fn setPropertyOp(prog Program, mut m Machine, mut a Activation) () ? Thrown:
	v = a.pop()
	index = i64(try prog.popNumber(m, a))
	which = a.pop()
	n = prog.nodeOfTarget(m, a, which) ?? return
	if index < 0 or index >= displayNames.len: return
	try prog.setDisplayProperty(m, n, displayNames[index], v)

# sets a node's display property by name; the read-only ones are left
pub fn setDisplayProperty(
	prog Program,
	mut m Machine,
	n Handle<swf.Node>,
	name str,
	v Value
) () ? Thrown:
	index = displayIndex(name) ?? return
	if index == 13:
		m.stage.nodes[n].placed.name = try prog.toText(m, v)
		return
	if index == 7:
		m.stage.nodes[n].placed.visible = v.isTrue()
		return
	x = try prog.toNumber(m, v)
	if isNaN(x): return
	t = m.stage.nodes[n].placed.matrix
	match index:
		0: t.tx = f32(x * 20.0)
		1: t.ty = f32(x * 20.0)
		2, 3, 10: t = t.transformWith(index, f32(x))
		6:
			m.stage.nodes[n].placed.color.mul.w = f32(x / 100.0)
			return
		8, 9: t = prog.resized(m, n, index == 8, f32(x))
		_: return
	m.stage.nodes[n].placed.matrix = t
	m.stage.nodes[n].scripted = true

# the matrix with its x scale, y scale or rotation (index 2, 3, 10) set, the rest kept
fn transformWith(t swf.Affine, index i64, x f32):
	sx = Vec2(t.a, t.b).length()
	sy = Vec2(t.c, t.d).length()
	rx = f64(t.b).atan2(f64(t.a))
	ry = f64(-t.c).atan2(f64(t.d))
	if index == 2: sx = x / 100.0
	elif index == 3: sy = x / 100.0
	else:
		turn = f64(x).radians() - rx
		rx += turn
		ry += turn
	out = t
	out.a = f32(rx.cos()) * sx
	out.b = f32(rx.sin()) * sx
	out.c = -f32(ry.sin()) * sy
	out.d = f32(ry.cos()) * sy
	out

# the matrix scaled so its bounds in the parent are this wide (or high), pixels
fn resized(prog Program, m Machine, n Handle<swf.Node>, wide bool, size f32):
	t = m.stage.nodes[n].placed.matrix
	b = prog.parentBounds(m, n) ?? return t
	now = (b.xmax - b.xmin if wide else b.ymax - b.ymin) / 20.0
	if now <= 0.0: return t
	k = size / now
	if wide:
		t.a *= k
		t.b *= k
	else:
		t.c *= k
		t.d *= k
	t
