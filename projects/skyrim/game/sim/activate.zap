# Activation, by the kind of the base record, as the game does it: an item is taken into the
# actor's inventory and its reference disabled (a theft when the actor may not take what its owner
# owns: the crime is recorded and what was taken is marked stolen); a container opens for the
# menus; a harvestable gives what PFIG gives in the season (once, until it respawns); a load door
# teleports (the destination named, its cell not loaded), a plain door opens or closes, a locked
# one needs its key or the lock to be picked; a furniture is used at its first marker in use
# (sit, sleep in a bed the actor may sleep in, lean), a workbench opens its crafting; an actor is
# talked to; an activator does nothing by itself: its scripts answer (papyrus/activation.zap
# sends their OnActivate). BlockActivation leaves only the scripts.

import skyrim.nif
import skyrim.esm

# what an activation did
pub type Activation:
	Taken(item i64, count i64, stolen bool, bounty i64)
	Harvested(item i64, count i64, stolen bool, bounty i64)   # item 0: nothing this season
	Opened(container i64)
	Teleported(door i64, destination i64, cell i64)
	DoorMoved(open bool, key i64)   # key: the key it was unlocked with first, 0 for none
	Locked(level i64)
	Used(kind i64, marker i64, position Vec3, heading f32)
	Crafting(bench i64)
	Refused(reason str)
	Talked(actor i64)
	Pickpocketing(victim i64)   # the player sneaks up to a living actor: the container menu's pickpocket mode
	Reading(book i64)   # the book's menu opens; taking it is the menu's (takeRef)
	Scripted   # nothing but the scripts

# Activates the reference by the actor (a reference too): what the game does by default.
pub fn activate(mut w GameWorld, refId i64, actorRef i64) Activation:
	f = w.forms.get(refId) ?? return .Refused("no reference {refId:08X}")
	if f.deleted or not f.enabled: return .Refused("{refId:08X} is not there")
	if f.blocked: return .Scripted
	kind = f.baseKind.copy()
	if kind == "BOOK": return w.readBook(refId, actorRef)
	if kind in itemKinds: return w.takeRef(refId, actorRef)
	match kind:
		"CONT": .Opened(refId)
		"DOOR": w.useDoor(refId, actorRef)
		"FURN": w.useFurniture(refId, actorRef)
		"FLOR", "TREE": w.harvest(refId, actorRef)
		"NPC_": w.activateNpc(refId, actorRef)
		_: .Scripted

# an actor activated: the player sneaking up to one pickpockets it, anyone else talks to it
fn activateNpc(w GameWorld, refId i64, actorRef i64) Activation:
	if actorRef == w.player and w.canPickpocket(refId): return .Pickpocketing(refId)
	.Talked(refId)

# puts count of the item into the actor's (or container's) inventory, marked stolen from `owner`
# when it is not 0
pub fn giveItem(mut w GameWorld, to i64, item i64, count i64, stolenFrom i64):
	w.ensureInventory(to)
	w.inventories[to].addExtra(item, ItemExtra(count, owner = stolenFrom))

# takes the loose item into the actor's inventory, a theft when the actor may not take what its
# owner owns; what was taken
pub fn takeRef(mut w GameWorld, refId i64, actorRef i64) Activation:
	f = w.forms[refId].copy()
	item = w.items.get(f.base) ?? return .Refused("{f.base:08X} is no item the world knows")
	if not item.isCarried(): return .Scripted
	owner = w.ownerOf(f)
	stolen = not w.canTake(actorRef, owner)
	w.giveItem(actorRef, f.base, f.count, owner if stolen else 0)
	w.forms[refId].enabled = false
	bounty = w.recordTheft(actorRef, refId, f.base, f.count, owner).bounty if stolen else 0
	w.record("{actorRef:08X} takes {f.count} {item.editorId} ({refId:08X})")
	.Taken(f.base, f.count, stolen, bounty)

# Opens the book for reading: a book that teaches a skill raises it by one the first time it is
# read (the game's skill books; the record's read flag kept per base form).
fn readBook(mut w GameWorld, refId i64, actorRef i64) Activation:
	base = w.forms[refId].base
	item = w.items.get(base) ?? return .Refused("{base:08X} is no book the world knows")
	skill = -1
	if item.kind.Book is b: skill = b.skill
	if skill >= firstSkill and skill < firstSkill + skillNames.len and
		w.booksRead.get(base) == none:
		if w.actors.get(actorRef) != none:
			name = skillNames[skill - firstSkill]
			if actorRef == w.player: w.incrementSkill(name, 1)
			else: w.actors[actorRef].setBaseValue(name, w.actors[actorRef].baseValueOf(name) + 1.0)
			w.record("{actorRef:08X} reads {base:08X}: {skillNames[skill - firstSkill]} rises by 1")
	w.booksRead[base] = true
	.Reading(base)

