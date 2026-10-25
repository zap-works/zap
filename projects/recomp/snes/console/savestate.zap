# Save states: the whole machine written to a file and read back, play going on exactly there.
# A request waits for the next frame's end, then for the CPU's next instruction start (cpu.poll, an
# interrupt handler's first instruction included), where the CPU's place is known and no line is
# half drawn; the CPU's side does it (cpu/savestate.zap), a load unwinding the translated code's
# native stack. Each part of the console lists its fields once, in a function `<part>Fields(f)`
# beside its variables, which both writes and reads them. What the next frame redraws whole (the
# line buffers, the tiles fetched, the output picture) is not kept.

import digest
import fs

# the layout's version: a file of another one is refused
stateVersion u32 = 2

mut askedPath = ""
mut askedLoad = false
pub mut stateArmed = false   # the frame ended with a request: the next instruction start takes it
mut framesFrom = 0   # the frame --frames counts from: a loaded state's

# The game's state saved to `path` at the next safe point.
pub fn requestSave(path str):
	askedPath = path.copy()
	askedLoad = false

# The state in `path` loaded at the next safe point.
pub fn requestLoad(path str):
	askedPath = path.copy()
	askedLoad = true

# at a frame's end: a request waiting is taken at the next instruction start
fn armState():
	if askedPath.isEmpty: return
	stateArmed = true
	updateDue()

# The request armed, taken: its path and whether it loads.
pub fn takeStateRequest() (str, bool):
	stateArmed = false
	updateDue()
	path = askedPath.copy()
	askedPath = ""
	(path, askedLoad)

# The fields of a state as one function lists them: written in order, or read back in the same.
pub type StateFile:
	loading bool
	out u8[] = []
	reader Reader

	pub mut fn int(v i64) i64:
		if loading: return reader.i64()
		out.extend(v.toBytes())
		v

	pub mut fn long(v u32) u32:
		if loading: return reader.u32()
		out.extend(v.toBytes())
		v

	pub mut fn word(v u16) u16:
		if loading: return reader.u16()
		out.extend(v.toBytes())
		v

	pub mut fn byte(v u8) u8:
		if loading: return reader.u8()
		out.push(v)
		v

	pub mut fn isSet(v bool) bool:
		byte(1 if v else 0) != 0

	pub mut fn byteList(mut v u8[]):
		if loading: v = u8[].fromBytes(reader)
		else: out.extend(v.toBytes())

	# the n bytes of v from `at`, kept as byteList keeps a list
	pub mut fn bytesAt(mut v u8[], at i64, n i64):
		part = v[at..at + n].copy()
		byteList(part)
		if loading: v.place(at, part)

	pub mut fn wordList(mut v u16[]):
		if loading: v = u16[].fromBytes(reader)
		else: out.extend(v.toBytes())

	pub mut fn intList(mut v i64[]):
		if loading: v = i64[].fromBytes(reader)
		else: out.extend(v.toBytes())

	fn spcState(mut v SpcState):
		if loading: v = SpcState.fromBytes(reader)
		else: out.extend(v.toBytes())

	fn voices(mut v DspVoice[]):
		if loading: v = DspVoice[].fromBytes(reader)
		else: out.extend(v.toBytes())

	fn portWrites(mut v PortWrite[]):
		if loading: v = PortWrite[].fromBytes(reader)
		else: out.extend(v.toBytes())

	fn dsp1Part(v Dsp1Part):
		if loading: return Dsp1Part.fromBytes(reader)
		out.extend(v.toBytes())
		v.copy()

	fn events(mut v RewriteEvent[]):
		if loading: v = RewriteEvent[].fromBytes(reader)
		else: out.extend(v.toBytes())

	# whether every field read was in the file and the file holds nothing after them
	pub fn isWhole() bool:
		not reader.short and reader.at == reader.d.len

noBytes u8[] = []

pub fn savingState() StateFile:
	StateFile(loading = false, reader = Reader(d = noBytes))

pub fn writeState(path str, f StateFile):
	fs.writeBytes(path, f.out) ?? eprint("cannot save the state in {path}: {error}")

# a state file's bytes; none when it cannot be read
pub fn stateBytes(path str) u8[]?:
	if fs.readBytes(path) is saved: return saved
	refuseState(path, "it cannot be read")
	none

# The state's header, written or checked: the layout's version and the cartridge it is of. Why a
# state read is not of this build and cartridge, none when it is.
pub fn headerMismatch(mut f StateFile) str?:
	cartridgeHash = digest.fnv1a(memoryMap.bytes[romAt..].copy())
	if f.long(stateVersion) != stateVersion: return "another version's state"
	if f.long(cartridgeHash) != cartridgeHash: return "another cartridge's state"
	none

pub fn refuseState(path str, why str):
	eprint("cannot load the state {path}: {why}")

# The console's fields, each part's in turn.
pub fn consoleFields(mut f StateFile):
	f.timingFields()
	f.bytesAt(memoryMap.bytes, 0, wramSize)
	f.bytesAt(memoryMap.bytes, sramAt, sramLen)
	wramPort = f.int(wramPort)
	f.busFields()
	f.ioFields()
	f.aluFields()
	f.ppuFields()
	f.mode7Fields()
	f.dmaFields()
	f.spcFields()
	f.dspFields()
	if necMapped: f.necFields()
	if necRewritten: f.rewriteFields()
	f.routeFields()
	wideOn = f.isSet(wideOn)
	wideWhy = f.int(wideWhy)
	wideBias = f.int(wideBias)
	if f.loading: afterLoad()

# what a load leaves as a fresh start would: the counts derived from the fields, the battery
# kept again, --frames counted from here
fn afterLoad():
	layersKey = -1
	sramChanged = sramLen > 0
	framesFrom = frameCount
	updateDue()
