# The data path the game fills its item menus by (inventorymenu.swf and containermenu.swf share
# the Inventory components: InventoryLists, ItemCard, BottomBar). The categories go to
# GameDelegate's SetCategoriesList as (name, filter bits, shown when empty) triples, a filter of 0
# a divider; the items into the entryList of the list GetInventoryItemList() hands out, shown by
# InvalidateListData; the item card's object to UpdateItemCardInfo when the movie asks for it
# (RequestItemCardInfo); the player's values to UpdatePlayerInfo. The members of each object are
# the ones the movies' ActionScript reads (InventoryScrollingList.SetEntryText, ItemCard's itemInfo,
# BottomBar.UpdatePlayerInfo). The names of the categories are the game's settings (sAllItems...).

import engine.swf.avm1
import game.sim

# an item shows under a category when their filter bits meet (ListFilterer.EntryMatchesFilter)
favoritesBit = 1
# the other side's items in the container menu
containerBit = 1 << 10
# the player's categories after Favorites, the game setting naming each; the bit of each is
# 2 << its index
kindSettings = ["sWeapons", "sApparel", "sPotions", "sScrolls", "sFood", "sIngredients", "sBooks",
	"sKeys", "sMisc"]
allKinds = ((2 << kindSettings.len) - 1) & ~favoritesBit
# InventoryScrollingList's equip icons by equipState: none, worn, left hand, right hand, both
equipWorn = 1
equipLeft = 2
equipRight = 3
equipBoth = 4
listPath = "Menu_mc.InventoryLists_mc.ItemsList"

pub type Category:
	text str
	flag i64
	shownEmpty bool

# the game setting naming the category the item is listed under
fn kindSetting(item sim.Item):
	match item.kind:
		"WEAP", "AMMO": "sWeapons"
		"ARMO": "sApparel"
		"ALCH": "sFood" if item.isFood() else "sPotions"
		"SCRL": "sScrolls"
		"INGR": "sIngredients"
		"BOOK": "sBooks"
		"KEYM": "sKeys"
		_: "sMisc"

fn kindBit(item sim.Item):
	2 << (kindSettings.indexOf(item.kindSetting()) ?? kindSettings.len - 1)

# the item card's kind (InventoryDefines' ICT_ names)
fn cardKind(item sim.Item):
	match item.kind:
		"WEAP", "AMMO": "ICT_WEAPON"
		"ARMO": "ICT_ARMOR"
		"ALCH": "ICT_FOOD" if item.isFood() else "ICT_POTION"
		"INGR": "ICT_INGREDIENT"
		"BOOK": "ICT_BOOK"
		"KEYM": "ICT_KEY"
		"SLGM": "ICT_SOUL_GEMS"
		_: "ICT_MISC"

# the player's categories: Favorites, All, then one per kind
pub fn playerCategories(t GameTexts, all str) Category[]:
	out = [
		Category(text = t.setting("sFavorites"), flag = favoritesBit, shownEmpty = false),
		Category(text = all.copy(), flag = allKinds, shownEmpty = true)
	]
	for k, key in kindSettings:
		out.push(Category(text = t.setting(key), flag = 2 << k, shownEmpty = false))
	out

# the container's side of the container menu: its name over a divider, then the player's
pub fn containerCategories(t GameTexts, name str, player str) Category[]:
	out = [
		Category(text = name.copy(), flag = containerBit, shownEmpty = true),
		Category(text = "", flag = 0, shownEmpty = true)
	]
	theirs = t.playerCategories(player)
	out.extend(theirs[1..].copy())
	out

# the categories given to the movie
pub fn showCategories(mut p avm1.Player, categories Category[]):
	args avm1.Value[] = []
	for c in categories:
		args.push(.Str(c.text.copy()))
		args.push(.Num(f64(c.flag)))
		args.push(.Bool(c.shownEmpty))
	p.delegate("SetCategoriesList", args)

# the entries given to the movie's item list and the categories shown again for them; the movie's
# requests for a card answered from the selected row
pub fn showItems(mut p avm1.Player, move entries avm1.Value[]):
	p.m.answers["RequestItemCardInfo"] = avm1.Answer(callback = "UpdateItemCardInfo",
		path = "{listPath}.selectedEntry.card")
	list = p.invoke("GetInventoryItemList", [])
	p.refill(p.member(list, "entryList"), entries)
	p.delegate("InvalidateListData", [])

# a stack's equip icon
fn equipStateOf(s sim.Stack, item sim.Item):
	right = s.extras.any(.worn)
	left = s.extras.any(.wornLeft)
	if item.kind != "WEAP" and item.kind != "LIGH": return equipWorn if right or left else 0
	if right and left or right and item.isTwoHanded(): return equipBoth
	if right: return equipRight
	equipLeft if left else 0

