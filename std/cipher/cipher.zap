# Block ciphers: AES-128 (FIPS 197) by tables of whole rounds, with the modes a console's
# packages use: ECB for a wrapped key, CTR for a stream read at any offset, and XTS for sectors.

# the field's multiplication of two bytes (the polynomial 0x11B)
pub fn gmul(a i64, b i64) i64:
	r = 0
	x = a
	y = b
	while y != 0:
		if (y & 1) != 0: r ^= x
		x = ((x << 1) ^ (0x11B if (x & 0x80) != 0 else 0)) & 0xFF
		y >>= 1
	r

fn rotl8(b i64, n i64):
	((b << n) | (b >> (8 - n))) & 0xFF

# the S-box: each byte's inverse in the field, then the affine map
fn makeSbox():
	s u8[] = zeros(256)
	for x in 0..256:
		inv = 0
		if x != 0:
			for y in 1..256:
				if gmul(x, y) == 1:
					inv = y
					break
		s[x] = u8(inv ^ rotl8(inv, 1) ^ rotl8(inv, 2) ^ rotl8(inv, 3) ^ rotl8(inv, 4) ^ 0x63)
	s

pub sbox = makeSbox()

fn makeInverse(s u8[]):
	inv u8[] = zeros(256)
	for x in 0..256:
		inv[s[x]] = x
	inv

pub inverseSbox = makeInverse(sbox)

# a round's column mix of one byte, for each of the four places it lands: `coef` the column's
# multipliers (2 1 1 3 forward, 14 9 13 11 back) over the S-box's or its inverse's byte
fn makeRound(s u8[], coef i64[], shift i64):
	t u32[] = zeros(256)
	for x in 0..256:
		v = i64(s[x])
		w = gmul(v, coef[0]) << 24 | gmul(v, coef[1]) << 16 | gmul(v, coef[2]) << 8 | gmul(
			v,
			coef[3]
		)
		t[x] = u32(w).rotateLeft(32 - shift) if shift != 0 else u32(w)
	t

te0 = makeRound(sbox, [2, 1, 1, 3], 0)
te1 = makeRound(sbox, [2, 1, 1, 3], 8)
te2 = makeRound(sbox, [2, 1, 1, 3], 16)
te3 = makeRound(sbox, [2, 1, 1, 3], 24)
td0 = makeRound(inverseSbox, [14, 9, 13, 11], 0)
td1 = makeRound(inverseSbox, [14, 9, 13, 11], 8)
td2 = makeRound(inverseSbox, [14, 9, 13, 11], 16)
td3 = makeRound(inverseSbox, [14, 9, 13, 11], 24)

roundConstants u32[10] = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1B, 0x36]

fn subWord(w u32):
	u32(sbox[w >> 24]) << 24 | u32(
		sbox[(w >> 16) & 0xFF]
	) << 16 | u32(sbox[(w >> 8) & 0xFF]) << 8 | sbox[w & 0xFF]

