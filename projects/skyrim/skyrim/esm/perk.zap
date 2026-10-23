# Perks (PERK) and the skills' perk trees (the nodes inside AVIF), as SkyrimSE.exe 1.7.104 reads
# them (BGSPerk::Load 0x140396cc0, reference/exe/README.md, "Perks and their entry points"). A perk
# is its name and description, the conditions that say who may take it (the CTDAs before DATA), DATA
# (trait, minimum level, ranks, playable, hidden), NNAM the perk that follows it in its chain (each
# rank of a tree's perk is a record of its own), and then its entries, each opened by PRKE (type,
# rank, priority) and closed by PRKF: a quest entry (DATA: the quest, its stage), an ability entry
# (DATA: the spell) or an entry point (DATA: the entry point, the function, the number of
# parameters; PRKC starts the conditions of one parameter; EPFT the type of the function's data and
# EPFD the data). Layout after UESP's Skyrim Mod File Format (PERK, AVIF).

pub entryQuest = 0
pub entryAbility = 1
pub entryPoint = 2

pub type PerkTab:
	index i64   # the parameter the conditions are asked about (0 the perk's owner)
	conditions Condition[]

pub type PerkEntry:
	kind i64
	rank i64   # the entry applies at the perk's rank rank + 1
	priority i64
	form i64 = 0   # the quest, the ability spell, or what EPFD names
	stage i64 = 0
	point i64 = 0   # the entry point
	function i64 = 0   # 1 set, 2 add, 3 multiply, 4 add range, 5 add AV mult, 6 absolute, ...
	parameters i64 = 0   # the entry point's number of parameters, the owner first
	tabs PerkTab[] = []
	dataType i64 = 0   # EPFT: 1 one value, 2 two values, 3 a leveled list, 5 a spell...
	values f32[] = []
	label str = ""

pub type Perk:
	formId i64
	editorId str
	conditions Condition[]   # who may take it
	trait bool
	minLevel i64
	ranks i64
	playable bool
	hidden bool
	next i64   # the next perk of its chain, 0 for none
	entries PerkEntry[]
	name str = ""   # filled from the strings table where the game has one
	description str = ""

# a node of a skill's perk tree
pub type SkillNode:
	index i64
	perk i64   # 0 for the tree's root
	x i64
	y i64
	horizontal f32
	vertical f32
	skill i64   # the skill's AVIF
	children i64[]

pub type SkillTree:
	skill i64   # the AVIF
	editorId str
	nodes SkillNode[]

fn byteAt(body u8[], at i64) i64:
	body[at]

# the data of a PRKE section's function, EPFD, by its type EPFT
fn dataValues(body u8[], f Field, dataType i64):
	if dataType == 1 and f.size >= 4: return [body.f32le(f.at)]
	if dataType == 2 and f.size >= 8: return [body.f32le(f.at), body.f32le(f.at + 4)]
	[]

# the entry the PRKE field at fields[k] opens: it reads on to PRKF
fn entryAt(body u8[], fields Field[], k i64):
	head = fields[k]
	e = PerkEntry(
		kind = body.byteAt(head.at),
		rank = body.byteAt(head.at + 1),
		priority = body.byteAt(head.at + 2)
	)
	at = k + 1
	while at < fields.len and fields[at].tag != "PRKF":
		f = fields[at]
		match f.tag:
			"DATA":
				if e.kind == entryQuest:
					e.form = body.u32le(f.at)
					e.stage = body.byteAt(f.at + 4)
				elif e.kind == entryAbility:
					e.form = body.u32le(f.at)
				else:
					e.point = body.byteAt(f.at)
					e.function = body.byteAt(f.at + 1)
					e.parameters = body.byteAt(f.at + 2)
			"PRKC":
				e.tabs.push(PerkTab(index = body[f.at], conditions = []))
			"CTDA":
				if f.size >= 28 and not e.tabs.isEmpty:
					e.tabs[len - 1].conditions.push(conditionAt(body, f.at, f.size))
			"CIS1":
				if not e.tabs.isEmpty and not e.tabs[len - 1].conditions.isEmpty:
					last = e.tabs[len - 1].conditions.len - 1
					e.tabs[len - 1].conditions[last].text1 = body.cStringAt(f.at)
			"CIS2":
				if not e.tabs.isEmpty and not e.tabs[len - 1].conditions.isEmpty:
					last = e.tabs[len - 1].conditions.len - 1
					e.tabs[len - 1].conditions[last].text2 = body.cStringAt(f.at)
			"EPFT":
				e.dataType = body.byteAt(f.at)
			"EPFD":
				e.values = body.dataValues(f, e.dataType)
				if e.dataType in [3, 5] and f.size >= 4: e.form = body.u32le(f.at)
			"EPF2":
				e.label = body.cStringAt(f.at)
			_: pass
		at += 1
	(e, at)

