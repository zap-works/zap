# The fight's animations as the game's behavior graph gives them, not named by hand: the events a
# fight sends (WeapEquip, attackStart, attackPowerStartForward, blockStart, bashStart,
# staggerStart...) are run on the graph and what plays is read off it, the clips the cast must
# carry (fightClipNames) and the attacks' timings (fightTimings): a clip's length, and where its
# HitFrame trigger lies in the swing.

import skyrim
import skyrim.actor
import skyrim.esm
import game.combat
import game.sim
import skyrim.hkx

# the hand types the graph reads (iRightHandType, iLeftHandType): fists, then WEAP DNAM's animation
# types as they come, then a spell in the hand and a shield
pub handFists i64 = 0
pub handSword i64 = 1
pub handSpell i64 = 9
pub handShield i64 = 10
lastMelee i64 = 6   # the two-handed axe

# the events of the fight, in the graph's words
pub drawEvent = "WeapEquip"
pub drawMagicEvent = "Magic_Equip"
pub sheatheEvent = "Unequip"
pub attackEvent = combat.attackEvent
pub releaseEvent = "attackRelease"
pub blockEvent = "blockStart"
pub unblockEvent = "blockStop"
pub bashEvent = combat.bashEvent
pub staggerEvent = "staggerStart"
pub deathEvent = "Ragdoll"
pub bleedEvent = "bleedOutStart"
pub bleedEndEvent = "bleedOutStop"
pub hitMark = "HitFrame"

pub staggerVariable = "staggerMagnitude"

measureStep f32 = 1.0 / 240.0   # the frame the graph is run at to read its timings
settleTime f32 = 2.0   # seconds a drawn weapon is given to be ready
longest f32 = 4.0   # the longest an attack is waited for

# the event that starts a power attack with this hand type
pub fn powerEventOf(hand i64) str:
	combat.powerEventOf(hand == handFists)

# an animator in the stance of a fighter with this weapon in its hand
pub fn takeStance(mut a Animator, right i64, left i64, out bool):
	a.setVariable("iRightHandType", f32(right))
	a.setVariable("iLeftHandType", f32(left))
	a.setVariable("currentDefaultState", 10.0 if out else 0.0)
	a.setVariable("bAttached", 1.0 if out else 0.0)

# the graph run `seconds` at a fine step, each clip it plays with weight collected in `seen`
fn play(mut a Animator, g hkx.Graph, durations {str: f32}, seconds f32, mut seen str[]):
	loop i64(seconds / measureStep):
		a.stepAnimator(g, durations, measureStep)
		for l in a.layers:
			if l.weight > 0.05 and l.clip not in seen: seen.push(l.clip.copy())

# the player's animator with the hand type drawn and ready
fn drawnAnimator(g hkx.Graph, durations {str: f32}, right i64, left i64, mut seen str[]):
	a = g.newWalker(true).animator
	a.takeStance(right, left, true)
	a.play(g, durations, 0.1, seen)
	a.sendEvent(drawMagicEvent if handSpell in [right, left] else drawEvent)
	a.play(g, durations, settleTime, seen)
	a

# the swing the events start, read off the graph: where its HitFrame lies and where its clip ends,
# from the moment its first clip begins to play
fn swingOf(
	g hkx.Graph,
	durations {str: f32},
	hand i64,
	before str[],
	events str[]
) combat.AttackTime ? str:
	seen = []
	a = g.drawnAnimator(durations, hand, handFists, seen)
	for e in before:
		a.sendEvent(e)
		a.play(g, durations, 0.5, seen)
	for e in events: a.sendEvent(e)
	t = f32(0.0)
	while t < longest:
		a.stepAnimator(g, durations, measureStep)
		t += measureStep
		if a.fired.find(.event == hitMark) is f:
			started = t - (a.layers.find(.clip == f.clip)?.time ?? 0.0)
			ended = started + (durations.get(f.clip) ?? 0.0)
			return combat.AttackTime(
				duration = ended - measureStep,
				hit = started + f.at - measureStep
			)
	"the graph sends no {hitMark} for {events} with hand {hand}"

