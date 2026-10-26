# The journal's controls list as the game answers it: RequestInputMappings gives the list the
# commands of controlmap.txt's first context that the player may remap, each with the art of its
# key; StartRemapMode waits for the next key (`remapTo`), which takes the command over (a key
# another command had is let go) or is refused when it is no key to map; SaveControls writes the
# commands that differ from the map's own into this game's folder, which is read back at the next
# start.

import engine
import engine.swf.avm1
import fs
import game
import skyrim

remapsFile = "ControlMap.txt"

pub type InputMap:
	bindings Binding[]
	defaults Binding[]
	folder str   # where the remaps are saved, empty for nowhere
	remapping str = ""   # the command waiting for a key
	list avm1.Value = .Undefined   # the movie's list of mappings, whose art the remap changes
	menuMode {str: str[]} = {}   # the contexts the menus read: Accept and Cancel
	book {str: str[]} = {}   # PrevPage and NextPage

# The map of the install's controlmap.txt with the remaps this game saved in `folder`.
pub fn openInputMap(install skyrim.Install, folder str) InputMap:
	text = install.controlMapText()
	defaults = bindingsOf(text)
	m = InputMap(bindings = defaults.copy(), defaults, folder = folder.copy(),
		menuMode = contextOf(text, "Menu Mode"), book = contextOf(text, "Book"))
	if not folder.isEmpty:
		for line in (fs.readFile("{folder}/{remapsFile}") ?? "").lines():
			fields = line.split("\t")
			if fields.len < 3: continue
			for mut binding in m.bindings:
				if binding.event == fields[0]:
					binding.key = i64.parse(fields[1]) ?? -1
					binding.mouse = i64.parse(fields[2]) ?? -1
	m

# the commands the player may remap
fn remappable(m InputMap):
	m.bindings.filter(.remapKey or .remapMouse)

# the list's entries: the command's name (the movie turns it into its "$" key), its key art and
# the key's code, in the map's order
fn mappingRows(m InputMap):
	rows = []
	for k, b in m.remappable():
		rows.push(avm1.Row(members = [
			avm1.Member("text", .Str(b.event.copy())),
			avm1.Member("buttonName", .Str(b.artName())),
			avm1.Member("buttonID", .Num(f64(b.key if b.key >= 0 else b.mouse))),
			avm1.Member("sortIndex", .Num(f64(k)))
		]))
	rows

# the answer to the controls list's request, given the map as it stands
pub fn answerInputList(mut pl avm1.Player, m InputMap):
	pl.m.replies["RequestInputMappings"] = [.Fill(0, m.mappingRows())]

fn saveRemaps(m InputMap):
	if m.folder.isEmpty: return
	lines = []
	for k, b in m.bindings:
		d = m.defaults[k]
		if b.key != d.key or b.mouse != d.mouse: lines.push("{b.event}\t{b.key}\t{b.mouse}")
	fs.createDir(m.folder) ?? return
	fs.writeFile("{m.folder}/{remapsFile}", lines.join("\n")) ?? eprint("controls not saved")

# Applies what the controls page asks of the game: StartRemapMode(command, list), SaveControls and
# ResetControlsToDefaults; whether the call was one of these.
pub fn answerInputCall(mut m InputMap, mut pl avm1.Player, c avm1.ExternalCall) bool:
	if c.name == "StartRemapMode":
		if c.args.len > 2:
			m.remapping = c.args[1].primitiveText()
			m.list = c.args[2].copy()
		return true
	if c.name == "SaveControls":
		m.saveRemaps()
		pl.delegate("SettingsSaved", [])
		return true
	if c.name == "ResetControlsToDefaults" or c.name == "ResetControlsToDefaults_Ounce":
		m.bindings = m.defaults.copy()
		pl.answerInputList(m)
		return true
	false

# The key a remap waits for: the next key of the window takes the command over and the movie is
# told (FinishRemapMode); whether the key was taken for the remap.
pub fn remapTo(mut m InputMap, mut pl avm1.Player, k engine.Key) bool:
	if m.remapping.isEmpty: return false
	event = m.remapping.copy()
	m.remapping = ""
	code = k.scanCodeOf()
	ok = code > 1   # Escape is the game's own

	if ok:
		ok = m.bindings.any(.event == event and .remapKey)
	if ok:
		for mut binding in m.bindings:
			if binding.key == code: binding.key = -1
			if binding.event == event: binding.key = code
		m.showArt(pl)
	pl.delegate("FinishRemapMode", [.Bool(ok)])
	true

# the list's entries given the art of the keys they are on now
fn showArt(m InputMap, mut pl avm1.Player):
	count = i64(pl.member(m.list, "length").primitiveNumber())
	for k in 0..count:
		entry = pl.member(m.list, "{k}")
		name = avm1.primitiveText(pl.member(entry, "text"))
		for b in m.bindings:
			if b.event == name:
				pl.setProperty(entry, "buttonName", .Str(b.artName()))
				pl.setProperty(entry, "buttonID", .Num(f64(b.key if b.key >= 0 else b.mouse)))

# the command a key of the window is on, empty for none
pub fn commandOf(m InputMap, k engine.Key) str:
	code = k.scanCodeOf()
	if code < 0: return ""
	for b in m.bindings:
		if b.key == code: return b.event.copy()
	""

# whether a key is on a command of a menu context ("Menu Mode", "Book")
pub fn isMenuCommand(m InputMap, context {str: str[]}, event str, k engine.Key) bool:
	code = k.scanCodeOf()
	code >= 0 and code in keysOf(context, event, m.bindings)

# the key of a command, the default's when the map has none for it
fn keyOf(m InputMap, event str, otherwise engine.Key):
	for b in m.bindings:
		if b.event == event and b.key >= 0: return keyOfCode(b.key) ?? otherwise
	otherwise

# The keys the player's own controls and the commands read, as the map has them: the walk, the run
# and the drawing of the weapon, and every key a command is on watched for its press.
pub fn playerKeys(m InputMap) game.PlayerKeys:
	keys = game.PlayerKeys()
	keys.forward = m.keyOf("Forward", keys.forward)
	keys.back = m.keyOf("Back", keys.back)
	keys.left = m.keyOf("Strafe Left", keys.left)
	keys.right = m.keyOf("Strafe Right", keys.right)
	keys.run = m.keyOf("Run", keys.run)
	keys.draw = m.keyOf("Ready Weapon", keys.draw)
	keys.sneak = m.keyOf("Sneak", keys.sneak)
	for b in m.bindings:
		if keyOfCode(b.key) is key:
			if key not in keys.watch: keys.watch.push(key)
	keys
