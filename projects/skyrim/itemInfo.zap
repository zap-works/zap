# The items of the Sleeping Giant Inn and what activating them does, as the game's model holds
# them (game/sim) with the scripts bound (papyrus). Run from the repository root:
#
#   zap run projects/skyrim/itemInfo.zap --inn                  the loose items and containers, where
#                                                               each stands
#   zap run projects/skyrim/itemInfo.zap --activate <ref | id>  an activation by the player
#   zap run projects/skyrim/itemInfo.zap --player               the player's start
#   zap run projects/skyrim/itemInfo.zap --install D:/Data ...  another install

import skyrim
import skyrim.esm
import game.sim
import papyrus

inn = "RiverwoodSleepingGiantInn"

fn editorIdOf(mut plugin esm.Esm, formId i64):
	r = plugin.recordOf(formId) ?? return "{formId:08X}"
	esm.textOf(r.body, r.fields, "EDID")

fn stackLine(w sim.GameWorld, s sim.Stack):
	item = w.items.get(s.form) ?? return "{s.count} x {s.form:08X} (unknown)"
	marks = s.extras.filter(.isEquipped()).map("worn" if .worn else "left").join(" ")
	stolen = s.extras.filter(.owner != 0).map(.count).sum()
	extra = (" [{marks}]" if not marks.isEmpty else "") +
		(" [{stolen} stolen]" if stolen > 0 else "")
	"{s.count} x {item.name} ({item.editorId} {item.kind}) value {item.value} weight {item.weight}{extra}"

# the opening of the book's text, from the plugin's descriptions table
fn bookText(w sim.GameWorld, texts skyrim.Strings, book i64):
	textId = ((w.items.get(book) ?? return "").book ?? return "").textId
	text = (texts.texts.get(textId) ?? "").replace("\r", " ").replace("\n", " ")
	"{text[..text.len.min(240)]}..."

fn printInventory(w sim.GameWorld, refId i64, pad str):
	inv = w.inventories.get(refId) ?? return print("{pad}(no inventory)")
	for s in inv.stacks:
		print("{pad}{w.stackLine(s)}")
	print("{pad}weight {inv.weightOf(w.items):.1}")

fn ownerText(mut plugin esm.Esm, w sim.GameWorld, f sim.WorldForm):
	owner = w.ownerOf(f)
	if owner == 0: return "no owner"
	own = "" if f.owner != 0 else " (the cell's)"
	"owned by {plugin.editorIdOf(owner)}{own}"

fn placeText(f sim.WorldForm):
	"at {f.x:.0}, {f.y:.0}, {f.z:.0}"

fn printInn(mut plugin esm.Esm, w sim.GameWorld):
	loose = 0
	value = 0
	ids = w.forms.keys().sorted()
	for id in ids:
		f = w.forms[id]
		if f.baseKind not in sim.itemKinds or f.cell == 0: continue
		item = w.items.get(f.base) ?? continue
		loose += 1
		value += item.value * f.count
		print("{id:08X} {f.count} x {item.name} ({item.editorId} {item.kind}) value {item.value} {f.placeText()}, {plugin.ownerText(w, f)}{"" if f.enabled else ", disabled"}")
	print("{loose} loose items worth {value}")
	containers = 0
	for id in ids:
		f = w.forms[id]
		if f.baseKind != "CONT": continue
		containers += 1
		respawn = ", respawns" if f.respawns else ""
		print("{id:08X} {plugin.editorIdOf(f.base)} {f.placeText()}, {plugin.ownerText(w, f)}{respawn}")
		w.printInventory(id, "    ")
	print("{containers} containers")

fn printPlayer(w sim.GameWorld):
	a = w.actors.get(w.player) ?? fail("no player")
	print("player {w.player:08X} level {a.level}, race {a.race:08X}")
	for name in ["health", "magicka", "stamina", "carryweight", "speedmult"]:
		print("  {name} {a.valueOf(name)}")
	print("  skills {sim.skillNames.map("{it} {a.valueOf(it)}").join(", ")}")
	w.printInventory(w.player, "  ")

# the reference named by a form id in hex or by its editor id or its base's
fn findRef(mut plugin esm.Esm, w sim.GameWorld, want str) i64?:
	if i64.parse("0x{want}") is id:
		if w.forms.get(id) != none: return id
	lower = want.lower()
	for id in w.forms.keys().sorted():
		f = w.forms[id]
		if f.editorId.lower() == lower or plugin.editorIdOf(f.base).lower() == lower: return id
	none

fn printActivation(mut plugin esm.Esm, mut vm papyrus.Vm, texts skyrim.Strings, want str):
	refId = plugin.findRef(vm.rt.world, want) ?? fail("no reference {want} in the inn")
	logFrom = vm.rt.log.len
	f = vm.rt.world.forms[refId]
	print(
		"{refId:08X} {f.baseKind} {plugin.editorIdOf(f.base)}, {plugin.ownerText(vm.rt.world, f)}"
	)
	a, sent = vm.activateRef(refId, vm.rt.world.player)
	print(vm.rt.world.activationText(a))
	if a is Opened(container): vm.rt.world.printInventory(container, "    ")
	if a is Reading(book): print("    {vm.rt.world.bookText(texts, book)}")
	if a is Teleported:
		t = vm.rt.world.forms[refId].teleport ?? fail("no teleport")
		print("    to {t.door:08X} at {t.position} in cell {t.cell:08X} {t.cellEditorId}, {t.location}")
	print("OnActivate sent to {sent} scripts")
	for line in vm.rt.world.events:
		print("  event: {line}")
	for line in vm.rt.log[logFrom..]:
		print("  script: {line}")

install = skyrim.openInstall(args.option("--install") ?? skyrim.defaultInstall) ?? fail
plugin = esm.openEsm(install.installPlugin("Skyrim.esm")) ?? fail
names = install.readNames("Skyrim.esm") ?? fail
texts = install.readDescriptions("Skyrim.esm") ?? fail
vm = papyrus.cellVm(install, plugin, names, inn) ?? fail
vm.rt.world.events.clear()
if args.hasFlag("--inn"):
	plugin.printInn(vm.rt.world)
elif args.option("--activate") is want:
	plugin.printActivation(vm, texts, want)
elif args.hasFlag("--player"):
	vm.rt.world.printPlayer()
else:
	fail("give --inn, --activate <ref or editor id> or --player")
