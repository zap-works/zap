# An inventory as the game keeps one (InventoryChanges): a stack per base item with its count, and
# within it the instances that carry data of their own (an ExtraDataList each: worn, worn in the
# left hand, a favorite, a charge, a health, the owner a stolen one was taken from). The rest of
# the count is plain, and an instance whose data is all default goes back into it: the game keeps
# instances only when needed. Names after CommonLibSSE-NG's InventoryChanges, InventoryEntryData
# and ExtraDataList.

# the data a group of instances of a stack carries
pub type ItemExtra:
	count i64 = 1
	worn bool = false   # ExtraWorn: equipped, in the right hand for a weapon
	wornLeft bool = false   # ExtraWornLeft: equipped in the left hand
	favorite bool = false   # ExtraHotkey
	charge f32 = -1.0   # ExtraCharge: an enchanted weapon's charge, -1 for none
	health f32 = 1.0   # ExtraHealth: tempered quality, 1 for none
	owner i64 = 0   # ExtraOwnership: stolen from this owner, 0 for none

pub type Stack:
	form i64
	count i64
	extras ItemExtra[] = []

pub type Inventory:
	stacks Stack[] = []

pub fn isEquipped(x ItemExtra) bool:
	x.worn or x.wornLeft

fn isPlain(x ItemExtra):
	not x.isEquipped() and not x.favorite and x.charge < 0.0 and x.health == 1.0 and x.owner == 0

# whether two groups carry the same data (their counts aside)
fn sameData(a ItemExtra, b ItemExtra):
	a.worn == b.worn and a.wornLeft == b.wornLeft and a.favorite == b.favorite and
		a.charge == b.charge and a.health == b.health and a.owner == b.owner

# the stack's count with no data of its own
pub fn plainCount(s Stack) i64:
	s.count - s.extras.map(.count).sum()

fn stackAt(inv Inventory, form i64) i64?:
	for k, s in inv.stacks:
		if s.form == form: return k
	none

pub fn countOf(inv Inventory, form i64) i64:
	k = inv.stackAt(form) ?? return 0
	inv.stacks[k].count

# folds equal groups together, drops the empty and the default ones, and the empty stacks
fn tidy(mut inv Inventory):
	k = inv.stacks.len - 1
	while k >= 0:
		merged ItemExtra[] = []
		for x in inv.stacks[k].extras:
			if x.count <= 0 or x.isPlain(): continue
			found = -1
			for i, m in merged:
				if m.sameData(x): found = i
			if found >= 0:
				merged[found].count += x.count
			else:
				merged.push(x.copy())
		inv.stacks[k].extras = merged
		if inv.stacks[k].count <= 0: inv.stacks.remove(k)
		k -= 1

# adds count plain instances of the item
pub fn addItem(mut inv Inventory, form i64, count i64):
	if count <= 0: return
	match inv.stackAt(form):
		k: inv.stacks[k].count += count
		none: inv.stacks.push(Stack(form, count))

# adds the instances of a group with their data (an equipped flag is not carried over)
pub fn addExtra(mut inv Inventory, form i64, x ItemExtra):
	inv.addItem(form, x.count)
	k = inv.stackAt(form) ?? return
	moved = x.copy()
	moved.worn = false
	moved.wornLeft = false
	inv.stacks[k].extras.push(moved)
	inv.tidy()

# Takes count instances of the item out: plain ones first, then those with data of their own,
# equipped ones last (which unequips them); the groups taken, as many as there were.
pub fn takeOut(mut inv Inventory, form i64, count i64) ItemExtra[]:
	k = inv.stackAt(form) ?? return []
	left = count.min(inv.stacks[k].count)
	out = []
	plain = inv.stacks[k].plainCount().min(left)
	if plain > 0: out.push(ItemExtra(count = plain))
	left -= plain
	for equipped in [false, true]:
		for i in 0..inv.stacks[k].extras.len:
			if left <= 0 or inv.stacks[k].extras[i].isEquipped() != equipped: continue
			n = inv.stacks[k].extras[i].count.min(left)
			taken = inv.stacks[k].extras[i].copy()
			taken.count = n
			taken.worn = false
			taken.wornLeft = false
			out.push(taken)
			inv.stacks[k].extras[i].count -= n
			left -= n
	inv.stacks[k].count -= out.map(.count).sum()
	inv.tidy()
	out

# moves count of the item from one inventory to another with the data of each instance; how many
pub fn moveItems(mut from Inventory, mut to Inventory, form i64, count i64) i64:
	moved = 0
	for x in from.takeOut(form, count):
		to.addExtra(form, x)
		moved += x.count
	moved

# The weight of everything in the inventory, each item's from `items` (an unknown one weighs 0).
# Ammunition weighs nothing outside Survival Mode, whatever its record says (the game's capture
# shows 53 where 23 iron arrows of 0.1 would make 55).
pub fn weightOf(inv Inventory, items {i64: Item}) f32:
	total = 0.0
	for s in inv.stacks:
		item = items.get(s.form) ?? continue
		if item.kind.Ammo == none: total += f32(s.count) * item.weight
	total

# marks or clears an instance of the item as a favorite
pub fn setFavorite(mut inv Inventory, form i64, favorite bool):
	k = inv.stackAt(form) ?? return
	for i in 0..inv.stacks[k].extras.len:
		inv.stacks[k].extras[i].favorite = favorite
	if favorite and inv.stacks[k].extras.isEmpty:
		inv.stacks[k].extras.push(ItemExtra(count = inv.stacks[k].count, favorite = true))
	elif favorite and inv.stacks[k].plainCount() > 0:
		inv.stacks[k].extras.push(ItemExtra(count = inv.stacks[k].plainCount(), favorite = true))
	inv.tidy()

pub fn isFavorite(inv Inventory, form i64) bool:
	k = inv.stackAt(form) ?? return false
	inv.stacks[k].extras.any(.favorite)
