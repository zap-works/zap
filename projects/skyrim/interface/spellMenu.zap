# The magic menu (magicmenu.swf) and the favorites menu (favoritesmenu.swf) fed from the game's
# model as the item menus are (itemMenu.zap): the magic menu is the inventory's ItemMenu with the
# spells for its items, the categories the schools (the game settings sAlteration...) then the
# powers, a row's filter bits its school's and its equip icon the hand it is in; the item card of
# a spell (ICT_SPELL; a power's is ICT_SPELL_DEFAULT) says its effects, its cost in magicka (a
# second's, when it is held: the card puts "per sec" when its castTime is 0), and the level of skill
# it asks. The favorites menu is a list the game fills by hand
# (FavoritesMenu's ItemList entries: text and equipState) of the favorite items and spells, the
# selected one worn or put in the right hand when it is chosen.

import engine.swf.avm1
import game.sim
import skyrim

# the schools of magic in the menu's order, the game setting naming each and its actor value
schoolSettings = ["sAlteration", "sConjuration", "sDestruction", "sIllusion", "sRestoration"]
schools = ["alteration", "conjuration", "destruction", "illusion", "restoration"]
powersSetting = "sPowers"
shoutsSetting = "sShouts"
# the magic menu's own texts, which no setting names
allMagic = "All Magic"
activeEffects = "Active Effects"
# the game settings naming the levels of skill a spell asks, from 0 by 25s
levelSettings = ["sNoviceDisplayName", "sApprenticeDisplayName", "sAdeptDisplayName",
	"sExpertDisplayName", "sMasterDisplayName"]
levelWords = ["Novice", "Apprentice", "Adept", "Expert", "Master"]

# the filter bits of the categories after the schools: the powers, the shouts and the active effects
powersBit = 2 << schools.len
shoutsBit = 4 << schools.len
activeBit = 8 << schools.len

# the magic menu's categories: the favorites, all of it, the active effects, a school each, the
# shouts, the powers; the active effects and the shouts are listed empty
pub fn magicCategories(t GameTexts) Category[]:
	out = [
		Category(text = t.setting("sFavorites"), flag = favoritesBit, shownEmpty = false),
		Category(text = allMagic.copy(), flag = powersBit * 2 - 2, shownEmpty = true),
		Category(text = activeEffects.copy(), flag = activeBit, shownEmpty = true)
	]
	for k, key in schoolSettings:
		out.push(Category(text = t.setting(key), flag = 2 << k, shownEmpty = false))
	out.push(Category(text = t.setting(shoutsSetting), flag = shoutsBit, shownEmpty = true))
	out.push(Category(text = t.setting(powersSetting), flag = powersBit, shownEmpty = false))
	out

# the filter bit of the category a spell is listed under: its school's, the powers' for a power
fn spellBit(s sim.Spell):
	if s.kind != sim.spellKindSpell: return powersBit
	2 << (schools.indexOf(s.school) ?? 0)

# the equip icon of the spell: the hand or hands that hold it
fn handIcon(m sim.Magic, form i64):
	left = m.left == form
	right = m.right == form
	if left and right: return equipBoth
	if left: return equipLeft
	equipRight if right else 0

# the skill level's name
fn levelName(t GameTexts, level i64):
	k = (level / 25).min(levelWords.len - 1)
	name = t.setting(levelSettings[k])
	levelWords[k].copy() if name.isEmpty else name

# what the item card shows of a spell
fn spellCardOf(mut p avm1.Player, mut t GameTexts, w sim.GameWorld, s sim.Spell) avm1.Value:
	cardKind = "ICT_SPELL" if s.kind == sim.spellKindSpell else "ICT_SPELL_DEFAULT"
	kind = p.read("_global.InventoryDefines.{cardKind}")
	held = s.castType == .Concentration
	p.newRecord([
		("type", kind),
		("name", .Str(s.name.copy())),
		("effects", .Str(s.effects.map(t.effectText(it)).filter(not .isEmpty).join(" "))),
		("spellCost", .Num(f64(w.spellCost(w.player, s)))),
		("castTime", .Num(0.0 if held else 1.0)),
		("castLevel", .Str(t.levelName(s.level))),
		("magicSchoolName", .Str(t.skillName(s.school))),
		("magicSchoolLevel", .Num(f64(w.actors[w.player].valueOf(s.school)))),
		("magicSchoolPct", .Num(0.0))
	])

