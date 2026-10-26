# The natives of references and actors over the game's model (game/sim): a reference's cell,
# links, owner, lock and door, its inventory (AddItem, RemoveItem, GetItemCount, DropObject),
# references made and moved (PlaceAtMe, MoveTo, Delete), keywords; an actor's equipment and its
# values (base, modifier, damage), death and level. Semantics after the Creation Kit wiki's pages
# of ObjectReference, Actor and Form. Anything else falls to the stub (natives.zap).

import game.sim

# GetOpenState's answers
openStateOpen = 1
openStateClosed = 3
# how far before an actor DropObject puts what it drops, in units, and how high
dropReach f32 = 64.0
dropHeight f32 = 64.0

fn meForm(rt Runtime, c NativeCall):
	rt.objects[c.me].form

# the form an argument names (an object's form), 0 for none
fn formArg(rt Runtime, c NativeCall, k i64):
	match c.arg(k):
		Object(id): rt.objects[id].form if id > 0 else 0
		_: 0

fn intArg(c NativeCall, k i64, otherwise i64):
	if k < c.args.len: return c.arg(k).asInt()
	otherwise

fn reference(lib Library, mut rt Runtime, form i64) Value:
	.Object(lib.objectFor(rt, form, "objectreference")) if form != 0 else .None

# AddItem: count of the item into the reference's inventory
fn addItem(mut rt Runtime, c NativeCall) Value:
	rt.world.giveItem(rt.meForm(c), rt.formArg(c, 0), c.intArg(1, 1), 0)
	.None

# RemoveItem: count of the item out of the inventory, into the other container when one is named
fn removeItem(mut rt Runtime, c NativeCall) Value:
	me = rt.meForm(c)
	item = rt.formArg(c, 0)
	to = rt.formArg(c, 3)
	count = c.intArg(1, 1)
	if rt.world.inventories.get(me) == none: return .None
	if to == 0:
		rt.world.inventories[me].takeOut(item, count)
		return .None
	taken = rt.world.inventories[me].takeOut(item, count)
	rt.world.ensureInventory(to)
	for x in taken:
		rt.world.inventories[to].addExtra(item, x)
	.None

fn itemCount(rt Runtime, c NativeCall) Value:
	inv = rt.world.inventories.get(rt.meForm(c)) ?? return .Int(0)
	.Int(inv.countOf(rt.formArg(c, 0)))

fn groundBefore(rt Runtime, form i64):
	f = rt.world.forms.get(form) ?? return Vec3(0, 0, 0)
	heading = f.rotation.z
	f.positionOf() + Vec3(heading.sin() * dropReach, heading.cos() * dropReach, dropHeight)

# DropObject: count of the item out of the inventory as a new reference before the actor
fn dropObject(lib Library, mut rt Runtime, c NativeCall) Value:
	me = rt.meForm(c)
	item = rt.formArg(c, 0)
	inv = rt.world.inventories.get(me) ?? return .None
	count = c.intArg(1, 1).min(inv.countOf(item))
	if count <= 0: return .None
	rt.world.inventories[me].takeOut(item, count)
	placed = rt.world.placeNew(item, rt.groundBefore(me), count)
	rt.note("dropped {count} {item:08X} as {placed:08X}")
	lib.reference(rt, placed)

# PlaceAtMe: a new reference of the form where this one stands
fn placeAtMe(lib Library, mut rt Runtime, c NativeCall) Value:
	f = rt.world.forms.get(rt.meForm(c)) ?? return .None
	placed = rt.world.placeNew(rt.formArg(c, 0), f.positionOf(), c.intArg(1, 1))
	if c.args.len > 3 and c.arg(3).asInt() != 0: rt.world.forms[placed].enabled = false
	lib.reference(rt, placed)

# MoveTo and MoveToNode: where the target stands (with the offsets given), in its cell
fn moveTo(mut rt Runtime, c NativeCall) Value:
	me = rt.meForm(c)
	target = rt.world.forms.get(rt.formArg(c, 0)) ?? return .None
	offset = Vec3(0, 0, 0)
	if c.args.len >= 4 and c.key.endsWith("moveto"):
		offset = Vec3(c.arg(1).asFloat(), c.arg(2).asFloat(), c.arg(3).asFloat())
	p = target.positionOf() + offset
	cell = target.cell
	rt.world.addForm(me)
	rt.world.forms[me].x = p.x
	rt.world.forms[me].y = p.y
	rt.world.forms[me].z = p.z
	rt.world.forms[me].cell = cell
	.None

