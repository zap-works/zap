# The settings of the pause menu (SDLPoP's menu.c draw_settings_menu, draw_settings_area,
# draw_setting, handle_setting, the dialogs): the kinds of settings at the left, the settings of the
# kind at the right, nine of them on view. The mouse hovers, clicks and scrolls as in menu.c.

import image

settingRows = 9
settingsArea = Rect(20, 100, 150, 300)

# the value of a setting: a level's, for the customization of a level
fn settingValue(g Game, s MenuSetting):
	if s.section == 4: return g.options.optAt(s.option, g.menu.level)
	g.options.opt(s.option)

fn setSettingValue(mut g Game, s MenuSetting, v i64):
	g.menu.changed = true
	if s.section == 4:
		g.options.values[s.option.copy()][g.menu.level] = v
	else:
		g.options.values[s.option.copy()] = [v]

# whether a toggle is on
fn settingOn(g Game, s MenuSetting):
	if s.option == "cheats": return g.cheatsEnabled
	if s.option == "sound": return g.soundOn
	g.options.isOn(s.option)

# turn_setting_on_off
fn setSettingOn(mut g Game, s MenuSetting, on bool):
	g.menu.changed = true
	if s.option == "cheats":
		g.cheatsEnabled = on
	elif s.option == "sound":
		g.soundOn = on
	elif s.option == "use_custom_options":
		g.options.setCustomOn(on)
	else:
		g.options.values[s.option.copy()] = [1 if on else 0]

# a setting is greyed when the option it depends on is off
fn settingDisabled(g Game, s MenuSetting):
	s.required != "" and not g.options.isOn(s.required)

# SDL_GetScancodeName for the virtual-key codes of the key settings
fn keyName(vk i64):
	if (vk >= 'A' and vk <= 'Z') or (vk >= '0' and vk <= '9'): return str.fromCode(vk)
	if vk >= 112 and vk <= 123: return "F{vk - 111}"
	if vk >= 96 and vk <= 105: return "Keypad {vk - 96}"
	match vk:
		37: "Left"
		38: "Up"
		39: "Right"
		40: "Down"
		36: "Home"
		35: "End"
		33: "PageUp"
		34: "PageDown"
		13: "Return"
		27: "Escape"
		32: "Space"
		16: "Shift"
		17: "Ctrl"
		18: "Alt"
		9: "Tab"
		8: "Backspace"
		45: "Insert"
		46: "Delete"
		_: "Key"

# print_setting_value: a name, a time in seconds for the ticks, a key, or the number
fn settingValueText(s MenuSetting, v i64):
	if s.kind == 3: return "{keyName(v)} ({v})"
	name = valueName(s.names, v)
	if name != "": return name
	if s.option in [
		"start_ticks_left",
		"shift_L_reduced_ticks",
		"mouse_delay",
		"loose_floor_delay"
	]:
		hundredths = (v * 1000 / 12 + 5) / 10
		return "{hundredths / 100}.{hundredths % 100:02}"
	"{v}"

# increase_setting, decrease_setting: a step inside the range (1000 for the joystick's threshold)
fn stepSetting(mut g Game, s MenuSetting, step i64):
	old = g.settingValue(s)
	v = old + step
	if s.option == "joystick_threshold":
		v = (old / 1000 + 1) * 1000 if step > 0 else ((old + 999) / 1000 - 1) * 1000
	if v >= s.lo and v <= s.hi: g.setSettingValue(s, v)

fn lineWidth(g Game, text str):
	w = 0
	for k in 0..text.len:
		w += g.charWidth(text[k])
	w

# the box of a setting, where the mouse is taken to be over it
fn settingBox(text Rect):
	Rect(text.top - 5, text.left - 10, text.top + 10, text.right + 10)

