# The game's model without the install: items made by hand, inventories, equipping, actor
# values, the dice and the seasons (game/sim).

import skyrim.esm
import game.sim

fn handItem(form i64, kind str, weight f32, slots i64, animation i64):
	sim.Item(
		formId = form,
		kind = kind.copy(),
		editorId = "item{form}",
		name = "",
		model = "",
		value = 10,
		weight,
		keywords = [],
		armor = sim.ArmorData(rating = 1.0, slots, armorType = 0, addons = []) if kind == "ARMO"
		else none,
		weapon = sim.WeaponData(
			animation,
			damage = 7,
			speed = 1.0,
			reach = 1.0,
			skill = 6,
			critDamage = 3,
			critMult = 1.0,
			critEffect = 0,
			twoHanded = animation in [5, 6, 7, 9]
		) if kind == "WEAP" else none,
		flags = 2 if kind == "LIGH" else 0
	)

fn handItems():
	items {i64: sim.Item} = {}
	for item in [
		handItem(1, "WEAP", 9.0, 0, 1),   # a sword
		handItem(2, "WEAP", 2.0, 0, 2),   # a dagger
		handItem(3, "WEAP", 17.0, 0, 5),   # a greatsword
		handItem(4, "ARMO", 12.0, sim.slotShield, 0),   # a shield
		handItem(5, "ARMO", 1.0, 0x4, 0),   # a cuirass (slot 32)
		handItem(6, "ARMO", 5.0, 0x4 | 0x8, 0),   # a robe with its hands (slots 32, 33)
		handItem(7, "LIGH", 0.5, 0, 0),   # a torch
		handItem(8, "MISC", 0.0, 0, 0)
	]:
		items[item.formId] = item
	items

test "an inventory counts, takes plain instances first and keeps data only where needed":
	inv = sim.Inventory()
	inv.addItem(1, 2)
	inv.addExtra(1, sim.ItemExtra(count = 1, owner = 0x3_5D44))
	expect inv.countOf(1) == 3 and inv.stacks[0].extras.len == 1
	taken = inv.takeOut(1, 2)
	expect taken.map(.count).sum() == 2 and taken.all(.owner == 0)
	expect inv.countOf(1) == 1 and inv.stacks[0].extras[0].owner == 0x3_5D44
	inv.addExtra(1, sim.ItemExtra(count = 2))   # all default: plain again
	expect inv.countOf(1) == 3 and inv.stacks[0].extras.len == 1
	other = sim.Inventory()
	expect inv.moveItems(other, 1, 5) == 3 and inv.countOf(1) == 0 and inv.stacks.isEmpty
	expect other.countOf(1) == 3 and other.stacks[0].extras[0].owner == 0x3_5D44

test "the weight is each item's times its count":
	items = handItems()
	inv = sim.Inventory()
	inv.addItem(1, 2)
	inv.addItem(7, 3)
	inv.addItem(99, 4)   # unknown: no weight
	expect inv.weightOf(items) == 19.5

test "equipping: two hands take both, a shield and a torch the left, armor its slots":
	items = handItems()
	inv = sim.Inventory()
	for form in 1..9:
		inv.addItem(form, 1)
	expect (inv.equip(items, 1, false) ?? fail).isEmpty
	expect (inv.equip(items, 4, false) ?? fail).isEmpty
	expect inv.weaponIn(items, false) == 1 and inv.shieldWorn(items) == 4
	expect (inv.equip(items, 3, false) ?? fail) == [1, 4]   # both hands
	expect inv.heldType(items, false) == 5 and inv.heldType(items, true) == 5
	expect (inv.equip(items, 7, false) ?? fail) == [3]   # the torch frees the left hand
	expect (inv.equip(items, 2, true) ?? fail) == [7]   # the dagger in the left hand
	expect inv.weaponIn(items, true) == 2 and inv.weaponIn(items, false) == 0
	expect (inv.equip(items, 5, false) ?? fail).isEmpty
	expect (inv.equip(items, 6, false) ?? fail) == [5]   # the robe covers the cuirass's slot
	refused = false
	if inv.equip(items, 8, false) is error: refused = not error.isEmpty
	expect refused
	expect inv.wornForms() == [2, 6]

test "a one-handed weapon held alone moves from one hand to the other":
	items = handItems()
	inv = sim.Inventory()
	inv.addItem(1, 1)
	inv.equip(items, 1, false) ?? fail
	expect (inv.equip(items, 1, true) ?? fail) == [1]
	expect inv.weaponIn(items, true) == 1 and inv.weaponIn(items, false) == 0
	expect inv.countOf(1) == 1

test "an actor's values: damage down to 0 kills, restore gives back, mod raises the maximum":
	a = sim.ActorState(npc = 7, race = 0, level = 1, values = {})
	a.setBaseValue("Health", 100.0)
	a.damageValue("health", 30.0)
	expect a.valueOf("health") == 70.0 and a.percentOf("health") == 0.7
	a.restoreNamed("health", 50.0)
	expect a.valueOf("health") == 100.0
	a.modValue("health", 20.0)
	expect a.valueOf("health") == 120.0 and a.baseValueOf("health") == 100.0
	a.damageValue("health", 500.0)
	expect a.valueOf("health") == 0.0 and a.dead

test "the plain dice gives a leveled list's first eligible entry, the fair one rolls":
	plain = esm.Dice()
	expect not plain.below(99) and plain.below(100) and plain.choose(5) == 0
	fair = esm.Dice(rng = Random(7), fair = true)
	rolls = []
	loop 200:
		rolls.push(fair.choose(4))
	expect rolls.all(it >= 0 and it < 4) and rolls.any(it == 3)

test "the season of the game's start is summer, of its new year winter":
	expect sim.seasonOf(0.0) == 1 and sim.seasonOf(140.0) == 3 and sim.seasonOf(260.0) == 0
