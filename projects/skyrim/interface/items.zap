# The inventory and container menus run over the game's model (game/sim) as the game runs them:
# opened and filled (itemMenu.zap), told the keys of the frame, and what the movie asks of the game
# answered: equipping, dropping, taking from the container (a theft when the container's owner is
# not the player), closing; the selected item's card is answered at once (itemMenu.zap).

import engine
import engine.swf.avm1
import game.sim
import game.stealth
import skyrim

# the notice of an item put into the actor being pickpocketed (the game's string, 0x1418ac980)
placeText = "You cannot place items in a container while pickpocketing."

# an item menu open over the game
pub type ItemMenu:
	p avm1.Player
	container i64 = 0   # the container menu's container, 0 for the inventory
	pickpocket bool = false   # the container menu in its pickpocket mode: the container is an actor
	merchant i64 = 0   # the barter menu's merchant, 0 for the other menus
	open bool = true
	magic bool = false   # the magic menu, its items spells
	favorites bool = false   # the favorites menu
	asked str[] = []   # the sounds the movie asked for as it opened, queued with its first answers

# the player's inventory menu (inventorymenu.swf), filled from the world
pub fn openInventory(
	install skyrim.Install,
	mut t GameTexts,
	w sim.GameWorld,
	width i64,
	height i64
) ItemMenu ? str:
	p = try install.openPlayer("interface/inventorymenu.swf", width, height)
	menu = ItemMenu(p)
	menu.start(t, w)
	menu

# the container menu (containermenu.swf) of the reference `container`, filled from the world, its
# items shown at once as the game opens it
pub fn openContainer(
	install skyrim.Install,
	mut t GameTexts,
	w sim.GameWorld,
	container i64,
	width i64,
	height i64
) ItemMenu ? str:
	p = try install.openPlayer("interface/containermenu.swf", width, height)
	menu = ItemMenu(p, container)
	menu.start(t, w)
	menu.p.invoke("Menu_mc.ShowItemsList", [])
	menu

# the container menu in its pickpocket mode (ContainerMenu mode 2, 0x1409120d0): the actor `victim`'s
# loose items, each card with the chance of taking it; taking rolls against the chance
pub fn openPickpocket(
	install skyrim.Install,
	mut t GameTexts,
	w sim.GameWorld,
	victim i64,
	width i64,
	height i64
) ItemMenu ? str:
	p = try install.openPlayer("interface/containermenu.swf", width, height)
	menu = ItemMenu(p, victim, pickpocket = true)
	menu.start(t, w)
	menu.p.write("Menu_mc.bNPCMode", .Bool(true))
	menu.p.invoke("Menu_mc.ShowItemsList", [])
	menu

# the barter menu (bartermenu.swf) with the merchant `merchant`: his stock under his name, the
# player's items after the divider, the prices the movie makes of the multipliers it is given
pub fn openBarter(
	install skyrim.Install,
	mut t GameTexts,
	w sim.GameWorld,
	merchant i64,
	width i64,
	height i64
) ItemMenu ? str:
	p = try install.openPlayer("interface/bartermenu.swf", width, height)
	menu = ItemMenu(p, merchant)
	menu.start(t, w)
	menu.p.invoke("Menu_mc.InventoryLists_mc.ShowItemsList", [])
	menu

fn start(mut menu ItemMenu, mut t GameTexts, w sim.GameWorld):
	menu.p.invokeText("InitExtensions()")
	menu.p.invokeText("SetPlatform(0, false)")
	menu.refresh(t, w)
	menu.asked = soundsOfCalls(menu.p.takeExternal())

# whether taking from the menu's container is stealing
fn stealing(menu ItemMenu, w sim.GameWorld):
	f = w.forms.get(menu.container) ?? return false
	not w.canTake(w.player, w.ownerOf(f))

# what the container side lists: the container's items, an actor pickpocketed only its loose ones
fn heldBy(menu ItemMenu, w sim.GameWorld):
	if menu.pickpocket: return sim.Inventory(stacks = w.takableFrom(menu.container))
	(w.inventories.get(menu.container) ?? sim.Inventory()).copy()

