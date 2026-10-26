# Finds records across the whole load order the game uses (skyrim/esm/loadOrder.zap): Skyrim.esm,
# Update.esm, the DLCs, the creation club's and the active plugins. Printed for each record found
# is the id the game shows, its type and editor id, then every plugin that has it in load order,
# the last one winning. Run from the repository root:
#
#   zap run projects/skyrim/esmInfo.zap --form 0x00013BBF          by the id the game shows
#   zap run projects/skyrim/esmInfo.zap --edid RiverwoodSleepingGiantInn [--type CELL]
#   zap run projects/skyrim/esmInfo.zap --field FULL=Orgnar --type NPC_ --fields
#       a field's text (any case; a localized plugin's FULL and SHRT by its strings table, when
#       the base game's archives hold it), or a number: a field's first u32, a form id as the game
#       shows it
#   zap run projects/skyrim/esmInfo.zap --order          the load order
#
# --type limits the search to one record type (much faster); --fields prints every field of each
# version; --install names another Data dir.

import skyrim
import skyrim.esm

# the top groups a record type lies in: placed things in cells and worlds, topics' lines in DIAL
fn groupsOfKind(kind str):
	if kind in [
		"REFR",
		"ACHR",
		"PGRE",
		"PHZD",
		"PARW",
		"PBAR",
		"PBEA",
		"PCON",
		"PFLA",
		"PMIS",
		"NAVM",
		"LAND",
		"CELL"
	]:
		return ["CELL", "WRLD"]
	if kind == "INFO": return ["DIAL"]
	[kind.copy()]

# the fields a localized plugin keeps as ids into its names table
namedTags = ["FULL", "SHRT"]

# the plugins in load order with their names tables (empty for a plugin not localized, or whose
# table no archive holds)
type Loaded:
	order esm.Plugin[]
	names skyrim.Strings[]

fn openLoaded(data str):
	order = esm.openLoadOrder(data)
	install = skyrim.openInstall(data) ?? fail
	names = []
	for p in order:
		empty = skyrim.Strings(texts = {})
		names.push(install.readNames(p.name) ?? empty if p.localized else empty)
	Loaded(order, names)

# the field's text: a localized name looked up, else the bytes up to their NUL
fn fieldText(l Loaded, k i64, body u8[], f esm.Field):
	if l.order[k].localized and f.tag in namedTags and f.size == 4:
		return (l.names[k].texts.get(i64(body.u32le(f.at))) ?? "").copy()
	body.cStringAt(f.at, f.size)

# the record types that carry no editor id, the bulk of what an editor id search would inflate
unnamedKinds = ["LAND", "NAVM"]

type Query:
	form i64?
	editorId str   # lower case, "" for any
	fieldTag str   # "" for any
	fieldText str   # lower case
	fieldNumber i64?
	kind str   # "" for any

fn queryOf():
	q = Query(
		form = none,
		editorId = "",
		fieldTag = "",
		fieldText = "",
		fieldNumber = none,
		kind = ""
	)
	if args.option("--form") is f:
		q.form = i64.parse(f) ?? i64.parse("0x{f}") ?? fail("--form {f}: give a hex id")
	if args.option("--edid") is e: q.editorId = e.lower()
	if args.option("--type") is t: q.kind = t.upper()
	if args.option("--field") is f:
		eq = f.indexOf("=") ?? fail("--field TAG=value")
		q.fieldTag = f[..eq].upper()
		q.fieldText = f[eq + 1..].lower()
		q.fieldNumber = i64.parse(f[eq + 1..])
	q

fn needsBody(q Query):
	not q.editorId.isEmpty or not q.fieldTag.isEmpty

fn fieldMatches(q Query, l Loaded, k i64, body u8[], f esm.Field):
	if q.fieldNumber is n:
		if f.size < 4: return false
		raw = i64(body.u32le(f.at))
		return raw == n or l.order.loadedId(k, raw) == n
	l.fieldText(k, body, f).lower() == q.fieldText

fn bodyMatches(q Query, l Loaded, k i64, body u8[]):
	fields = esm.fieldsOf(body)
	if not q.editorId.isEmpty and esm.textOf(body, fields, "EDID").lower() != q.editorId:
		return false
	if q.fieldTag.isEmpty: return true
	for f in fields:
		if f.tag == q.fieldTag and q.fieldMatches(l, k, body, f): return true
	false

