# A spell cast as the game's magic behavior animates it (the MRh_ and MLh_ behaviors of the
# graph): BeginCastRight or BeginCastLeft, then the start event of the spell's kind (aimed or at the
# caster, held or let go), the release that lets a held spell flow or a charged one go, and
# CastStop. The clip's own trigger, MRh_SpellFire_Event or MLh_SpellFire_Event, says when the spell
# leaves the hand.

import skyrim.hkx

# how a spell is cast
pub type CastKind:
	left bool   # the left hand's
	held bool   # a concentration spell, flowing while the hand holds it
	aimed bool   # ahead of the caster, not at him
	charge f32 = 0.0   # the spell's charge time (SPIT): seconds the hand charges before it lets go
	intro f32 = 0.0   # seconds the graph's own wind-up takes (castIntro): no charge is told before

castReadyWord = "SpellReady_Event"
castReleaseWord = "SpellRelease_Event"
pub stopCastEvent = "CastStop"
startGap f32 = 0.05   # seconds from the begin event to the start event

fn handOf(k CastKind):
	"MLh" if k.left else "MRh"

# the event that begins the cast, in the graph's words
fn beginCastEvent(k CastKind):
	"BeginCastLeft" if k.left else "BeginCastRight"

# the event of the spell's kind that starts its charge
fn startCastEvent(k CastKind):
	"{k.handOf()}_Spell{"Aimed" if k.aimed else "Self"}{"Concentration" if k.held else ""}Start"

# the event that lets the charged spell go (a held one flows from it)
pub fn releaseCastEvent(k CastKind) str:
	"{k.handOf()}_{castReleaseWord}"

fn readyCastEvent(k CastKind):
	"{k.handOf()}_{castReadyWord}"

# the trigger of the release clip that is the moment the spell leaves the hand
pub fn fireMark(k CastKind) str:
	"{k.handOf()}_SpellFire_Event"

# the variable that tells the graph the hand wants to cast
pub fn wantCastVariable(k CastKind) str:
	"bWantCastLeft" if k.left else "bWantCastRight"

# the place of the kind in a list of the eight kinds
pub fn slotOf(k CastKind) i64:
	(4 if k.left else 0) + (2 if k.held else 0) + (1 if k.aimed else 0)

# the kind of that place, no charge told
pub fn kindOfSlot(slot i64) CastKind:
	CastKind(left = slot >= 4, held = (slot / 2) % 2 == 1, aimed = slot % 2 == 1)

# Starts the cast on the animator: the variable and the begin event, then the start event a frame
# on (the cast's behavior is entered by the first, which the second needs), then the charge: the
# graph's wind-up is over, and the spell's charge time long, before a charged spell is made ready
# and, as long again, released; a held one flows once its wind-up is over.
pub fn startCast(mut a Animator, k CastKind):
	a.setVariable(k.wantCastVariable(), 1.0)
	a.sendEvent(k.beginCastEvent())
	a.sendEventAfter(k.startCastEvent(), startGap)
	ready = startGap + k.intro.max(k.charge).max(eventGap)
	if not k.held:
		a.sendEventAfter(k.readyCastEvent(), ready)
		a.sendEventAfter(k.releaseCastEvent(), ready + k.charge.max(eventGap))
	else:
		a.sendEventAfter(k.releaseCastEvent(), ready)

# Ends the cast on the animator.
pub fn stopCast(mut a Animator, k CastKind):
	a.setVariable(k.wantCastVariable(), 0.0)
	a.sendEvent(stopCastEvent)

# the clips of the casts of every kind, from either hand, by running the graph
pub fn magicClips(g hkx.Graph, durations {str: f32}) str[]:
	seen = []
	for left in [false, true]:
		for held in [false, true]:
			for aimed in [false, true]:
				k = CastKind(left, held, aimed)
				a = g.drawnAnimator(
					durations,
					handFists if left else handSpell,
					handSpell if left else handFists,
					seen
				)
				a.startCast(k)
				a.play(g, durations, 3.0, seen)
				a.stopCast(k)
				a.play(g, durations, 1.0, seen)
	seen

# Seconds the graph's wind-up of the kind of cast takes after its begin event: until its clip sends
# its own end event (MRh_PreChargeOut...) or the charge loop opens its window (MRh_WinStart), which
# is when the hand can be charged; none when the clip holds the hand by itself until the charge is
# told (an aimed spell let go).
pub fn castIntro(g hkx.Graph, durations {str: f32}, k CastKind) f32:
	seen = []
	a = g.drawnAnimator(
		durations,
		handFists if k.left else handSpell,
		handSpell if k.left else handFists,
		seen
	)
	a.setVariable(k.wantCastVariable(), 1.0)
	a.sendEvent(k.beginCastEvent())
	a.sendEventAfter(k.startCastEvent(), startGap)
	t = f32(0.0)
	while t < longest:
		a.stepAnimator(g, durations, measureStep)
		t += measureStep
		if a.fired.any(.event == "{k.handOf()}_{windowStartWord}" or isWindUpEnd(.event, k)):
			return t
	0.0

windowStartWord = "WinStart"

fn isWindUpEnd(event str, k CastKind):
	event.startsWith("{k.handOf()}_Pre") and event.endsWith("Out")

# the wind-ups of the eight kinds of cast, by their place
pub fn castIntros(g hkx.Graph, durations {str: f32}) f32[]:
	(0..8).map(g.castIntro(durations, kindOfSlot(it)))

# What the graph needs to be told of a shout, in its words (Shout_Behavior): shoutStart (the NPCs'
# has its own), then, once the words are said, the exhale of their count, the weapon out or not.
# The exhale clip's Voice_SpellFire_Event is when the voice leaves, and it ends the shout by itself.
shoutPlayerEvent = "shoutStart"
shoutNpcEvent = "NPCshoutStart"
pub voiceMark = "Voice_SpellFire_Event"
exhaleAtEase = ["MT_BreathExhaleShort", "MT_BreathExhaleMedium", "MT_BreathExhaleLong"]
exhaleReady = [
	"CombatReady_BreathExhaleShort",
	"CombatReady_ShoutExhaleMedium",
	"CombatReady_BreathExhaleLong"
]

# Starts the shout of this many words (1 to 3), said for `hold` seconds, on the animator.
pub fn startShout(mut a Animator, words i64, hold f32, player bool, ready bool):
	a.sendEvent(shoutPlayerEvent if player else shoutNpcEvent)
	exhales = exhaleReady if ready else exhaleAtEase
	a.sendEventAfter(exhales[(words - 1).clamp(0, len - 1)], startGap + hold)
