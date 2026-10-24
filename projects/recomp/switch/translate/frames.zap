# Where a module's functions start and how long they are, from its unwind tables: the module's
# MOD0 header (its offset at the module's word 1: the dynamic section, .bss, .eh_frame_hdr and the
# module object, each relative to MOD0) points at .eh_frame_hdr, whose sorted table pairs each
# function's start with its FDE; the FDE holds the function's range, in the pointer encoding its
# CIE's augmentation names ('R'). Encodings are DWARF's (low nibble: 0x03 udata4, 0x04 udata8,
# 0x0B sdata4, 0x0C sdata8; high: 0x10 pcrel, 0x30 datarel).

import recomp.switch.cpu

pub type Span:
	at i64
	size i64

fn word(at i64) i64:
	i64(cpu.memory.load(at, 2))

fn signedWord(at i64) i64:
	i32(u32(word(at)))

fn byteAt(at i64) i64:
	i64(cpu.memory.load(at, 0))

# a value of the encoding at `at` and its bytes, `base` what datarel counts from
fn encoded(at i64, encoding i64, base i64):
	wide = encoding & 0x0F in [0x04, 0x0C]
	v = i64(cpu.memory.load(at, 3)) if wide else signedWord(at)
	if encoding & 0x0F == 0x03: v = word(at)
	match encoding & 0x70:
		0x10: v += at
		0x30: v += base
		_: pass
	(v, 8 if wide else 4)

# an unsigned LEB128 at `at`: its value and where what follows starts
fn leb(at i64):
	v = 0
	shift = 0
	p = at
	while true:
		b = byteAt(p)
		v |= (b & 0x7F) << shift
		p += 1
		shift += 7
		if b & 0x80 == 0: return (v, p)

# the pointer encoding a CIE gives its FDEs (its augmentation's R), sdata4 pcrel when none
fn fdeEncoding(cie i64):
	at = cie + 9   # past the length, the id and the version
	augmentation = at
	while byteAt(at) != 0:
		at += 1
	if byteAt(augmentation) != 0x7A: return 0x1B   # no 'z': no augmentation data
	_, at = leb(at + 1)   # code alignment
	_, at = leb(at)   # data alignment (a signed LEB of the same length)
	_, at = leb(at)   # the return address register (version 3; version 1's one byte is a LEB too)
	_, at = leb(at)   # the augmentation data's length
	k = augmentation + 1
	while byteAt(k) != 0:
		match byteAt(k):
			0x52: return byteAt(at)   # 'R'
			0x50:   # 'P': its encoding, then the personality routine
				_, n = encoded(at + 1, byteAt(at), 0)
				at += 1 + n
			_: at += 1   # 'L': one byte
		k += 1
	0x1B

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
	if hdrEnd <= hdr or byteAt(hdr) != 1: return []
	tableEncoding = byteAt(hdr + 3)
	_, n = encoded(hdr + 4, byteAt(hdr + 1), hdr)
	count, _ = encoded(hdr + 4 + n, byteAt(hdr + 2), hdr)
	at = hdr + 4 + n + 4
	encodings {i64: i64} = {}
	out = []
	for k in 0..count:
		start, _ = encoded(at + k * 8, tableEncoding, hdr)
		fde, _ = encoded(at + k * 8 + 4, tableEncoding, hdr)
		cie = fde + 4 - word(fde + 4)
		encoding = encodings.get(cie) ?? fdeEncoding(cie)
		encodings[cie] = encoding
		begin, size = encoded(fde + 8, encoding, 0)
		range, _ = encoded(fde + 8 + size, encoding & 0x0F, 0)
		if begin == start: out.push(Span(at = start, size = range))
	out
