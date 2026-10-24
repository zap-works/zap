# The cartridge's sprite windows as the widescreen widens them (cartridge/patches.zap): the edges,
# relative to the camera, at which a level's sprites spawn ($02:A802) and are erased (the three
# banks' SubOffscreen), each a 16-bit offset the code adds to the camera from a pair of byte
# tables (low bytes, high bytes) by an index. While the scene is drawn wide a right edge moves out
# by the right margin and a left one by the left; natively the byte read is the byte given.

import recomp.snes.console
import recomp.snes.cpu

# the edge at `index` of the tables, moved out on `side` (1 right, -1 left, 0 kept)
fn widenedEdge(low i64, high i64, index i64, side i64) i64:
	edge = romByte(low + index) | (romByte(high + index) << 8)
	if edge & 0x8000 != 0: edge -= 0x1_0000
	if side > 0: return edge + console.sideRight
	if side < 0: return edge - console.sideLeft
	edge

fn edgeByte(read u8, low i64, high i64, side i64, wantHigh bool) u8:
	if side == 0 or not console.growsLogic(): return read
	edge = widenedEdge(low, high, i64(cpu.y & 0xFF), side)
	u8.wrap(edge >> 8 if wantHigh else edge)

# SubOffscreen's horizontal check: Y even the right edge, odd the left (they alternate by frame)
pub fn eraseEdge(read u8, low i64, high i64, wantHigh bool) u8:
	edgeByte(read, low, high, 1 - 2 * i64(cpu.y & 1), wantHigh)

# The spawner's column: Y is the scroll's direction, 0 left, 2 right (1, the level's load, kept);
# a vertical level's spawn is by row, kept.
pub fn spawnEdge(read u8, wantHigh bool) u8:
	direction = i64(cpu.y & 0xFF)
	side = direction - 1 if direction != 1 and console.wram[0x5B] & 1 == 0 else 0
	edgeByte(read, 0x02_A7F6, 0x02_A7F9, side, wantHigh)
