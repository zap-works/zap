# An emulator's gdb stub as the oracle (Eden's: `use_gdbstub` in its configuration), spoken to
# over GDB's remote serial protocol: each packet `$data#ck` (ck the bytes' sum mod 256 in hex),
# acknowledged by `+`. Registers come as `g` (x0-x30, sp, pc, cpsr; little-endian hex), memory as
# `m addr,len`, a breakpoint is `Z0,addr,4`, `c` runs to the next stop.

import fs
import net

# why the stub could not answer
pub type RemoteError:
	why str

pub type Remote:
	conn net.TcpConn

pub fn remoteAt(host str, port i64) Remote ? RemoteError:
	conn = net.tcpConnect(host, port) ??
		return RemoteError(why = "cannot reach the gdb stub at {host}:{port}: {error}")
	Remote(conn)

fn checksum(text str):
	sum = 0
	for b in text.bytes():
		sum = (sum + b) & 0xFF
	"{sum:02x}"

# the next byte from the stub
fn nextByte(mut r Remote) u8 ? RemoteError:
	got = r.conn.receive(1) ?? return RemoteError(why = "the gdb stub went away: {error}")
	if got.isEmpty: return RemoteError(why = "the gdb stub went away")
	got[0]

# The command sent and the stub's answer (its data, acknowledged).
pub fn ask(mut r Remote, command str) str ? RemoteError:
	r.conn.sendStr("${command}#{checksum(command)}") ??
		return RemoteError(why = "cannot send to the gdb stub: {error}")
	try r.answer()

# the next packet's data (acknowledgements and an interrupt's notifications before it skipped)
fn answer(mut r Remote) str ? RemoteError:
	while (try r.nextByte()) != '$':
		pass
	data = []
	loop:
		b = try r.nextByte()
		if b == '#': break
		data.push(b)
	_ = try r.nextByte()   # the checksum, trusted on a local connection
	_ = try r.nextByte()
	r.conn.sendStr("+") ?? return RemoteError(why = "cannot send to the gdb stub: {error}")
	data.text().copy()

fn hexByte(text str, at i64) u8:
	u8(i64.parse("0x{text[at..at + 2]}") ?? 0)

# little-endian hex as a number
fn littleEndian(text str):
	v = u64(0)
	for k in 0..text.len / 2:
		v |= u64(hexByte(text, k * 2)) << u64(8 * k)
	v

# The registers: x0-x30, sp, pc (33 values; the flags after them left out).
pub fn registers(mut r Remote) u64[] ? RemoteError:
	text = try r.ask("g")
	if text.len < 33 * 16:
		return RemoteError(why = "the gdb stub's registers are cut short: {text.len} digits")
	(0..33).map(littleEndian(text[it * 16..it * 16 + 16]))

# n bytes of the guest's memory at `at`
pub fn memory(mut r Remote, at i64, n i64) u8[] ? RemoteError:
	text = try r.ask("m{at:x},{n:x}")
	if text.startsWith("E"):
		return RemoteError(why = "the gdb stub cannot read {n} bytes at {at:x}: {text}")
	(0..text.len / 2).map(hexByte(text, it * 2))

# a breakpoint at `at`
pub fn breakAt(mut r Remote, at i64) ? RemoteError:
	said = try r.ask("Z0,{at:x},4")
	if said != "OK": return RemoteError(why = "the gdb stub sets no breakpoint at {at:x}: {said}")

# a watchpoint on the `n` bytes at `at`: the next write to them stops the guest (`T05watch:...`)
pub fn watchWrites(mut r Remote, at i64, n i64) ? RemoteError:
	said = try r.ask("Z2,{at:x},{n}")
	if said != "OK": return RemoteError(why = "the gdb stub sets no watchpoint at {at:x}: {said}")

# steps the stopped thread past the write its watchpoint stopped it at (the stub stops at the same
# instruction again otherwise)
pub fn stepPastWatch(mut r Remote, at i64, n i64) ? RemoteError:
	said = try r.ask("z2,{at:x},{n}")
	if said != "OK":
		return RemoteError(why = "the gdb stub takes out no watchpoint at {at:x}: {said}")
	_ = try r.ask("s")
	try r.watchWrites(at, n)

# runs to the next stop; the stop's reply (`T05...` at a breakpoint)
pub fn resume(mut r Remote) str ? RemoteError:
	try r.ask("c")

