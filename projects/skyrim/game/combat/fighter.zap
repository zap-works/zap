# A fighter: an actor of the world as combat sees it, what it holds and wears, its AI's character
# and combat style, and where it stands in its fight. An NPC fights with the weapon it holds, else
# the melee weapon of its inventory that does the most damage (it draws its best weapon when combat
# starts; bows and staves are left: the fight here is melee); the player with what it holds, else
# fists. Its reach is the weapon's (WEAP DNAM) times fCombatDistance (141), fists the race's unarmed
# reach (RACE DATA at 100, 96 for the Nord). Its armor is what it wears that is not clothing nor a
# shield, each rated in its skill's hands (light or heavy armor). The AIDT and ACBS flags decide the
# rest: essential actors (flag 0x2) do not die but bleed out, protected ones (0x800) die only by
# the player's hand.

import skyrim.actor
import game.sim

pub type Mode:
	Idle
	Alert   # saw a crime or lost its target: searching, not fighting
	Approach
	Circle
	Fallback
	Guard   # in reach, waiting for an opening
	Swing
	Block
	Staggered
	Flee
	Bleedout
	Fled
	Dead

pub type Swing:
	strike Strike
	hitAt f32   # the fight's time it lands
	endsAt f32
	landed bool = false
	sneak bool = false   # the player swung while sneaking: a sneak attack on whoever has not detected him

pub type Fighter:
	refId i64
	name str
	player bool
	weapon i64   # 0 for fists
	weaponName str
	baseDamage f32
	weight f32
	speed f32
	reach f32   # units
	animation i64   # WEAP DNAM's type, 0 fists
	staggerPower f32
	attackStaggers f32[]   # the race's ATKD stagger of its plain, power and bash strikes
	skill str   # the actor value that raises its damage, "" for fists
	shield i64
	shieldRating f32
	armorRating f32
	armorPieces i64
	lightWeight i64 = 0   # the share of the armor it wears the Light Armor skill trains, its body piece twice
	heavyWeight i64 = 0   # and the Heavy Armor skill
	ai actor.AiData
	style Style
	essential bool
	protected bool
	at Vec3
	facing Vec3   # unit, flat
	mode Mode = .Idle
	target i64 = 0
	swing Swing? = none
	until f32 = 0.0   # when a timed mode (stagger, block, circle, fallback, bleedout) ends
	nextDecision f32 = 0.0
	targetSince f32 = 0.0   # when it took its target (chosen again no sooner than fCombatSelectTargetSwitchUpdateTime)
	lastSwingAt f32? = none   # when its last swing started
	circleSide f32 = 1.0   # which way a circle goes round the target
	movingUntil f32 = 0.0   # when a fall back stops moving and only waits
	combo i64 = 0   # which of the plain attacks comes next
	damagedAt {str: f32} = {}   # when each of health, magicka, stamina last fell
	controlled bool = false   # a person plays it: its swings land and end, the rest is not thought
	ragdoll bool = false   # dead: the physics takes the body (the skeleton's Havok rigid bodies)
	wasHostile {i64: bool} = {}   # whom it fought before any crime
	casting Cast? = none   # the spell it holds up (magic.zap)
	shouting i64 = 0   # the words of a shout it is saying, 0 for none (magic.zap)
	shoutHold f32 = 0.0   # seconds saying them takes
	shoutReadyAt f32 = 0.0   # when it can shout again
	staggerMagnitude f32 = 0.0   # the last stagger's, as the graph's blend takes it
	struckBy i64 = 0   # who last hurt it, and when
	struckAt f32 = -1000.0
	landedOn i64 = 0   # whom it last hurt, and when
	landedAt f32 = -1000.0
	targetCheckAt f32 = 0.0   # when it next weighs its foes (select.zap)
	confidenceModifier f32 = 0.0   # drawn as it starts fighting, added to its confidence (flee.zap)

# melee weapons: none of the bows, staves and crossbows
fn isMelee(item sim.Item):
	weapon = item.kind.Weapon ?? return false
	weapon.animation >= 1 and weapon.animation <= 6

