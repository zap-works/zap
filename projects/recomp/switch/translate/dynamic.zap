# What a module's dynamic section (MOD0's first offset) says of its code before the loader runs:
# the code addresses its relocations store (R_AARCH64_RELATIVE's addends in .rela.dyn, the words
# RELR marks, both holding offsets from the module's start: vtables and callbacks) and its symbols
# of type function. Each a function's start, as SavageWindRecomp finds them.

import recomp.switch.cpu.core

dtHash = 4
dtStrtab = 5
dtSymtab = 6
dtRela = 7
dtRelasz = 8
dtRelrsz = 35
dtRelr = 36
relative = 1027   # R_AARCH64_RELATIVE

fn quad(at i64) i64:
	i64(core.memory.load(at, 3))

# the dynamic section's values by tag, each an offset from the module's start
fn dynamicTags(moduleAt i64):
	tags {i64: i64} = {}
	m = mod0(moduleAt) ?? return tags
	at = m + signedWord(m + 4)
	while quad(at) != 0:
		tags[quad(at)] = quad(at + 8)
		at += 16
	tags

# The places in [moduleAt, textEnd) the module's relocations and symbols name as code: function
# starts.
pub fn dynamicStarts(moduleAt i64, textEnd i64) i64[]:
	tags = dynamicTags(moduleAt)
	out = []
	inText = (offset i64): offset > 0 and moduleAt + offset < textEnd and offset % 4 == 0
	rela = tags.get(dtRela) ?? 0
	for k in 0..(tags.get(dtRelasz) ?? 0) / 24:
		entry = moduleAt + rela + k * 24
		if quad(entry + 8) & 0xFFFF_FFFF == relative and inText(quad(entry + 16)):
			out.push(moduleAt + quad(entry + 16))
	for offset in relrPlaces(moduleAt, tags):
		if inText(quad(moduleAt + offset)): out.push(moduleAt + quad(moduleAt + offset))
	symtab = tags.get(dtSymtab) ?? 0
	for k in 0..symbolCount(moduleAt, tags):
		sym = moduleAt + symtab + k * 24
		isFunction = core.memory.load(sym + 4, 0) & 0xF == 2
		if isFunction and core.memory.load(sym + 6, 1) != 0 and inText(quad(sym + 8)):
			out.push(moduleAt + quad(sym + 8))
	out

# the offsets of the words RELR relocates: an even entry a word's offset, an odd one a bitmap of
# the 63 words after the last
fn relrPlaces(moduleAt i64, tags {i64: i64}):
	out = []
	at = moduleAt + (tags.get(dtRelr) ?? 0)
	next = 0
	for k in 0..(tags.get(dtRelrsz) ?? 0) / 8:
		e = quad(at + k * 8)
		if e & 1 == 0:
			out.push(e)
			next = e + 8
			continue
		for b in 1..64:
			if (e >> b) & 1 != 0: out.push(next + (b - 1) * 8)
		next += 63 * 8
	out

# how many symbols .dynsym holds: DT_HASH's chain length, else the room up to .dynstr
fn symbolCount(moduleAt i64, tags {i64: i64}):
	if tags.get(dtHash) is hash: return word(moduleAt + hash + 4)
	symtab = tags.get(dtSymtab) ?? return 0
	strtab = tags.get(dtStrtab) ?? return 0
	(strtab - symtab) / 24 if strtab > symtab else 0

# the module's named symbols by address (.dynsym with .dynstr: the sdk's are nn's mangled names)
pub fn symbolNames(moduleAt i64) {i64: str}:
	out {i64: str} = {}
	tags = dynamicTags(moduleAt)
	symtab = tags.get(dtSymtab) ?? return out
	strtab = tags.get(dtStrtab) ?? return out
	for k in 0..symbolCount(moduleAt, tags):
		sym = moduleAt + symtab + k * 24
		value = quad(sym + 8)
		if value == 0: continue
		at = moduleAt + strtab + word(sym)
		bytes = []
		while core.memory.load(at, 0) != 0 and bytes.len < 400:
			bytes.push(u8(core.memory.load(at, 0)))
			at += 1
		if not bytes.isEmpty: out[moduleAt + value] = bytes.text().copy()
	out