# One row of an item list: the stack of the item, under the category bits `flag`, red when taking
# it is stealing, marked when it is the best of its class, greyed when not `enabled`, with the card the game shows for it
# when the movie asks (RequestItemCardInfo, answered at once from the selected row's `card`).
pub fn entryOf(
	mut p avm1.Player,
	item sim.Item,
	s sim.Stack,
	flag i64,
	stealing bool,
	best bool,
	enabled bool,
	card avm1.Value
) avm1.Value:
	favorite = s.extras.any(.favorite)
	p.newRecord([
		("card", card.copy()),
		("text", .Str(item.name.copy())),
		("count", .Num(f64(s.count))),
		("equipState", .Num(f64(s.equipStateOf(item)))),
		("favorite", .Bool(favorite)),
		("filterFlag", .Num(f64(flag | (favoritesBit if favorite else 0)))),
		("enabled", .Bool(enabled)),
		("bestInClass", .Bool(best)),
		("isStealing", .Bool(stealing)),
		("isStolen", .Bool(s.extras.any(.owner != 0))),
		("value", .Num(f64(item.value))),
		("weight", .Num(f64(item.weight))),
		("formId", .Num(f64(item.formId)))
	])

# the rows of an inventory's stacks in the game's order (by name), gold left out (it is the
# bottom bar's), under the filter bits `side` (0: each item's category), greyed what the `buyer`
# (a merchant the player is selling to) would not take
pub fn entriesOf(
	mut p avm1.Player,
	mut t GameTexts,
	w sim.GameWorld,
	inv sim.Inventory,
	side i64,
	stealing bool,
	buyer sim.Vendor?,
	chances {i64: i64}
) avm1.Value[]:
	best = w.bestInClass(inv)
	stacks = inv.stacks.filter(.form != sim.goldForm and w.items.get(.form) != none)
	out = []
	for s in stacks.sortedBy(w.items[.form].name.lower()):
		item = w.items[s.form]
		flag = side if side != 0 else item.kindBit()
		card = p.cardOf(t, w, item, s.count, s.extras.any(.owner != 0), chances.get(s.form) ?? -1)
		stolen = s.plainCount() <= 0 and s.extras.any(.owner != 0)
		wanted = true
		if buyer is v: wanted = w.buys(v, item, stolen) == none
		out.push(p.entryOf(item, s, flag, stealing, s.form in best, wanted, card))
	out

# what the item card shows of an item, `count` of them
pub fn cardOf(
	mut p avm1.Player,
	mut t GameTexts,
	w sim.GameWorld,
	item sim.Item,
	count i64,
	stolen bool,
	chance i64
) avm1.Value:
	kind = p.read("_global.InventoryDefines.{item.cardKind()}")
	a = w.actors[w.player]
	p.newRecord([
		("pickpocketChance", .Num(f64(chance)) if chance >= 0 else .Undefined),
		("type", kind),
		("name", .Str(item.name.copy())),
		("count", .Num(f64(count))),
		("value", .Num(f64(item.value))),
		("weight", .Num(f64(item.weight))),
		("armor", .Num(f64(sim.shownRound(a.armorShown(item))))),
		("damage", .Num(f64(sim.shownRound(a.damageShown(item))))),
		("effects", .Str(t.effectsText(item))),
		("skillText", .Str(t.armorSkillText(item))),
		("stolen", .Bool(stolen))
	])

# the skill of an armor the card names over it ("Heavy Armor"), "" for clothing and the rest
fn armorSkillText(mut t GameTexts, item sim.Item) str:
	armor = item.armor ?? return ""
	if armor.armorType >= sim.armorSkills.len: return ""
	t.skillName(sim.armorSkills[armor.armorType])

# the player's values as the bottom bar shows them
pub fn playerInfoOf(mut p avm1.Player, w sim.GameWorld) avm1.Value:
	a = w.actors[w.player]
	inv = w.inventories.get(w.player) ?? sim.Inventory()
	p.newRecord([
		("encumbrance", .Num(f64(inv.weightOf(w.items)))),
		("maxEncumbrance", .Num(f64(a.valueOf("carryweight")))),
		("gold", .Num(f64(inv.countOf(sim.goldForm)))),
		("health", .Num(f64(a.valueOf("health")))),
		("maxHealth", .Num(f64(a.baseValueOf("health")))),
		("magicka", .Num(f64(a.valueOf("magicka")))),
		("maxMagicka", .Num(f64(a.baseValueOf("magicka")))),
		("stamina", .Num(f64(a.valueOf("stamina")))),
		("maxStamina", .Num(f64(a.baseValueOf("stamina")))),
		("armor", .Num(f64(w.armorRatingOf(w.player)))),
		("damage", .Num(f64(w.damageOf(w.player))))
	])
