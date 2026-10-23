# The data area: float constants, string literals and the module variables' storage.

alias nodes = g.c.nodes

# the data-area offset of an 8-byte float constant (shared between its uses)
fn floatConst(mut g Gen, bits i64):
	match g.floatOffs.get(bits):
		off: return off
		none:
			bytesAlign(g.a.data, 8)
			off = g.a.data.len
			bytesPut64(g.a.data, bits)
			g.floatOffs[bits] = off
			return off

fn strLit(mut g Gen, text str):
	match g.strOffs.get(text):
		off: return off
		none:
			bytesAlign(g.a.data, 8)
			off = g.a.data.len
			bytesPutStr(g.a.data, text)
			g.a.data.push(0)
			g.strOffs[text.copy()] = off   # the map keeps a key of its own
			return off

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
