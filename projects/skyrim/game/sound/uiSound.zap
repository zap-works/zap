# The interface's sounds as UI::PlaySound (0x1409920a0) plays them: the name is an editor id, first
# of a sound descriptor (SNDR), which plays through the default objects' interface output model
# (IOPM, played as is to the speakers: 2D) whatever model it names, else of a sound marker (SOUN,
# the old records "UIMenuOK" stays as), which plays the descriptor its SDSC names with that
# descriptor's own rules. Its category, loudness, pitch variance and files are the descriptor's.
# The world queues the sounds asked for (game.sim's SoundAsk); playAsk plays them.

import game.sim
import skyrim.esm

# the descriptor an interface sound's name stands for, and whether it plays through the interface
# output model (a descriptor named as is) or as its own record says (through a sound marker)
pub type UiSoundTarget:
	descriptor i64
	throughInterface bool

# What the name stands for, none when no record is named so.
pub fn uiSoundTarget(mut b Book, name str) UiSoundTarget?:
	if b.plugin.formByEditorId("SNDR", name) is id:
		return UiSoundTarget(descriptor = id, throughInterface = true)
	marker = try b.plugin.formByEditorId("SOUN", name)
	id = (try b.plugin.recordOf(marker)).formOf("SDSC") ?? return none
	UiSoundTarget(descriptor = id, throughInterface = false)

# The descriptor a form names as a sound to play: itself, or the descriptor of a sound marker.
pub fn descriptorOfSound(mut b Book, form i64) i64:
	r = b.plugin.recordOf(form) ?? return 0
	if r.kind == "SOUN": return r.formOf("SDSC") ?? 0
	form

# Plays the interface sound `name`; the descriptor it names, 0 when no record is named so. Every
# play is in the book's log.
pub fn playUiSound(mut b Book, name str) i64:
	target = b.uiSoundTarget(name) ?? return 0
	model = 0
	if target.throughInterface: model = b.plugin.defaultObject("IOPM") ?? 0
	b.playDescriptorThrough(target.descriptor, model, b.listener, "the interface: {name}")
	target.descriptor

# Plays a sound asked for: an interface sound by its name, or a descriptor as its record says,
# where the listener is (the player's own: eating, drinking).
pub fn playAsk(mut b Book, ask sim.SoundAsk):
	if not ask.name.isEmpty:
		b.playUiSound(ask.name)
		return
	id = b.descriptorOfSound(ask.descriptor)
	if id != 0: b.playDescriptor(id, b.listener, "the player")