fn movesetOf(g hkx.Graph, durations {str: f32}, hand i64) combat.Moveset ? str:
	plain = try g.swingOf(durations, hand, [], [attackEvent])
	combat.Moveset(
		normal = [plain.copy(), plain.copy()],
		power = try g.swingOf(durations, hand, [], [powerEventOf(hand), releaseEvent])
	)

# the places of the blends the graph staggers by (staggerMagnitude is their parameter), rising
fn staggerPlaces(g hkx.Graph):
	places f32[] = []
	for n in g.nodes:
		if n.kind != .Blender or
			not n.bindings.any(.member == "blendParameter" and .variable == staggerVariable):
			continue
		for p in n.positions:
			if p not in places: places.push(p)
	places.sorted()

# the length of the clip the stagger event brings at that magnitude
fn staggerLength(g hkx.Graph, durations {str: f32}, magnitude f32) f32 ? str:
	seen = []
	a = g.drawnAnimator(durations, handSword, handFists, seen)
	a.setVariable(staggerVariable, magnitude)
	a.sendEvent(staggerEvent)
	a.play(g, durations, 0.3, seen)
	clip = a.layers.find(.weight > 0.5) ?? return "the graph plays no stagger"
	durations.get(clip.clip) ?? return "{clip.clip} has no length"

# the staggers' lengths at every place of the graph's blend
fn staggersOf(g hkx.Graph, durations {str: f32}) combat.Staggers ? str:
	places = g.staggerPlaces()
	if places.isEmpty: return "no blend of the graph is driven by {staggerVariable}"
	lengths = []
	for m in places: lengths.push(try g.staggerLength(durations, m))
	combat.Staggers(magnitudes = places, lengths)

# The attacks' timings the graph gives: fists and a sword's, a bash from a block, the staggers.
pub fn fightTimings(g hkx.Graph, durations {str: f32}) combat.Timings ? str:
	combat.Timings(
		armed = try g.movesetOf(durations, handSword),
		unarmed = try g.movesetOf(durations, handFists),
		bash = try g.swingOf(durations, handSword, [blockEvent], [bashEvent]),
		staggers = try g.staggersOf(durations),
		castIntros = g.castIntros(durations)
	)

# the clips of a hand's melee: drawn, struck with, blocked with, staggered, sheathed
fn meleeClips(g hkx.Graph, durations {str: f32}, hand i64, mut seen str[]):
	a = g.drawnAnimator(durations, hand, handFists, seen)
	for step in [[attackEvent], [powerEventOf(hand), releaseEvent], [blockEvent, bashEvent]]:
		for e in step: a.sendEvent(e)
		a.play(g, durations, 2.5, seen)
	a.sendEvent(unblockEvent)
	for m in g.staggerPlaces():
		a.setVariable(staggerVariable, m)
		a.sendEvent(staggerEvent)
		a.play(g, durations, 2.5, seen)
	a.sendEvent(sheatheEvent)
	a.play(g, durations, 2.5, seen)

# The clips the fight plays, whatever the weapon: those the events bring in the graph for every
# melee hand type, for the spells' hands (magic.zap) and the stances between.
pub fn fightClipNames(g hkx.Graph, durations {str: f32}) str[]:
	seen = []
	for hand in handFists..=lastMelee: g.meleeClips(durations, hand, seen)
	seen.extend(g.magicClips(durations))
	seen

# The timings of an install, its graph read and run (the scene has its graph already: tools and
# tests ask this).
pub fn timingsOf(install skyrim.Install) combat.Timings ? str:
	g = try install.readCharacterGraph()
	g.fightTimings(install.clipDurations(g.clipNamesOf()))

# The fight of the interior cell as a new game has it, the player wielding the weapon with this
# editor id (none to keep his hands empty).
pub fn cellFight(
	mut plugin esm.Esm,
	install skyrim.Install,
	cellId str,
	weapon str,
	seed i64
) combat.Fight ? str:
	names = install.readNames("Skyrim.esm") ?? fail
	w = install.worldOfCell(plugin, names, cellId) ?? fail
	if not weapon.isEmpty:
		form = plugin.formByEditorId("WEAP", weapon) ?? fail("no {weapon}")
		w.inventories[w.player].equip(w.items, form, false) ?? fail
	plugin.sceneFight(w, install.timingsOf() ?? fail, seed) ?? fail
