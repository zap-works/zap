# The cartridge's sprite windows that the widescreen widens (wide/sprites.zap), found where the
# community's disassemblies name them (snesrev/smw's port, SMWCentral's ROM map): the translation
# writes a call in place of each constant or table read, which returns it unchanged unless the
# scene is drawn wide; the instruction's cycles are the same either way.

import recomp.snes.snes

# GetDrawInfo of banks 01, 02 and 03: a sprite is drawn while its x from the camera, plus $40,
# is below $180; the window grows by both margins
fn drawWindow(from i64):
	[
		snes.Patch.Immediate(from, 0x40, "console.widenLeft"),
		snes.Patch.Immediate(from, 0x180, "console.widenSpan")
	]

read = r"{operand}"   # the patch's place for the byte the instruction reads

# SubOffscreen's horizontal edges: the low and the high byte read from its tables
fn eraseWindow(lowAt i64, highAt i64, low i64, high i64):
	[
		snes.Patch.Operand(lowAt, "adc", "wide.eraseEdge({read}, {low}, {high}, false)"),
		snes.Patch.Operand(highAt, "adc", "wide.eraseEdge({read}, {low}, {high}, true)")
	]

pub fn widePatches() snes.Patch[]:
	out = drawWindow(0x01_A379)
	out.extend(drawWindow(0x02_D38C))
	out.extend(drawWindow(0x03_B774))
	out.extend(eraseWindow(0x01_AC5F, 0x01_AC6B, 0x01_AC11, 0x01_AC19))
	out.extend(eraseWindow(0x02_D059, 0x02_D065, 0x02_D007, 0x02_D00F))
	out.extend(eraseWindow(0x03_B88B, 0x03_B897, 0x03_B83F, 0x03_B847))
	out.extend([
		.Operand(0x02_A81A, "adc", r"wide.spawnEdge({operand}, false)"),
		.Operand(0x02_A823, "adc", r"wide.spawnEdge({operand}, true)")
	])
	out
