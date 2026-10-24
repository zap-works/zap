# The operands of the addressing modes: an immediate's value, else the long address the mode makes
# (cpu's direct, data, indexed, pointer...) read and written through cpu's data accesses, which
# count the wait states of where they land. The direct page and the stack are in bank 0, a 16-bit
# access there wrapping at FFFF. A read through an 8-bit index pays a page crossed.

# where an instruction reads and writes: the accumulator, or memory at an address
type Place:
	read str
	address str   # empty for the accumulator
	inBank0 bool
	wide bool

# the long address of a memory operand, and whether it is in bank 0
fn operandAddress(i Instr):
	v = i.valueText()
	match i.mode:
		"d": ("cpu.direct({v})", true)
		"d,x": ("cpu.directIndexed({v}, cpu.x)", true)
		"d,y": ("cpu.directIndexed({v}, cpu.y)", true)
		"d,s": ("cpu.stackRelative({v})", true)
		"(d)": ("cpu.pointer(cpu.direct({v}))", false)
		"(d,x)": ("cpu.pointer(cpu.directIndexed({v}, cpu.x))", false)
		"(d),y": ("{i.indexing()}(cpu.pointer(cpu.direct({v})), cpu.y)", false)
		"[d]": ("cpu.read24Bank0(cpu.direct({v}))", false)
		"[d],y": ("cpu.indexed(cpu.read24Bank0(cpu.direct({v})), cpu.y)", false)
		"(d,s),y": ("cpu.indexedIdle(cpu.pointer(cpu.stackRelative({v})), cpu.y)", false)
		"w": ("cpu.data({v})", false)
		"w,x": ("{i.indexing()}(cpu.data({v}), cpu.x)", false)
		"w,y": ("{i.indexing()}(cpu.data({v}), cpu.y)", false)
		"l": (v, false)
		"l,x": ("cpu.indexed({v}, cpu.x)", false)
		_: fail("no memory operand in {i.text()}")

# the index's sum and its internal cycle: where an 8-bit index register reads, only across a page
fn indexing(i Instr):
	"cpu.indexedRead" if i.widths.x and i.readsOnly() else "cpu.indexedIdle"

fn readAt(address str, inBank0 bool, wide bool):
	if not wide: return "cpu.readData8({address})"
	"cpu.readData16Bank0({address})" if inBank0 else "cpu.readData16({address})"

fn writeAt(address str, inBank0 bool, wide bool, value str):
	if not wide: return "cpu.writeData8({address}, {value})"
	"cpu.writeData16Bank0({address}, {value})" if inBank0 else "cpu.writeData16({address}, {value})"

# the operand's value as wide as the register it goes with
fn operandValue(mut ft FnText, depth i64, i Instr, wide bool):
	if isImmediate(i.mode):
		value = i.valueAs(typeOf(wide))
		if ft.patches.get(i.at) is Immediate(_, _, call): return "{call}({value})"
		return value
	address, inBank0 = i.operandAddress()
	read = readAt(address, inBank0, wide)
	if ft.patches.get(i.at) is Operand(_, _, text): return text.replace(r"{operand}", read)
	read

fn store(mut ft FnText, depth i64, i Instr, wide bool, value str):
	address, inBank0 = i.operandAddress()
	ft.put(depth, writeAt(address, inBank0, wide, value))

# the place a read, change and write works on: memory's address computed once
fn placeOf(mut ft FnText, depth i64, i Instr, wide bool):
	if i.mode == "A": return Place(read = readReg("a", wide), address = "", inBank0 = false, wide)
	address, inBank0 = i.operandAddress()
	at = ft.temp("at")
	ft.put(depth, "{at} = {address}")
	Place(read = readAt(at, inBank0, wide), address = at, inBank0, wide)

# the write back of a read, change and write: an internal cycle first, a 16-bit one high byte first
fn writePlace(mut ft FnText, depth i64, place Place, value str):
	if place.address.isEmpty:
		ft.writeReg(depth, "a", place.wide, value)
		return
	ft.put(depth, "console.idle()")
	if not place.wide:
		ft.put(depth, writeAt(place.address, place.inBank0, false, value))
	elif place.inBank0:
		ft.put(depth, "cpu.modifyData16Bank0({place.address}, {value})")
	else:
		ft.put(depth, "cpu.modifyData16({place.address}, {value})")