# One row of the magic list for the spell the actor knows
fn spellEntryOf(
	mut p avm1.Player,
	mut t GameTexts,
	w sim.GameWorld,
	s sim.Spell,
	m sim.Magic
) avm1.Value:
	favorite = s.formId in m.favorites
	p.newRecord([
		("card", p.spellCardOf(t, w, s)),
		("text", .Str(s.name.copy())),
		("equipState", .Num(f64(m.handIcon(s.formId)))),
		("favorite", .Bool(favorite)),
		("filterFlag", .Num(f64(s.spellBit() | (favoritesBit if favorite else 0)))),
		("enabled", .Bool(true)),
		("formId", .Num(f64(s.formId)))
	])

# One row of the active effects: the magic effect's name over the card of what it does
fn activeEntryOf(
	mut p avm1.Player,
	mut t GameTexts,
	w sim.GameWorld,
	a sim.ActiveEffect
) avm1.Value:
	name = (w.magicEffects.get(a.effect.effect) ?? return .Undefined).name
	card = p.newRecord([
		("type", p.read("_global.InventoryDefines.ICT_ACTIVE_EFFECT")),
		("name", .Str(name.copy())),
		("effects", .Str(t.effectText(a.effect))),
		("timeRemaining", .Num(a.remaining))
	])
	p.newRecord([
		("card", card),
		("text", .Str(name.copy())),
		("equipState", .Num(0.0)),
		("favorite", .Bool(false)),
		("filterFlag", .Num(f64(activeBit))),
		("enabled", .Bool(true)),
		("formId", .Num(f64(a.effect.effect)))
	])

# the rows of the spells the player casts, by name, then the effects it lives under
fn spellEntries(mut p avm1.Player, mut t GameTexts, w sim.GameWorld):
	m = w.actors[w.player].magic.copy()
	out = []
	for form in w.castableSpells(w.player).sortedBy(w.spells[it].name.lower()):
		out.push(p.spellEntryOf(t, w, w.spells[form], m))
	for a in w.activeEffects(w.player):
		out.push(p.activeEntryOf(t, w, a))
	out

# the magic menu opened over the world as the game opens it
pub fn openMagic(
	install skyrim.Install,
	mut t GameTexts,
	w sim.GameWorld,
	width i64,
	height i64
) ItemMenu ? str:
	p = try install.openPlayer("interface/magicmenu.swf", width, height)
	menu = ItemMenu(p, magic = true)
	menu.start(t, w)
	menu

# the magic menu's lists filled again from the world
fn refreshMagic(mut menu ItemMenu, mut t GameTexts, w sim.GameWorld):
	menu.p.showCategories(t.magicCategories())
	menu.p.showItems(menu.p.spellEntries(t, w))
	menu.p.delegate("UpdatePlayerInfo", [menu.p.playerInfoOf(w)])

# the spell of the selected row, 0 for none
fn selectedSpell(mut menu ItemMenu):
	form, _ = menu.selected() ?? return 0
	form

# the selected spell put in the hand the slot says (1 the right, 2 the left, the right by default),
# or taken out when it is in that hand already
fn equipSelectedSpell(mut menu ItemMenu, mut w sim.GameWorld, slot i64):
	form = menu.selectedSpell()
	if not w.isCastable(w.player, form): return
	left = slot == 2
	if w.spellIn(w.player, left) == form:
		w.unequipSpell(w.player, form)
		return
	if w.equipSpell(w.player, form, left) is why: w.record(why)

