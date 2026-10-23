# Where a module's functions start and how long they are, from its unwind tables: the module's
# MOD0 header (its offset at the module's word 1: the dynamic section, .bss, .eh_frame_hdr and the
# module object, each relative to MOD0) points at .eh_frame_hdr, whose sorted table pairs each
# function's start with its FDE; the FDE holds the function's length. Encodings are DWARF's
# (pointer encodings 0x03 udata4, 0x0B sdata4, 0x1B pcrel sdata4, 0x3B datarel sdata4).

import recomp.switch.cpu

pub type Span:
	at i64
	size i64

fn word(at i64) i64:
	i64(cpu.memory.load(at, 2))

fn signedWord(at i64) i64:
	i32(u32(word(at)))

# a value of the encoding at `at`, `base` the start of what datarel counts from
fn encoded(at i64, encoding i64, base i64):
	v = word(at) if encoding & 0x0F == 0x03 else signedWord(at)
	match encoding & 0x70:
		0x10: at + v
		0x30: base + v
		_: v

# the MOD0 header of the module at `at`, none when it has none
fn mod0(at i64) i64?:
	m = at + word(at + 4)
	if word(m) != 0x3044_4F4D: return none   # "MOD0"
	m

# The module's functions by its unwind tables, none when it has no .eh_frame_hdr.
pub fn frameSpans(moduleAt i64) Span[]:
	m = mod0(moduleAt) ?? return []
	hdr = m + signedWord(m + 16)
	hdrEnd = m + signedWord(m + 20)
	if hdrEnd <= hdr or cpu.memory.load(hdr, 0) != 1: return []
	tableEncoding = i64(cpu.memory.load(hdr + 3, 0))
	count = encoded(hdr + 8, i64(cpu.memory.load(hdr + 2, 0)), hdr)
	out = []
	for k in 0..count:
		entry = hdr + 12 + k * 8
		start = encoded(entry, tableEncoding, hdr)
		fde = encoded(entry + 4, tableEncoding, hdr)
		# the FDE: length, CIE pointer, pc_begin (pcrel sdata4), pc_range
		out.push(Span(at = start, size = word(fde + 12)))
	out
