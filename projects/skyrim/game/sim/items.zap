# Items as the plugin defines them: the base records a reference or an inventory can hold, each
# with what the game reads of it: value, weight, keywords (KWDA), the name (FULL, an id in the
# strings table), and per kind its data. Layouts after UESP's Skyrim Mod File Format pages and
# xEdit's record definitions for the Special Edition: WEAP (DATA value, weight, damage; DNAM the
# animation type, speed, reach, the skill at 76, the stagger at 96; CRDT the critical damage, multiplier and effect),
# ARMO (DATA value, weight; DNAM the rating times 100; BOD2 the biped slots and the armor type;
# MODL its addons, ARMA), AMMO (DATA projectile, flags, damage, value, weight), BOOK (DESC its
# text; DATA flags, type, skill or spell, value, weight), ALCH (DATA weight; ENIT value and flags),
# INGR (DATA value, weight), MISC, KEYM and SLGM (DATA value, weight; SLGM's SOUL and SLCP), LIGH
# (base.zap's Light; flag 2 a light that is carried, a torch), the effects of potions and
# ingredients (EFID the magic effect, EFIT magnitude, area, duration), FLOR and TREE (PFIG what
# harvesting gives, PFPC its chance in spring, summer, autumn, winter).

import skyrim
import skyrim.esm
import skyrim.actor

# the record types an inventory holds
pub itemKinds = [
	"WEAP", "ARMO", "AMMO", "BOOK", "ALCH", "INGR", "MISC", "KEYM", "SLGM", "LIGH", "SCRL", "APPA"
]
# the record types harvested where they stand
pub harvestKinds = ["FLOR", "TREE"]

# WEAP DNAM's animation types, by number
pub weaponTypes = [
	"HandToHand", "OneHandSword", "OneHandDagger", "OneHandAxe", "OneHandMace", "TwoHandSword",
	"TwoHandAxe", "Bow", "Staff", "Crossbow"
]
twoHandedTypes = [5, 6, 7, 9]

# LIGH DATA's flag of a light an actor carries (a torch)
flagCarried = 0x2
# BOOK DATA's flags: it raises a skill, it teaches a spell
flagTeachesSkill = 0x1
flagTeachesSpell = 0x4
# ALCH ENIT's flags
pub flagFood = 0x2
pub flagPoison = 0x2_0000
# the biped slot of a shield, 39 (slot 30 is bit 0)
pub slotShield = 0x200

pub type Effect:
	effect i64   # the magic effect (MGEF)
	magnitude f32
	area i64
	duration i64   # seconds

pub type WeaponData:
	animation i64   # weaponTypes' index
	damage i64
	speed f32
	reach f32
	skill i64   # the actor value it trains, -1 for none
	critDamage i64
	critMult f32
	critEffect i64   # a spell, 0 for none
	twoHanded bool
	stagger f32 = 0.0   # DNAM at 96: how hard its power attacks stagger

pub type ArmorData:
	rating f32
	slots i64   # the biped slots it covers, slot 30 the lowest bit
	armorType i64   # 0 light, 1 heavy, 2 clothing
	addons i64[]   # its ARMA

pub type BookData:
	textId i64   # DESC: its text in the plugin's .DLSTRINGS
	flags i64
	skill i64   # the actor value it teaches when its flag says so, else -1
	spell i64   # the spell it teaches, 0 for none
	note bool = false   # DATA's type 255: a note or a scroll, one page at a time, else a book

pub type Harvest:
	gives esm.Counted[]   # PFIG as a new game's first roll gives it
	seasons i64[]   # the chance of a harvest in spring, summer, autumn, winter

pub type PotionData:
	effects Effect[]
	flags i64   # ENIT's flags
	useSound i64   # the sound (SNDR) of eating or drinking it, ENIT at 16

pub type SoulGemData:
	soul i64   # the soul it holds
	capacity i64   # the largest soul it takes

# what an item is by its record type, with the data of that kind alone
pub type ItemKind:
	Weapon(weapon WeaponData)
	Armor(armor ArmorData)
	Ammo(damage f32)
	Book(book BookData)
	Potion(potion PotionData)
	Ingredient(effects Effect[])
	Scroll(effects Effect[])
	Misc
	Key
	SoulGem(gem SoulGemData)
	Light(flags i64)   # LIGH's flags
	Apparatus
	Flora(harvest Harvest)
	Tree(harvest Harvest)

	# the record type the kind is made from
	fn recordType():
		match self:
			Weapon: "WEAP"
			Armor: "ARMO"
			Ammo: "AMMO"
			Book: "BOOK"
			Potion: "ALCH"
			Ingredient: "INGR"
			Scroll: "SCRL"
			Misc: "MISC"
			Key: "KEYM"
			SoulGem: "SLGM"
			Light: "LIGH"
			Apparatus: "APPA"
			Flora: "FLOR"
			Tree: "TREE"

