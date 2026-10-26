# Activation in the inn (game/sim) with the scripts bound (papyrus): triggers, doors, seats and the player's start.

import skyrim.nif
import game.sim
import papyrus
import world

inn = "RiverwoodSleepingGiantInn"

test "a weapon entering the rack's trigger disables the rack's activator, its linked ref":
	_, vm = papyrus.archivesCellVm(inn) ?? return
	trigger = 0xA_0D68
	activator = vm.rt.world.linkedRef(trigger, 0x6_D95F)
	expect activator == 0xA_0D6A and vm.rt.world.forms[activator].enabled
	expect vm.enterTrigger(trigger, 0xA_0E2F) == 1
	expect not vm.rt.world.forms[activator].enabled

test "the front door leads to Riverwood's cell, to the door outside, not loaded":
	_, vm = papyrus.archivesCellVm(inn) ?? return
	door = 0x1_3419
	a, _ = vm.activateRef(door, vm.rt.world.player)
	expect a == sim.Activation.Teleported(door, 0x1_3424, 0x9712)
	t = vm.rt.world.forms[door].teleport ?? fail("no teleport")
	expect t.world == 0x3C and t.cellEditorId == "Riverwood02"
	expect t.location.startsWith("RiverwoodLocation")

test "a chair seats at its sit marker; the rented bed sleeps only once rented":
	plugin, vm = papyrus.archivesCellVm(inn) ?? return
	a, _ = vm.activateRef(0x5_39E0, vm.rt.world.player)
	expect a is Used(kind, marker, _, _) and kind == nif.furnitureSit and marker == 0
	bed = 0x5_EDA7
	b, _ = vm.activateRef(bed, vm.rt.world.player)
	expect b == sim.Activation.Refused("sNoSleepInOwnedBed")
	quest = vm.bindQuest(plugin, "DialogueGeneric", "DialogueGenericScript") ?? fail("no quest")
	renter = vm.boundObject(0x1_3486, "RentRoomScript") ?? fail("no RentRoomScript on Orgnar")
	vm.callFunction("RentRoomScript", renter, "RentRoom", [.Object(quest)])
	expect vm.rt.world.forms[bed].owner == sim.playerBase
	expect vm.rt.world.inventories[vm.rt.world.player].countOf(0xF) == 130
	c, _ = vm.activateRef(bed, vm.rt.world.player)
	expect c is Used(kind, _, _, _) and kind == nif.furnitureSleep

test "the player starts at level 1 with 100 health, magicka and stamina, in the prisoner's clothes":
	_, vm = papyrus.archivesCellVm(inn) ?? return
	w = vm.rt.world
	a = w.actors[w.player]
	expect a.level == 1 and a.valueOf("health") == 100.0 and a.valueOf("magicka") == 100.0
	expect a.valueOf("stamina") == 100.0 and a.valueOf("carryweight") == 300.0
	inv = w.inventories[w.player]
	expect inv.wornForms().map(w.items[it].editorId) ==
		["ClothesPrisonerTunic", "ClothesPrisonerShoes"]
	expect inv.countOf(0xF) == 140 and inv.countOf(0xA) == 10   # gold, lockpicks

test "Delphine's secret door stays shut without its key and opens with it, the key named":
	_, vm = papyrus.archivesCellVm(inn) ?? return
	door = 0x9_3BCD
	key = 0x9_90DF   # MQDelphineSecretDoorKey
	player = vm.rt.world.player
	a, _ = vm.activateRef(door, player)
	expect a == sim.Activation.Locked(255)
	vm.rt.world.giveItem(player, key, 1, 0)
	opened, _ = vm.activateRef(door, player)
	expect opened is DoorMoved(_, used) and used == key
	expect not (vm.rt.world.forms[door].lock?.locked ?? true)