fn bestWeapon(w sim.GameWorld, refId i64, player bool):
	inv = w.inventories.get(refId) ?? return 0
	held = inv.weaponIn(w.items, false)
	if held != 0 and w.items[held].isMelee(): return held
	if player: return 0
	best = 0
	for s in inv.stacks:
		item = w.items.get(s.form) ?? continue
		if not item.isMelee(): continue
		if best == 0 or (item.kind.Weapon?.damage ?? 0) > (w.items[best].kind.Weapon?.damage ?? 0):
			best = s.form
	best

# the biped slot of body armor, 32 (slot 30 is bit 0)
slotBody = 0x4

fn skillOfArmor(armorType i64):
	"heavyarmor" if armorType == 1 else "lightarmor"

# The fighter the actor placed as refId makes, named `name`, fighting in `style` with its race's
# fists and attacks; its weapon is drawn into its hand.
pub fn fighterOf(
	mut w sim.GameWorld,
	settings {str: f64},
	refId i64,
	name str,
	move style Style,
	race RaceCombat
) Fighter:
	a = w.actors[refId].copy()
	player = refId == w.player
	weapon = w.bestWeapon(refId, player)
	if weapon != 0 and not w.inventories[refId].isWorn(weapon):
		w.inventories[refId].equip(w.items, weapon, false) ?? fail
	data sim.WeaponData? = none
	if w.items.get(weapon) is item: data = item.kind.Weapon
	inv = w.inventories.get(refId) ?? sim.Inventory()
	shield = inv.shieldWorn(w.items)
	shieldRating = 0.0
	if w.items.get(shield) is item: shieldRating = item.kind.Armor?.rating ?? 0.0
	rating = 0.0
	pieces = 0
	light = 0
	heavy = 0
	for form in inv.wornForms():
		item = w.items.get(form) ?? continue
		armor = item.kind.Armor ?? continue
		if armor.armorType < 2 and armor.rating > 0.0:
			share = 2 if armor.slots & slotBody != 0 else 1
			if armor.armorType == 1: heavy += share
			else: light += share
		if form == shield or armor.armorType == 2: continue
		rating += settings.armorRating(
			armor.rating,
			a.valueOf(skillOfArmor(armor.armorType)),
			player
		)
		pieces += 1
	f = w.forms.get(refId)
	Fighter(
		refId,
		name = name.copy(),
		player,
		weapon,
		weaponName = w.items.get(weapon)?.name ?? "fists",
		baseDamage = f32(data?.damage ?? 0) if weapon != 0 else a.valueOf("unarmeddamage"),
		weight = w.items.get(weapon)?.weight ?? 0.0,
		speed = data?.speed ?? 1.0,
		reach = (data?.reach ?? 0.0) * settings.gmst("fcombatdistance") if weapon != 0
		else race.reach,
		animation = data?.animation ?? 0,
		staggerPower = data?.stagger ?? 0.0,
		attackStaggers = race.strikeStaggers(weapon == 0),
		skill = sim.actorValueNames[data?.skill ?? 0].copy() if weapon != 0 else "",
		shield,
		shieldRating,
		armorRating = rating,
		armorPieces = pieces,
		lightWeight = light,
		heavyWeight = heavy,
		ai = a.aiOf(),
		style,
		essential = a.flags & actor.flagEssential != 0,
		protected = a.flags & actor.flagProtected != 0,
		at = f?.positionOf() ?? Vec3(0, 0, 0),
		facing = Vec3(1, 0, 0)
	)

# the AIDT the actor's values keep
pub fn aiOf(a sim.ActorState) actor.AiData:
	actor.AiData(
		aggression = i64(a.valueOf("aggression")),
		confidence = i64(a.valueOf("confidence")),
		energy = i64(a.valueOf("energy")),
		morality = i64(a.valueOf("morality")),
		mood = i64(a.valueOf("mood")),
		assistance = i64(a.valueOf("assistance"))
	)

pub fn isOut(f Fighter) bool:
	f.mode in [.Dead, .Fled, .Bleedout]

# whether it fights: it has a target and is not out of the fight
pub fn isFighting(f Fighter) bool:
	f.target != 0 and not f.isOut() and f.mode != .Alert and f.mode != .Idle
