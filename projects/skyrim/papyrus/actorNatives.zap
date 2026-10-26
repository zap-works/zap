# The natives of actors over the game's model (game/sim): the actor base, the equipment (EquipItem
# adds the item when the actor has none, as the game does), the actor values (Get, Set, Mod,
# Damage, Restore, the base and the percentage; the short AV forms alike), death, the level, the
# gold carried, the AI asked to pick a package again and the location a reference is in (no
# dialogue runs yet: none is with the player). Semantics after the Creation Kit wiki's Actor page.

import game.sim

fn actorOf(rt Runtime, c NativeCall) sim.ActorState?:
	(try rt.world.actors.get(rt.meForm(c))).copy()

fn actorBase(lib Library, mut rt Runtime, c NativeCall) Value:
	f = rt.world.forms.get(rt.meForm(c)) ?? return .None
	.Object(lib.objectFor(rt, f.base, "actorbase")) if f.base != 0 else .None

fn equipped(lib Library, mut rt Runtime, c NativeCall, what str) Value:
	inv = rt.world.inventories.get(rt.meForm(c)) ?? return .None
	form = match what:
		"shield": inv.shieldWorn(rt.world.items)
		_: inv.weaponIn(rt.world.items, c.arg(0).isTrue(0))
	typeName = "armor" if what == "shield" else "weapon"
	.Object(lib.objectFor(rt, form, typeName)) if form != 0 else .None

fn equippedType(rt Runtime, c NativeCall) Value:
	inv = rt.world.inventories.get(rt.meForm(c)) ?? return .Int(0)
	.Int(inv.heldType(rt.world.items, c.arg(0).asInt() == 0))

fn equipItem(mut rt Runtime, c NativeCall) Value:
	me = rt.meForm(c)
	item = rt.formArg(c, 0)
	rt.world.ensureInventory(me)
	if rt.world.inventories[me].countOf(item) == 0: rt.world.giveItem(me, item, 1, 0)
	match rt.world.inventories[me].equip(rt.world.items, item, false):
		off: rt.note("equipped {item:08X}, off: {off.map("{it:08X}").join(" ")}")
		error: rt.note("error: EquipItem: {error}")
	.None

fn unequipItem(mut rt Runtime, c NativeCall) Value:
	me = rt.meForm(c)
	if rt.world.inventories.get(me) == none: return .None
	if c.key.endsWith("unequipall"):
		rt.world.inventories[me].unequipAll()
	else:
		rt.world.inventories[me].unequip(rt.formArg(c, 0))
	.None

fn isEquipped(rt Runtime, c NativeCall) Value:
	inv = rt.world.inventories.get(rt.meForm(c)) ?? return .Bool(false)
	.Bool(inv.isWorn(rt.formArg(c, 0)))

# Get, GetBase and the percentage of an actor value
fn readValue(rt Runtime, c NativeCall, what str) Value:
	a = rt.actorOf(c) ?? return .Float(0.0)
	name = rt.valueText(c.arg(0))
	match what:
		"base": .Float(a.baseValueOf(name))
		"percent": .Float(a.percentOf(name))
		_: .Float(a.valueOf(name))

# Set, Mod, Damage and Restore of an actor value
fn changeValue(mut rt Runtime, c NativeCall, what str) Value:
	me = rt.meForm(c)
	if rt.world.actors.get(me) == none: return .None
	name = rt.valueText(c.arg(0))
	amount = c.arg(1).asFloat()
	match what:
		"set": rt.world.actors[me].setBaseValue(name, amount)
		"mod": rt.world.actors[me].modValue(name, amount)
		"damage": rt.world.actors[me].damageValue(name, amount)
		_: rt.world.actors[me].restoreNamed(name, amount)
	.None

fn kill(mut rt Runtime, c NativeCall) Value:
	me = rt.meForm(c)
	if rt.world.actors.get(me) == none: return .None
	rt.world.actors[me].kill()
	rt.note("{me:08X} dies")
	.None

fn goldAmount(rt Runtime, c NativeCall) Value:
	inv = rt.world.inventories.get(rt.meForm(c)) ?? return .Int(0)
	.Int(inv.countOf(sim.goldForm))

# EvaluatePackage: the AI picks the actor's package again (game/residents.zap reads the request)
fn evaluatePackage(mut rt Runtime, c NativeCall) Value:
	rt.world.evaluate[rt.meForm(c)] = true
	.None