# An AES-128 key expanded into its round keys, for both directions.
pub type Aes128:
	enc u32[] = []
	dec u32[] = []

	# the 16 bytes at `at` of `src` encrypted into `out` at `to`
	fn encryptInto(src u8[], at i64, mut out u8[], to i64):
		rk = enc
		s0 = src.u32be(at) ^ rk[0]
		s1 = src.u32be(at + 4) ^ rk[1]
		s2 = src.u32be(at + 8) ^ rk[2]
		s3 = src.u32be(at + 12) ^ rk[3]
		k = 4
		loop 9:
			t0 = te0[s0 >> 24] ^ te1[
				(s1 >> 16) & 0xFF
			] ^ te2[(s2 >> 8) & 0xFF] ^ te3[s3 & 0xFF] ^ rk[k]
			t1 = te0[s1 >> 24] ^ te1[
				(s2 >> 16) & 0xFF
			] ^ te2[(s3 >> 8) & 0xFF] ^ te3[s0 & 0xFF] ^ rk[k + 1]
			t2 = te0[s2 >> 24] ^ te1[
				(s3 >> 16) & 0xFF
			] ^ te2[(s0 >> 8) & 0xFF] ^ te3[s1 & 0xFF] ^ rk[k + 2]
			t3 = te0[s3 >> 24] ^ te1[
				(s0 >> 16) & 0xFF
			] ^ te2[(s1 >> 8) & 0xFF] ^ te3[s2 & 0xFF] ^ rk[k + 3]
			s0 = t0
			s1 = t1
			s2 = t2
			s3 = t3
			k += 4
		out.setU32be(to, lastRound(sbox, s0, s1, s2, s3) ^ rk[40])
		out.setU32be(to + 4, lastRound(sbox, s1, s2, s3, s0) ^ rk[41])
		out.setU32be(to + 8, lastRound(sbox, s2, s3, s0, s1) ^ rk[42])
		out.setU32be(to + 12, lastRound(sbox, s3, s0, s1, s2) ^ rk[43])

	# the 16 bytes at `at` of `src` decrypted into `out` at `to`
	fn decryptInto(src u8[], at i64, mut out u8[], to i64):
		rk = dec
		s0 = src.u32be(at) ^ rk[0]
		s1 = src.u32be(at + 4) ^ rk[1]
		s2 = src.u32be(at + 8) ^ rk[2]
		s3 = src.u32be(at + 12) ^ rk[3]
		k = 4
		loop 9:
			t0 = td0[s0 >> 24] ^ td1[
				(s3 >> 16) & 0xFF
			] ^ td2[(s2 >> 8) & 0xFF] ^ td3[s1 & 0xFF] ^ rk[k]
			t1 = td0[s1 >> 24] ^ td1[
				(s0 >> 16) & 0xFF
			] ^ td2[(s3 >> 8) & 0xFF] ^ td3[s2 & 0xFF] ^ rk[k + 1]
			t2 = td0[s2 >> 24] ^ td1[
				(s1 >> 16) & 0xFF
			] ^ td2[(s0 >> 8) & 0xFF] ^ td3[s3 & 0xFF] ^ rk[k + 2]
			t3 = td0[s3 >> 24] ^ td1[
				(s2 >> 16) & 0xFF
			] ^ td2[(s1 >> 8) & 0xFF] ^ td3[s0 & 0xFF] ^ rk[k + 3]
			s0 = t0
			s1 = t1
			s2 = t2
			s3 = t3
			k += 4
		out.setU32be(to, lastRound(inverseSbox, s0, s3, s2, s1) ^ rk[40])
		out.setU32be(to + 4, lastRound(inverseSbox, s1, s0, s3, s2) ^ rk[41])
		out.setU32be(to + 8, lastRound(inverseSbox, s2, s1, s0, s3) ^ rk[42])
		out.setU32be(to + 12, lastRound(inverseSbox, s3, s2, s1, s0) ^ rk[43])

	# The bytes (a whole number of blocks) decrypted block by block (ECB).
	fn decryptEcb(src u8[]):
		out u8[] = zeros(src.len)
		for at in (0..src.len / 16).map(it * 16):
			decryptInto(src, at, out, at)
		out

	# The bytes (a whole number of blocks) encrypted block by block (ECB).
	fn encryptEcb(src u8[]):
		out u8[] = zeros(src.len)
		for at in (0..src.len / 16).map(it * 16):
			encryptInto(src, at, out, at)
		out

	# The bytes xored in place with the counter's stream (CTR): `counter` the 16-byte big-endian
	# block number of the first byte, which starts a block.
	fn ctrInPlace(mut d u8[], counter u8[]):
		ctr = counter.copy()
		stream u8[] = zeros(16)
		at = 0
		while at < d.len:
			encryptInto(ctr, 0, stream, 0)
			n = (d.len - at).min(16)
			for i in 0..n:
				d[at + i] ^= stream[i]
			at += 16
			i = 15
			while i >= 0:
				ctr[i] += 1
				if ctr[i] != 0: break
				i -= 1

# the S-box's bytes of the four words' bytes in a round's last order, as one word
fn lastRound(s u8[], a u32, b u32, c u32, d u32):
	u32(s[a >> 24]) << 24 | u32(
		s[(b >> 16) & 0xFF]
	) << 16 | u32(s[(c >> 8) & 0xFF]) << 8 | s[d & 0xFF]

