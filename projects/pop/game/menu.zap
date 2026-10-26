# The pause menu (SDLPoP's menu.c): Esc or Backspace (or the left button) opens it over the paused
# game, which waits; a tick of the game is a turn of draw_menu's loop. The menu is drawn on a
# translucent layer over the picture the game had (menuDraw.zap). It is the top menu (resume,
# quicksave, quickload, restart the level, settings, restart the game, quit) and the settings, the
# ones the options have (menuTable.zap, menuSettings.zap). The keys and the mouse drive it.

import image

pub type Menu:
	shown bool = false
	drawn i64 = 0   # 0 the pause menu, 1 the settings
	hovering i64 = 0   # the item highlighted
	area i64 = 0   # 0 the list of kinds of settings, 1 the settings of the kind
	activeSub i64 = 0   # the kind of settings opened, 0 for none
	highlightedSub i64 = 0
	setting i64 = 0   # the setting highlighted, in the kind's list
	scroll i64 = 0
	dialog i64 = 0   # a question asked: dialogRestore, dialogQuit, dialogLevel, dialogKey
	dialogDrawn bool = false
	button i64 = 1
	oldButton i64 = -1
	level i64 = 1   # the level being customized
	oldLevel i64 = -1
	keyOption str = ""   # the key setting being redefined
	redraw i64 = 0
	needClose bool = false
	changed bool = false   # a setting was changed: they are saved when the menu closes
	pendingKey str = ""   # a key the menu presses itself, Ctrl+A for "restart level"
	x i64 = 0
	y i64 = 0
	back bool = false
	enter bool = false
	mouseX i64 = 0
	mouseY i64 = 0
	moved bool = false
	clicked bool = false
	rightClicked bool = false
	scrollY i64 = 0
	rawKey i64 = 0
	base image.Image = image.Image(1, 1)

	fn haveMouse():
		moved or clicked or rightClicked or scrollY != 0

	fn haveKeyboard():
		x != 0 or y != 0 or back or enter

	fn over(r Rect):
		mouseX >= r.left and mouseX < r.right and mouseY >= r.top and mouseY < r.bottom

menuResume = 0
menuSave = 2
menuLoad = 3
menuRestartLevel = 4
menuSettings = 5
menuRestartGame = 6
menuQuit = 7
subGeneral = 8
subGameplay = 9
subVisuals = 10
subMods = 11
subLevel = 12
subBack = 13
subControls = 14
dialogRestore = 1
dialogQuit = 2
dialogLevel = 3
dialogKey = 4

# an item of the pause menu or of the list of kinds of settings
type MenuItem:
	id i64
	label str

pauseItems = [
	MenuItem(menuResume, "RESUME"),
	MenuItem(menuSave, "QUICKSAVE (F6)"),
	MenuItem(menuLoad, "QUICKLOAD (F9)"),
	MenuItem(menuRestartLevel, "RESTART LEVEL"),
	MenuItem(menuSettings, "SETTINGS"),
	MenuItem(menuRestartGame, "RESTART GAME"),
	MenuItem(menuQuit, "QUIT GAME")
]

settingsItems = [
	MenuItem(subGeneral, "GENERAL"),
	MenuItem(subGameplay, "GAMEPLAY"),
	MenuItem(subVisuals, "VISUALS"),
	MenuItem(subMods, "MODS"),
	MenuItem(subControls, "CONTROLS"),
	MenuItem(subBack, "BACK")
]

tileLabels = [
	"Empty", "Floor", "Spikes", "Pillar", "Gate", "Stuck button", "Closer button", "Tapestry/floor",
	"Big pillar: bottom", "Big pillar: top", "Potion", "Loose floor", "Tapestry", "Mirror",
	"Floor/debris", "Raise button", "Level door: left", "Level door: right", "Chomper", "Torch",
	"Wall", "Skeleton", "Sword", "Balcony: left", "Balcony: right", "Lattice: pillar",
	"Lattice: down", "Lattice: small", "Lattice: left", "Lattice: right", "Torch/debris",
	"Tile 31 (unused)"
]

guardLabels = ["None", "Normal", "Fat", "Skeleton", "Vizier", "Shadow"]

# the names SDLPoP's lists give the values of a setting, "" for a plain number
pub fn valueName(names i64, v i64) str:
	if names == 1 and v >= 0 and v < tileLabels.len: return tileLabels[v].copy()
	if names == 2 and v >= 0 and v < 3: return ["Top", "Middle", "Bottom"][v].copy()
	if names == 3 and (v == -1 or v == 0): return "Left" if v == -1 else "Right"
	if names == 4 and v == 16: return "Never"
	if names == 5 and v >= 0 and v < 2: return ["Dungeon", "Palace"][v].copy()
	if names == 6 and v >= -1 and v < 5: return guardLabels[v + 1].copy()
	if names == 7 and v >= 0 and v < 3: return ["Turning", "Falling", "Running"][v].copy()
	if names == 8 and v == -1: return "Off"
	if names == 9 and v >= 0 and v < 3: return ["OFF", "ON", "AUTO"][v].copy()
	if names == 10 and v >= 0 and v < 3: return ["Sharp", "Fuzzy", "Blurry"][v].copy()
	""