# ShowBarterMenu: the merchant asks for the barter menu, opened by the interface once he has spoken
fn showBarter(mut rt Runtime, c NativeCall) Value:
	rt.world.barterWith = rt.meForm(c)
	.None

# the location (LCTN) the reference is in, none for one in no location
# a reference's location: its own (XLCN), else the cell's it stands in (the player's: the cell's)
fn currentLocation(lib Library, mut rt Runtime, c NativeCall) Value:
	me = rt.meForm(c)
	place = rt.world.forms.get(me)?.location ?? 0
	if place == 0 and (me == rt.world.player or rt.world.forms.get(me)?.cell == rt.world.cell):
		place = rt.world.cellLocation
	.Object(lib.objectFor(rt, place, "location")) if place != 0 else .None

# AddSpell, RemoveSpell and HasSpell on the spells the actor knows (an ability's effects are the
# magic menu's Active Effects where the world has the spell's record)
fn changeSpell(mut rt Runtime, c NativeCall, add bool) Value:
	me = rt.meForm(c)
	spell = rt.formArg(c, 0)
	spells = (rt.world.actors.get(me) ?? return .Bool(false)).magic.known.copy()
	known = spell in spells
	if add and not known:
		rt.world.actors[me].magic.known.push(spell)
		if rt.world.spells.get(spell) == none: rt.world.unlearned.push(spell)
	if not add and known: rt.world.actors[me].magic.known = spells.filter(it != spell)
	.Bool(add != known)

# AddPerk, RemovePerk and HasPerk (perks.zap): a perk the world has no record of yet is learned
# by the next learnPending
fn changePerk(mut rt Runtime, c NativeCall, add bool) Value:
	me = rt.meForm(c)
	perk = rt.formArg(c, 0)
	if add:
		rt.world.addPerk(me, perk)
	else:
		rt.world.removePerk(me, perk)
	.None

# long: the table of the actors' natives, one arm per function
# a native of an actor over the game's model, or the stub
pub fn actorNative(lib Library, mut rt Runtime, c NativeCall) Value:
	match c.key:
		"actor.getactorbase", "actor.getleveledactorbase": lib.actorBase(rt, c)
		"actor.getequippedweapon": lib.equipped(rt, c, "weapon")
		"actor.getequippedshield": lib.equipped(rt, c, "shield")
		"actor.getequippeditemtype": rt.equippedType(c)
		"actor.equipitem": rt.equipItem(c)
		"actor.unequipitem", "actor.unequipall": rt.unequipItem(c)
		"actor.isequipped": rt.isEquipped(c)
		"actor.getactorvalue", "actor.getav": rt.readValue(c, "current")
		"actor.getbaseactorvalue", "actor.getbaseav": rt.readValue(c, "base")
		"actor.getactorvaluepercentage", "actor.getavpercentage": rt.readValue(c, "percent")
		"actor.setactorvalue", "actor.setav": rt.changeValue(c, "set")
		"actor.modactorvalue", "actor.modav": rt.changeValue(c, "mod")
		"actor.damageactorvalue", "actor.damageav": rt.changeValue(c, "damage")
		"actor.restoreactorvalue", "actor.restoreav": rt.changeValue(c, "restore")
		"actor.isdead": .Bool((rt.actorOf(c) ?? return .Bool(false)).dead)
		"actor.kill", "actor.killsilent": rt.kill(c)
		"actor.getlevel": .Int((rt.actorOf(c) ?? return .Int(1)).level)
		"actor.getgoldamount": rt.goldAmount(c)
		"actor.evaluatepackage": rt.evaluatePackage(c)
		"actor.showbartermenu": rt.showBarter(c)
		"actor.isindialoguewithplayer": .Bool(false)
		"objectreference.getcurrentlocation": lib.currentLocation(rt, c)
		"actor.addspell": rt.changeSpell(c, true)
		"actor.removespell": rt.changeSpell(c, false)
		"actor.hasspell": .Bool(rt.formArg(c, 0) in (rt.actorOf(c)?.magic?.known ?? []))
		"actor.addperk": rt.changePerk(c, true)
		"actor.removeperk": rt.changePerk(c, false)
		"actor.hasperk": .Bool(rt.world.hasPerk(rt.meForm(c), rt.formArg(c, 0)))
		_: rt.stub(c)
