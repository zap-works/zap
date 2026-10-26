# long: the Control Manager's, the Dialog Manager's and TextEdit's traps, one arm each
#
# The Control Manager's, the Dialog Manager's and TextEdit's traps: their Pascal arguments popped,
# their work done by controls.zap, dialogs.zap and textEdit.zap. ModalDialog and the alerts run
# their own event loop.

import cpu

fn alertIcon(n i64):
	match n:
		0x186: 0
		0x187: 1
		0x188: 2
		_: -1

# An alert: a dialog of its ALRT's rectangle and items, its icon at the top left, run modally;
# the item hit, or -1 when the run stopped waiting for input
fn alert(id i64, filter u32, icon i64):
	h = getResource(0x414C_5254, id, [], false)
	if h == 0: return -1
	p = address(cpu.read32(h))
	bounds = readRect(p)
	ditl = getResource(0x4449_544C, word(p + 8), [], false)
	if ditl == 0: return -1
	items = newHandle(theZone(), handleSize(ditl))
	moveBytes(address(cpu.read32(items)), address(cpu.read32(ditl)), handleSize(ditl))
	saved = thePort()
	d = newDialog(0, bounds, [], true, 1, 0xFFFF_FFFF, false, 0, items)
	if icon >= 0:
		plotIcon(
			d,
			Rect(top = 10, left = 20, bottom = 42, right = 52),
			getResource(0x4943_4F4E, icon, [], false)
		)
	hit = modalLoop(filter)
	if hit >= 0: disposeDialog(d, true)
	setPort(saved)
	hit

# ModalDialog's loop over the front dialog: updates drawn, a click on an enabled item or Return
# (the default item) ends it; -1 when the run stops for want of input
fn modalLoop(filter u32):
	while true:
		d = frontVisibleWindow()
		tick()
		poll(false)
		e = nextEvent(0xFFFF, true)
		if e.what == nullEvent:
			idleCount += 1
			poll(true)
			if not waitsForInput(): return -1
			continue
		idleCount = 0
		if e.what == updateEvt:
			w = e.message
			beginUpdate(w)
			if word(w + wKind) == 2: drawDialog(w)
			endUpdate(w)
			continue
		if filter != 0:
			eventAt = cpu.a7 - 64
			setWord(eventAt, e.what)
			cpu.write32(eventAt + 2, e.message)
			cpu.write32(eventAt + 10, e.where)
			hitAt = eventAt + 16
			setWord(hitAt, 0)
			cpu.a7 -= 80
			isTaken = callPascal(filter, [(d, 4), (eventAt, 4), (hitAt, 4)], 2) & 0xFF00 != 0
			cpu.a7 += 80
			if isTaken: return word(hitAt)
		if e.what == mouseDown:
			ov, oh = originOf(d)
			gv, gh = pointOf(e.where)
			n = itemAt(d, gv - ov, gh - oh)
			if n > 0: return n
		if e.what == keyDown and (e.message & 0xFF == 13 or e.message & 0xFF == 3):
			return word(d + dDefItem)
	0

fn isDialog(w u32):
	w != 0 and word(w + wKind) == 2

# the dialog an event is for: an update's or an activation's window, else the front window for
# the mouse and the keys; 0 when it is no dialog
fn dialogOfEvent(eventAt u32):
	what = word(eventAt)
	w = cpu.read32(eventAt + 2) if what == updateEvt or what == activateEvt
		else frontVisibleWindow()
	w if isDialog(w) and what != nullEvent else 0

# DialogSelect: an update drawn, a click on an enabled item or a key in the text field handled:
# the item hit, 0 for none
fn dialogSelect(d u32, eventAt u32):
	if d == 0: return 0
	match word(eventAt):
		6:
			beginUpdate(d)
			drawDialog(d)
			endUpdate(d)
		1:
			ov, oh = originOf(d)
			gv, gh = pointOf(cpu.read32(eventAt + 10))
			return itemAt(d, gv - ov, gh - oh)
		3, 5:
			te = cpu.read32(d + dTextH)
			if te != 0:
				teKey(te, cpu.read32(eventAt + 2) & 0xFF)
				return word(d + dEditField) + 1
		_: pass
	0

