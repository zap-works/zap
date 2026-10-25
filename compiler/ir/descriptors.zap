# Type descriptors in the data area, one per type (tdOffs).
# Words of 8 bytes; references to other descriptors and to name strings are offsets from the
# start of the data area. kind: 0 int (bits, signed) 1 float (bits) 2 bool 3 str 4 unit
# 5 list (elem, stride) 6 map (key, val) 7 option (inner) 8 result (ok, err)
# 9 struct (name, nfields, size, [name, td, offset]...) 10 enum (name, nvariants, [name, nfields, [name, td, offset]...]...) 11 fn

alias nodes = g.c.nodes
alias tys = g.c.types

fn reserveWords(mut g Gen, n i64) i64:
	bytesAlign(g.a.data, 8)
	g.a.asmDataZero(8 * n)

fn putWord(mut g Gen, off i64, i i64, v i64):
	patch64(g.a.data, off + 8 * i, v)

# (the map of names already written and the data section: only those change, so the name may
# be read from the nodes while it is written)
fn nameLit(mut offs {str: i64}, mut data u8[], text str):
	# name strings in descriptors are [length][bytes] blocks (the runtime builds a str from them)
	match offs.get(text):
		off: return off
		none:
			bytesAlign(data, 8)
			off = data.len
			bytesPut64(data, text.len)
			bytesPutStr(data, text)
			data.push(0)
			offs[text.copy()] = off   # the map keeps a key of its own
			return off

fn descriptor(mut g Gen, t TypeId) i64:
	k = g.tyK(t)
	key = typeKey(tys, t)
	if g.tdOffs.get(key) is found: return found
	n = 4
	if k == tStruct:
		n = 4 + 3 * nodes[declOf(tys, t)].kids.len
	if k == tEnum:
		for v in nodes[declOf(tys, t)].kids:
			n = n + 2 + 3 * nodes[v].kids.len
	off = g.reserveWords(n)
	g.tdOffs[key] = off
	if k == tInt:
		g.putWord(off, 0, 0)
		g.putWord(off, 1, tys[t].bits)
		sg = 0
		if tys[t].isSigned:
			sg = 1
		g.putWord(off, 2, sg)
	elif k == tFloat:
		g.putWord(off, 0, 1)
		g.putWord(off, 1, tys[t].bits)
	elif k == tSimd:
		g.putWord(off, 0, 1)
		g.putWord(off, 1, 256)
	elif k == tBytes:
		g.putWord(off, 0, 0)
		g.putWord(off, 1, 128)
		g.putWord(off, 2, 0)
	elif k == tBool:
		g.putWord(off, 0, 2)
	elif k == tStr:
		g.putWord(off, 0, 3)
	elif k == tUnit:
		g.putWord(off, 0, 4)
	elif k == tList:
		elem = g.listElem(t)
		a = g.descriptor(elem)
		g.putWord(off, 0, 5)
		g.putWord(off, 1, a)
		g.putWord(off, 2, g.c.elemStride(elem))
	elif k == tMap:
		a = g.descriptor(innerOf(tys, t))
		b = g.descriptor(valOf(tys, t))
		g.putWord(off, 0, 6)
		g.putWord(off, 1, a)
		g.putWord(off, 2, b)
	elif k == tOption:
		a = g.descriptor(innerOf(tys, t))
		g.putWord(off, 0, 7)
		g.putWord(off, 1, a)
		g.putWord(off, 2, g.sizeOf(t))
		g.putWord(off, 3, g.c.optionPayload(t))
	elif k == tResult:
		a = g.descriptor(innerOf(tys, t))
		b = g.descriptor(errOf(tys, t))
		g.putWord(off, 0, 8)
		g.putWord(off, 1, a)
		g.putWord(off, 2, b)
		g.putWord(off, 3, g.sizeOf(t))
	elif k == tArray:
		a = g.descriptor(innerOf(tys, t))
		g.putWord(off, 0, 14)
		g.putWord(off, 1, a)
		g.putWord(off, 2, tys[t].bits)
		g.putWord(off, 3, g.c.elemStride(innerOf(tys, t)))
	elif k == tFn:
		g.putWord(off, 0, 11)
	elif k == tBox:
		a = g.descriptor(innerOf(tys, t))
		g.putWord(off, 0, 13)
		g.putWord(off, 1, a)
	elif k == tRef:
		a = g.descriptor(innerOf(tys, t))
		g.putWord(off, 0, 12)
		g.putWord(off, 1, a)
		if g.c.refIsWindow(t):
			g.putWord(off, 2, 1)
	elif k == tStruct:
		g.descriptorStruct(t, off)
	elif k == tEnum:
		g.descriptorEnum(t, off)
	else:
		g.putWord(off, 0, 4)
	off

fn descriptorStruct(mut g Gen, t TypeId, off i64):
	dcl = declOf(tys, t)
	# the fields are read through g at each step: the descriptors change g
	nf = nodes[dcl].kids.len
	offs = g.c.structFieldOffsets(dcl)
	g.putWord(off, 0, 9)
	g.putWord(off, 1, nameLit(g.nameOffs, g.a.data, g.c.shownName(dcl)))
	g.putWord(off, 2, nf)
	g.putWord(off, 3, g.sizeOf(t))
	for i in 0..nf:
		f = nodes[dcl].kids[i]
		nm = nameLit(g.nameOffs, g.a.data, nodes[f].text)
		fd = g.descriptor(g.c.resolveType(nodes[f].types()[0]))
		g.putWord(off, 4 + 3 * i, nm)
		g.putWord(off, 5 + 3 * i, fd)
		g.putWord(off, 6 + 3 * i, offs[i])

fn descriptorEnum(mut g Gen, t TypeId, off i64):
	dcl = declOf(tys, t)
	# the variants and their fields are read through g at each step: the descriptors change g
	nv = nodes[dcl].kids.len
	g.putWord(off, 0, 10)
	g.putWord(off, 1, nameLit(g.nameOffs, g.a.data, g.c.shownName(dcl)))
	g.putWord(off, 2, nv)
	g.putWord(off, 3, g.sizeOf(t))
	w = 4
	for vi in 0..nv:
		v = nodes[dcl].kids[vi]
		offs = g.c.variantFieldOffsets(dcl, v)
		g.putWord(off, w, nameLit(g.nameOffs, g.a.data, nodes[v].text))
		w += 1
		g.putWord(off, w, nodes[v].kids.len)
		w += 1
		for i in 0..g.c.nodes[v].kids.len:
			f = nodes[v].kids[i]
			nm = nameLit(g.nameOffs, g.a.data, nodes[f].text)
			fd = g.descriptor(g.c.resolveType(nodes[f].types()[0]))
			g.putWord(off, w, nm)
			w += 1
			g.putWord(off, w, fd)
			w += 1
			g.putWord(off, w, offs[i])
			w += 1
