# The per-bank tables of the cartridge's structure (DKC1Recomp's form, projects/dkc/README.md, `tables/`),
# a line a record, its kind first. Read here: `bank = 0x80` (the bank of the
# records after it), `data_region <bank> <from> <to>` (bytes inside a code bank that are no code,
# `to` excluded), `func <name> <pc> end:<pc> entry_mx:<m>,<x>` (a function, the bytes to its end
# its own), `exit_mx_at <address> <m> <x>` (the widths its returns leave), `indirect_dispatch <pc>
# <count> ptrtail|ptrcall [return:<pc> frame:<n>] targets:<address>,...` (a jump or call through
# memory and where it goes; the return a phk and pea pushed before it the flow finds itself)
# and `auto_vectors` (the cartridge's interrupt vectors are entries). Addresses are hex, a bank's pc
# 16 bits, a long one 24.

import fs

pub type CfgFunction:
	name str
	at i64
	end i64
	m bool
	x bool

# a jump (ptrtail) or a call (ptrcall) through memory, and where it goes
pub type Dispatch:
	at i64
	calls bool
	targets i64[]

# bytes of a code bank that are no code, [from, to) as long addresses
pub type Region:
	from i64
	to i64

pub type Cfg:
	functions CfgFunction[]
	dataRegions Region[]
	exits {i64: Widths}   # a function's address to the widths it returns with
	starts {i64: Widths}   # a function's address to the widths it is entered in
	dispatches {i64: Dispatch}   # by the jump's address
	vectors bool

	fn read(text str):
		bank = 0
		for line in text.lines():
			parts = line.words()
			if parts.isEmpty or parts[0].startsWith("#"): continue
			match parts[0]:
				"bank": bank = i64.parse(parts[2]) ?? fail("bad bank in '{line}'")
				"auto_vectors": vectors = true
				"data_region":
					b = hexOf(parts[1], line) << 16
					dataRegions.push(
						Region(from = b | hexOf(parts[2], line), to = b | hexOf(parts[3], line))
					)
				"func":
					f = functionOf(parts, bank, line)
					starts[f.at] = Widths(e = false, m = f.m, x = f.x)
					functions.push(f)
				"exit_mx_at":
					exits[hexOf(parts[1], line)] = Widths(
						e = false,
						m = flagOf(parts[2], line),
						x = flagOf(parts[3], line)
					)
				"indirect_dispatch":
					at = (bank << 16) | hexOf(parts[1], line)
					listed = parts.filter(.startsWith("targets:")).first ??
						fail("no targets in '{line}'")
					targets = listed["targets:".len..]
						.split(",")
						.map(hexOf(it, line))
					calls = parts[3] == "ptrcall"
					if dispatches.get(at) is known:
						merged = known.targets.copy()
						merged.extend(targets.filter(not (it in known.targets)))
						targets = merged
						calls = known.calls
					dispatches[at] = Dispatch(at, calls, targets)
				_: pass

fn hexOf(text str, line str):
	i64.parse("0x{text}") ?? fail("bad number '{text}' in '{line}'")

fn flagOf(text str, line str):
	match text:
		"0": false
		"1": true
		_: fail("bad flag '{text}' in '{line}'")

# every bank*.cfg of the dir, then played.cfg (the targets tools/oracle.lua's played mode saw the game's jumps
# through memory take in Mesen 2, which add to those the bank's table names), read
pub fn readCfg(dir str) Cfg:
	cfg = Cfg(
		functions = [],
		dataRegions = [],
		exits = {},
		starts = {},
		dispatches = {},
		vectors = false
	)
	names = (
		fs.list(dir) ?? fail("cannot read {dir}: {error}")
	).filter(.startsWith("bank") and .endsWith(".cfg"))
	files = names.sorted()
	if fs.exists("{dir}/played.cfg"): files.push("played.cfg")
	for name in files:
		cfg.read(fs.readFile("{dir}/{name}") ?? fail("cannot read {dir}/{name}: {error}"))
	if cfg.functions.isEmpty: cfg.vectors = true
	cfg

# no tables: the cartridge's vectors are the entries, the rest found from them
pub fn vectorsOnly() Cfg:
	Cfg(functions = [], dataRegions = [], exits = {}, starts = {}, dispatches = {}, vectors = true)

fn functionOf(parts str[], bank i64, line str):
	widths = parts[4]["entry_mx:".len..].split(",")
	CfgFunction(
		name = parts[1].copy(),
		at = (bank << 16) | hexOf(parts[2], line),
		end = (bank << 16) | hexOf(parts[3]["end:".len..], line),
		m = flagOf(widths[0], line),
		x = flagOf(widths[1], line)
	)
