# The keys the game's commands are on, from controlmap.txt (the PC's default map: a command's
# DirectInput scan codes for the keyboard and the mouse buttons it listens to), as the names of the
# key art the menus draw ("Mouse1", "L-Alt", "Q"): what GameDelegate's GetButtonFromUserEvent
# answers the help texts' "[Activate]" with, and the controls list the player remaps (inputMap.zap).

import engine
import skyrim

# the DirectInput scan code of the first key of each row, the names of the keys that follow it
rows = [(0x02, ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "Hyphen", "Equal", "Backspace",
	"Tab", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "Bracketleft", "Bracketright",
	"Enter", "L-Ctrl", "A", "S", "D", "F", "G", "H", "J", "K", "L", "Semicolon", "Quotesingle",
	"Tilde", "L-Shift", "Backslash", "Z", "X", "C", "V", "B", "N", "M", "Comma", "Period", "Slash",
	"R-Shift", "NumPadMult", "L-Alt", "Space", "CapsLock", "F1", "F2", "F3", "F4", "F5", "F6", "F7",
	"F8", "F9", "F10"]), (0x57, ["F11", "F12"]), (0xc7, ["Home", "Up", "PgUp"]),
	(0xcb, ["Left"]), (0xcd, ["Right"]), (0xcf, ["End", "Down", "PgDn", "Insert", "Delete"])]

# the key art's name of a scan code, "" for none
fn keyName(code i64):
	if code == 0x01: return "Esc"
	for (first, names) in rows:
		if code >= first and code < first + names.len: return names[code - first].copy()
	""

# the scan code of the key art of this name, -1 for none
fn codeOfName(name str):
	if name == "Esc": return 1
	for (first, names) in rows:
		for k, n in names:
			if n == name: return first + k
	-1

# The scan code of a key of the window, -1 for one the controls have no art for.
pub fn scanCodeOf(k engine.Key) i64:
	name = match k:
		Char(c): str.fromCode(c)
		F(n): "F{n}"
		Left: "Left"
		Up: "Up"
		Right: "Right"
		Down: "Down"
		Space: "Space"
		Enter: "Enter"
		Shift: "L-Shift"
		Ctrl: "L-Ctrl"
		Raw: ""   # no art
		Backspace: "Backspace"
		Tab: "Tab"
		Escape: "Esc"
	codeOfName(name)

# The key of the window a scan code is, none for one the window does not read.
pub fn keyOfCode(code i64) engine.Key?:
	name = "Esc" if code == 1 else keyName(code)
	if name.isEmpty: return none
	if name.len == 1: return .Char(name.charCode())
	if name.startsWith("F") and (i64.parse(name[1..]) ?? 0) > 0:
		return .F(i64.parse(name[1..]) ?? 0)
	match name:
		"Left": .Left
		"Up": .Up
		"Right": .Right
		"Down": .Down
		"Space": .Space
		"Enter": .Enter
		"L-Shift", "R-Shift": .Shift
		"L-Ctrl": .Ctrl
		"Backspace": .Backspace
		"Tab": .Tab
		"Esc": .Escape
		_: none

# one command of the map: its keyboard key and mouse button (scan code and button number, -1
# unmapped) and whether the player may remap each
pub type Binding:
	event str
	key i64
	mouse i64
	remapKey bool
	remapMouse bool

# the first number of a field that lists some ("0x02,0x4f"), -1 for none or an unmapped 0xff
fn firstCode(field str):
	first = field.split(",")[0].copy()
	code = i64.parse(first) ?? return -1
	-1 if code == 0xff else code

# The commands of the map's first context (the game's own, not its menus), in order.
pub fn bindingsOf(text str) Binding[]:
	out = []
	started = false
	for line in text.lines():
		if line.trimmed().isEmpty:
			if started: break
			continue
		if line.startsWith("//"): continue
		started = true
		fields = line.split("	").filter(not .isEmpty)
		if fields.len < 7: continue
		out.push(Binding(event = fields[0].trimmed().copy(), key = firstCode(fields[1]),
			mouse = firstCode(fields[2]), remapKey = fields[4].trimmed() == "1",
			remapMouse = fields[5].trimmed() == "1"))
	out

pub fn controlMapText(install skyrim.Install) str:
	bytes = install.installRead("interface/controls/pc/controlmap.txt") ?? return ""
	str(move bytes)

pub fn defaultBindings(install skyrim.Install) Binding[]:
	bindingsOf(install.controlMapText())

# A menu context of the map (the lines after its "// <name>" heading, up to a blank line): each
# command with the keyboard entries it lists, a scan code ("0xcb") or the main context's command
# whose key it shares (the "!0,Activate" form), resolved by `keysOf`.
pub fn contextOf(text str, name str) {str: str[]}:
	out {str: str[]} = {}
	inside = false
	for line in text.lines():
		trimmed = line.trimmed()
		if trimmed.startsWith("//"):
			if trimmed[2..].trimmed() == name: inside = true
			continue
		if not inside: continue
		if trimmed.isEmpty: break
		fields = line.split("	").filter(not .isEmpty)
		if fields.len < 2: continue
		out[fields[0].trimmed().copy()] = fields[1].split(",").filter(.trimmed() != "!0")
			.map(.trimmed().copy())
	out

# the scan codes of a context's command, its shared ones as the main context maps them now
pub fn keysOf(context {str: str[]}, event str, main Binding[]) i64[]:
	out = []
	for entry in context.get(event) ?? []:
		if entry.startsWith("0x"):
			code = i64.parse(entry) ?? continue
			if code != 0xff: out.push(code)
		else:
			for b in main:
				if b.event == entry and b.key >= 0: out.push(b.key)
	out

# the key art of a command: its keyboard key, else its mouse button, "" for none
pub fn artName(b Binding) str:
	if b.key >= 0 and keyName(b.key) != "": return keyName(b.key)
	if b.mouse >= 0 and b.mouse < 8: return "Mouse{b.mouse + 1}"
	""

# The key art of each command, by the command's name.
pub fn buttonNames(bindings Binding[]) {str: str}:
	out {str: str} = {}
	for b in bindings:
		if b.artName() != "": out[b.event.copy()] = b.artName()
	out
