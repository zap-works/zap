# What the game holds while it runs, as the scripts and the menus see it: the forms they name (the
# placed references with their state), the player, the game's clock, the quests' stages and the
# global variables; and the items: each item's data, the inventories of containers and actors,
# the actors' values, the crimes. build.zap fills it from the plugin; activate.zap and the
# Papyrus natives read and change it.

import skyrim.esm

# XLKR: a reference this one is linked to, under a keyword (0 for none)
pub type Link:
	keyword i64
	refId i64

# XTEL: where a load door leads, and the cell that holds that place (the world's grid cell for an
# exterior), which is not loaded: only the inn is
pub type Teleport:
	door i64   # the door at the other side
	position Vec3
	rotation Vec3
	world i64   # the worldspace, 0 for none found
	cell i64   # the cell, 0 for none found
	cellEditorId str = ""
	location str = ""   # the cell's location: its editor id and name
	placeName str = ""   # what the HUD calls the place: the cell's name, else its location's

# the id the game opens the place a load door leads to by: the exterior area around its place
# (esm.areaId) or the interior cell's editor id
pub fn placeId(t Teleport) str:
	if t.world != 0: return esm.areaAround(t.world, t.position).areaId()
	t.cellEditorId.copy()

# XLOC: a lock's level (0 to 100, 255 for one that needs its key) and key
pub type Lock:
	level i64
	key i64
	locked bool

pub type WorldForm:
	formId i64
	kind str   # the record type ("REFR", "ACHR", "QUST", ...)
	editorId str
	base i64   # a placed reference's base record, 0 for others
	enabled bool
	x f32
	y f32
	z f32
	baseKind str = ""   # the base record's type ("CONT", "DOOR", "WEAP", ...)
	rotation Vec3 = Vec3(0, 0, 0)   # radians, as the plugin places it
	scale f32 = 1.0
	cell i64 = 0   # the cell it is in, 0 for none (in an inventory, or not placed)
	count i64 = 1   # XCNT: how many of its item a loose reference is
	owner i64 = 0   # XOWN: an actor base or a faction; 0 for none, the cell's owner then
	links Link[] = []
	teleport Teleport? = none
	lock Lock? = none
	open bool = false   # a door's state
	harvested bool = false   # a harvestable's: picked until it respawns
	respawns bool = false   # a container's: its contents come back when the cell resets
	deleted bool = false
	motion i64 = 0   # SetMotionType's last value, 0 when no script set one
	blocked bool = false   # BlockActivation: the default activation does not run, only scripts
	location i64 = 0   # XLCN: the location (LCTN) a placed actor or object is in, 0 for none

# a theft or another crime, with the bounty it carries when it is reported
pub type Crime:
	kind str   # "steal"
	actor i64   # who did it
	refId i64   # the reference taken or taken from
	item i64
	count i64
	value i64   # the gold value of what was taken
	owner i64
	faction i64   # the crime faction it is reported to, 0 for none
	bounty i64

pub type GameWorld:
	forms {i64: WorldForm}
	player i64
	daysPassed f64   # the game's clock, in days since the game began
	playSeconds f64 = 0.0   # real seconds played, as the game counts them (a save's play time)
	timeScale f64   # game seconds per real second
	stages {i64: i64}   # a quest's current stage, by its form id
	stagesDone {i64: bool}   # a quest's stage done, by quest form id * 65536 + stage
	runningQuests {i64: bool}
	globals {i64: f32}
	notifications str[]   # what the scripts showed the player, in order
	soundAsks SoundAsk[] = []   # the sounds asked for and not yet played (uiSounds.zap)
	noticeTimes {str: f64} = {}   # when each notice with a sound was last shown, by its text (playSeconds)
	cell i64 = 0   # the cell the player is in
	difficulty i64 = 2   # the player's setting (iDifficulty), Adept: combat multiplies by difficultyMultipliers
	cellOwner i64 = 0   # its XOWN
	cellLocation i64 = 0   # its XLCN: where an actor in it is (GetCurrentLocation)
	shownMessages i64[] = []   # the MESG forms the scripts showed (Message.Show), in order
	items {i64: Item} = {}   # every item the world knows, by base form id
	spells {i64: Spell} = {}   # every spell the actors know, by form id
	magicEffects {i64: MagicEffect} = {}   # their magic effects
	projectiles {i64: Projectile} = {}   # and what those throw
	shouts {i64: Shout} = {}   # every shout the actors know, by form id
	inventories {i64: Inventory} = {}   # by the reference of the container or the actor
	actors {i64: ActorState} = {}   # by the actor's reference
	keywords {i64: i64[]} = {}   # the keywords (KWDA) of the base forms that are not items
	furniture {i64: Furniture} = {}   # by the furniture's base form id
	crimes Crime[] = []
	crimeValues {i64: CrimeValues} = {}   # by crime faction
	crimeFactions {i64: i64} = {}   # the crime faction a theft from this owner is reported to
	settings {str: f64} = {}   # the plugin's game settings by lower-case editor id
	dice esm.Dice = esm.Dice()   # the rolls the game makes as things happen
	nextFormId i64 = 0xFF00_0800   # the next id given to a reference made while the game runs
	events str[] = []   # what activations did, in order
	booksRead {i64: bool} = {}   # the books read, by base form id
	dialogueQuests {i64: i64} = {}   # the quest each dialogue response (INFO) said belongs to
	barterWith i64 = 0   # the merchant a script asked the barter menu for (ShowBarterMenu), 0 for none
	evaluate {i64: bool} = {}   # the actors whose packages EvaluatePackage asks the AI to pick again
	skillUses {str: SkillUse} = {}   # the skills' AVSK by actor value name (skills.zap)
	progress Progress = Progress()   # the player's skills' experience and the character's
	sleepWait SleepWait? = none   # the player's wait or sleep while it runs (sleepWait.zap)
	perks {i64: esm.Perk} = {}   # the perk records the actors' perks name, by form id (perks.zap)
	skillTrees {str: esm.SkillTree} = {}   # each skill's perk tree by actor value name
	unlearned i64[] = []   # the spells and perks scripts gave an actor before the world had their records
	stealth Stealth = Stealth()   # whether the player sneaks and who has detected him (stealth.zap)

