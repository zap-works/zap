# Looks a function up in a decompiler's export and prints its text, its community name, its
# callers and callees and the strings it reads. The export is a dir laid out as Ghidra's
# ExportAll.java writes it: index.tsv (entry, name, bytes, shard), names.tsv (entry, id, source,
# name, ghidra), calls.tsv (caller, callee, at), strings.tsv (address, readers, value) and
# functions/<shard>.c, each function under a line `// ==== <entry> <name> ====`. Run from the
# repository root:
#
#   zap run projects/recomp/tools/decompInfo.zap 0x140001160          by address, or one inside it
#   zap run projects/recomp/tools/decompInfo.zap PlayerCharacter::Update      by name, or part of one
#   zap run projects/recomp/tools/decompInfo.zap 0x140001160 --dir <export> --no-text
#
# The export defaults to SkyrimSE.exe's, C:/tools/skyrim-decomp.

import fs

defaultDir = "C:/tools/skyrim-decomp"
maxMatches = 40

type Function:
	entry i64
	name str
	bytes i64
	shard str

type Export:
	dir str
	functions Function[]   # in index.tsv's order, by entry
	byEntry {i64: i64}   # entry -> index in functions
	names {i64: str}   # entry -> community name

# the lines of a TSV file, the header line left out
fn rowsOf(path str):
	text = fs.readFile(path) ?? fail("cannot read {path}")
	lines = text.lines()
	lines.remove(0)
	lines

fn parseAddress(s str):
	if s.startsWith("0x") or s.startsWith("0X"): return i64.parse(s)
	none

fn openExport(dir str):
	functions = []
	byEntry {i64: i64} = {}
	for line in rowsOf("{dir}/index.tsv"):
		row = line.split("	")
		entry = parseAddress(row[0]) ?? continue
		byEntry[entry] = functions.len
		functions.push(
			Function(
				entry,
				name = row[1].copy(),
				bytes = i64.parse(row[2]) ?? 0,
				shard = row[3].copy()
			)
		)
	names {i64: str} = {}
	if fs.exists("{dir}/names.tsv"):
		for line in rowsOf("{dir}/names.tsv"):
			row = line.split("	")
			if parseAddress(row[0]) is entry: names[entry] = row[3]
	Export(dir.copy(), functions, byEntry, names)

# the function's community name, else the decompiler's
fn label(x Export, entry i64):
	if x.names.get(entry) is name: return name.copy()
	if x.byEntry.get(entry) is k: return x.functions[k].name.copy()
	"?"

# the functions the query names: the one at an address or holding it, else those whose name is
# the query, else those whose name holds it
fn matching(x Export, query str):
	if parseAddress(query) is at:
		if at in x.byEntry: return [at]
		for f in x.functions:
			if f.entry <= at and at < f.entry + f.bytes: return [f.entry]
		return []
	exact = []
	partial = []
	for f in x.functions:
		community = x.names.get(f.entry) ?? ""
		if f.name == query or community == query: exact.push(f.entry)
		elif query in f.name or query in community: partial.push(f.entry)
	if not exact.isEmpty: return exact
	partial

# the text of the function at `entry` in its shard
fn textOf(x Export, f Function):
	path = "{x.dir}/functions/{f.shard}.c"
	text = fs.readFile(path) ?? return "(no {path})"
	marker = "// ==== 0x{f.entry:x} "
	start = text.indexOf(marker) ?? return "(no text for 0x{f.entry:x} in {path})"
	end = text.indexOf("// ==== ", start + marker.len) ?? text.len
	text[start..end].trimmedEnd().copy()

fn printCalls(x Export, entry i64):
	callers i64[] = []
	callees i64[] = []
	for line in rowsOf("{x.dir}/calls.tsv"):
		row = line.split("	")
		caller = parseAddress(row[0]) ?? continue
		callee = parseAddress(row[1]) ?? continue
		if callee == entry and caller not in callers: callers.push(caller)
		if caller == entry and callee not in callees: callees.push(callee)
	print("callers ({callers.len}):")
	for c in callers:
		print("  0x{c:x} {x.label(c)}")
	print("callees ({callees.len}):")
	for c in callees:
		print("  0x{c:x} {x.label(c)}")

fn printStrings(x Export, entry i64):
	path = "{x.dir}/strings.tsv"
	if not fs.exists(path): return
	wanted = "0x{entry:x}"
	read = []
	for line in rowsOf(path):
		row = line.split("	")
		if row.len >= 3 and wanted in row[1].split(","): read.push("  {row[0]} {row[2]}")
	print("strings ({read.len}):")
	for line in read:
		print(line)

fn printFunction(x Export, entry i64, withText bool):
	k = x.byEntry.get(entry) ?? return
	f = x.functions[k]
	community = x.names.get(entry) ?? "(none)"
	print("0x{entry:x} {f.name}, {f.bytes} bytes, shard {f.shard}")
	print("community name: {community}")
	x.printCalls(entry)
	x.printStrings(entry)
	if withText: print(x.textOf(f))

args.options(
	[
		ArgOption("--dir", true, "the export's dir"),
		ArgOption("--no-text", false, "leave the function's text out")
	]
)
query = args.positional()
if query.isEmpty: fail("give a function's address (0x...) or name\n{args.usage()}")
export = openExport(args.option("--dir") ?? defaultDir)
found = export.matching(query[0])
if found.isEmpty: fail("no function {query[0]} in {export.dir}")
if found.len > 1:
	print("{found.len} functions match {query[0]}:")
	for e in found[..found.len.min(maxMatches)]:
		print("  0x{e:x} {export.label(e)}")
	return
export.printFunction(found[0], not args.hasFlag("--no-text"))
