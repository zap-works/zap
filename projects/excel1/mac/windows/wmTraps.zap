# long: the Window and Menu Managers' traps, one arm each
#
# The Window Manager's and the Menu Manager's traps: their Pascal arguments popped, their work
# done by windows.zap and menus.zap.

import cpu

fn windowOfPort():
	thePort()

fn invalidate(local Area, isAdded bool):
	changeUpdate(windowOfPort(), local, isAdded)

# long: a dispatch, an arm a trap
pub fn windowTrap(n i64, trapWord i64, back u32) u32:
	match n:
		0x104: drawGrowIcon(popLong())
		0x108:
			isShown = popBool()
			w = popLong()
			if isShown:
				showWindow(w)
			else:
				hideWindow(w)
		0x109: calcVis(popLong())
		0x10A:
			popLong()
			calcVisBehind(popLong())
		0x10C:
			clobbered = areaOfHandle(popLong())
			paintOne(popLong(), clobbered)
		0x10D:
			clobbered = areaOfHandle(popLong())
			paintBehind(popLong(), clobbered)
		0x110: cpu.write32(popLong(), wMgrPort())
		0x112: initWindows()
		0x113:
			refCon = popLong()
			hasGoAway = popBool()
			behind = popLong()
			procId = popInt()
			isShown = popBool()
			title = pascalAt(popLong())
			bounds = readRect(popLong())
			storage = popLong()
			resultLong(
				newWindow(storage, bounds, title, isShown, procId, behind, hasGoAway, refCon)
			)
		0x114, 0x12D:
			w = popLong()
			disposeWindow(w, n == 0x114)
		0x115: showWindow(popLong())
		0x116: hideWindow(popLong())
		0x117: resultLong(cpu.read32(popLong() + wRefCon))
		0x118:
			data = popLong()
			cpu.write32(popLong() + wRefCon, data)
		0x119:
			at = popLong()
			w = popLong()
			writePascal(at, pascalAt(address(cpu.read32(cpu.read32(w + wTitle)))))
		0x11A:
			title = pascalAt(popLong())
			setWindowTitle(popLong(), title)
		0x11B:
			isFront = popBool()
			v = popInt()
			h = popInt()
			moveWindow(popLong(), h, v, isFront)
		0x11C:
			on = popBool()
			hiliteWindow(popLong(), on)
		0x11D:
			isUpdated = popBool()
			height = popInt()
			width = popInt()
			sizeWindow(popLong(), width, height, isUpdated)
		0x11F: selectWindow(popLong())
		0x120: bringToFront(popLong())
		0x122: beginUpdate(popLong())
		0x123: endUpdate(popLong())
		0x124: resultLong(frontVisibleWindow())
		0x127: areaOfHandle(popLong()).invalidate(true)
		0x128: readRect(popLong()).rectToArea().invalidate(true)
		0x129: areaOfHandle(popLong()).invalidate(false)
		0x12A: readRect(popLong()).rectToArea().invalidate(false)
		0x130: initMenus()
		0x131:
			title = pascalAt(popLong())
			resultLong(newMenu(popInt(), title))
		0x132: disposeHandle(popLong())
		0x133:
			data = pascalAt(popLong())
			appendMenu(popLong(), data)
		0x134: clearMenuBar()
		0x135:
			before = popInt()
			insertMenu(popLong(), before)
		0x136: deleteMenu(popInt())
		0x137: drawMenuBar()
		0x138: hiliteMenu(popInt())
		0x139, 0x13A:
			item = popInt()
			m = popLong()
			if item == 0:
				at = address(cpu.read32(m)) + menuEnable
				cpu.write32(at, cpu.read32(at) | 1 if n == 0x139 else cpu.read32(at) & ~u32(1))
			else:
				setEnabled(m, item, n == 0x139)
		0x145:
			isChecked = popBool()
			item = popInt()
			setItemField(popLong(), item, 2, 0x12 if isChecked else 0)
		0x146:
			at = popLong()
			item = popInt()
			writePascal(at, itemText(popLong(), item))
		0x149: resultLong(menuWithId(popInt()))
		0x14A: popInt()
		0x150: resultWord(itemCount(popLong()))
		0x12C:
			at = popLong()
			v, h = pointOf(popLong())
			part, w = findWindow(v, h)
			cpu.write32(at, w)
			resultWord(part)
		0x13B: resultLong(copyMenuBar())
		0x13D:
			v, h = pointOf(popLong())
			resultLong(menuSelect(v, h))
		0x148: calcMenuSize(popLong())
		0x147:
			text = pascalAt(popLong())
			item = popInt()
			setItemText(popLong(), item, text)
		0x14D:
			kind = i64(popLong())
			addResMenu(popLong(), kind)
		0x13C: setMenuBar(popLong())
		0x1BF: resultLong(getMenu(popInt()))
		0x1C0: resultLong(getNewMenuBar(popInt()))
		_: return dialogTrap(n, trapWord, back)
	back