# the perk with this form id, none when it is no PERK
pub fn perkOf(mut e Esm, formId i64) Perk?:
	r = try e.recordOf(formId)
	if r.kind != "PERK": return none
	p = Perk(
		formId,
		editorId = textOf(r.body, r.fields, "EDID"),
		conditions = [],
		trait = false,
		minLevel = 0,
		ranks = 1,
		playable = true,
		hidden = false,
		next = r.formOf("NNAM") ?? 0,
		entries = []
	)
	k = 0
	while k < r.fields.len:
		f = r.fields[k]
		match f.tag:
			"CTDA":
				if f.size >= 28 and p.entries.isEmpty:
					p.conditions.push(conditionAt(r.body, f.at, f.size))
			"CIS2":
				if not p.conditions.isEmpty and p.entries.isEmpty:
					p.conditions[len - 1].text2 = r.body.cStringAt(f.at)
			"DATA":
				if p.entries.isEmpty and f.size >= 5:
					p.trait = r.body[f.at] != 0
					p.minLevel = r.body[f.at + 1]
					p.ranks = r.body[f.at + 2]
					p.playable = r.body[f.at + 3] != 0
					p.hidden = r.body[f.at + 4] != 0
			"PRKE":
				entry, end = entryAt(r.body, r.fields, k)
				p.entries.push(entry)
				k = end
			_: pass
		k += 1
	p

# the perk tree inside an AVIF record: its nodes (PNAM opens one, INAM closes it with its index);
# none when the record has none
pub fn skillTreeOf(mut e Esm, formId i64) SkillTree?:
	r = try e.recordOf(formId)
	if r.kind != "AVIF": return none
	tree = SkillTree(skill = formId, editorId = textOf(r.body, r.fields, "EDID"), nodes = [])
	started = false
	node = SkillNode(index = 0, perk = 0, x = 0, y = 0, horizontal = 0.0, vertical = 0.0, skill = 0,
		children = [])
	for f in r.fields:
		if f.tag == "PNAM" and f.size >= 4:
			started = true
			node = SkillNode(
				index = 0,
				perk = r.body.u32le(f.at),
				x = 0,
				y = 0,
				horizontal = 0.0,
				vertical = 0.0,
				skill = 0,
				children = []
			)
		elif not started:
			continue
		elif f.tag == "XNAM": node.x = r.body.u32le(f.at)
		elif f.tag == "YNAM": node.y = r.body.u32le(f.at)
		elif f.tag == "HNAM": node.horizontal = r.body.f32le(f.at)
		elif f.tag == "VNAM": node.vertical = r.body.f32le(f.at)
		elif f.tag == "SNAM": node.skill = r.body.u32le(f.at)
		elif f.tag == "CNAM": node.children.push(r.body.u32le(f.at))
		elif f.tag == "INAM":
			node.index = r.body.u32le(f.at)
			tree.nodes.push(node.copy())
			started = false
	if tree.nodes.isEmpty: return none
	tree
