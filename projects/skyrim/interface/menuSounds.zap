# The sounds the menus play. A menu's movie asks for one through GameDelegate.call("PlaySound",
# [name]) (the handler every menu registers, 0x140991e00), the name the editor id of an interface
# sound ("UIMenuFocus", "UIMenuBladeOpenSD"); the executable's own menus play theirs by the same
# name (UI::PlaySound 0x1409920a0). Both end in the world's queue (game.sim's playUi), which the
# game's sound system empties each frame.

import engine.swf.avm1
import game.sim

# the sound a call of the movie asks for, none for another call
pub fn soundOfCall(c avm1.ExternalCall) str?:
	if c.name != "PlaySound": return none
	for a in c.args:
		if a is Str(name): return name.copy()
	none

# the sounds among the calls, in order
pub fn soundsOfCalls(calls avm1.ExternalCall[]) str[]:
	out = []
	for c in calls:
		if c.soundOfCall() is name: out.push(name)
	out

# The sound the call asks for, if it asks for one, queued in the world.
pub fn playCallSound(mut w sim.GameWorld, c avm1.ExternalCall):
	if c.soundOfCall() is name: w.playUi(name)

# The sounds of a menu's own events, by the executable's addresses
pub sleepWaitAcceptSound = "UIMenuOK"   # SleepWaitMenu accept 0x1409752a0 (InterfaceStrings+0x1f8)
pub sleepWaitEndSound = "UIMenuCancel"   # SleepWaitMenu::ProcessMessage 0x140974e00, as a run ends (+0x200)
pub messageBoxButtonSound = "UIMenuOK"   # MessageBoxMenu button 0x140962f50 (+0x1f8)
pub journalOpenSound = "UIJournalOpen"   # JournalMenu::ProcessMessage 0x1409abe30, as it shows
pub statsOpenSound = "UISkillsTransitionUp"   # StatsMenu::ProcessMessage 0x140976a50, as it shows
pub notePageTurnSound = "ITMNotePageTurn"   # BookMenu::ProcessMessage 0x1409063d0, a note's page turned
