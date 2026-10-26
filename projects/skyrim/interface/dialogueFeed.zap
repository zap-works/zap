# The dialogue menu (interface/dialoguemenu.swf) fed from a conversation (game/talk.zap) as the game
# feeds it. Its ActionScript's DialogueMenu (DialogueMenu_mc) takes the game's calls through
# GameDelegate's callbacks: SetSpeakerName(name); ShowDialogueText(text) (only with
# bDialogueSubtitles on) and NotifyVoiceReady() as a line begins, HideDialogueText() once the lines
# end; PopulateDialogueList(text, isNew, index, ..., selected or -1) filling
# TopicListHolder.List_mc's entryList with {text, topicIsNew, topicIndex} (a topic heard before
# grey, 0x606060), then ShowDialogueList(newList, hideExit) sliding it in; StartHideMenu() fading
# it out. It asks the game for TopicClicked(index) (Enter or a click on a topic: the list slides
# away), SkipText() (a click while a line is said, from ALLOW_PROGRESS_DELAY on), CloseMenu() (Tab
# or the exit button) and FadeDone() once faded out.

import engine.swf.avm1
import game
import game.dialogue
import skyrim

pub type DialogueMenu:
	p avm1.Player
	c game.Conversation
	subtitles bool   # bDialogueSubtitles: the lines' texts shown
	spoken i64 = 0   # the conversation's lines shown
	showing bool = false   # a line's text shown
	listed i64 = 0   # its topics given
	hiding bool = false   # fading out
	done bool = false   # faded out: the menu closes

# The dialogue menu opened on the conversation as the game opens it, the speaker's name given.
pub fn openDialogue(
	install skyrim.Install,
	move c game.Conversation,
	subtitles bool,
	width i64,
	height i64
) DialogueMenu ? str:
	p = try install.openPlayer("interface/dialoguemenu.swf", width, height)
	p.invokeText("InitExtensions()")
	p.invokeText("SetPlatform(0, false)")
	p.delegate("SetSpeakerName", [.Str(c.name.copy())])
	DialogueMenu(p, c, subtitles)

# the conversation's topics as the menu lists them: each one's text, whether it is new, its index
fn topicArgs(c game.Conversation, t dialogue.Talk):
	out avm1.Value[] = []
	for k, m in c.topics:
		out.extend([.Str(m.prompt.copy()), .Bool(t.isNewTopic(m.topic)), .Num(f64(k))])
	out.push(.Num(0.0))   # the first selected, as the game's captures show the list each time
	out

# what the conversation changed since the last frame given to the movie
fn feed(mut d DialogueMenu, t dialogue.Talk):
	if d.c.spoken != d.spoken:
		d.spoken = d.c.spoken
		d.showing = true
		if d.subtitles and d.c.lineText() is text: d.p.delegate("ShowDialogueText", [.Str(text)])
		d.p.delegate("NotifyVoiceReady", [])
	elif d.showing and not d.c.isSaying():
		d.showing = false
		d.p.delegate("HideDialogueText", [])
	if d.c.listed != d.listed:
		d.listed = d.c.listed
		d.p.delegate("PopulateDialogueList", d.c.topicArgs(t))
		d.p.delegate("ShowDialogueList", [.Bool(true), .Bool(false)])
	if d.c.phase == .Ended and not d.hiding:
		d.hiding = true
		d.p.delegate("StartHideMenu", [])

# TopicClicked's topic: its last argument (the dialogue's GameDelegate.call puts its call's id
# first), -1 for none
fn topicIndexOf(c avm1.ExternalCall):
	match c.args.last ?? .Undefined:
		Num(x): i64(x)
		_: -1

# what the movie asked of the game answered: a topic chosen, a line skipped, the menu closed
fn answerDialogue(mut d DialogueMenu, mut t dialogue.Talk):
	for call in d.p.takeExternal():
		t.vm.rt.world.playCallSound(call)
		match call.name:
			"TopicClicked": d.c.chooseTopic(t, call.topicIndexOf())
			"SkipText": d.c.skipLine()
			"CloseMenu":
				d.hiding = true
				d.c.endConversation(t)
			"FadeDone": d.done = true
			_: pass

# The dialogue's frame: the keys pressed (the menu's arrows, Enter and Tab) and the pointer given
# to the movie, its calls answered, the conversation run for dt seconds and what it changed shown.
pub fn updateDialogue(mut d DialogueMenu, mut t dialogue.Talk, i game.Input, dt f32):
	for k in i.pressed:
		d.p.press(k)
	if i.pointer.x >= 0: d.p.pointer(i.pointer.x, i.pointer.y, i.clicking)
	d.answerDialogue(t)
	d.c.stepConversation(t, dt)
	d.feed(t)
	d.p.advance()
