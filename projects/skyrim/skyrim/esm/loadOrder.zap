# The plugins in the order the game loads them: Skyrim.esm, Update.esm and the three DLCs, then
# the creation club's (Skyrim.ccc beside the Data dir), then those Plugins.txt marks active (`*`),
# each kept when the Data dir has it; masters (the ESM flag, .esm, .esl) go before the rest. A
# record's form id names its owner by its top byte, an index into the plugin's masters (MAST),
# the plugin itself past them; the id the game shows is the owner's place in the order then the
# low bytes: 00..FD for a full plugin, FE then 12 bits of place for a light one (ESL).

import fs

implicitPlugins = ["Skyrim.esm", "Update.esm", "Dawnguard.esm", "HearthFires.esm", "Dragonborn.esm"]
flagMaster = 0x1
flagLight = 0x200
flagLocalized = 0x80

pub type Plugin:
	name str
	esm Esm
	masters str[]
	master bool
	light bool
	localized bool   # its names and descriptions are ids into its strings tables
	place i64   # among the full plugins, or among the light ones
	owners i64[]   # the load order's index of each master, then of the plugin itself

# the plugin names a list file holds, one a line, `#` lines left out; `activeOnly` keeps the
# lines Plugins.txt marks with `*`
fn namesIn(path str, activeOnly bool):
	text = fs.readFile(path) ?? return []
	out = []
	for line in text.lines():
		name = line.trimmed()
		if name.isEmpty or name.startsWith("#"): continue
		if activeOnly:
			if not name.startsWith("*"): continue
			out.push(name[1..].copy())
		else:
			out.push(name.copy())
	out

# the names of the plugins of the Data dir `data` in the game's order, as its files spell them
pub fn loadOrder(data str) str[]:
	present {str: str} = {}
	for name in fs.list(data) ?? []:
		present[name.lower()] = name.copy()
	listed = implicitPlugins.copy()
	club = namesIn("{fs.dirOf(data)}/Skyrim.ccc", false)
	if club.isEmpty:
		# a Data dir copied without the install's Skyrim.ccc: its creation club plugins by name
		club = present.values().filter(.lower().startsWith("cc")).sorted()
	listed.extend(club)
	local = env.get("LOCALAPPDATA") ?? ""
	listed.extend(namesIn("{local}/Skyrim Special Edition/Plugins.txt", true))
	out = []
	seen {str: bool} = {}
	for name in listed:
		key = name.lower()
		if key in seen: continue
		seen[key.copy()] = true
		if present.get(key) is file: out.push(file.copy())
	out

# the TES4 record's flags and masters
fn headerOf(e Esm):
	raw = e.file.readAt(0, headerSize) ?? fail("{e.path}: no header")
	span = headerSize + raw.u32le(4)
	d = e.file.readAt(0, span) ?? fail("{e.path}: the header is cut short")
	body = d[headerSize..span].copy()
	masters = []
	for f in fieldsOf(body):
		if f.tag == "MAST": masters.push(body.cStringAt(f.at))
	(raw.u32le(8), masters)

fn openPlugin(data str, name str):
	e = openEsm("{data}/{name}") ?? fail
	flags, masters = e.headerOf()
	lower = name.lower()
	light = (flags & flagLight) != 0 or lower.endsWith(".esl")
	master = light or (flags & flagMaster) != 0 or lower.endsWith(".esm")
	localized = (flags & flagLocalized) != 0
	Plugin(name = name.copy(), esm = e, masters, master, light, localized, place = 0, owners = [])

# the plugins of the Data dir `data` opened in the game's order, masters first, each with its
# place and its masters found
pub fn openLoadOrder(data str) Plugin[]:
	names = loadOrder(data)
	if names.isEmpty: fail("no plugins in {data}: give the Data dir of your Skyrim install")
	masters = names.filter(openPlugin(data, it).master)
	order = masters.map(openPlugin(data, it))
	for name in names:
		if name not in masters: order.push(openPlugin(data, name))
	index {str: i64} = {}
	full = 0
	light = 0
	for k in 0..order.len:
		index[order[k].name.lower()] = k
		if order[k].light:
			order[k].place = light
			light += 1
		else:
			order[k].place = full
			full += 1
	for k in 0..order.len:
		owners = order[k].masters.map(
			index.get(.lower()) ?? fail("{order[k].name} needs {it}, not loaded")
		)
		owners.push(k)
		order[k].owners = owners
	order

# the id the game shows for the form id `local` as the plugin at `k` of the order writes it
pub fn loadedId(order Plugin[], k i64, local i64) i64:
	p = order[k]
	top = local >> 24
	owner = order[p.owners[top.min(len - 1)]]
	if owner.light: return 0xFE00_0000 | (owner.place << 12) | (local & 0xFFF)
	(owner.place << 24) | (local & 0xFF_FFFF)