# the settings of one kind, in the menu's order
fn areaSettings(sub i64):
	section = -1
	if sub == subGeneral: section = 0
	if sub == subVisuals: section = 1
	if sub == subGameplay: section = 2
	if sub == subMods: section = 3
	if sub == subLevel: section = 4
	if sub == subControls: section = 5
	settingsTable.filter(.section == section)

# the key of this tick, as the menu reads keys
fn menuKey(mut g Game):
	if g.menu.pendingKey != "":
		k = g.menu.pendingKey.copy()
		g.menu.pendingKey = ""
		return k
	i = g.input
	if i.pressed != "": return i.pressed.copy()
	if i.enter: return "return"
	if i.backspace: return "backspace"
	if i.up: return "up"
	if i.down: return "down"
	if i.left: return "left"
	if i.right: return "right"
	if i.showTime: return "space"
	if i.restart: return "ctrl+a"
	""

fn playMenuSound(mut g Game, id i64):
	g.playSound(id)
	g.playNextSound()

# the menu opened over the paused game (is_menu_shown set)
pub fn openMenu(mut g Game):
	level = g.menu.level
	mouseX = g.menu.mouseX
	mouseY = g.menu.mouseY
	g.menu = Menu(shown = true, hovering = menuResume, redraw = 2, level, mouseX, mouseY)
	g.menu.base = g.screen.onscreen.copy()

# menu_was_closed: the game's picture back, the pause over, the settings changed saved
pub fn closeMenu(mut g Game):
	if not g.menu.shown: return
	g.menu.shown = false
	g.isPaused = false
	g.screen.onscreen = g.menu.base.copy()
	g.eraseBottomText(true)
	if g.menu.changed:
		g.menu.changed = false
		g.saveSettings()

# key_test_paused_menu and read_mouse_state: the controls this tick's input stands for
fn readMenuInput(mut g Game, key str):
	m = g.menu
	i = g.input
	g.menu.moved = i.mouseX != m.mouseX or i.mouseY != m.mouseY
	g.menu.mouseX = i.mouseX
	g.menu.mouseY = i.mouseY
	g.menu.clicked = i.mouseClicked
	g.menu.rightClicked = i.mouseRight
	g.menu.scrollY = i.wheel
	g.menu.rawKey = i.rawKey
	g.menu.x = 0
	g.menu.y = 0
	g.menu.back = i.mouseRight   # the right button closes menus
	g.menu.enter = false
	match key:
		"up": g.menu.y = -1
		"down": g.menu.y = 1
		"pageup": g.menu.y = -9
		"pagedown": g.menu.y = 9
		"home": g.menu.y = -1000
		"end": g.menu.y = 1000
		"right": g.menu.x = 1
		"left": g.menu.x = -1
		"return", "enter", "space": g.menu.enter = true
		"esc", "backspace": g.menu.back = true
		"f6", "shift+f6":
			if g.kid.alive < 0: g.needQuickSave = true
			g.menu.needClose = true
		"f9", "shift+f9":
			g.needQuickLoad = true
			g.menu.needClose = true
		_: pass

# a tick of draw_menu's loop; true when the menu has closed
pub fn menuTick(mut g Game) bool:
	g.soundsPlayed.clear()
	key = g.menuKey()
	g.menu.needClose = false
	g.readMenuInput(key)
	if key.startsWith("ctrl+"):
		g.input.pressed = key.copy()
		g.processKey()   # Ctrl+A, Ctrl+R, ...: the key acts and the menu is closed
		g.closeMenu()
		return true
	if g.menu.needClose:
		g.closeMenu()
		return true
	if g.menu.dialog != 0: g.dialogTick()
	if g.menu.needClose:
		g.closeMenu()
		return true
	if g.menu.dialog != 0:
		g.tickSounds(1)
		return false   # the dialog is up: the menu is not drawn over it
	if g.menu.back:
		g.playMenuSound(soundLooseShake3)
		if g.menu.drawn == 1:
			if g.menu.area == 1:
				g.leaveSettingsSubsection()
			else:
				g.resetPausedMenu()
				g.menu.hovering = menuSettings
		else:
			g.closeMenu()
			return true
	if g.menu.scrollY != 0: g.menuScroll(g.menu.scrollY)
	if g.menu.haveMouse() or g.menu.haveKeyboard():
		g.menu.redraw = 2
	elif g.menu.redraw == 0:
		g.tickSounds(1)
		return false
	g.drawMenuLayer()
	if g.menu.needClose:
		g.closeMenu()
		return true
	g.composeMenu()
	g.menu.redraw -= 1
	g.tickSounds(1)
	false

