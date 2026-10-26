# The interface's and the notices' sounds (game/sim/uiSounds.zap, interface/menuSounds.zap,
# game/sound/uiSound.zap): each path of the game asks the world for the sound SkyrimSE.exe plays,
# and the sound system resolves it as UI::PlaySound (0x1409920a0) does. Nothing is played aloud:
# the world's queue is read, and the book's log of what the offline mixer was given. The paths
# that read the install are skipped quietly without it.

import engine.audio
import engine.swf.avm1

import game.dialogue
import game.sim
import game.sound
import interface
import papyrus
import skyrim

inn = "RiverwoodSleepingGiantInn"
flames = 0x1_2FCD
healing = 0x1_2FCC
mixRate = 48_000

# the names of the sounds asked for, in order
fn namesOf(asks sim.SoundAsk[]):
	asks.map(.name.copy())

fn formNamed(w sim.GameWorld, name str):
	w.items.keys().find(w.items[it].name == name) ?? fail("no item {name}")

fn innWorld() sim.GameWorld?:
	_, vm = try papyrus.archivesCellVm(inn)
	vm.rt.world.copy()

test "a movie's PlaySound call names the sound whichever the id before it, no other call does":
	call = avm1.ExternalCall(name = "PlaySound", args = [.Num(3.0), .Str("UIMenuFocus")])
	expect call.soundOfCall() == "UIMenuFocus"
	expect interface.soundOfCall(avm1.ExternalCall(name = "PlaySound", args = [])) == none
	expect interface.soundOfCall(avm1.ExternalCall(name = "CloseMenu", args = [.Str("x")])) == none
	w = sim.newWorld()
	w.playCallSound(call)
	w.playCallSound(avm1.ExternalCall(name = "OK", args = [.Str("UIMenuOK")]))
	expect w.takeSoundAsks().namesOf() == ["UIMenuFocus"] and w.takeSoundAsks().isEmpty

test "a notice with a sound shows and sounds once in five seconds, again after":
	w = sim.newWorld()
	w.showNotice("This lock cannot be picked.", "DRSLocked")
	w.showNotice("This lock cannot be picked.", "DRSLocked")
	w.playSeconds = 4.9
	w.showNotice("This lock cannot be picked.", "DRSLocked")
	expect w.notifications == ["This lock cannot be picked."]
	expect w.takeSoundAsks().namesOf() == ["DRSLocked"]
	w.playSeconds = 5.1
	w.showNotice("This lock cannot be picked.", "DRSLocked")
	w.showNotice("Another notice", "UILockpickingUnlock")
	expect w.notifications.len == 3
	expect w.takeSoundAsks().namesOf() == ["DRSLocked", "UILockpickingUnlock"]

test "the level rising asks for UILevelUp, a skill rising for UISkillIncrease":
	w = innWorld() ?? return
	w.useSkill("onehanded", 1000.0)
	expect w.takeSoundAsks().namesOf() == ["UISkillIncrease"]
	w.progress.xp = w.nextLevelXp() + 10.0
	expect w.levelUp("magicka") == none
	expect w.takeSoundAsks().namesOf() == ["UILevelUp"]
	expect w.levelUp("health") is why and "experience" in why
	expect w.takeSoundAsks().isEmpty

test "the player's spell put in a hand asks for UIMagicSelect, taken out for UIMagicUnselect, an actor's not":
	w = innWorld() ?? return
	player = w.player
	expect w.equipSpell(player, flames, false) == none
	expect w.takeSoundAsks().namesOf() == ["UIMagicSelect"]
	w.unequipSpell(player, flames)
	w.unequipSpell(player, flames)
	expect w.takeSoundAsks().namesOf() == ["UIMagicUnselect"]
	expect w.equipSpell(0x1_0000, healing, false) != none
	expect w.takeSoundAsks().isEmpty

test "the player's favorite used by its key asks for UIFavorite":
	w = innWorld() ?? return
	player = w.player
	w.setFavoriteSpell(player, healing, true)
	w.setHotkey(player, healing, 4)
	expect w.useHotkey(player, 4) == none
	expect w.takeSoundAsks().namesOf() == ["UIMagicSelect", "UIFavorite"]
	expect w.useHotkey(player, 6) == none and w.takeSoundAsks().isEmpty

test "the player eating or drinking asks for the item's own sound, an actor eating asks for none":
	_, vm = papyrus.archivesCellVm(inn) ?? return
	w = vm.rt.world
	apple = w.formNamed("Red Apple")
	ale = w.formNamed("Ale")
	w.ensureInventory(w.player)
	w.inventories[w.player].addItem(apple, 1)
	w.inventories[w.player].addItem(ale, 1)
	ate = w.consume(w.player, apple) ?? fail
	drank = w.consume(w.player, ale) ?? fail
	asks = w.takeSoundAsks()
	expect asks.map(.descriptor) == [ate.sound, drank.sound] and ate.sound != drank.sound
	expect asks.all(.name.isEmpty)
	w.consume(0x1_3486, apple) ?? fail
	expect w.takeSoundAsks().isEmpty