# draw_setting: the label, the value, the explanation of the one highlighted
fn drawSetting(mut g Game, s MenuSetting, index i64, parent Rect, yOffset i64):
	text = Rect(parent.top + yOffset, parent.left, parent.bottom, parent.right)
	box = text.settingBox()
	if g.menu.clicked and g.menu.over(box):
		g.menu.setting = index
		g.menu.area = 1
	lit = g.menu.setting == index
	if lit:
		g.fillOverlayRgba(box, image.Rgba8(55, 55, 55, 255))
		g.screen.drawRect(g.pal, Rect(box.top, box.left - 2, box.bottom, box.left), 15)
		g.showText(Rect(170, 20, 200, 300), 0, -1, s.explanation, 7)
	disabled = g.settingDisabled(s)
	g.showText(text, -1, -1, s.text, 7 if disabled else 15)
	if disabled: return
	if s.kind == 0:
		g.drawToggle(s, text, box, lit)
	elif s.kind == 1:
		g.drawNumber(s, text, box, lit)
	elif s.kind == 3:
		g.showText(text, 1, -1, s.settingValueText(g.settingValue(s)), 15)
	elif lit and (g.menu.enter or (g.menu.clicked and g.menu.over(box))):
		g.playMenuSound(soundLooseShake3)
		g.menu.dialog = dialogRestore if s.option == "reset" else dialogLevel

# a toggle: a click on its OFF or ON, or Left and Right, turn it
fn drawToggle(mut g Game, s MenuSetting, text Rect, box Rect, lit bool):
	on = g.settingOn(s)
	if lit:
		if g.menu.clicked:
			if not on:
				if g.menu.over(Rect(box.top, box.right - 22, box.bottom, box.right)):
					g.turnSettingWithSound(s, true)
					on = false   # drawn as it was this once, as SDLPoP draws it
			elif g.menu.over(Rect(box.top, box.right - 49, box.bottom, box.right - 22)):
				g.turnSettingWithSound(s, false)
				on = true
		elif on and g.menu.x < 0:
			g.turnSettingWithSound(s, false)
			on = false
		elif not on and g.menu.x > 0:
			g.turnSettingWithSound(s, true)
			on = true
	g.showText(text, 1, -1, "ON", 15 if on else 7)
	g.showText(
		Rect(text.top, text.left, text.bottom, text.right - 15),
		1,
		-1,
		"OFF",
		7 if on else 15
	)

fn turnSettingWithSound(mut g Game, s MenuSetting, on bool):
	g.playMenuSound(soundSwordVsSword)
	g.setSettingOn(s, on)

# a number: a click on an arrow, or Left and Right, step it
fn drawNumber(mut g Game, s MenuSetting, text Rect, box Rect, lit bool):
	value = g.settingValue(s)
	if lit:
		if g.menu.clicked:
			right = Rect(box.top, text.right - 5, box.bottom, text.right + 10)
			w = g.lineWidth(s.settingValueText(value))
			if g.menu.over(right):
				g.stepSetting(s, 1)
			elif g.menu.over(
				Rect(box.top, right.left - (w + 10), box.bottom, right.right - (w + 5))
			):
				g.stepSetting(s, -1)
		elif g.menu.x != 0:
			g.stepSetting(s, 1 if g.menu.x > 0 else -1)
	shown = s.settingValueText(g.settingValue(s))
	g.showText(text, 1, -1, shown, 15)
	if lit:
		g.drawArrow(arrowRight, text.right + 2, text.top)
		g.drawArrow(arrowLeft, text.right - g.lineWidth(shown) - 6, text.top)

# handle_setting: a key setting is redefined by Enter or a click, after the list is drawn
fn handleSetting(mut g Game, s MenuSetting, index i64, parent Rect, yOffset i64):
	box = settingBox(Rect(parent.top + yOffset, parent.left, parent.bottom, parent.right))
	if s.kind == 3 and g.menu.setting == index:
		if g.menu.enter or (g.menu.clicked and g.menu.over(box)):
			g.menu.dialog = dialogKey
			g.menu.keyOption = s.option.copy()