# The stop reply's pc (register 0x20, the first pair after the signal `T05`), none when it names none.
pub fn stopPc(reply str) u64?:
	if not reply.startsWith("T0520:"): return none
	littleEndian(reply[6..].split(";").first ?? "")

# a breakpoint at `at` taken out
fn unbreakAt(mut r Remote, at i64) ? RemoteError:
	said = try r.ask("z0,{at:x},4")
	if said != "OK":
		return RemoteError(why = "the gdb stub takes out no breakpoint at {at:x}: {said}")

# Runs on to the next time the code reaches one of `addresses` (breakpoints there). The stub
# patches a breakpoint into the code and runs on from one only after a step, so a thread standing
# at a breakpoint steps with it taken out and put back; the first `c` after a step stops again at
# once, and the loop runs on from every stop elsewhere.
pub fn resumeTo(mut r Remote, addresses i64[]) str ? RemoteError:
	here = i64((try r.registers())[32])
	stop = ""
	if addresses.any(it == here):
		try r.unbreakAt(here)
		stop = try r.ask("s")
		try r.breakAt(here)
	loop:
		if not stop.isEmpty and
			(
				addresses.any(it == i64(stopPc(stop) ?? 0)) or not stop.startsWith("T") or
					"watch" in stop
			):
			return stop
		stop = try r.ask("c")

# The stub reached once Eden opens it: tried every half second for `within` milliseconds.
pub fn remoteWithin(host str, port i64, within i64) Remote ? RemoteError:
	until = clockMs() + within
	loop:
		if remoteAt(host, port) is r: return r
		if clockMs() > until:
			return RemoteError(why = "no gdb stub at {host}:{port} within {within} ms")
		sleepMs(500)

# Eden's configuration (sdl2-config.ini) set to run headless for the oracle's stops: its gdb stub on
# at `port`, waiting for us at the start, and its null renderer.
pub fn setGdbStub(config str, port i64) ? RemoteError:
	try setSettings(config, [("use_gdbstub", "true"), ("gdbstub_port", "{port}"), ("backend", "2")])

# Eden's configuration set to draw frames: no gdb stub and its Vulkan renderer.
pub fn setFrames(config str) ? RemoteError:
	try setSettings(config, [("use_gdbstub", "false"), ("backend", "1")])

fixedSeed = [("rng_seed_enabled", "true"), ("rng_seed", "0")]

# `settings` and the fixed random seed (one layout every run) in the configuration. Each setting's
# `\default` line goes false, or Eden keeps its default; the file's own line ends are kept.
fn setSettings(config str, settings (str, str)[]) ? RemoteError:
	text = fs.readFile(config) ??
		return RemoteError(why = "cannot read {config}: {error} (run eden-cli once to make it)")
	for (key, value) in settings:
		text = text.setting(key, value)
	for (key, value) in fixedSeed:
		text = text.setting(key, value)
	fs.writeFile(config, text) ?? return RemoteError(why = "cannot write {config}: {error}")

# the ini text with key's value and its `\default` line set
fn setting(text str, key str, value str):
	lines = text.lines()
	for k in 0..lines.len:
		if lines[k] == "{key}\\default=true": lines[k] = "{key}\\default=false"
		elif lines[k].startsWith("{key}="): lines[k] = "{key}={value}"
	lines.join("\n")

# the program the stub runs ended (`k`: no answer comes)
pub fn kill(mut r Remote):
	_ = r.conn.sendStr("$k#{checksum("k")}")

# A monitor command's text (`qRcmd`, the text in hex both ways; Eden's `get info` names the
# modules and where they lie): its output packets (`O...`) joined, until the stub's OK.
pub fn monitor(mut r Remote, command str) str ? RemoteError:
	said = try r.ask("qRcmd,{command.bytes().map("{it:02x}").join("")}")
	out = []
	while said != "OK" and not said.startsWith("E"):
		hex = said[1..] if said.startsWith("O") else said
		out.extend((0..hex.len / 2).map(hexByte(hex, it * 2)))
		if not said.startsWith("O"): break
		said = try r.answer()
	out.text().copy()

# The running program stopped (an interrupt, the byte 3: Eden's stub lets the game run on when
# we connect, and takes a breakpoint or `c` only from a stop); its stop reply.
pub fn pause(mut r Remote) str ? RemoteError:
	r.conn.send([3]) ?? return RemoteError(why = "cannot send to the gdb stub: {error}")
	try r.answer()
