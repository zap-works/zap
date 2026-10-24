# A phone's graphics choices, in its menu after save and load: the picture's look
# (projects/recomp/touch/look.zap: smooth, CRT lines, vivid) and, with the widescreen, 120 pictures
# a second (interpolate.zap). Kept beside the dump (<stem>.look, a line for each choice that is on)
# so the next start looks the same; an item's name says whether it is on.

import engine
import fs
import recomp.touch

lookChoices = ["smooth", "crt lines", "vivid", "120 fps"]
mut lookOn = [true, false, true, false]   # by lookChoices, before the player changed them
firstLookItem = 2   # the menu's save state and load state come first

fn lookFile():
	besideDump("look")

# the choices the menu offers: 120 fps only with the widescreen, which interpolation needs
fn lookCount():
	lookChoices.len if hasPresetFlag("--wide") else lookChoices.len - 1

# the menu with the look's choices, as they were kept
fn startLook():
	if fs.readFile(lookFile()) is kept:
		words = kept.lines().map(.trimmed().copy())
		lookOn = lookChoices.map(it in words)
	items = ["save state", "load state"]
	for i in 0..lookCount():
		items.push(lookChoices[i].copy())
	items.push("resume")
	overlay = touch.newOverlay(touch.snesLayout(), items)
	applyLook()

# the menu's item chosen, when it is one of the look's: turned over and kept
fn chooseLook(chosen i64):
	at = chosen - firstLookItem
	if at < 0 or at >= lookCount(): return
	lookOn[at] = not lookOn[at]
	applyLook()
	on = []
	for i, name in lookChoices:
		if lookOn[i]: on.push(name.copy())
	fs.writeFile(lookFile(), "{on.join("\n")}\n") ?? eprint("cannot write {lookFile()}: {error}")

fn applyLook():
	overlay.setLook(touch.Look(smooth = lookOn[0], scanlines = lookOn[1], vivid = lookOn[2]))
	for i in 0..lookCount():
		overlay.setItem(firstLookItem + i, "{lookChoices[i]} {"on" if lookOn[i] else "off"}")
	if lookCount() == lookChoices.len:
		shownPerFrame = presentsPerFrame(120 if lookOn[3] else 60)
		displays[0].setFrameRate(framesPerSecond * shownPerFrame)