# draw_settings_area
fn drawSettingsArea(mut g Game, list MenuSetting[]):
	start = 0
	if g.menu.activeSub == subLevel:
		start = 15
		g.showText(settingsArea, 0, -1, "LEVEL {g.menu.level}", 15)
	yOffset = start
	drawn = 0
	for i in 0..list.len:
		if i >= g.menu.scroll and drawn < settingRows:
			drawn += 1
			g.drawSetting(list[i], i, settingsArea, yOffset)
			yOffset += 15
	yOffset = start
	handled = 0
	for i in 0..list.len:
		if i >= g.menu.scroll and handled < settingRows:
			handled += 1
			g.handleSetting(list[i], i, settingsArea, yOffset)
			yOffset += 15
	if g.menu.scroll > 0: g.drawArrow(arrowUp, 200, 10)
	if g.menu.scroll + drawn < list.len: g.drawArrow(arrowDown, 200, 151)
	if drawn < list.len:
		bar = Rect(
			settingsArea.top - 5,
			settingsArea.right + 8,
			settingsArea.bottom,
			settingsArea.right + 10
		)
		g.screen.drawRect(g.pal, bar, 8)
		height = bar.bottom - bar.top
		slider = Rect(
			bar.top + g.menu.scroll * height / list.len,
			bar.left,
			bar.top + (g.menu.scroll + drawn) * height / list.len,
			bar.right
		)
		g.screen.drawRect(g.pal, slider, 7)

# the highlighted setting moved by the keys, and the list scrolled to keep it in view
fn moveSettingHighlight(mut g Game, count i64):
	if count == 0 or g.menu.y == 0: return
	last = count - 1
	maxScroll = (count - settingRows).max(0)
	index = (g.menu.setting + g.menu.y).clamp(0, last)
	if g.menu.y > 1 or g.menu.y < -1: g.menu.scroll += g.menu.y
	if index - 8 > g.menu.scroll: g.menu.scroll = index - 8
	if index < g.menu.scroll: g.menu.scroll = index
	g.menu.scroll = g.menu.scroll.clamp(0, maxScroll)
	if index != g.menu.setting: g.playMenuSound(soundLooseShake2)
	g.menu.setting = index

# draw_settings_menu
fn drawSettingsMenu(mut g Game):
	list = areaSettings(g.menu.activeSub)
	inArea = g.menu.activeSub != 0
	g.fillOverlay(Rect(0, 0, 200, 320), 0, 255 if inArea else 220)
	if not g.menu.haveMouse():
		if g.menu.area == 0:
			if g.menu.y == 1 or g.menu.y == -1:
				g.menu.hovering = ringNeighbour(settingsItems, g.menu.hovering, g.menu.y)
				g.playMenuSound(soundLooseShake2)
		else:
			g.moveSettingHighlight(list.len)
	inner = Rect(5, 15, 187, 75)
	yOffset = 50
	for item in settingsItems:
		inactive = 15 if g.menu.highlightedSub == item.id else 7
		g.drawMenuItem(item.id, item.label, inner, yOffset, inactive)
		yOffset += 13
	if inArea: g.drawSettingsArea(list)

# confirmation_dialog_result
fn dialogResult(mut g Game, ok bool):
	if not ok:
		g.playMenuSound(soundLooseShake3)
	elif g.menu.dialog == dialogRestore:
		g.playMenuSound(soundSwordVsSword)
		g.menu.changed = true
		g.options = Options()
		g.soundOn = true
	else:
		g.gameOver = true   # Ctrl+Q
		g.menu.needClose = true

okBox = Rect(103, 108, 116, 158)
cancelBox = Rect(103, 162, 116, 212)

# a tick of the dialog the menu asks: drawn on its first, then it answers to the controls
fn dialogTick(mut g Game):
	if not g.menu.dialogDrawn:
		g.menu.dialogDrawn = true
		g.drawDialogOfMenu()
		return
	d = g.menu.dialog
	if d == dialogKey:
		g.keyDialogTick()
	elif d == dialogLevel:
		g.levelDialogTick()
	else:
		g.confirmationTick()
	if g.menu.dialog == 0:
		g.menu.dialogDrawn = false
		g.menu.oldButton = -1
		g.menu.oldLevel = -1
		g.menu.button = 1
		g.clearMenuControls()
		g.menu.redraw = g.menu.redraw.max(1)

