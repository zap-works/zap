# Perks as SkyrimSE.exe 1.7.104 holds and applies them (reference/exe/README.md, "Perks and their
# entry points" has the addresses). An actor has a perk at a rank (Actor::HasPerk 0x14069f920 gives
# the rank, 0 for none); a perk's entry of rank n applies while the perk's rank is n + 1. The
# abilities an actor knows give it their effects' perks (an MGEF's perk, Rested's) at rank 1. The
# perk a record names comes from the plugin (esm.perkOf), learned as the first actor takes it.
#
# An entry point (BGSEntryPoint::HandleEntryPoint 0x14038cff0) takes the perk owner, the forms its
# parameters name and the value to change. Each entry of the owner's perks for that entry point,
# ordered by priority (higher first), then rank (lower first), then the later taken first
# (0x140397600), is asked: it applies when it has as many parameters as the call has (the owner
# counts) and the conditions of each parameter hold for the form given there (an absent form meets
# no conditions, 0x1403960d0); then its function changes the value (0x14038d2c0 to 0x14038d950): 1
# sets it, 2 adds, 3 multiplies, 4 adds a random value between the two the entry gives (rolled
# from a copy of the world's dice, which it does not advance), 5 adds the owner's actor value times
# a factor, 12 sets it to that, 13 multiplies it by that and the value, 14 multiplies it by 1 plus
# that, 6 takes its absolute value, 7 its negative. The other kinds of function (leveled lists,
# spells, text) are read but not applied here. Skyrim.esm uses 1, 2, 3 and 14 for numbers.

import skyrim
import skyrim.esm

# the entry points the port applies, after CommonLibSSE-NG's BGSEntryPoint::ENTRY_POINTS
pub epCalculateWeaponDamage = 0
pub epModSneakAttackMult = 0x12
pub epModSkillUse = 0x16
pub epModPowerAttackDamage = 0x1c
pub epModAttackDamage = 0x23
pub epModIncomingDamage = 0x24
pub epModSpellMagnitude = 0x1d
pub epModSpellDuration = 0x1e
pub epModIncomingSpellMagnitude = 0x29
pub epModIncomingSpellDuration = 0x2a
pub epModSpellCost = 0x26
pub epModBuyPrices = 8
pub epModSellPrices = 0x3c
pub epModPickpocketChance = 0x38

# the perk with this form id, learned from the plugin when the world does not know it yet; none
# when it is no PERK
pub fn learnPerk(
	mut w GameWorld,
	mut plugin esm.Esm,
	names skyrim.Strings,
	formId i64
) esm.Perk?:
	if w.perks.get(formId) is known: return known.copy()
	p = try plugin.perkOf(formId)
	r = try plugin.recordOf(formId)
	p.name = names.localText(r, "FULL")
	p.description = names.localText(r, "DESC")
	w.perks[formId] = p.copy()
	p

# the rank at which the actor has the perk: given to it, or by an ability it knows; 0 for none
pub fn perkRank(w GameWorld, refId i64, perk i64) i64:
	a = w.actors.get(refId) ?? return 0
	own = a.perks.find(.perk == perk)
	if own is given: return given.rank
	for form in a.magic.known:
		s = w.spells.get(form) ?? continue
		if s.kind != spellKindAbility: continue
		for e in s.effects:
			if (w.magicEffects.get(e.effect)?.perk ?? 0) == perk: return 1
	0

pub fn hasPerk(w GameWorld, refId i64, perk i64) bool:
	w.perkRank(refId, perk) > 0

# the perks the actor has with their ranks, in the order it took them, then those its abilities give
fn heldPerks(w GameWorld, refId i64):
	a = w.actors.get(refId) ?? return []
	out = a.perks.map(.copy())
	for form in a.magic.known:
		s = w.spells.get(form) ?? continue
		if s.kind != spellKindAbility: continue
		for e in s.effects:
			perk = w.magicEffects.get(e.effect)?.perk ?? 0
			if perk != 0 and out.find(.perk == perk) == none: out.push(PerkRank(perk, 1))
	out

# the quest entries of the perk at this rank set their stage when it is ahead of the quest's, the
# ability entries give the actor their spell (BGSQuestPerkEntry, BGSAbilityPerkEntry::ApplyPerkEntry
# 0x140395f80)
fn applyRankEntries(mut w GameWorld, refId i64, perk esm.Perk, rank i64):
	for e in perk.entries:
		if e.rank + 1 != rank: continue
		if e.kind == esm.entryQuest and e.stage > (w.stages.get(e.form) ?? -1):
			w.setStage(e.form, e.stage)
		elif e.kind == esm.entryAbility:
			known = w.actors[refId].magic.known
			if e.form not in known: w.actors[refId].magic.known.push(e.form)