# the lists and the bottom bar filled again from the world
pub fn refresh(mut menu ItemMenu, mut t GameTexts, w sim.GameWorld):
	if menu.magic:
		menu.refreshMagic(t, w)
		return
	if menu.favorites:
		menu.refreshFavorites(w)
		return
	player = t.nameOf(w.forms[w.player].base)
	inv = w.inventories.get(w.player) ?? sim.Inventory()
	entries = []
	vendor = w.vendorAt(menu.merchant)
	if vendor is v:
		menu.refreshBarter(t, w, v)
		return
	if menu.container == 0:
		menu.p.showCategories(t.playerCategories(t.setting("sAllItems")))
	else:
		name = t.nameOf(w.forms[menu.container].base)
		menu.p.showCategories(t.containerCategories(name, player))
		held = menu.heldBy(w)
		chances {i64: i64} = {}
		if menu.pickpocket:
			for s in held.stacks:
				chances[s.form] = w.shownChance(menu.container, s)
		entries = menu.p.entriesOf(t, w, held, containerBit,
			menu.stealing(w) and not menu.pickpocket, none, chances)
	entries.extend(menu.p.entriesOf(t, w, inv, 0, false, none, {}))
	menu.p.showItems(entries)
	menu.p.delegate("UpdatePlayerInfo", [menu.p.playerInfoOf(w)])

# the barter menu's lists, multipliers and gold: the merchant's stock under his name, the player's
# items greyed where he would not buy them
fn refreshBarter(mut menu ItemMenu, mut t GameTexts, w sim.GameWorld, v sim.Vendor):
	name = t.nameOf(w.forms[menu.merchant].base)
	menu.p.delegate(
		"SetBarterMultipliers",
		[.Num(w.buyMultiplier(menu.merchant)), .Num(w.sellMultiplier(menu.merchant))]
	)
	menu.p.showCategories(t.containerCategories(name, t.nameOf(w.forms[w.player].base)))
	stock = w.inventories.get(v.chest) ?? sim.Inventory()
	entries = menu.p.entriesOf(t, w, stock, containerBit, false, none, {})
	mine = w.inventories.get(w.player) ?? sim.Inventory()
	entries.extend(menu.p.entriesOf(t, w, mine, 0, false, v.copy(), {}))
	menu.p.showItems(entries)
	menu.p.delegate("UpdatePlayerInfo", [.Num(f64(mine.countOf(sim.goldForm))),
		.Num(f64(w.vendorGold(v))), .Str(name.copy()), menu.p.playerInfoOf(w)])

# the item of the selected row and whether it is the container's, none when no row is selected
fn selected(mut menu ItemMenu) (i64, bool)?:
	entry = menu.p.read("{listPath}.selectedEntry")
	if not entry.isObject(): return none
	form = try menu.p.numberAt("{listPath}.selectedEntry.formId")
	flag = menu.p.numberAt("{listPath}.selectedEntry.filterFlag") ?? 0
	(form, (flag & containerBit) != 0)

# the number at a path of the movie, none when it holds no number
fn numberAt(mut p avm1.Player, path str) i64?:
	match p.read(path):
		Num(x): i64(x)
		_: none

# the inventory the row's item is in
fn holderOf(menu ItemMenu, w sim.GameWorld, theirs bool):
	menu.container if theirs else w.player

# the card of the selected item given to the movie again
fn showCard(mut menu ItemMenu):
	card = menu.p.read("{listPath}.selectedEntry.card")
	if not card.isNullish(): menu.p.delegate("UpdateItemCardInfo", [card])

# the selected item used: worn or taken off, eaten or drunk (one of it gone)
fn useSelected(mut menu ItemMenu, mut w sim.GameWorld):
	form, theirs = menu.selected() ?? return
	if theirs: return
	item = w.items.get(form) ?? return
	inv = w.inventories.getMut(w.player) ?? return
	if item.kind == "ALCH":
		w.consume(w.player, form) ?? w.record("cannot use {item.editorId}: {error}")
	elif item.kind == "INGR":
		inv.takeOut(form, 1)
	elif not inv.unequip(form):
		inv.equip(w.items, form, false) ?? w.record("cannot equip {item.editorId}: {error}")
		w.settleHands(w.player)

# `count` of the selected item dropped
fn dropSelected(mut menu ItemMenu, mut w sim.GameWorld, count i64):
	form, theirs = menu.selected() ?? return
	if theirs: return
	inv = w.inventories.getMut(w.player) ?? return
	inv.takeOut(form, count)

# `count` of the selected item taken from the actor the player pickpockets: the roll against the
# chance, the menu closing on a failure (ContainerMenu 0x1409120d0); nothing can be put in
fn pickpocketSelected(mut menu ItemMenu, mut w sim.GameWorld, form i64, theirs bool, count i64):
	if not theirs:
		w.notifications.push(placeText.copy())
		return
	match w.attempt(menu.container, form, count):
		Caught: menu.open = false
		Refused(why): w.record("pickpocket refused: {why}")
		_: pass

