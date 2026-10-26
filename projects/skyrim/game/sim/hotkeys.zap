# The favorites' hotkeys (MagicFavorites' hotkeys: eight slots of the user events Hotkey1 to
# Hotkey8, the keys 1 to 8 of controlmap.txt), each naming a favorite item or spell. In the
# favorites menu a key assigns the selected favorite to its slot (the same key again clears it,
# the favorite leaving any other slot it had); in the game the key wears the item or puts the
# spell in the right hand, and takes it off when it is there.

pub hotkeySlots = 8

# the sound a favorite marked or unmarked, or used by its key, plays (0x14092d0d0, 0x14092e110)
pub favoriteSound = "UIFavorite"

# the slot the favorite is on, -1 for none
pub fn hotkeyOf(w GameWorld, refId i64, form i64) i64:
	m = (w.actors.get(refId) ?? return -1).magic
	m.hotkeys.indexOf(form) ?? -1

# the favorite put on the slot, or taken off it when it is there already; a favorite is made of an
# item or a spell that was not
pub fn setHotkey(mut w GameWorld, refId i64, form i64, slot i64):
	if w.actors.get(refId) == none or slot < 0 or slot >= hotkeySlots: return
	was = w.actors[refId].magic.hotkeys[slot]
	list = w.actors[refId].magic.hotkeys.map(0 if it == form else it)
	if was != form:
		list[slot] = form
		if form in w.spells: w.setFavoriteSpell(refId, form, true)
		elif w.inventories.getMut(refId) is mut inv: inv.setFavorite(form, true)
	w.actors[refId].magic.hotkeys = list

# an item or a spell marked a favorite or not, its hotkey cleared with the mark
pub fn setFavoriteForm(mut w GameWorld, refId i64, form i64, favorite bool):
	if form in w.spells:
		w.setFavoriteSpell(refId, form, favorite)
	else:
		if w.inventories.getMut(refId) is mut inv: inv.setFavorite(form, favorite)
	if favorite or w.actors.get(refId) == none: return
	w.actors[refId].magic.hotkeys = w.actors[refId].magic.hotkeys.map(0 if it == form else it)

# the favorite worn, or put in the right hand when it is a spell; taken off when it is there
# already. why not when it cannot be.
pub fn useFavorite(mut w GameWorld, refId i64, form i64) str?:
	if form in w.spells:
		if w.spellIn(refId, false) == form:
			w.unequipSpell(refId, form)
			return none
		return w.equipSpell(refId, form, false)
	if w.items.get(form) is item and item.kind.Potion != none:
		w.consume(refId, form) ?? return error
		return none
	inv = w.inventories.getMut(refId) ?? return "no inventory"
	if inv.isWorn(form):
		inv.unequip(form)
	else:
		inv.equip(w.items, form, false) ?? return "cannot equip {form:08X}: {error}"
	w.settleHands(refId)
	none

# what the key of a slot does: its favorite used; why not when it cannot be
pub fn useHotkey(mut w GameWorld, refId i64, slot i64) str?:
	if w.actors.get(refId) == none or slot < 0 or slot >= hotkeySlots: return none
	form = w.actors[refId].magic.hotkeys[slot]
	if form == 0: return none
	used = w.useFavorite(refId, form)
	if used == none and refId == w.player: w.playUi(favoriteSound)
	used
