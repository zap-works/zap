# Eating, drinking and the effects that last, as SkyrimSE.exe does them (reference/exe/README.md,
# "Eating, drinking and active effects" has the addresses). Using an ALCH item from the inventory
# (ActorEquipManager::EquipObject 0x1406dc310, its form-type switch at 0x1406b2570, case 0x2e)
# refuses a poison, which is put on a weapon, and otherwise has the actor drink it
# (Actor::DrinkPotion, 0x1406d5890): one of the item is gone and each of its effects becomes an
# active effect on the actor, started at once (ActiveEffect::Update 0x1405bcde0 with 0 seconds). The
# model plays the value modifiers: the archetype 0 of a plain effect and the archetype 34 (0x22) of
# the peak one, which of equal effects lets only the strongest hold.
#
# A value modifier (ValueModifierEffect, 0x1405e6dd0...) keeps its magnitude with the sign of its
# harm (a detrimental effect lowers) and works by the effect's Recover flag:
#   - Recover (the fortify effects): the magnitude is added to the value's modifier when the effect
#     starts and taken off when it ends (ShouldModifyOnStart 0x1405e7170, ModifyOnFinish
#     0x1405e7430), however long it lasts;
#   - otherwise it is a change of the damage taken (restore, damage): an effect with no duration
#     changes it once, at its start; one with a duration changes it magnitude x dt on every update
#     (ShouldModifyOnUpdate 0x1405e72f0, ModifyOnUpdate 0x1405e7340), so it gives magnitude x
#     duration over its seconds, the last update cut short at the end.
# A lowering never takes more than the value has, health aside (0x1405e71d0); a fortify that ends
# first gives back the damage that would take the value below 0 (0x1405e7430). The magnitude tapers in the effect's last
# taperDuration seconds (ActiveEffect::GetTaperedMagnitude 0x1404220e0).

# the peak value modifier archetype (the plain one is spells.zap's)
pub archetypePeakValueModifier = 34

# the actor values a value modifier never takes below 0: the skills and the attributes, but health
# (indexes 6 to 23 and 24 to 38 of the actor values)
firstClampedValue = 6
lastClampedValue = 38
healthIndex = 24

# the largest resistance, the game's cap
resistCap f32 = 85.0

# an effect an actor lives under (ActiveEffect)
pub type TimedEffect:
	source i64   # the item or spell that gave it
	effect i64   # its MGEF
	value str   # the actor value it changes
	magnitude f32   # signed: harm lowers the value
	duration f32   # seconds, 0 for an effect that does not last
	recover bool   # the MGEF's Recover flag: a modifier given back when the effect ends
	peak bool   # archetype 34: of equal effects only the strongest holds
	shown bool   # listed in the magic menu
	taperWeight f32
	taperCurve f32
	taperDuration f32
	elapsed f32 = 0.0
	started bool = false
	held f32 = 0.0   # the modifier in force, which ending the effect takes off

# what an actor's eating or drinking did
pub type Consumed:
	item i64
	food bool
	sound i64   # the sound (SNDR) the game plays for it, 0 for none

# whether harm from the effect is lowered by the target's resistances
pub fn isHarmful(m MagicEffect) bool:
	(m.flags & (flagHostile | flagDetrimental)) != 0

# the share of an effect's harm that gets through the target's resistance to its element and to
# magic (MagicTarget::CheckResistance, 0x1406d4e30)
pub fn resistedShare(a ActorState, m MagicEffect) f32:
	factor = 1.0
	for name in [m.resist.copy(), "magicresist"]:
		if name.isEmpty: continue
		factor *= 1.0 - a.valueOf(name).clamp(0.0, resistCap) / 100.0
	factor