# `count` of the selected item moved to the other side; taking from an owner's container is a theft
fn transfer(mut menu ItemMenu, mut w sim.GameWorld, count i64):
	form, theirs = menu.selected() ?? return
	if menu.pickpocket:
		menu.pickpocketSelected(w, form, theirs, count)
		return
	from = menu.holderOf(w, theirs)
	to = w.player if theirs else menu.container
	w.ensureInventory(to)
	source = w.inventories[from].copy()
	target = w.inventories[to].copy()
	moved = source.moveItems(target, form, count)
	w.inventories[from] = source
	w.inventories[to] = target
	if theirs and moved > 0 and menu.stealing(w):
		owner = w.ownerOf(w.forms[menu.container])
		w.recordTheft(w.player, menu.container, form, moved, owner)

# `count` of the selected item bought from the merchant or sold to him, as its side says; why not
# when the trade is refused
fn trade(mut menu ItemMenu, mut w sim.GameWorld, count i64):
	form, theirs = menu.selected() ?? return
	refused = w.buyFrom(menu.merchant, form, count) if theirs
		else w.sellTo(menu.merchant, form, count)
	if refused is why: w.record("barter refused: {why}")

# the selected row marked a favorite or not, the lists filled again
pub fn favoriteSelected(mut menu ItemMenu, mut t GameTexts, mut w sim.GameWorld):
	if menu.magic:
		menu.toggleFavoriteSpell(w)
	elif menu.favorites:
		return
	else:
		form, theirs = menu.selected() ?? return
		if theirs: return
		inv = w.inventories.get(w.player) ?? return
		w.setFavoriteForm(w.player, form, not inv.isFavorite(form))
	w.playUi(sim.favoriteSound)
	menu.refresh(t, w)
	menu.showCard()

# the number the answer's argument k gives, 0 for none
pub fn numberArg(c avm1.ExternalCall, k i64) i64:
	if k >= c.args.len: return 0
	match c.args[k]:
		Num(x): i64(x)
		_: 0

# the number an answer's first argument gives, else `otherwise`
fn amountOf(c avm1.ExternalCall, otherwise i64):
	match c.args.first ?? .Undefined:
		Num(x): i64(x)
		_: otherwise

# What the movie asked of the game since the last frame done; the lists filled again when the
# world changed.
pub fn answer(mut menu ItemMenu, mut t GameTexts, mut w sim.GameWorld):
	changed = false
	for name in menu.asked:
		w.playUi(name)
	menu.asked.clear()
	for c in menu.p.takeExternal():
		w.playCallSound(c)
		match c.name:
			"ItemSelect":
				if menu.magic:
					menu.equipSelectedSpell(w, c.numberArg(1))
				elif menu.favorites:
					menu.equipFavorite(w)
					menu.open = false
				elif menu.merchant != 0:
					menu.trade(w, c.amountOf(1))
				else:
					menu.useSelected(w)
				changed = true
			"ItemDrop":
				menu.dropSelected(w, c.amountOf(1))
				changed = true
			"ItemTransfer":
				menu.transfer(w, c.amountOf(1))
				changed = true
			"CloseTweenMenu", "CloseMenu", "FadeDone": menu.open = false
			_: pass
	if changed:
		menu.refresh(t, w)
		menu.showCard()

# The game's keys in a menu as the movie gets them: the Flash key code the game sends for each
# (the menu mode's Up, Down, Left, Right, Accept and Cancel of controlmap.txt; R and F are the
# Item Menus' XButton and YButton, sent as InputDelegate's gamepad codes 98 and 99).
pub fn menuKeyCode(k engine.Key) i64?:
	match k:
		Up: 38
		Down: 40
		Left: 37
		Right: 39
		Enter: 13
		Tab, Escape: 9
		Char(c):
			match c:
				'W', 'w': 38
				'S', 's': 40
				'A', 'a': 37
				'D', 'd': 39
				'E', 'e': 13
				'R', 'r': 98
				'F', 'f': 99
				_: none
		_: none

# a key pressed in the menu (down and up)
pub fn press(mut p avm1.Player, k engine.Key):
	code = k.menuKeyCode() ?? return
	p.key(code, true)
	p.key(code, false)
