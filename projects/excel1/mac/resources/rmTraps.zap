# long: the Resource Manager's traps, one arm each
#
# The Resource Manager's traps: their Pascal arguments popped, their work done by resources.zap.

import cpu

# the type of the reference: the type entry whose references hold it
fn typeOfRef(r ResRef) i64:
	p = deref(r.map)
	typesAt = p + cpu.read16(p + 24)
	types = (i64(cpu.read16(typesAt)) + 1) & 0xFFFF
	at = p + r.at
	for t in 0..types:
		entry = typesAt + 2 + u32(t * 8)
		refs = typesAt + cpu.read16(entry + 6)
		count = i64(cpu.read16(entry + 4)) + 1
		if at >= refs and at < refs + u32(count * 12): return cpu.read32(entry)
	0

# the types of the maps from the current one down, each once
fn typesInMaps():
	out i64[] = []
	h = mapOf(curMap())
	while h != 0:
		p = deref(h)
		typesAt = p + cpu.read16(p + 24)
		types = (i64(cpu.read16(typesAt)) + 1) & 0xFFFF
		for t in 0..types:
			kind = i64(cpu.read32(typesAt + 2 + u32(t * 8)))
			if kind not in out: out.push(kind)
		h = cpu.read32(p + 16)
	out

pub fn resourceTrap(n i64, trapWord i64, back u32) u32:
	match n:
		0x192: detachResource(popLong())
		0x193: popBool()
		0x194: resultWord(curMap())
		0x195: resultWord(cpu.read16(sysMapAt))
		0x196: pass
		0x197:
			name = str(pascalAt(popLong()))
			match openResFile("", name):
				refNum: resultWord(refNum)
				none:
					setResErr(resFNotFound)
					resultWord(-1)
		0x198:
			refNum = popInt()
			if mapOf(refNum) != 0:
				cpu.write16(curMapAt, u32.wrap(refNum))
				setResErr(0)
			else:
				setResErr(resFNotFound)
		0x199, 0x19A: popInt()
		0x19B: cpu.write8(resLoadAt, 1 if popBool() else 0)
		0x19C: resultWord(resourcesOfType(popLong(), false).len)
		0x19D:
			index = popInt()
			refs = resourcesOfType(popLong(), false)
			if index >= 1 and index <= refs.len:
				setResErr(0)
				resultLong(refs[index - 1].loadRef(isResLoad()))
			else:
				setResErr(resNotFound)
				resultLong(0)
		0x19E: resultWord(typesInMaps().len)
		0x19F:
			index = popInt()
			at = popLong()
			types = typesInMaps()
			cpu.write32(at, u32(types[index - 1]) if index >= 1 and index <= types.len else 0)
		0x1A1:
			name = pascalAt(popLong())
			kind = i64(popLong())
			resultLong(getResource(kind, 0, name, false))
		0x1A2:
			h = popLong()
			match refOfHandle(h):
				r:
					r.loadRef(true)
					setResErr(0)
				none: setResErr(resNotFound)
		0x1A3: releaseResource(popLong())
		0x1A4: resultWord(homeResFile(popLong()))
		0x1A5: resultLong(u32.wrap(sizeOfResource(popLong())))
		0x1A6:
			match refOfHandle(popLong()):
				r: resultWord(cpu.read8(r.refAt() + 4))
				none: resultWord(0)
		0x1A7:
			attributes = popInt()
			match refOfHandle(popLong()):
				r: cpu.write8(r.refAt() + 4, attributes & 0xFF)
				none: setResErr(resNotFound)
		0x1A8:
			nameAt = popLong()
			typeAt = popLong()
			idAt = popLong()
			match refOfHandle(popLong()):
				r:
					setWord(idAt, word(r.refAt()))
					cpu.write32(typeAt, u32(r.typeOfRef()))
					writePascal(nameAt, r.resourceName())
					setResErr(0)
				none: setResErr(resNotFound)
		0x1AA, 0x1B0: popLong()
		0x1AF: resultWord(i16.wrap(i64(cpu.read16(resErrAt))))
		_: return unimplemented(trapWord, back)
	back