pub type Item:
	formId i64
	kind ItemKind
	editorId str
	name str
	model str
	value i64
	weight f32
	keywords i64[]
	equipSlot str = ""   # ETYP's editor id: RightHand, LeftHand, EitherHand, BothHands, Shield...

fn u32Of(r esm.Record, tag str, offset i64) i64:
	at = esm.dataOf(r.fields, tag) ?? return 0
	r.body.u32le(at + offset)

fn u8Of(r esm.Record, tag str, offset i64) i64:
	at = esm.dataOf(r.fields, tag) ?? return 0
	r.body[at + offset]

fn f32Of(r esm.Record, tag str, offset i64) f32:
	at = esm.dataOf(r.fields, tag) ?? return 0.0
	r.body.f32le(at + offset)

fn effectsOf(r esm.Record):
	out = []
	for f in r.fields:
		if f.tag == "EFID" and f.size >= 4:
			out.push(Effect(effect = r.body.u32le(f.at), magnitude = 0.0, area = 0, duration = 0))
		if f.tag == "EFIT" and f.size >= 12 and not out.isEmpty:
			last = out.len - 1
			out[last].magnitude = r.body.f32le(f.at)
			out[last].area = r.body.u32le(f.at + 4)
			out[last].duration = r.body.u32le(f.at + 8)
	out

fn weaponOf(r esm.Record):
	animation = r.u8Of("DNAM", 0)
	crit = r.fields.find(.tag == "CRDT") ?? esm.Field(tag = "CRDT", at = 0, size = 0)
	hasCrit = crit.size >= 16
	WeaponData(
		animation,
		damage = r.body.u16le((esm.dataOf(r.fields, "DATA") ?? 0) + 8),
		speed = r.f32Of("DNAM", 4),
		reach = r.f32Of("DNAM", 8),
		skill = i32(r.u32Of("DNAM", 76)),
		critDamage = r.body.u16le(crit.at) if hasCrit else 0,
		critMult = r.body.f32le(crit.at + 4) if hasCrit else 0.0,
		critEffect = r.body.u32le(crit.at + (16 if crit.size >= 24 else 12)) if hasCrit else 0,
		twoHanded = animation in twoHandedTypes,
		stagger = r.f32Of("DNAM", 96)
	)

fn armorOf(r esm.Record):
	modern = esm.dataOf(r.fields, "BOD2") != none
	ArmorData(
		rating = f32(r.u32Of("DNAM", 0)) / 100.0,
		slots = r.u32Of("BOD2", 0) if modern else r.u32Of("BODT", 0),
		armorType = r.u32Of("BOD2", 4) if modern else r.u32Of("BODT", 8),
		addons = esm.formsOf(r.body, r.fields, "MODL")
	)

fn bookOf(r esm.Record):
	flags = r.u8Of("DATA", 0)
	teaches = r.u32Of("DATA", 4)
	BookData(
		textId = r.u32Of("DESC", 0),
		flags,
		skill = i32(teaches) if (flags & flagTeachesSkill) != 0 else -1,
		spell = teaches if (flags & flagTeachesSpell) != 0 else 0,
		note = r.u8Of("DATA", 1) == 255
	)

fn harvestOf(mut plugin esm.Esm, r esm.Record):
	dice = esm.Dice()
	gives esm.Counted[] = []
	for c in plugin.leveledCounts(r.formOf("PFIG") ?? 0, 1, actor.newGameLevel, dice):
		at = -1
		for k, g in gives:
			if g.form == c.form: at = k
		if at < 0:
			gives.push(c.copy())
		else:
			gives[at].count += c.count
	at = esm.dataOf(r.fields, "PFPC")
	seasons = (0..4).map(r.u8Of("PFPC", it)) if at != none else [100, 100, 100, 100]
	Harvest(gives, seasons)

# the record's value and weight as its kind lays them out
fn valueWeight(r esm.Record, light esm.Light):
	match r.kind:
		"AMMO": (r.u32Of("DATA", 12), r.f32Of("DATA", 16))
		"BOOK": (r.u32Of("DATA", 8), r.f32Of("DATA", 12))
		"ALCH": (r.u32Of("ENIT", 0), r.f32Of("DATA", 0))
		"LIGH": (light.value, light.weight)
		"FLOR", "TREE": (0, 0.0)
		_: (r.u32Of("DATA", 0), r.f32Of("DATA", 4))

