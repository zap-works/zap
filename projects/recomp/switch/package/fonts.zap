# The system's shared fonts (data titles 0100000000000810-0815), kept as BFTTF: TrueType whose
# big-endian 32-bit words are xored with a key, the file's first word the result xored with it and its second
# the font's size xored with it. The decoding is yuzu's (DecryptSharedFont).

expectedMagic = 0x36F8_1A1E
expectedResult = 0x7F9A_0218

# the shared fonts' titles and the names their files are given
pub sharedFonts = [
	(0x0100_0000_0000_0810, "nintendo-extension"),
	(0x0100_0000_0000_0811, "standard"),
	(0x0100_0000_0000_0812, "chinese-simplified"),
	(0x0100_0000_0000_0813, "chinese-traditional"),
	(0x0100_0000_0000_0814, "korean"),
	(0x0100_0000_0000_0815, "nintendo-extension-2")
]

# The TrueType font inside a BFTTF, or none when it is not one.
pub fn decodeBfttf(b u8[]) u8[]?:
	if b.len < 8: return none
	if b.u32be(0) != expectedMagic: return none
	key = b.u32be(0) ^ expectedResult
	size = i64(b.u32be(4) ^ key)
	if size + 8 > b.len: return none
	out u8[] = zeros(size)
	at = 0
	while at + 4 <= size:
		out.setU32be(at, b.u32be(8 + at) ^ key)
		at += 4
	out