# long: a dispatch, an arm a trap
pub fn dialogTrap(n i64, trapWord i64, back u32) u32:
	match n:
		0x14B:
			icon = popLong()
			plotIcon(thePort(), readRect(popLong()), icon)
		0x153:
			popLong()
			drawControls(popLong())
		0x154:
			refCon = popLong()
			procId = popInt()
			max = popInt()
			min = popInt()
			value = popInt()
			isShown = popBool()
			title = pascalAt(popLong())
			bounds = readRect(popLong())
			resultLong(
				newControl(popLong(), bounds, title, isShown, value, min, max, procId, refCon)
			)
		0x155: disposeControl(popLong())
		0x156: killControls(popLong())
		0x157: showControl(popLong(), true)
		0x158: showControl(popLong(), false)
		0x159, 0x15C:
			b = popInt()
			a = popInt()
			c = popLong()
			r = readRect(ctl(c) + cRect)
			moved = Rect(
				top = b,
				left = a,
				bottom = b + r.bottom - r.top,
				right = a + r.right - r.left
			)
			sized = Rect(..r, bottom = r.top + b, right = r.left + a)
			writeRect(ctl(c) + cRect, moved if n == 0x159 else sized)
			drawControl(c)
		0x15A: resultLong(cpu.read32(ctl(popLong()) + cRefCon))
		0x15B:
			data = popLong()
			cpu.write32(ctl(popLong()) + cRefCon, data)
		0x15D:
			state = popInt()
			hiliteControl(popLong(), state)
		0x15E:
			at = popLong()
			writePascal(at, pascalAt(ctl(popLong()) + cTitle))
		0x15F:
			title = pascalAt(popLong())
			c = popLong()
			writePascal(ctl(c) + cTitle, title)
			drawControl(c)
		0x160, 0x161, 0x162:
			field = [cValue, cMin, cMax][n - 0x160]
			resultWord(word(ctl(popLong()) + field))
		0x163:
			v = popInt()
			setControlValue(popLong(), v)
		0x164, 0x165:
			v = popInt()
			setControlField(popLong(), cMin if n == 0x164 else cMax, v)
		0x166:
			v, h = pointOf(popLong())
			resultWord(testControl(popLong(), v, h))
		0x168:
			popLong()
			v, h = pointOf(popLong())
			resultWord(testControl(popLong(), v, h))
		0x169: drawControls(popLong())
		0x16A: resultLong(cpu.read32(ctl(popLong()) + cAction))
		0x16B:
			action = popLong()
			cpu.write32(ctl(popLong()) + cAction, action)
		0x16C:
			at = popLong()
			w = popLong()
			v, h = pointOf(popLong())
			c, part = findControl(w, v, h)
			cpu.write32(at, c)
			resultWord(part)
		0x16D: drawControl(popLong())
		0x178:
			popLong()
			drawDialog(popLong())
		0x17C:
			behind = popLong()
			storage = popLong()
			resultLong(getNewDialog(popInt(), storage, behind))
		0x17D:
			items = popLong()
			refCon = popLong()
			hasGoAway = popBool()
			behind = popLong()
			procId = popInt()
			isShown = popBool()
			title = pascalAt(popLong())
			bounds = readRect(popLong())
			resultLong(
				newDialog(
					popLong(),
					bounds,
					title,
					isShown,
					procId,
					behind,
					hasGoAway,
					refCon,
					items
				)
			)
		0x17E:
			end = popInt()
			start = popInt()
			popInt()
			te = cpu.read32(popLong() + dTextH)
			if te != 0: teSetSelect(te, start, end)
		0x17F: resultBool(dialogOfEvent(popLong()) != 0)
		0x180:
			itemAt = popLong()
			dialogAt = popLong()
			eventAt = popLong()
			d = dialogOfEvent(eventAt)
			cpu.write32(dialogAt, d)
			hit = dialogSelect(d, eventAt)
			setWord(itemAt, hit)
			resultBool(hit > 0)
		0x181: drawDialog(popLong())
		0x182, 0x183:
			d = popLong()
			disposeDialog(d, n == 0x183)
		0x185, 0x186, 0x187, 0x188:
			filter = popLong()
			hit = alert(popInt(), filter, alertIcon(n))
			resultWord(hit)
			if hit < 0:
				exitRequested = true
				return returnToZap
		0x18C: popLong()
		0x18D:
			boxAt = popLong()
			handleAt = popLong()
			typeAt = popLong()
			item = popInt()
			d = popLong()
			items = itemsOf(d)
			if item >= 1 and item <= items.len:
				entry = items[item - 1]
				setWord(typeAt, cpu.read8(entry.at + 12))
				cpu.write32(handleAt, cpu.read32(entry.at))
				writeRect(boxAt, entry.box)
		0x18E:
			box = readRect(popLong())
			h = popLong()
			kind = popInt()
			item = popInt()
			items = itemsOf(popLong())
			if item >= 1 and item <= items.len:
				entry = items[item - 1]
				cpu.write32(entry.at, h)
				writeRect(entry.at + 4, box)
				cpu.write8(entry.at + 12, kind & 0xFF)
		0x18F:
			text = pascalAt(popLong())
			h = popLong()
			setHandleSize(h, u32(text.len))
			at = address(cpu.read32(h))
			for i, b in text:
				cpu.write8(at + u32(i), b)
		0x190:
			at = popLong()
			h = popLong()
			writePascal(at, bytesAt(address(cpu.read32(h)), i64(handleSize(h)).min(255)))
		0x191:
			hitAt = popLong()
			filter = popLong()
			hit = modalLoop(filter)
			if hit < 0:
				exitRequested = true
				return returnToZap
			setWord(hitAt, hit)
		0x1CB: resultLong(cpu.read32(address(cpu.read32(popLong())) + 62))
		0x1CD: teDispose(popLong())
		0x1CE:
			just = popInt()
			box = readRect(popLong())
			length = i64(popLong())
			textBox(thePort(), bytesAt(popLong(), length), box, just)
		0x1CF:
			te = popLong()
			length = i64(popLong())
			teSetText(te, bytesAt(popLong(), length))
		0x1D0: popLong()
		0x1D1:
			te = popLong()
			end = i64(popLong())
			teSetSelect(te, popLong(), end)
		0x1D2:
			view = readRect(popLong())
			resultLong(readRect(popLong()).teNew(view))
		0x1D3:
			te = popLong()
			popLong()
			teUpdate(te)
		0x1D4:
			popLong()
			popBool()
			popLong()
		0x1D7: teDelete(popLong())
		0x1D8, 0x1D9: teActivate(popLong(), n == 0x1D8)
		0x1DE:
			te = popLong()
			length = i64(popLong())
			teInsert(te, bytesAt(popLong(), length))
		0x1DA: teIdle(popLong())
		0x1DC:
			te = popLong()
			teKey(te, popWord() & 0xFF)
		0x1BE:
			w = popLong()
			resultLong(getNewControl(popInt(), w))
		_: return utilityTrap(n, trapWord, back)
	back
