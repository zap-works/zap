# What activating something sounds like (sim.activate's outcomes, xEdit's record definitions): an
# item taken plays its own pick-up sound (YNAM) or the default objects' for its kind (PUSW a
# weapon, PUSA an armor, PUSB a book, PUSI an ingredient, PUSG anything else); a harvest its
# flora's (SNAM); a container its open sound (SNAM) and, as its menu closes, its close sound
# (QNAM); a door its open (SNAM) or close (ANAM) sound. The menus' sounds are uiSound.zap's.

import game.sim
import skyrim.esm

# the default objects' pick-up sound of an item of this kind
fn pickUpCode(kind str):
	match kind:
		"WEAP", "AMMO": "PUSW"
		"ARMO": "PUSA"
		"BOOK", "SCRL": "PUSB"
		"INGR": "PUSI"
		_: "PUSG"

# The descriptor the activation of a reference of the base `base` plays, 0 for none.
pub fn activationSound(mut b Book, base i64, a sim.Activation) i64:
	r = b.plugin.recordOf(base) ?? return 0
	match a:
		Taken: r.formOf("YNAM") ?? b.plugin.defaultObject(pickUpCode(r.kind)) ?? 0
		Harvested, Opened: r.formOf("SNAM") ?? 0
		DoorMoved(open, _): r.formOf("SNAM" if open else "ANAM") ?? 0
		_: 0

# Plays what the activation of a reference of `base` standing at `at` sounds like.
pub fn playActivation(mut b Book, base i64, a sim.Activation, at Vec3):
	id = b.activationSound(base, a)
	if id != 0: b.playDescriptor(id, at, "activation")

# Plays a container's close sound as its menu closes.
pub fn playContainerClosed(mut b Book, base i64, at Vec3):
	r = b.plugin.recordOf(base) ?? return
	id = r.formOf("QNAM") ?? return
	_ = b.playDescriptor(id, at, "the container closes")
