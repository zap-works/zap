# pl:u, the shared fonts (switchbrew: Shared fonts): the system's fonts as one shared memory of
# BFTTF fonts one after the other, which a game maps and reads. The fonts are the firmware's,
# extracted beside the game (rom/firmware/fonts); a game gets what the shared memory holds.

import fs
import recomp.switch.package

sharedFontsSize = 0x110_0000
loadStateLoaded = 2

# the fonts in the order of nn::pl's types (JapanUS, then the Chinese, Korean and Nintendo ones)
fontFiles = [
	"nintendo_udsg-r_std_003.ttf",
	"nintendo_udsg-r_org_zh-cn_003.ttf",
	"nintendo_udsg-r_ext_zh-cn_003.ttf",
	"nintendo_udjxh-db_zh-tw_003.ttf",
	"nintendo_udsg-r_ko_003.ttf",
	"nintendo_ext_003.ttf",
	"nintendo_ext2_003.ttf"
]

# The shared fonts of a firmware: each BFTTF's place in the memory and its size, and the memory.
pub type SharedFonts:
	offsets i64[] = []
	sizes i64[] = []
	memory u8[] = []

pub fn loadSharedFonts(firmwareDir str) SharedFonts:
	f = SharedFonts(memory = zeros(sharedFontsSize))
	at = 0
	for name in fontFiles:
		ttf = fs.readBytes(fs.join(fs.join(firmwareDir, "fonts"), name)) ?? []
		bfttf = package.encodeBfttf(ttf)
		f.offsets.push(at)
		f.sizes.push(bfttf.len)
		for j, b in bfttf:
			f.memory[at + j] = b
		at += bfttf.len.alignUp(0x10)
	f

# the font of a request's type, none when there is no such one
fn fontType(k Kernel, req Request) i64?:
	t = req.arg(0, 4)
	if t < 0 or t >= fontFiles.len: return none
	t

fn platformService(mut k Kernel, i i64, req Request, mut res Response):
	if not k.files.fontsLoaded:
		k.files.fonts = loadSharedFonts(fs.join(fs.dirOf(k.titleDir), "firmware"))
		k.files.fontsLoaded = true
	f = k.files.fonts.copy()
	match req.command:
		0: pass
		1: res.u32(loadStateLoaded)
		2: res.u32(f.sizes[k.fontType(req) ?? return res.fail(resultInvalidFont)])
		3: res.u32(f.offsets[k.fontType(req) ?? return res.fail(resultInvalidFont)])
		4: res.copied.push(k.newSharedMemory(sharedFontsSize, f.memory))
		5, 6:
			types u8[] = []
			offsets u8[] = []
			sizes u8[] = []
			for t in 0..fontFiles.len:
				types.pushU32le(t)
				offsets.pushU32le(f.offsets[t])
				sizes.pushU32le(f.sizes[t])
			putBuffer(req.b[0], types)
			putBuffer(req.b[1], offsets)
			putBuffer(req.b[2], sizes)
			res.u8(1)
			res.align(4)
			res.u32(fontFiles.len)
		_: k.unwritten(i, req)

# the Result for a font type that does not exist (pl 1)
resultInvalidFont = 0x202