# the menu drawn on the layer with the small font
fn drawMenuLayer(mut g Game):
	g.smallFont = true
	g.screen.toOverlay = true
	if g.menu.drawn == 0:
		g.drawPauseMenu()
	else:
		g.drawSettingsMenu()
	g.screen.toOverlay = false
	g.smallFont = false

# menu_scroll: the mouse wheel scrolls the settings
fn menuScroll(mut g Game, y i64):
	maxScroll = (areaSettings(g.menu.activeSub).len - settingRows).max(0)
	if g.menu.drawn == 1 and g.menu.area == 1:
		if y < 0 and g.menu.scroll > 0:
			g.menu.scroll -= 1
		elif y > 0 and g.menu.scroll < maxScroll:
			g.menu.scroll += 1

fn resetPausedMenu(mut g Game):
	g.menu.drawn = 0
	g.menu.area = 0
	g.menu.hovering = menuResume

fn enterSettingsSubsection(mut g Game, sub i64):
	if g.menu.activeSub != sub: g.menu.setting = 0
	g.menu.activeSub = sub
	g.menu.highlightedSub = sub
	if not g.menu.clicked: g.menu.hovering = 0
	g.menu.area = 1
	g.menu.scroll = 0

# leave_settings_subsection: the level's settings lead back to the mods'
fn leaveSettingsSubsection(mut g Game):
	if g.menu.activeSub == subLevel:
		g.enterSettingsSubsection(subMods)
	else:
		g.menu.area = 0
		g.menu.hovering = g.menu.activeSub
		g.menu.activeSub = 0
		g.menu.highlightedSub = 0

# clear_menu_controls: what a click or a key did is not read again
fn clearMenuControls(mut g Game):
	g.menu.x = 0
	g.menu.y = 0
	g.menu.back = false
	g.menu.enter = false
	g.menu.clicked = false
	g.menu.rightClicked = false
	g.menu.moved = false
	g.menu.scrollY = 0

# pause_menu_clicked
fn pauseMenuClicked(mut g Game, id i64):
	g.playMenuSound(soundLooseShake3)
	if id == menuResume:
		g.menu.needClose = true
	elif id == menuSave:
		if g.kid.alive < 0: g.needQuickSave = true
		g.menu.needClose = true
	elif id == menuLoad:
		g.needQuickLoad = true
		g.menu.needClose = true
		g.stopSounds()
	elif id == menuRestartLevel:
		g.menu.pendingKey = "ctrl+a"
	elif id == menuSettings:
		g.menu.drawn = 1
		g.menu.hovering = subGeneral
		g.menu.highlightedSub = subGeneral
		g.menu.activeSub = 0
		g.menu.area = 0
	elif id == menuRestartGame:
		g.menu.pendingKey = "ctrl+r"
	elif id == menuQuit:
		g.menu.dialog = dialogQuit
	elif id == subBack:
		g.resetPausedMenu()
		g.menu.hovering = menuSettings
	else:
		g.enterSettingsSubsection(id)
	g.clearMenuControls()

# the item before or after `id` in a ring of items
fn ringNeighbour(items MenuItem[], id i64, step i64):
	at = 0
	for k in 0..items.len:
		if items[k].id == id: at = k
	items[(at + step + len) % len].id

# draw_pause_menu_item: a mouse over it highlights it, a click or Enter takes it
fn drawMenuItem(mut g Game, id i64, label str, parent Rect, yOffset i64, inactive i64):
	text = Rect(parent.top + yOffset, parent.left, parent.bottom, parent.right)
	box = Rect(text.top - 3, text.left, text.top + 8, text.right)
	if g.menu.haveMouse() and g.menu.over(box): g.menu.hovering = id
	color = inactive
	if g.menu.hovering == id:
		color = 15
		g.drawContours(box, 7)
		if g.menu.clicked:
			if g.menu.over(box): g.pauseMenuClicked(id)
		elif g.menu.enter and (g.menu.drawn == 0 or (g.menu.drawn == 1 and g.menu.area == 0)):
			g.pauseMenuClicked(id)
	g.showText(text, 0, -1, label, color)

# draw_pause_menu
fn drawPauseMenu(mut g Game):
	g.fillOverlay(Rect(0, 0, 200, 320), 0, 120)
	g.fillOverlay(Rect(193, 70, 202, 250), 0, 0)   # the text "GAME PAUSED" stays visible
	inner = Rect(5, 115, 187, 205)
	if not g.menu.haveMouse():
		if g.menu.y == 1:
			g.playMenuSound(soundLooseShake2)
			g.menu.hovering = ringNeighbour(pauseItems, g.menu.hovering, 1)
		elif g.menu.y == -1:
			g.playMenuSound(soundLooseShake2)
			g.menu.hovering = ringNeighbour(pauseItems, g.menu.hovering, -1)
	yOffset = 50
	for item in pauseItems:
		g.drawMenuItem(item.id, item.label, inner, yOffset, 15)
		yOffset += 13