# the names the game plays in these paths: the menus' own, the executable's
uiNames = ["UIMenuOK", "UIMenuCancel", "UIMenuFocus", "UIMenuPrevNext", "UIMenuBladeOpenSD",
	"UIMenuBladeCloseSD", interface.journalOpenSound, interface.statsOpenSound,
	interface.notePageTurnSound, interface.messageBoxButtonSound, interface.sleepWaitAcceptSound,
	interface.sleepWaitEndSound, interface.lockedSound, interface.lockpickingUnlockSound,
	sim.favoriteSound, sim.levelUpSound, sim.skillIncreaseSound, sim.spellSelectSound,
	sim.spellUnselectSound]

test "every sound these paths ask for names a record: a descriptor, else a marker whose descriptor is played":
	install, plugin = skyrim.installAndPlugin() ?? return
	b = sound.newBook(install, move plugin)
	for name in uiNames:
		target = b.uiSoundTarget(name) ?? fail("no record named {name}")
		expect target.descriptor != 0
		d = b.descriptorOf(target.descriptor) ?? fail("{name} names no descriptor")
		expect not d.files.isEmpty
	expect b.uiSoundTarget("UIMenuOK")?.throughInterface == false
	expect b.uiSoundTarget("UIFavorite")?.throughInterface == true
	expect b.uiSoundTarget("NoSuchSound") == none

test "an interface sound plays 2D through the interface output model, its descriptor's files and volume":
	install, plugin = skyrim.installAndPlugin() ?? return
	audio.startOffline(mixRate)
	b = sound.newBook(install, move plugin)
	b.hearFrom(Vec3(100.0, 200.0, 50.0), 0.0)
	favorite = b.playUiSound("UIFavorite")
	expect favorite == 0x6_B460
	locked = b.playUiSound("DRSLocked")
	expect locked == 0x3_39C7
	expect b.log.len == 2
	expect b.log[0].what == "UIFavorite" and b.log[0].distance < 0.0 and b.log[0].gain == 1.0
	lockedName = b.descriptorOf(locked)?.editorId ?? ""
	expect b.log[1].distance < 0.0 and b.log[1].what == lockedName
	expect b.log.all(.volume > 0.0 and .why.startsWith("the interface"))
	expect b.playUiSound("NoSuchSound") == 0 and b.log.len == 2

test "the eating sound plays the descriptor where the player is":
	install, plugin = skyrim.installAndPlugin() ?? return
	audio.startOffline(mixRate)
	b = sound.newBook(install, move plugin)
	b.playAsk(sim.SoundAsk(descriptor = 0xC_AF94))
	b.playAsk(sim.SoundAsk(name = "UIMenuOK"))
	expect b.log.len == 2 and b.log[0].why == "the player" and b.log[1].what == "UIMenuOKSD"

test "a lock that needs its key says so with DRSLocked, a lock to pick with no lockpick says it is out, a key that unlocks UILockpickingUnlock":
	install = skyrim.openInstall(skyrim.defaultInstall) ?? return
	_, vm = papyrus.archivesCellVm(inn) ?? return
	w = vm.rt.world.copy()
	texts = install.openTexts(w.settings) ?? fail
	texts.noticeLocked(w, 255)
	expect w.notifications == [texts.setting("sImpossibleLock")]
	expect w.takeSoundAsks().namesOf() == [interface.lockedSound]
	w.playSeconds = 10.0
	w.inventories[w.player].takeOut(0xA, w.inventories[w.player].countOf(0xA))
	texts.noticeLocked(w, 50)
	expect w.notifications.len == 2 and w.notifications[1] == texts.setting("sOutOfLockpicks")
	expect w.takeSoundAsks().namesOf() == [interface.lockedSound]
	w.inventories[w.player].addItem(0xA, 1)
	w.playSeconds = 20.0
	texts.noticeLocked(w, 50)
	expect w.notifications.len == 2 and w.takeSoundAsks().isEmpty
	w.showNotice("Unlocked with Key.", interface.lockpickingUnlockSound)
	expect w.takeSoundAsks().namesOf() == ["UILockpickingUnlock"]

test "the wait menu's OK asks for UIMenuOK, closing it asks for UIMenuCancel only once it ran":
	talk = dialogue.talkOfArchives(inn) ?? return
	panel = interface.SleepWaitPanel(sleeping = false)
	expect panel.closingSound() == none
	talk.startSleepWait(panel, 2)
	expect talk.vm.rt.world.takeSoundAsks().namesOf() == ["UIMenuOK"]
	expect panel.running and panel.closingSound() == "UIMenuCancel"