fn linkedRef(lib Library, mut rt Runtime, c NativeCall) Value:
	lib.reference(rt, rt.world.linkedRef(rt.meForm(c), rt.formArg(c, 0)))

fn parentCell(lib Library, mut rt Runtime, c NativeCall) Value:
	cell = (rt.world.forms.get(rt.meForm(c)) ?? return .None).cell
	.Object(lib.objectFor(rt, cell, "cell")) if cell != 0 else .None

# changes the reference's state through a function of the world's form
fn setForm(mut rt Runtime, c NativeCall, what str) Value:
	me = rt.meForm(c)
	rt.world.addForm(me)
	match what:
		"delete":
			rt.world.forms[me].deleted = true
			rt.world.forms[me].enabled = false
		"motion": rt.world.forms[me].motion = c.arg(0).asInt()
		"owner": rt.world.forms[me].owner = rt.formArg(c, 0)
		"block": rt.world.forms[me].blocked = c.arg(0).isTrue(0)
		"open": rt.world.forms[me].open = c.arg(0).isTrue(0)
		_: pass
	.None

fn openState(rt Runtime, c NativeCall) Value:
	f = rt.world.forms.get(rt.meForm(c)) ?? return .Int(0)
	.Int(openStateOpen if f.open else openStateClosed)

fn isLocked(rt Runtime, c NativeCall) Value:
	f = rt.world.forms.get(rt.meForm(c)) ?? return .Bool(false)
	.Bool(f.lock?.locked ?? false)

fn setLocked(mut rt Runtime, c NativeCall) Value:
	me = rt.meForm(c)
	rt.world.addForm(me)
	lock = rt.world.forms[me].lock ?? sim.Lock(level = 0, key = 0, locked = false)
	lock.locked = c.arg(0).isTrue(0) if not c.args.isEmpty else true
	rt.world.forms[me].lock = lock
	.None

# HasKeyword: a reference has its base's keywords
fn hasKeyword(rt Runtime, c NativeCall) Value:
	form = rt.meForm(c)
	base = form
	if rt.world.forms.get(form) is f:
		if f.base != 0: base = f.base
	.Bool(rt.formArg(c, 0) in rt.world.keywordsOf(base))

fn is3dLoaded(rt Runtime, c NativeCall) Value:
	f = rt.world.forms.get(rt.meForm(c)) ?? return .Bool(false)
	.Bool(f.enabled and not f.deleted and f.cell == rt.world.cell and f.cell != 0)

fn goldValue(rt Runtime, c NativeCall) Value:
	.Int((rt.world.items.get(rt.meForm(c)) ?? return .Int(0)).value)

# long: the table of the references' natives, one arm per function
# a native of a reference or a form over the game's model, or the stub
pub fn referenceNative(lib Library, mut rt Runtime, c NativeCall) Value:
	match c.key:
		"objectreference.getparentcell": lib.parentCell(rt, c)
		"objectreference.getlinkedref": lib.linkedRef(rt, c)
		"objectreference.additem": rt.addItem(c)
		"objectreference.removeitem": rt.removeItem(c)
		"objectreference.getitemcount": rt.itemCount(c)
		"objectreference.dropobject": lib.dropObject(rt, c)
		"objectreference.placeatme": lib.placeAtMe(rt, c)
		"objectreference.moveto", "objectreference.movetonode": rt.moveTo(c)
		"objectreference.delete": rt.setForm(c, "delete")
		"objectreference.setmotiontype": rt.setForm(c, "motion")
		"objectreference.setactorowner", "objectreference.setfactionowner": rt.setForm(c, "owner")
		"objectreference.blockactivation": rt.setForm(c, "block")
		"objectreference.setopen": rt.setForm(c, "open")
		"objectreference.getopenstate": rt.openState(c)
		"objectreference.islocked": rt.isLocked(c)
		"objectreference.lock": rt.setLocked(c)
		"objectreference.is3dloaded": rt.is3dLoaded(c)
		"form.haskeyword": rt.hasKeyword(c)
		"form.getgoldvalue": rt.goldValue(c)
		_: lib.actorNative(rt, c)