fn equipSlotOf(mut plugin esm.Esm, r esm.Record):
	slot = r.formOf("ETYP") ?? return ""
	e = plugin.recordOf(slot) ?? return ""
	esm.textOf(e.body, e.fields, "EDID")

# the record's kind with its data
fn kindOf(mut plugin esm.Esm, r esm.Record, light esm.Light) ItemKind:
	match r.kind:
		"WEAP": .Weapon(r.weaponOf())
		"ARMO": .Armor(r.armorOf())
		"AMMO": .Ammo(r.f32Of("DATA", 8))
		"BOOK": .Book(r.bookOf())
		"ALCH": .Potion(
			PotionData(
				effects = r.effectsOf(),
				flags = r.u32Of("ENIT", 4),
				useSound = r.u32Of("ENIT", 16)
			)
		)
		"INGR": .Ingredient(r.effectsOf())
		"SCRL": .Scroll(r.effectsOf())
		"KEYM": .Key
		"SLGM": .SoulGem(SoulGemData(soul = r.u8Of("SOUL", 0), capacity = r.u8Of("SLCP", 0)))
		"LIGH": .Light(light.flags)
		"APPA": .Apparatus
		"FLOR": .Flora(plugin.harvestOf(r))
		"TREE": .Tree(plugin.harvestOf(r))
		_: .Misc

# a light's data, all zero for a form that is no light
fn lightOf(mut plugin esm.Esm, formId i64):
	if plugin.baseRecord(formId) is b:
		if b.light is l: return l.copy()
	esm.Light(
		time = 0,
		radius = 0,
		color = esm.Color(r = 0, g = 0, b = 0),
		flags = 0,
		falloff = 0.0,
		fov = 0.0,
		nearClip = 0.0,
		flickerPeriod = 0.0,
		flickerIntensity = 0.0,
		flickerMovement = 0.0,
		fade = 0.0,
		value = 0,
		weight = 0.0,
		flickerPeriod = 0.0,
		flickerIntensity = 0.0,
		flickerMovement = 0.0
	)

# The item with this form id as the plugin defines it, its name from the strings table `names`;
# none when the form is no item (nor a harvestable).
pub fn itemOf(mut plugin esm.Esm, names skyrim.Strings, formId i64) Item?:
	r = try plugin.recordOf(formId)
	if r.kind not in itemKinds and r.kind not in harvestKinds: return none
	light = plugin.lightOf(formId)
	value, weight = r.valueWeight(light)
	Item(
		formId,
		kind = plugin.kindOf(r, light),
		editorId = esm.textOf(r.body, r.fields, "EDID"),
		name = names.localText(r, "FULL"),
		model = esm.textOf(r.body, r.fields, "MOD2" if r.kind == "ARMO" else "MODL"),
		value,
		weight,
		keywords = esm.formsOf(r.body, r.fields, "KWDA"),
		equipSlot = plugin.equipSlotOf(r)
	)

# whether an actor can take the item into an inventory: every item but a light that is not carried
pub fn isCarried(item Item) bool:
	if item.kind.Light is flags: return (flags & flagCarried) != 0
	item.plantHarvest() == none

# the effects of a potion, an ingredient or a scroll, none for the rest
pub fn effects(item Item) Effect[]:
	match item.kind:
		Potion(p): p.effects.copy()
		Ingredient(e), Scroll(e): e.copy()
		_: []

# what harvesting a flora or a tree gives
pub fn plantHarvest(item Item) Harvest?:
	if item.kind.Flora is h: return h.copy()
	if item.kind.Tree is h: return h.copy()
	none

# AlchemyItem::IsFood (0x1401468b0): the food flag and no poison flag
pub fn isFood(item Item) bool:
	if item.kind.Potion is p: return (p.flags & flagFood) != 0 and (p.flags & flagPoison) == 0
	false

pub fn isPoison(item Item) bool:
	if item.kind.Potion is p: return (p.flags & flagPoison) != 0
	false

pub fn isShield(item Item) bool:
	item.equipSlot == "Shield" or ((item.kind.Armor?.slots ?? 0) & slotShield) != 0

pub fn isTwoHanded(item Item) bool:
	item.kind.Weapon?.twoHanded ?? false

pub fn weaponTypeName(item Item) str:
	animation = (item.kind.Weapon ?? return "").animation
	weaponTypes[animation].copy() if animation >= 0 and animation < weaponTypes.len
		else "type {animation}"