fn removeRankEntries(mut w GameWorld, refId i64, perk esm.Perk, rank i64):
	for e in perk.entries:
		if e.rank + 1 == rank and e.kind == esm.entryAbility:
			w.actors[refId].magic.known = w.actors[refId].magic.known.filter(it != e.form)

fn perkIndex(perks PerkRank[], perk i64) i64?:
	for k, held in perks:
		if held.perk == perk: return k
	none

# Actor.AddPerk: the actor takes the perk at rank 1, or at its next rank when it has it already
# (up to the ranks the record has); the entries of the new rank apply, those of the old end. A perk
# the world has no record of (learnPerk) is taken at rank 1 and its entries apply once learnPending
# has the record. Whether the actor has the perk now, false when there is no such actor.
pub fn addPerk(mut w GameWorld, refId i64, perk i64) bool:
	if w.actors.get(refId) == none: return false
	record = w.perks.get(perk)
	ranks = (record?.ranks ?? 1).max(1)
	index = w.actors[refId].perks.perkIndex(perk)
	old = 0
	if index is k: old = w.actors[refId].perks[k].rank
	rank = (old + 1).min(ranks)
	if rank == old: return true
	if index is k:
		w.actors[refId].perks[k].rank = rank
	else:
		w.actors[refId].perks.push(PerkRank(perk, rank))
	if record is p:
		if old > 0: w.removeRankEntries(refId, p, old)
		w.applyRankEntries(refId, p, rank)
	else:
		w.unlearned.push(perk)
	true

# Queues for learnPending the spells the actors know and the perks they hold that the world has no
# record of (after a save is loaded).
pub fn queueUnlearned(mut w GameWorld):
	for id in w.actors.keys().sorted():
		for form in w.actors[id].magic.known:
			if w.spells.get(form) == none and form not in w.unlearned: w.unlearned.push(form)
		for held in w.actors[id].perks:
			if w.perks.get(held.perk) == none and held.perk not in w.unlearned:
				w.unlearned.push(held.perk)

# Learns the records of the spells and perks that scripts gave the actors before the world had
# them (an ability's magic effect and its perk with them), and applies the entries of the perks
# the actors already hold.
pub fn learnPending(mut w GameWorld, mut plugin esm.Esm, names skyrim.Strings):
	if w.unlearned.isEmpty: return
	forms = w.unlearned.copy()
	w.unlearned = []
	for form in forms:
		if w.perks.get(form) != none or w.spells.get(form) != none: continue
		if w.learnSpell(plugin, names, form): continue
		if w.learnPerk(plugin, names, form) is p:
			for id in w.actors.keys().sorted():
				held = w.actors[id].perks.find(.perk == form) ?? continue
				w.applyRankEntries(id, p, held.rank)

# Actor.RemovePerk: the actor loses the perk at every rank
pub fn removePerk(mut w GameWorld, refId i64, perk i64):
	a = w.actors.get(refId) ?? return
	given = a.perks.find(.perk == perk) ?? return
	record = w.perks.get(perk)
	w.actors[refId].perks = a.perks.filter(.perk != perk)
	if record is p: w.removeRankEntries(refId, p, given.rank)

# the base form of a reference: an actor's base, an item's own form
fn baseForm(w GameWorld, form i64):
	if w.actors.get(form) is a: return a.npc
	if w.forms.get(form) is f and f.base != 0: return f.base
	form

fn truth(b bool) f32:
	1.0 if b else 0.0

fn wornKeyword(w GameWorld, refId i64, keyword i64):
	inv = w.inventories.get(refId) ?? return false
	inv.wornForms().any(keyword in w.keywordsOf(it))

# What a perk's condition function gives for the form it runs on; none when nothing answers it.
fn perkFunctionValue(w GameWorld, c esm.Condition, subject i64) f32?:
	a = w.actors.get(subject)
	name = actorValueNames[c.param1] if c.param1 >= 0 and c.param1 < actorValueNames.len else ""
	match c.function:
		14: a?.valueOf(name) ?? 0.0
		277, 494: a?.baseValueOf(name) ?? 0.0
		640: (a?.percentOf(name) ?? 0.0) * 100.0
		448: truth(w.hasPerk(subject, c.param1))
		560: truth(c.param1 in w.keywordsOf(w.baseForm(subject)))
		682: truth(w.wornKeyword(subject, c.param1))
		80: f32(a?.level ?? 0)
		72: truth(w.baseForm(subject) == c.param1)
		69: truth((a?.race ?? -1) == c.param1)
		71: truth(a?.isInFaction(c.param1) ?? false)
		182: truth(w.inventories.get(subject)?.isWorn(c.param1) ?? false)
		264: truth(c.param1 in (a?.magic?.known ?? []))
		47: f32(w.inventories.get(subject)?.countOf(c.param1) ?? 0)
		46: truth(a?.dead ?? false)
		74: w.globals.get(c.param1) ?? 0.0
		286: truth(subject == w.player and w.stealth.sneaking)
		713: truth((w.spells.get(subject)?.castingPerk ?? -1) == c.param1)
		696: truth((w.spells.get(subject)?.school ?? "") == name)
		_: none