# draw_confirmation_dialog, a tick of it: Left and Right or the mouse choose, Enter or a click
# answers, Esc or the right button cancels
fn confirmationTick(mut g Game):
	if g.menu.back:
		g.dialogResult(false)
		g.menu.dialog = 0
		return
	if g.menu.haveMouse():
		if g.menu.over(okBox):
			g.menu.button = 1
		elif g.menu.over(cancelBox):
			g.menu.button = 0
	if g.menu.x < 0:
		g.menu.button = 1
	elif g.menu.x > 0:
		g.menu.button = 0
	elif g.menu.clicked or g.menu.enter:
		g.dialogResult(g.menu.button == 1)
		g.menu.dialog = 0
		return
	if g.menu.button != g.menu.oldButton:
		g.menu.oldButton = g.menu.button
		g.drawDialogOfMenu()

# draw_select_level_dialog, a tick of it: Left and Right choose the level, Enter or a click opens it
fn levelDialogTick(mut g Game):
	if g.menu.back:
		g.playMenuSound(soundLooseShake3)
		g.menu.dialog = 0
		return
	if g.menu.x < 0:
		g.menu.level = (g.menu.level - 1).max(0)
	elif g.menu.x > 0:
		g.menu.level = (g.menu.level + 1).min(15)
	elif g.menu.clicked or g.menu.enter:
		g.enterSettingsSubsection(subLevel)
		g.menu.highlightedSub = subMods
		g.playMenuSound(soundLooseShake3)
		g.menu.dialog = 0
		return
	if g.menu.level != g.menu.oldLevel:
		g.menu.oldLevel = g.menu.level
		g.drawDialogOfMenu()

# redefine_key's showmessage_any_key: the next key is the setting's, Esc cancels
fn keyDialogTick(mut g Game):
	if g.menu.rawKey == 0: return
	if g.menu.rawKey != 27:
		g.options.values[g.menu.keyOption.copy()] = [g.menu.rawKey]
		g.menu.changed = true
	g.menu.dialog = 0

# the dialog in force drawn on the layer, in the game's font, and shown
fn drawDialogOfMenu(mut g Game):
	g.screen.toOverlay = true
	d = g.menu.dialog
	if d == dialogKey:
		g.drawDialog(
			"Redefining keys:\nPress key for \"{g.keySettingLabel()}\".\nOr press Esc to cancel."
		)
	else:
		g.fillOverlay(Rect(0, 0, 200, 320), 0, 255)
		g.screen.drawRect(g.pal, dialogPeelRect(), 0)
		if d == dialogLevel:
			g.drawLevelDialog()
		else:
			g.drawConfirmation()
	g.screen.toOverlay = false
	g.composeMenu()

fn keySettingLabel(g Game):
	for s in settingsTable:
		if s.option == g.menu.keyOption: return s.text.copy()
	""

fn drawLevelDialog(mut g Game):
	g.drawDialogTrimmed("Customize level...", 14)
	input = Rect(104, 64, 118, 256)
	g.showText(input, 0, 0, "{g.menu.level}", 15)
	g.drawArrow(arrowRight, 175, input.top + 3)
	g.drawArrow(arrowLeft, 142, input.top + 3)

fn drawConfirmation(mut g Game):
	text = "Restore all settings to their default values?" if g.menu.dialog == dialogRestore
		else "Quit SDLPoP?"
	g.drawDialogTrimmed(text, 14)
	ok = g.menu.button == 1
	g.screen.drawRect(g.pal, okBox if ok else cancelBox, 8)
	g.showText(Rect(104, 108, 118, 158), 0, 0, "OK", 15 if ok else 7)
	g.showText(Rect(104, 162, 118, 212), 0, 0, "Cancel", 7 if ok else 15)