# a world with only the player, at the start of the game's first day (8 in the morning)
pub fn newWorld() GameWorld:
	GameWorld(
		forms = {},
		player = 0x14,
		daysPassed = 8.0 / 24.0,
		timeScale = 20.0,
		stages = {},
		stagesDone = {},
		runningQuests = {},
		globals = {},
		notifications = []
	)

# adds the form with this id (enabled, at the origin) when the world does not know it yet
pub fn addForm(mut w GameWorld, formId i64):
	if w.forms.get(formId) != none: return
	w.forms[formId] = WorldForm(
		formId,
		kind = "",
		editorId = "",
		base = 0,
		enabled = true,
		x = 0.0,
		y = 0.0,
		z = 0.0
	)

pub fn editorIdOf(w GameWorld, formId i64) str:
	match w.forms.get(formId):
		f: f.editorId.copy()
		none: ""

# where a reference stands
pub fn positionOf(f WorldForm) Vec3:
	Vec3(f.x, f.y, f.z)

# the keywords of a base form: an item's, else those the world keeps for it
pub fn keywordsOf(w GameWorld, base i64) i64[]:
	if w.items.get(base) is item: return item.keywords.copy()
	(w.keywords.get(base) ?? []).copy()

# the reference linked from refId under the keyword (0 for the link without one), 0 for none
pub fn linkedRef(w GameWorld, refId i64, keyword i64) i64:
	f = w.forms.get(refId) ?? return 0
	(f.links.find(.keyword == keyword) ?? return 0).refId

# a new reference of the base placed at p, its id the next free one; the id
pub fn placeNew(mut w GameWorld, base i64, p Vec3, count i64) i64:
	id = w.nextFormId
	w.nextFormId += 1
	kind = (w.items.get(base) ?? return w.placeOther(id, base, p)).kind.recordType()
	w.forms[id] = WorldForm(
		formId = id,
		kind = "REFR",
		editorId = "",
		base,
		enabled = true,
		x = p.x,
		y = p.y,
		z = p.z,
		baseKind = kind,
		cell = w.cell,
		count
	)
	id

fn placeOther(mut w GameWorld, id i64, base i64, p Vec3):
	w.forms[id] = WorldForm(
		formId = id,
		kind = "REFR",
		editorId = "",
		base,
		enabled = true,
		x = p.x,
		y = p.y,
		z = p.z,
		cell = w.cell
	)
	id

# gives the reference an empty inventory when it has none
pub fn ensureInventory(mut w GameWorld, refId i64):
	if w.inventories.get(refId) == none: w.inventories[refId] = Inventory()

# the quest is at the stage, the stage done and the quest running
pub fn setStage(mut w GameWorld, quest i64, stage i64):
	w.stages[quest] = stage
	w.stagesDone[quest * 65_536 + stage] = true
	w.runningQuests[quest] = true

pub fn isStageDone(w GameWorld, quest i64, stage i64) bool:
	w.stagesDone.get(quest * 65_536 + stage) != none

# a line of what happened, kept in order
pub fn record(mut w GameWorld, line str):
	w.events.push(line.copy())