# The effect an item's EFIT gives on an actor with the magic effect `m`: a harmful one lowers
# (ValueModifierEffect::Func1, 0x1405e7050), one with no magnitude has 1 (the constructor), one
# with no duration lasts 0 seconds, and the actor's resistance lowers the harm.
pub fn timedEffectOf(a ActorState, source i64, e Effect, m MagicEffect) TimedEffect:
	magnitude f32 = 1.0 if (m.flags & flagNoMagnitude) != 0 else e.magnitude
	if m.isHarmful(): magnitude = -magnitude * a.resistedShare(m)
	tapers = (m.flags & (flagNoMagnitude | flagNoDuration)) == 0
	TimedEffect(
		source,
		effect = m.formId,
		value = m.value.copy(),
		magnitude,
		duration = 0.0 if (m.flags & flagNoDuration) != 0 else f32(e.duration),
		recover = (m.flags & flagRecover) != 0,
		peak = m.archetype == archetypePeakValueModifier,
		shown = (m.flags & flagHideInUi) == 0,
		taperWeight = m.taperWeight if tapers else 0.0,
		taperCurve = m.taperCurve if tapers else 0.0,
		taperDuration = m.taperDuration if tapers else 0.0
	)

# The magnitude now: tapered (1 over the last taperDuration seconds, raised to the curve, times the
# weight) when fewer seconds than the taper's are left.
pub fn currentMagnitude(t TimedEffect) f32:
	left = (t.duration - t.elapsed).max(0.0)
	if left >= t.taperDuration or left <= 0.0001 and t.taperCurve < 0.0: return t.magnitude
	t.magnitude * f32((f64(left) / f64(t.taperDuration)).pow(f64(t.taperCurve))) * t.taperWeight

# ShouldModifyOnStart: a fortify, or an effect with no duration
fn changesAtStart(t TimedEffect):
	t.recover or t.duration == 0.0

# ShouldModifyOnUpdate: an effect that is not a fortify and lasts
fn changesOnUpdate(t TimedEffect):
	not t.recover and t.duration != 0.0

# the change of a value: a fortify's goes to the modifier, the others to the damage taken
fn applyChange(mut a ActorState, t TimedEffect, amount f32):
	if amount == 0.0: return
	if t.recover:
		a.modValue(t.value, amount)
	elif amount > 0.0:
		a.restoreNamed(t.value, amount)
	else:
		a.damageValue(t.value, -amount)

# what a lowering may take: no more than the value has, but for health (0x1405e71d0)
fn clampedChange(a ActorState, t TimedEffect, amount f32):
	index = actorValueNames.indexOf(t.value) ?? return amount
	if index == healthIndex or index < firstClampedValue or index > lastClampedValue: return amount
	if amount > 0.0: return amount
	(-a.valueOf(t.value)).max(amount)

# the effect starts: it changes the value by its magnitude, kept as clamped
fn beginEffect(mut a ActorState, mut t TimedEffect):
	t.started = true
	if not t.changesAtStart(): return
	t.magnitude = a.clampedChange(t, t.currentMagnitude())
	if t.peak and t.recover: return
	a.applyChange(t, t.magnitude)
	if t.recover: t.held = t.magnitude

# ModifyOnFinish: what a fortify held is taken off, after giving back the damage that would take
# the value below 0; for health the exe gives back 1 point when the health is within 1 of the
# modifier
fn endEffect(mut a ActorState, t TimedEffect):
	if not t.recover or t.held == 0.0: return
	if t.value == "health" and t.held > 0.0 and a.valueOf("health") <= t.held + 1.0:
		a.restoreNamed("health", 1.0)
	elif t.held > 0.0 and a.valueOf(t.value) < t.held:
		a.restoreNamed(t.value, t.held - a.valueOf(t.value))
	a.modValue(t.value, -t.held)

# whether the effect of the peak kind is the strongest of its equals (the first of them in a tie)
fn isStrongestPeak(a ActorState, k i64):
	t = a.effects[k]
	for i, other in a.effects:
		if i == k or not other.peak or other.effect != t.effect or other.value != t.value: continue
		if other.magnitude.abs() > t.magnitude.abs(): return false
		if other.magnitude.abs() == t.magnitude.abs() and i < k: return false
	true

# the peak effects of equal kind hold only the strongest: the others give back what they hold
# and take it again when the strongest ends
fn settlePeaks(mut a ActorState):
	for k in 0..a.effects.len:
		t = a.effects[k].copy()
		if not t.peak or not t.recover or not t.started: continue
		strongest = a.isStrongestPeak(k)
		if strongest and t.held == 0.0:
			a.applyChange(t, t.magnitude)
			a.effects[k].held = t.magnitude
		elif not strongest and t.held != 0.0:
			a.modValue(t.value, -t.held)
			a.effects[k].held = 0.0

