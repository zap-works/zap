# The data area: float constants, string literals and the module variables' storage.

alias nodes = g.c.nodes

# the data-area offset of an 8-byte float constant (shared between its uses)
fn floatConst(mut g Gen, bits i64):
	if g.codeNoting: g.floatsNoted.extend([bits, g.labelsNoted.len / 3, g.a.labelPos.len])
	match g.floatOffs.get(bits):
		off: return off
		none:
			bytesAlign(g.a.data, 8)
			off = g.a.data.len
			bytesPut64(g.a.data, bits)
			g.floatOffs[bits] = off
			return off

# the data cut back to its first n bytes, what named the rest forgotten (the lowering of what is
# only checked leaves nothing in the executable)
fn dataBack(mut g Gen, n i64):
	g.a.data.truncate(n)
	for key in g.strOffs.keys().filter(g.strOffs[it] >= n):
		g.strOffs.remove(key)
	for key in g.tdOffs.keys().filter(g.tdOffs[it] >= n):
		g.tdOffs.remove(key)
	for key in g.nameOffs.keys().filter(g.nameOffs[it] >= n):
		g.nameOffs.remove(key)
	for bits in g.floatOffs.keys().filter(g.floatOffs[it] >= n):
		g.floatOffs.remove(bits)
	for fnd in g.loadedSlots.keys().filter(g.loadedSlots[it] >= n):
		g.loadedSlots.remove(fnd)

fn strLit(mut g Gen, text str):
	before = g.strOffs.len
	off = g.strOffs.get(text) ?? -1
	if off < 0:
		bytesAlign(g.a.data, 8)
		off = g.a.data.len
		bytesPutStr(g.a.data, text)
		g.a.data.push(0)
		g.strOffs[text.copy()] = off   # the map keeps a key of its own
	if g.asksNoting:
		g.noteAsk(KeptAsk(keptString, text.copy(), off, made = g.strOffs.len > before))
	off

# writes a str value { ptr, length, cap = 0 } pointing at a literal into the destination
fn genStrLiteral(mut g Gen, text str, d Dest):
	if d.kind == 2: return
	g.a.leaRaxData(g.strLit(text))
	g.storeWord(d)
	g.storeWordImm(d.destAt(8), text.len)
	g.storeWordImm(d.destAt(16), 0)

fn isConstName(g Gen, nm str) NodeId?:
	if g.findVar(nm) >= 0: return none
	if g.isReceiverField(nm):
		return none   # a field of the receiver shadows the constant
	d = try g.c.findDeclByGlobalName(nConstDecl, nm)
	d if not nodes[d].hasFlag(flagMut) else none

# the data offset of the module variable named nm, or -1
fn globalOf(g Gen, nm str):
	match g.globalOffs.get(nm):
		off: return off
		none: return -1

# Whether declaration d is kept in the data area: a module variable, or a constant list or map, made
# once at the start so that reading it (an index, a loop) does not build it again; a use of the
# constant as a whole value still makes a fresh one. A GPU file's are the GPU's.
fn hasStorage(mut g Gen, d NodeId):
	nodes[d].kind == nConstDecl and not nodes[d].hasFlag(flagGpu) and
		(
			nodes[d].hasFlag(flagMut) or nodes[d].hasFlag(flagOrdered) or
				g.tyK(g.c.constTypeOf(d)) in [tList, tMap] or g.c.isShared(g.c.constTypeOf(d))   # a shared value is made once
		)

# every module variable gets its storage in the data area before any code refers to it
fn reserveGlobals(mut g Gen):
	for d in g.c.decls:
		if g.hasStorage(d):
			t = g.c.constTypeOf(d)
			off = g.a.asmBssZero(g.c.slotSize(t))
			g.globalOffs[nodes[d].text.copy()] = off   # the map keeps a key of its own