# the selected spell put in the left hand, as a click of the right button does (the movie takes a
# click for the left hand only over its list, which the pointer is not), the lists filled again
pub fn equipSelectedLeft(mut menu ItemMenu, mut t GameTexts, mut w sim.GameWorld):
	menu.equipSelectedSpell(w, 2)
	menu.refresh(t, w)
	menu.showCard()

# the selected spell marked a favorite or not
fn toggleFavoriteSpell(mut menu ItemMenu, mut w sim.GameWorld):
	form = menu.selectedSpell()
	if not w.isCastable(w.player, form): return
	w.setFavoriteForm(w.player, form, not (form in w.actors[w.player].magic.favorites))

# the favorites list's instance in the movie
favoritesList = "MenuHolder.Menu_mc.List_mc"

# a favorite as the list shows it
type FavoriteRow:
	text str
	equip i64
	form i64
	spell bool
	hotkey i64

# One row of the favorites list: its name and what holds it
fn favoriteEntryOf(mut p avm1.Player, row FavoriteRow) avm1.Value:
	p.newRecord([
		("text", .Str(row.text.copy())),
		("equipState", .Num(f64(row.equip))),
		("hotkey", .Num(f64(row.hotkey))),
		("formId", .Num(f64(row.form))),
		("isSpell", .Bool(row.spell))
	])

# the favorites menu opened over the world, its list the favorite items and spells by name
pub fn openFavorites(
	install skyrim.Install,
	mut t GameTexts,
	w sim.GameWorld,
	width i64,
	height i64
) ItemMenu ? str:
	p = try install.openPlayer("interface/favoritesmenu.swf", width, height)
	menu = ItemMenu(p, favorites = true)
	menu.p.invokeText("InitExtensions()")
	menu.p.invokeText("SetPlatform(0, false)")
	menu.refresh(t, w)
	menu.asked = soundsOfCalls(menu.p.takeExternal())
	menu

# the favorites menu's list filled again from the world, the first row selected
fn refreshFavorites(mut menu ItemMenu, w sim.GameWorld):
	inv = w.inventories.get(w.player) ?? sim.Inventory()
	m = w.actors[w.player].magic.copy()
	rows = []
	for s in inv.stacks:
		item = w.items.get(s.form) ?? continue
		if not s.extras.any(.favorite): continue
		rows.push(FavoriteRow(text = item.name.copy(), equip = 1 if inv.isWorn(s.form) else 0,
			form = s.form, spell = false, hotkey = w.hotkeyOf(w.player, s.form)))
	for form in m.favorites:
		s = w.spells.get(form) ?? continue
		rows.push(FavoriteRow(text = s.name.copy(), equip = m.handIcon(form), form, spell = true,
			hotkey = w.hotkeyOf(w.player, form)))
	entries = []
	for row in rows.sortedBy(.text.lower()):
		entries.push(menu.p.favoriteEntryOf(row))
	list = menu.p.read(favoritesList)
	menu.p.refill(menu.p.member(list, "entryList"), entries)
	menu.p.invoke("{favoritesList}.InvalidateData", [])
	menu.p.delegate("setSelectedItem", [.Num(0.0)])

# the favorite chosen worn, or put in the right hand when it is a spell, taken off when it is there
fn equipFavorite(mut menu ItemMenu, mut w sim.GameWorld):
	form = menu.p.numberAt("{favoritesList}.selectedEntry.formId") ?? return
	if w.useFavorite(w.player, form) is why: w.record(why)

# the selected favorite put on the hotkey of the slot, or off it when it is there, the list filled
# again
pub fn assignHotkey(mut menu ItemMenu, mut t GameTexts, mut w sim.GameWorld, slot i64):
	form = menu.p.numberAt("{favoritesList}.selectedEntry.formId") ?? return
	w.setHotkey(w.player, form, slot)
	menu.refresh(t, w)
