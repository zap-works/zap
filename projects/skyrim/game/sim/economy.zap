# What things are worth and what taking them costs. Ownership: a reference's XOWN, else its cell's;
# an actor may take what no one owns, what its own base owns and what a faction it belongs to
# owns; anything else is stolen. A theft is reported to the owner's crime faction (an actor's
# CRIF; for a faction, the crime faction of the cell's actors in it, the witnesses who would
# report it), whose CRVA sets its bounty: the stolen value times its steal multiplier (0.5 for
# Whiterun's), the game's own GMSTs giving only the horse's and the werewolf's (iCrimeGoldStealHorse,
# iCrimeGoldWerewolf). Barter: a merchant sells at the value times fBarterMax less (fBarterMax -
# fBarterMin) times the Speech skill over 100 (at most 100), and buys at the value over that
# factor (perks and the merchant's disposition aside). Layouts after UESP's FACT page (CRVA:
# arrest, attack on sight, murder, assault, trespass, pickpocket, an unused word, the steal
# multiplier, escape, werewolf) and its Skyrim:Speech page.

import skyrim.esm

pub type CrimeValues:
	arrest bool
	attackOnSight bool
	murder i64
	assault i64
	trespass i64
	pickpocket i64
	stealMult f32
	escape i64
	werewolf i64

# the crime values of a crime faction, none when it has no CRVA
pub fn crimeValuesOf(mut plugin esm.Esm, faction i64) CrimeValues?:
	r = try plugin.recordOf(faction)
	at = try esm.dataOf(r.fields, "CRVA")
	d = r.body
	CrimeValues(
		arrest = d[at] != 0,
		attackOnSight = d[at + 1] != 0,
		murder = d.u16le(at + 2),
		assault = d.u16le(at + 4),
		trespass = d.u16le(at + 6),
		pickpocket = d.u16le(at + 8),
		stealMult = d.f32le(at + 12),
		escape = d.u16le(at + 16),
		werewolf = d.u16le(at + 18)
	)

# the bounty for stealing this much gold's worth
pub fn stealBounty(v CrimeValues, value i64) i64:
	i64(f32(value) * v.stealMult)

# the owner of what a placed reference holds: its own, else its cell's
pub fn ownerOf(w GameWorld, f WorldForm) i64:
	if f.owner != 0: return f.owner
	w.cellOwner if f.cell == w.cell else 0

# whether the actor may take what this owner owns
pub fn canTake(w GameWorld, actorRef i64, owner i64) bool:
	if owner == 0: return true
	a = w.actors.get(actorRef) ?? return false
	owner == a.npc or a.isInFaction(owner)

# records the theft of count of the item from the reference; the crime
pub fn recordTheft(mut w GameWorld, actorRef i64, refId i64, item i64, count i64, owner i64) Crime:
	value = (w.items.get(item)?.value ?? 0) * count
	faction = w.crimeFactions.get(owner) ?? 0
	values = w.crimeValues.get(faction)
	crime = Crime(
		kind = "steal",
		actor = actorRef,
		refId,
		item,
		count,
		value,
		owner,
		faction,
		bounty = values?.stealBounty(value) ?? 0
	)
	w.crimes.push(crime.copy())
	w.record("steal {count} {w.items.get(item)?.editorId ?? ""} worth {value} from {owner:08X}: bounty {crime.bounty} to {faction:08X}")
	crime

# The price factor of a merchant for a buyer with this Speech skill, as SkyrimSE.exe computes it
# (0x140420be0, reference/exe/README.md, "The menus"): lerp(fBarterMax, fBarterMin, Speech / 100),
# at least fBarterBuyMin; what he pays is its inverse, at most fBarterSellMax (barter.zap applies
# the perks).
pub fn barterFactor(settings {str: f64}, speech f32) f64:
	high = f64(settings.gmst("fbartermax"))
	low = f64(settings.gmst("fbartermin"))
	(high + (low - high) * f64(speech) * 0.01).max(f64(settings.gmst("fbarterbuymin")))

# the share of an item's value a merchant pays
pub fn sellFactor(settings {str: f64}, speech f32) f64:
	(1.0 / settings.barterFactor(speech)).min(f64(settings.gmst("fbartersellmax")))