# The 16-byte key expanded (FIPS 197's schedule, the decryption's keys mixed back for the
# equivalent inverse cipher).
pub fn aes128(key u8[]) Aes128:
	w u32[] = zeros(44)
	for i in 0..4:
		w[i] = key.u32be(4 * i)
	for i in 4..44:
		t = w[i - 1]
		if i % 4 == 0: t = subWord(t.rotateLeft(8)) ^ (roundConstants[i / 4 - 1] << 24)
		w[i] = w[i - 4] ^ t
	d u32[] = zeros(44)
	for r in 0..11:
		for c in 0..4:
			v = w[(10 - r) * 4 + c]
			if r > 0 and r < 10:
				v = td0[sbox[v >> 24]] ^ td1[
					sbox[(v >> 16) & 0xFF]
				] ^ td2[sbox[(v >> 8) & 0xFF]] ^ td3[sbox[v & 0xFF]]
			d[r * 4 + c] = v
	Aes128(enc = w, dec = d)

# Sectors decrypted in XTS mode (IEEE 1619) with the two halves of a 32-byte key: `first` the
# number of the first sector, written big-endian into its tweak as Nintendo's packages do.
pub fn decryptXts(key u8[], src u8[], first i64, sectorSize i64) u8[]:
	data = aes128(key[..16])
	tweaks = aes128(key[16..32])
	out u8[] = zeros(src.len)
	block u8[] = zeros(16)
	tweak u8[] = zeros(16)
	for sector in 0..src.len / sectorSize:
		number u8[] = zeros(16)
		number.setU64be(8, u64(first + sector))
		tweaks.encryptInto(number, 0, tweak, 0)
		base = sector * sectorSize
		for at in (0..sectorSize / 16).map(base + it * 16):
			for i in 0..16:
				block[i] = src[at + i] ^ tweak[i]
			data.decryptInto(block, 0, out, at)
			for i in 0..16:
				out[at + i] ^= tweak[i]
			carry = tweak[15] >> 7
			i = 15
			while i > 0:
				tweak[i] = (tweak[i] << 1) | (tweak[i - 1] >> 7)
				i -= 1
			tweak[0] = (tweak[0] << 1) ^ (0x87 if carry != 0 else 0)
	out

# The bytes written as hexadecimal digits, two a byte (a key as a keys file holds it); none when
# a character is no digit or the count is odd.
pub fn fromHex(s str) u8[]?:
	if s.len % 2 != 0: return none
	out = []
	for i in 0..s.len / 2:
		hi = s[2 * i].hexValue()
		lo = s[2 * i + 1].hexValue()
		if hi < 0 or lo < 0: return none
		out.push(u8(hi << 4 | lo))
	out

fn hex(b u8[]):
	b.map("{it:02x}").join("")

fn unhex(s str):
	fromHex(s) ?? []

test "AES-128 encrypts and decrypts FIPS 197's example":
	k = aes128(unhex("000102030405060708090a0b0c0d0e0f"))
	plain = unhex("00112233445566778899aabbccddeeff")
	sealed = k.encryptEcb(plain)
	expect hex(sealed) == "69c4e0d86a7b0430d8cdb78070b4c55a"
	expect hex(k.decryptEcb(sealed)) == hex(plain)

test "CTR is its own inverse and carries the counter across bytes":
	k = aes128(unhex("2b7e151628aed2a6abf7158809cf4f3c"))
	d = unhex("6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51")
	counter = unhex("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff")
	k.ctrInPlace(d, counter)
	expect hex(d) == "874d6191b620e3261bef6864990db6ce9806f66b7970fdff8617187bb9fffdff"

test "XTS decrypts IEEE 1619's first vector, a tweak of sector 0":
	key u8[] = zeros(32)
	sealed = unhex("917cf69ebd68b2ec9b9fe9a3eadda692cd43d2f59598ed858c02c2652fbf922e")
	expect hex(decryptXts(key, sealed, 0, 32)) ==
		"0000000000000000000000000000000000000000000000000000000000000000"
