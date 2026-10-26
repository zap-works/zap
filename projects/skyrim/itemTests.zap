# The scripts of the archives, and the items and their activation (game/sim) with the scripts bound (papyrus).

import skyrim
import skyrim.esm
import game.sim
import papyrus
import world

inn = "RiverwoodSleepingGiantInn"

test "every Papyrus script of the archives parses, its bytes read to the end":
	install = skyrim.installOfArchives() ?? return
	keys = install.installFind(papyrus.scriptDir).filter(.endsWith(".pex"))
	expect keys.len == 14_026
	for key in keys:
		bytes = install.installRead(key) ?? fail("{key} is in no archive")
		script = papyrus.readPex(bytes) ?? fail("{key}: {error}")
		expect script.major == 3 and script.minor == 2 and not script.objects.isEmpty

test "the inn's scripts bind with their properties, and defaultOnEnter's OnInit counts its two actors":
	install = skyrim.installOfArchives() ?? return
	plugin = esm.openEsm(install.installPlugin("Skyrim.esm")) ?? fail
	bindings = plugin.cellBindings(inn) ?? fail("no {inn}")
	vm = papyrus.newVm(install)
	ids = vm.bindCell(bindings)
	vm.tick(0.0)
	expect ids.len >= 20 and vm.rt.threads.isEmpty
	expect not vm.rt.log.any(.startsWith("error:"))
	triggers = ids.filter(vm.rt.objects[it].script == "defaultonenter")
	expect triggers.len == 2
	for k in triggers:
		expect vm.rt.objects[k].vars["targetcounttotal"] == .Int(2)
	renters = ids.filter(vm.rt.objects[it].script == "rentroomscript")
	expect renters.len == 2
	bed = vm.rt.objects[renters[0]].vars["::bed_var"]
	expect bed is Object(b) and vm.rt.objects[b].form == 0x5_EDA7

test "the inn's containers resolve to items the world knows, the loose items each an item":
	_, vm = papyrus.archivesCellVm(inn) ?? return
	w = vm.rt.world
	containers = w.forms.values().filter(.baseKind == "CONT")
	expect containers.len == 18
	for f in containers:
		inv = w.inventories.get(f.formId) ?? fail("no inventory for {f.formId:08X}")
		for s in inv.stacks:
			expect w.items.get(s.form) != none and s.count > 0
	loose = w.forms.values().filter(.baseKind in sim.itemKinds)
	expect loose.len > 200 and loose.all(w.items.get(.base) != none)
	expect w.inventories[0x7_8C0F].countOf(0xF) > 0   # the innkeeper's chest holds gold

test "taking the mead from a table is a theft of its value, reported to Whiterun":
	_, vm = papyrus.archivesCellVm(inn) ?? return
	mead = 0x6_00DD
	base = vm.rt.world.forms[mead].base
	value = vm.rt.world.items[base].value
	a, _ = vm.activateRef(mead, vm.rt.world.player)
	expect a == sim.Activation.Taken(base, 1, true, value / 2)
	expect not vm.rt.world.forms[mead].enabled
	crime = vm.rt.world.crimes.last ?? fail("no crime")
	expect crime.value == value and crime.owner == 0x3_5D44 and crime.faction == 0x2_67EA
	expect vm.rt.world.inventories[vm.rt.world.player].countOf(base) == 1
	b, _ = vm.activateRef(mead, vm.rt.world.player)
	expect b is Refused

test "the barrel opens with what its leveled list gives at level 1":
	_, vm = papyrus.archivesCellVm(inn) ?? return
	barrel = 0x3_6C37
	a, _ = vm.activateRef(barrel, vm.rt.world.player)
	expect a == sim.Activation.Opened(barrel)
	inv = vm.rt.world.inventories[barrel]
	expect inv.stacks.len == 1 and vm.rt.world.items[inv.stacks[0].form].editorId == "FoodCabbage"
