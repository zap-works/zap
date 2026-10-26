# Equipping as the game does it: an armor covers its biped slots and takes off whatever covers any
# of them; a weapon goes to the right hand, or the left when asked and it is one-handed; a
# two-handed weapon (swords and axes of two hands, bows, crossbows) takes both hands; a shield and
# a torch take the left hand, which a two-handed weapon also needs; arrows replace the arrows
# worn. What an equipped instance holds is a mask of the hands and the slots (the slots above the
# hands' bits), so one rule takes off whatever the new item needs.

handRight = 1
handLeft = 2
ammoHolder = 4
slotShift = 8

# Papyrus's GetEquippedItemType: a weapon's animation type as the script sees it, and the others
equippedTypeOfWeapon = [0, 1, 2, 3, 4, 5, 6, 7, 8, 12]
equippedShield = 10
equippedTorch = 11

# what an item needs to be equipped (in the left hand when `left`), 0 for an item not worn
fn needs(item Item, left bool):
	match item.kind:
		Weapon:
			if item.isTwoHanded(): return handRight | handLeft
			handLeft if left else handRight
		Armor(armor): (armor.slots << slotShift) | (handLeft if item.isShield() else 0)
		Light: handLeft if item.isCarried() else 0
		Ammo: ammoHolder
		_: 0

# what an equipped group of the item holds
fn holds(item Item, x ItemExtra):
	if not x.isEquipped(): return 0
	if item.kind is Weapon and not item.isTwoHanded():
		return (handRight if x.worn else 0) | (handLeft if x.wornLeft else 0)
	item.needs(x.wornLeft)

# takes off every equipped group whose hold meets the mask; the forms taken off
fn takeOff(mut inv Inventory, items {i64: Item}, mask i64):
	off i64[] = []
	for mut stack in inv.stacks:
		item = items.get(stack.form) ?? continue
		for i in 0..stack.extras.len:
			if item.holds(stack.extras[i]) & mask == 0: continue
			stack.extras[i].worn = false
			stack.extras[i].wornLeft = false
			if stack.form not in off: off.push(stack.form)
	inv.tidy()
	off

fn freeCount(s Stack):
	s.count - s.extras.filter(.isEquipped()).map(.count).sum()

# marks one free instance of the stack k equipped, in the left hand when `left`
fn putOn(mut inv Inventory, k i64, left bool):
	for i in 0..inv.stacks[k].extras.len:
		if inv.stacks[k].extras[i].isEquipped() or inv.stacks[k].extras[i].count <= 0: continue
		one = inv.stacks[k].extras[i].copy()
		one.count = 1
		one.worn = not left
		one.wornLeft = left
		inv.stacks[k].extras[i].count -= 1
		inv.stacks[k].extras.push(one)
		inv.tidy()
		return
	inv.stacks[k].extras.push(ItemExtra(count = 1, worn = not left, wornLeft = left))

# Equips one of the item the inventory holds, in the left hand when `left` and the item can go
# there; the forms it took off, or why it cannot be equipped.
pub fn equip(mut inv Inventory, items {i64: Item}, form i64, left bool) i64[] ? str:
	item = items.get(form) ?? return "{form:08X} is no item the world knows"
	inLeft = left and item.kind.Weapon != none and not item.isTwoHanded()
	need = needs(item, inLeft)
	if need == 0: return "{item.editorId} is not worn"
	k = inv.stackAt(form) ?? return "{item.editorId} is not in the inventory"
	nothing i64[] = []
	if inv.stacks[k].extras.any(.isEquipped() and item.holds(it) == need): return nothing
	off = inv.takeOff(items, need)
	k = inv.stackAt(form) ?? return off
	if inv.stacks[k].freeCount() == 0:
		inv.unequip(form)   # the one there is moves from the other hand
		if form not in off: off.push(form)
		k = inv.stackAt(form) ?? return off
	inv.putOn(k, inLeft)
	off

# takes off what holds the left hand (or the right one): a weapon, a shield, a torch
pub fn freeHand(mut inv Inventory, items {i64: Item}, left bool):
	inv.takeOff(items, handLeft if left else handRight)

# takes every equipped instance of the item off; whether one was
pub fn unequip(mut inv Inventory, form i64) bool:
	k = inv.stackAt(form) ?? return false
	was = inv.stacks[k].extras.any(.isEquipped())
	for i in 0..inv.stacks[k].extras.len:
		inv.stacks[k].extras[i].worn = false
		inv.stacks[k].extras[i].wornLeft = false
	inv.tidy()
	was

pub fn unequipAll(mut inv Inventory):
	forms = inv.wornForms()
	for form in forms:
		inv.unequip(form)

# whether an instance of the item is equipped
pub fn isWorn(inv Inventory, form i64) bool:
	k = inv.stackAt(form) ?? return false
	inv.stacks[k].extras.any(.isEquipped())

# the forms equipped, in inventory order
pub fn wornForms(inv Inventory) i64[]:
	inv.stacks.filter(.extras.any(.isEquipped())).map(.form)

# the item held in the hand (the right one unless `left`), 0 for none
pub fn heldIn(inv Inventory, items {i64: Item}, left bool) i64:
	want = handLeft if left else handRight
	for s in inv.stacks:
		item = items.get(s.form) ?? continue
		if s.extras.any(item.holds(it) & want != 0): return s.form
	0

# the weapon in the hand, 0 for none (a two-handed one is the right hand's)
pub fn weaponIn(inv Inventory, items {i64: Item}, left bool) i64:
	held = inv.heldIn(items, left)
	item = items.get(held) ?? return 0
	if item.kind.Weapon == none or left and item.isTwoHanded(): return 0
	held

pub fn shieldWorn(inv Inventory, items {i64: Item}) i64:
	held = inv.heldIn(items, true)
	item = items.get(held) ?? return 0
	held if item.isShield() else 0

# Papyrus's GetEquippedItemType for the hand: 0 nothing, 1 to 8 and 12 a weapon by its type, 10 a
# shield, 11 a torch (9, a spell, is not kept here)
pub fn heldType(inv Inventory, items {i64: Item}, left bool) i64:
	item = items.get(inv.heldIn(items, left)) ?? return 0
	if item.isShield(): return equippedShield
	if item.kind is Light: return equippedTorch
	animation = (item.kind.Weapon ?? return 0).animation
	equippedTypeOfWeapon[animation] if animation < equippedTypeOfWeapon.len else 0