# the season of the game's day (0 spring, 1 summer, 2 autumn, 3 winter): the game starts on the
# 17th of Last Seed (August), the months as long as ours
pub fn seasonOf(daysPassed f64) i64:
	lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	day = (227 + i64(daysPassed.floor())) % 365
	month = 0
	while day >= lengths[month]:
		day -= lengths[month]
		month += 1
	[3, 3, 0, 0, 0, 1, 1, 1, 2, 2, 2, 3][month]

fn harvest(mut w GameWorld, refId i64, actorRef i64) Activation:
	f = w.forms[refId].copy()
	if f.harvested: return .Refused("{f.editorId} is already harvested")
	plant = w.items.get(f.base) ?? return .Refused("{f.base:08X} is no harvestable the world knows")
	h = plant.plantHarvest() ?? return .Scripted
	w.forms[refId].harvested = true
	chance = h.seasons[seasonOf(w.daysPassed)]
	if w.dice.below(100 - chance): return .Harvested(0, 0, false, 0)
	owner = w.ownerOf(f)
	stolen = not w.canTake(actorRef, owner)
	bounty = 0
	for c in h.gives:
		w.giveItem(actorRef, c.form, c.count, owner if stolen else 0)
		if stolen: bounty += w.recordTheft(actorRef, refId, c.form, c.count, owner).bounty
	given = h.gives.map(.count).sum()
	w.record("{actorRef:08X} harvests {given} from {plant.editorId} ({refId:08X})")
	.Harvested(h.gives.first?.form ?? 0, given, stolen, bounty)

fn useDoor(mut w GameWorld, refId i64, actorRef i64) Activation:
	f = w.forms[refId].copy()
	used = 0
	if f.lock is lock and lock.locked:
		if lock.key == 0 or (w.inventories.get(actorRef)?.countOf(lock.key) ?? 0) == 0:
			return .Locked(lock.level)
		w.forms[refId].lock = Lock(..lock, locked = false)
		w.record("{actorRef:08X} unlocks {refId:08X} with its key")
		used = lock.key
	if f.teleport is t:
		w.record("{actorRef:08X} goes through {refId:08X} to {t.door:08X} in {t.cellEditorId}")
		return .Teleported(refId, t.door, t.cell)
	w.forms[refId].open = not f.open
	.DoorMoved(not f.open, used)

fn useFurniture(mut w GameWorld, refId i64, actorRef i64) Activation:
	f = w.forms[refId].copy()
	fu = w.furniture.get(f.base) ?? return .Refused("{f.base:08X} is no furniture the world knows")
	if fu.bench > 0: return .Crafting(fu.bench)
	seat = fu.seatOf(f) ?? return .Refused("{f.editorId} has no marker in use")
	if seat.kind == nif.furnitureSleep and not w.canTake(actorRef, w.ownerOf(f)):
		return .Refused("sNoSleepInOwnedBed")
	w.record("{actorRef:08X} uses {refId:08X}: {seatKindName(seat.kind)}")
	.Used(seat.kind, seat.marker, seat.position, seat.heading)

# what an activation did, in words
pub fn activationText(w GameWorld, a Activation) str:
	match a:
		Taken(
			item,
			count,
			stolen,
			bounty
		): "taken: {count} {w.itemName(item)}{stealText(stolen, bounty)}"
		Harvested(item, count, stolen, bounty):
			if item == 0: return "harvested: nothing this season"
			"harvested: {count} {w.itemName(item)}{stealText(stolen, bounty)}"
		Opened(container):
			stacks = (w.inventories.get(container) ?? Inventory()).stacks.len
			"opened: {container:08X}, {stacks} stacks"
		Teleported(
			door,
			destination,
			cell
		): "teleport: to {destination:08X} in cell {cell:08X} (not loaded yet)"
		DoorMoved(open, _): "door: {"opens" if open else "closes"}"
		Locked(level): "locked: level {level}"
		Used(
			kind,
			marker,
			position,
			heading
		): "furniture: {seatKindName(kind)} at marker {marker}, {position}, heading {heading:.3}"
		Crafting(bench): "workbench: {benchTypes[bench] if bench < benchTypes.len else "{bench}"}"
		Refused(reason): "refused: {reason}"
		Talked(actor): "talk: {actor:08X}"
		Pickpocketing(victim): "pickpocket: {victim:08X}"
		Reading(book): "reading: {w.itemName(book)}"
		Scripted: "scripts only"

fn stealText(stolen bool, bounty i64):
	", stolen, bounty {bounty}" if stolen else ""

pub fn itemName(w GameWorld, form i64) str:
	item = w.items.get(form) ?? return "{form:08X}"
	"{item.name} ({item.editorId})"