# the top groups of the plugin a search reads
fn groupsToRead(p esm.Plugin, kind str):
	if kind.isEmpty: return p.esm.tops.copy()
	wanted = groupsOfKind(kind)
	p.esm.tops.filter(.kind in wanted)

# the ids the game shows of every record the query matches
fn matchingIds(q Query, l Loaded):
	order = l.order
	if q.form is f: return [f]
	found {i64: bool} = {}
	for k in 0..order.len:
		for g in order[k].groupsToRead(q.kind):
			d, records = order[k].esm.topRecords(g)
			for h in records:
				if not q.kind.isEmpty and h.kind != q.kind: continue
				if not q.editorId.isEmpty and h.kind in unnamedKinds: continue
				body = esm.recordBody(d, h.at, h.flags, h.span) ?? continue
				if q.bodyMatches(l, k, body): found[order.loadedId(k, h.formId)] = true
	found.keys().sorted()

fn printFields(body u8[], l Loaded, k i64):
	order = l.order
	for f in esm.fieldsOf(body):
		bytes = body[f.at..f.at + f.size]
		text = l.fieldText(k, body, f)
		if f.size == 4 and not text.isEmpty and f.tag in namedTags:
			print("    {f.tag} \"{text}\" (string 0x{bytes.u32le(0):08X})")
		elif f.size == 4:
			raw = i64(bytes.u32le(0))
			print("    {f.tag} 0x{raw:08X} (as a form: {order.loadedId(k, raw):08X})")
		elif f.size > 1 and text.len == f.size - 1 and text.bytes().all(it >= 0x20):
			print("    {f.tag} \"{text}\"")
		else:
			shown = bytes[..f.size.min(32)].map("{it:02X}").join(" ")
			print("    {f.tag} {f.size} bytes: {shown}{" ..." if f.size > 32 else ""}")

# every version of the records with these ids, plugin by plugin in load order
fn printVersions(ids i64[], l Loaded, kind str, withFields bool):
	order = l.order
	wanted {i64: i64} = {}
	for id in ids:
		wanted[id] = 0
	for k in 0..order.len:
		for g in order[k].groupsToRead(kind):
			d, records = order[k].esm.topRecords(g)
			for h in records:
				id = order.loadedId(k, h.formId)
				seen = wanted.get(id) ?? continue
				body = esm.recordBody(d, h.at, h.flags, h.span) ??
					fail("{order[k].name} {h.formId:08X}: {error}")
				editorId = esm.textOf(body, esm.fieldsOf(body), "EDID")
				role = "defines" if seen == 0 else "overrides"
				deleted = " deleted" if (h.flags & esm.flagDeleted) != 0 else ""
				compressed = " compressed" if (h.flags & esm.flagCompressed) != 0 else ""
				print("{id:08X} {h.kind} {editorId}: {role} in {order[k].name} as {h.formId:08X}{deleted}{compressed}")
				wanted[id] = seen + 1
				if withFields: printFields(body, l, k)
	for id in ids:
		if (wanted.get(id) ?? 0) == 0: print("{id:08X}: in no plugin")

args.options(
	[
		skyrim.installOption,
		ArgOption("--form", true, "the id the game shows, hex"),
		ArgOption("--edid", true, "an editor id"),
		ArgOption("--field", true, "TAG=value"),
		ArgOption("--type", true, "a record type"),
		ArgOption("--fields", false, "print every field"),
		ArgOption("--order", false, "print the load order")
	]
)
data = args.option("--install") ?? skyrim.defaultInstall
loaded = openLoaded(data)
if args.hasFlag("--order"):
	for p in loaded.order:
		place = "FE{p.place:03X}" if p.light else "{p.place:02X}"
		print("{place} {p.name}")
	return
query = queryOf()
if query.form == none and not query.needsBody():
	fail("give --form, --edid or --field\n{args.usage()}")
ids = query.matchingIds(loaded)
if ids.isEmpty:
	print("nothing matches")
	return
printVersions(ids, loaded, query.kind, args.hasFlag("--fields"))
