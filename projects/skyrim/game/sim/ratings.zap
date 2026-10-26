# The armor and damage the menus show for the player's items, after UESP's Skyrim:Armor and
# Skyrim:Damage: an armor's rating times 1 + 0.4 x its skill / 100 (light or heavy armor; clothing
# keeps its own), a weapon's damage times 1 + its skill / 200, each piece rounded half up on its own
# and the worn ones summed (the game's capture: iron armor, boots, gauntlets and helmet of 25, 10,
# 10 and 15 show 27, 11, 11 and 16 at heavy armor 15, 65 in all), and the best of each class marked.
# Perks, smithing and enchantments are left out: the inn's player has none.

# the skill of each armor type (ARMO BOD2's), clothing after them having none
pub armorSkills = ["lightarmor", "heavyarmor"]

# a value rounded the way the menus round it, half up
pub fn shownRound(x f32) f32:
	(x + 0.5).floor()

# the rating the item card shows for the actor's armor piece
pub fn armorShown(a ActorState, item Item) f32:
	armor = item.kind.Armor ?? return 0.0
	if armor.armorType >= armorSkills.len: return armor.rating
	armor.rating * (1.0 + 0.4 * a.valueOf(armorSkills[armor.armorType]) / 100.0)

# the damage the item card shows for the actor's weapon (an arrow's own damage)
pub fn damageShown(a ActorState, item Item) f32:
	if item.kind.Ammo is damage: return damage
	weapon = item.kind.Weapon ?? return 0.0
	skill = weapon.skill - firstSkill
	level = a.valueOf(skillNames[skill]) if skill >= 0 and skill < skillNames.len else 0.0
	f32(weapon.damage) * (1.0 + level / 200.0)

# the armor rating the actor's worn pieces add up to
pub fn armorRatingOf(w GameWorld, actorRef i64) f32:
	a = w.actors.get(actorRef) ?? return 0.0
	inv = w.inventories.get(actorRef) ?? return 0.0
	total = 0.0
	for form in inv.wornForms():
		item = w.items.get(form) ?? continue
		if item.kind is Armor: total += shownRound(a.armorShown(item))
	total

# the damage of the weapon in the actor's right hand, 0 with none
pub fn damageOf(w GameWorld, actorRef i64) f32:
	a = w.actors.get(actorRef) ?? return 0.0
	inv = w.inventories.get(actorRef) ?? return 0.0
	item = w.items.get(inv.weaponIn(w.items, false)) ?? return 0.0
	shownRound(a.damageShown(item))

# the class an item is the best of, with its score: armor by the slots it covers (clothing, of no
# rating, is in none), weapons by how they are held, arrows on their own
fn classOf(item Item) (str, f32)?:
	match item.kind:
		Armor(armor):
			if armor.rating <= 0.0: return none
			("armor {armor.slots}", armor.rating)
		Weapon(weapon):
			held = weaponTypes[weapon.animation] if weapon.animation < weaponTypes.len else ""
			kind = held if held in ["Bow", "Crossbow", "Staff"]
				else ("two" if item.isTwoHanded() else "one")
			(kind, f32(weapon.damage))
		Ammo(damage): ("ammo", damage)
		_: none

# the items of the inventory the item lists mark as the best of their class (SE's bestInClass)
pub fn bestInClass(w GameWorld, inv Inventory) i64[]:
	top {str: f32} = {}
	best {str: i64} = {}
	for s in inv.stacks:
		item = w.items.get(s.form) ?? continue
		key, score = item.classOf() ?? continue
		if (top.get(key) ?? -1.0) >= score: continue
		top[key.copy()] = score
		best[key.copy()] = s.form
	best.values()