fn perkConditionHolds(w GameWorld, c esm.Condition, subject i64):
	x = w.perkFunctionValue(c, subject) ?? 0.0
	value = (w.globals.get(c.global) ?? 0.0) if c.useGlobal else c.value
	c.holds(x, value)

# Whether the conditions hold for the form they are asked about (a perk's requirements for the
# actor taking it, an entry's for the form at one of its parameters). A function nothing answers
# gives 0.
pub fn perkConditionsHold(w GameWorld, conditions esm.Condition[], subject i64) bool:
	esm.groupsHold(conditions, w.perkConditionHolds(it, subject))

# the entry's conditions at each of its parameters (the owner first) hold for the forms given
fn entryHolds(w GameWorld, e esm.PerkEntry, forms i64[]):
	if forms.len != e.parameters: return false
	for k, form in forms:
		tab = e.tabs.find(.index == k)
		conditions = tab?.conditions ?? []
		if form == 0:
			if not conditions.isEmpty: return false
			continue
		if not w.perkConditionsHold(conditions, form): return false
	true

# an entry that applies to the call, with the order it was taken in
type Pending:
	entry esm.PerkEntry
	seq i64

# the entries of the owner's perks for the entry point that are at their rank, in the order the
# game asks them
fn entriesFor(w GameWorld, owner i64, point i64):
	pending = []
	for k, held in w.heldPerks(owner):
		record = w.perks.get(held.perk) ?? continue
		for e in record.entries:
			if e.kind == esm.entryPoint and e.point == point and e.rank + 1 == held.rank:
				pending.push(Pending(e.copy(), k))
	pending
		.sortedBy(.seq * -1)
		.sortedBy(.entry.rank)
		.sortedBy(.entry.priority * -1)
		.map(.entry.copy())

# the owner's actor value an entry's function multiplies, by the index its first value holds
fn ownerValue(w GameWorld, owner i64, e esm.PerkEntry) f32?:
	a = try w.actors.get(owner)
	index = i64(e.values[0])
	if index < 0 or index >= actorValueNames.len: return none
	a.valueOf(actorValueNames[index])

# The value after an entry's function of kind 1 to 3, 5 to 7 or 12 to 14 (0x14038d2c0..), as the
# game's functions leave it: the entry's data type and values, and for the actor-value kinds the
# owner's actor value the first value names (none: the value stays).
pub fn entryFunctionValue(function i64, dataType i64, values f32[], owned f32?, value f32) f32:
	one = dataType == 1 and values.len >= 1
	two = dataType == 2 and values.len >= 2
	match function:
		1: values[0] if one else value
		2: values[0] + value if one else value
		3: values[0] * value if one else value
		5, 12, 13, 14:
			if not two: return value
			av = owned ?? return value
			match function:
				5: av * values[1] + value
				12: av * values[1]
				13: av * values[1] * value
				_: (av * values[1] + 1.0) * value
		6: f32.fromBits(value.toBits() & 0x7FFF_FFFF) if dataType == 0 else value
		7: f32.fromBits(value.toBits() | 0x8000_0000) if dataType == 0 else value
		_: value

# the value after one entry's function: 4 adds a random value between the two the entry gives
# (rolled from a copy of the world's dice, which it does not advance)
fn applyFunction(w GameWorld, e esm.PerkEntry, owner i64, value f32):
	if e.function != 4:
		owned = w.ownerValue(owner, e) if e.dataType == 2 and e.values.len >= 2 else none
		return entryFunctionValue(e.function, e.dataType, e.values, owned, value)
	if e.dataType != 2 or e.values.len < 2: return value
	dice = Random(1)
	dice.state = w.dice.rng.state
	(e.values[1] - e.values[0]) * f32(dice.nextFloat(0.0, 1.0)) + e.values[0] + value

# BGSEntryPoint::HandleEntryPoint for the entry points that change a number: the value after the
# perks of `owner` for this entry point changed it, given the forms (references or bases) the
# entry point's parameters name after the owner, 0 for one that is absent.
pub fn entryPointValue(
	w GameWorld,
	point i64,
	owner i64,
	forms i64[],
	value f32
) f32:
	if w.actors.get(owner) == none: return value
	args = [owner]
	args.extend(forms)
	out = value
	for e in w.entriesFor(owner, point):
		if e.function != 0 and w.entryHolds(e, args): out = w.applyFunction(e, owner, out)
	out

# the magicka the caster pays for the spell: the record's cost (MagicItem::GetCost 0x140153...)
# changed by the entry point 0x26 of the caster's perks, the spell its parameter
pub fn spellCost(w GameWorld, caster i64, s Spell) f32:
	w.entryPointValue(epModSpellCost, caster, [s.formId], s.cost)