# ActiveEffect::Update by dt seconds (the first one starts the effect): the elapsed time, cut at
# the duration; the change of a lasting effect, magnitude x dt; whether the effect is over
fn tickEffect(mut a ActorState, k i64, dt f32):
	t = a.effects[k].copy()
	span = dt
	if not t.started: a.beginEffect(t)
	if t.duration <= 0.0 or t.elapsed + span <= t.duration:
		t.elapsed += span
	else:
		span = t.duration - t.elapsed
		t.elapsed = t.duration
	if t.changesOnUpdate(): a.applyChange(t, t.currentMagnitude() * span)
	a.effects[k] = t.copy()
	a.settlePeaks()
	if t.duration > t.elapsed: return false
	a.endEffect(a.effects[k].copy())
	true

# All the effects of the actor by dt seconds; the ones that end are gone. A dead actor loses them
# all (ShouldDispelOnDeath).
pub fn stepEffects(mut a ActorState, dt f32):
	k = 0
	while k < a.effects.len:
		over = a.tickEffect(k, dt)
		if a.dead and not over:
			a.endEffect(a.effects[k].copy())
			over = true
		if over:
			a.effects.remove(k)
			a.settlePeaks()
		else:
			k += 1

# puts the effect on the actor and starts it
pub fn addEffect(mut a ActorState, t TimedEffect):
	a.effects.push(t.copy())
	a.stepEffects(0.0)

# the world's actors by dt seconds
pub fn tickEffects(mut w GameWorld, dt f32):
	for id in w.actors.keys():
		if w.actors.getMut(id) is mut a:
			if not a.effects.isEmpty: a.stepEffects(dt)

# The effect after the perks changed its duration and magnitude as an effect starts (0x1405baed0):
# the caster's entry points 0x1e and 0x1d (the caster, the item, the one it works on), then the
# target's 0x2a and 0x29 (the target, the item); drinking, the actor is both.
fn perkedEffect(w GameWorld, refId i64, item i64, e Effect):
	out = e.copy()
	both = [item, refId]
	out.duration = i64(w.entryPointValue(epModSpellDuration, refId, both, f32(out.duration)))
	out.magnitude = w.entryPointValue(epModSpellMagnitude, refId, both, out.magnitude)
	out.duration = i64(
		w.entryPointValue(epModIncomingSpellDuration, refId, [item], f32(out.duration))
	)
	out.magnitude = w.entryPointValue(epModIncomingSpellMagnitude, refId, [item], out.magnitude)
	out

# Has the actor eat or drink one of the item (Actor::DrinkPotion, 0x1406d5890): a poison is
# refused (it goes on a weapon), else one of the item is gone and its effects take hold; the sound
# the game plays, or why the item cannot be used. An effect the model does not play is told in the
# world's events.
pub fn consume(mut w GameWorld, refId i64, form i64) Consumed ? str:
	item = w.items.get(form) ?? return "{form:08X} is no item the world knows"
	potion = item.kind.Potion ?? return "{item.name} is neither food nor a potion"
	if item.isPoison(): return "{item.name} is a poison: it is put on a weapon, not drunk"
	if w.actors.get(refId) == none: return "{refId:08X} is no actor"
	inv = w.inventories.getMut(refId) ?? return "{refId:08X} carries nothing"
	if inv.countOf(form) <= 0: return "{refId:08X} has no {item.name}"
	inv.takeOut(form, 1)
	for e in potion.effects:
		m = w.magicEffects.get(e.effect) ?? continue
		if m.archetype not in [archetypeValueModifier, archetypePeakValueModifier] or
			m.value.isEmpty:
			w.record("{item.name}: {m.editorId} has an effect the model does not play")
			continue
		t = w.actors[refId].timedEffectOf(form, w.perkedEffect(refId, form, e), m)
		w.actors[refId].addEffect(t)
	if refId == w.player: w.playDescriptorForPlayer(potion.useSound)
	Consumed(item = form, food = item.isFood(), sound = potion.useSound)
