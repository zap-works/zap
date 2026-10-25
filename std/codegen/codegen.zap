# Zap source a program writes (a recompiler's translation), written as code: a line at the level
# the open blocks make, a block from its header to its end, temporaries named in turn. The text
# is laid out as zap fmt lays it out: a tab a level, and a guard holding one jump on its header's
# line when that fits (`if c: return`, fmt's guard rewrite). An integer goes in as fmt writes its
# literal by its format, `"pc = {k:#08X}"` (spec 2.3). Lines past fmt's 100 columns are left for
# fmt to break.

import fs

# the columns a line of zap fmt's layout fits in, a tab counted as four
lineWidth = 100

pub type Source:
	lines str[] = []
	level i64 = 0   # the blocks open
	temps i64 = 0   # the temporaries named so far
	heads i64[] = []   # the line of each open block's header

	# a line of code at the level of the blocks open
	fn line(text str):
		lines.push("{"\t".repeat(level)}{text}")

	# an empty line, between declarations
	fn blank():
		lines.push("")

	# A block's header (`if c:`, `match v:`, an arm `0x10:`): the lines after it are one level in
	# until its end.
	fn block(header str):
		self.line(header)
		heads.push(lines.len - 1)
		level += 1

	# The innermost block's end: one that holds a jump alone (break, continue, a return) under an
	# `if` is one line when it fits, as fmt writes it.
	fn end():
		self.close(true)

	# The innermost block's end and the next one of the same statement (`else:`, `elif c:`).
	fn otherwise(header str):
		self.close(false)
		self.block(header)

	# the innermost block closed, a guard of one jump joined to its header when `joins`
	fn close(joins bool):
		level -= 1
		head = heads.pop() ?? fail("codegen: a block ended that was not opened")
		if not joins or lines.len != head + 2: return
		h = lines[head].trimmed()
		b = lines[head + 1].trimmed()
		jump = b == "break" or b == "continue" or b == "return" or b.startsWith("return ")
		if not jump or not h.startsWith("if ") or "#" in h or "#" in b: return
		if 4 * level + h.len + b.len + 1 > lineWidth: return
		lines[head] = "{"\t".repeat(level)}{h} {b}"
		lines.pop()

	# a temporary's name: the prefix and a number no temporary before took (`v1`, `t2`)
	fn temp(prefix str):
		temps += 1
		"{prefix}{temps}"

	# the text, each line ending in a newline
	fn text():
		if lines.isEmpty: return ""
		"{lines.join("\n")}\n"

fn sample():
	s = Source()
	s.block("fn f{0xC0_8000:06x}():")
	s.line("pc u32 = {0xC0_8000:#08X}")
	s.block("loop:")
	s.block("match pc:")
	s.block("{0x00C0_8000:#08X}:")
	v = s.temp("v")
	s.line("{v} u16 = cpu.a + {100000:#}")
	s.block("if cpu.ret != {0xC0_8003:#06X}:")
	s.line("return")
	s.end()
	s.block("if {v} == 0:")
	s.line("cpu.push8({0x7E:#02X})")
	s.line("continue")
	s.end()
	s.block("if cpu.c:")
	s.line("pc = {0x00C0_8010:#08X}")
	s.otherwise("else:")
	s.line("break")
	s.end()
	s.end()
	s.block("_:")
	s.line("return")
	s.end()
	s.end()
	s.end()
	s.end()
	s

test "a source's lines at the levels its blocks open":
	print(sample().text().trimmed().replace("\t", ">"))
	prints """
		fn fc08000():
		>pc u32 = 0x00C0_8000
		>loop:
		>>match pc:
		>>>0x00C0_8000:
		>>>>v1 u16 = cpu.a + 100_000
		>>>>if cpu.ret != 0xC0_8003: return
		>>>>if v1 == 0:
		>>>>>cpu.push8(0x7E)
		>>>>>continue
		>>>>if cpu.c:
		>>>>>pc = 0x00C0_8010
		>>>>else:
		>>>>>break
		>>>_:
		>>>>return
		"""

test "zap fmt leaves a source's text as it is":
	text = sample().text()
	file = "{testDir()}codegen.zap"
	_ = fs.writeFile(file, text)
	zapFmt(file)
	laid = fs.readFile(file) ?? ""
	_ = fs.deleteFile(file)
	expect laid == text
