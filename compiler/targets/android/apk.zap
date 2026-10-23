# An app's APK, written by zap itself: a zip of AndroidManifest.xml (manifest.zap), with --icon its
# resources.arsc (first, so its bytes start at a multiple of 4 as Android maps it) and the icon's
# PNG (resources.zap), the program as lib/<abi>/libmain.so and the files of --assets' dir under assets/ (which the app copies into
# its files dir, runtime/core/linux/app/assets.zap), each stored as it is, signed by
# APK Signature Scheme v2: the APK Signing Block before the zip's central directory holds the
# SHA-256 of its parts' 1 MB chunks, signed by the machine's key (key.zap), with the key's
# certificate. Its bytes are the same for the same program on the same machine.

import digest
import fs

# a zip entry's date: 1980-01-01, the earliest, so a build writes the same bytes every time
zipDate = 0x21

# the chunks the content digest is taken over
apkChunkBytes = 1_048_576

# APK Signature Scheme v2's id in the signing block, and its algorithm: RSASSA-PKCS1-v1_5 with
# SHA-256
apkSignatureId = 0x7109_871A
apkAlgorithm = 0x0103

# the APK of the app whose program is the shared object at library, of this stem, written at
# path; false when it cannot be
fn writeApk(library str, stem str, path str):
	program = fs.readBytes(library) ?? return false
	icon = appIconFile != ""
	label = stem if appLabel == "" else appLabel
	manifest = binaryXml(manifestEvents(appPackage(stem), label, icon))
	abi = "arm64-v8a" if onArm() else "x86_64"
	files = []
	if icon:
		files.push(("resources.arsc", resourceTable(appPackage(stem))))
		files.push((appPicturePath, fs.readBytes(appIconFile) ?? return false))
		files.push((appAdaptivePath, adaptiveIconXml()))
	files.push(("AndroidManifest.xml", manifest))
	files.push(("lib/{abi}/libmain.so", program))
	if appAssetsDir != "":
		for name in fs.list(appAssetsDir) ?? []:
			files.push(("assets/{name}", fs.readBytes(fs.join(appAssetsDir, name)) ?? return false))
	entries = []
	central = []
	for (name, bytes) in files:
		central.extend(zipHeader(true, name, bytes, entries.len))
		entries.extend(zipHeader(false, name, bytes, 0))
		entries.extend(bytes)
	end = zipEnd(files.len, central.len, entries.len)
	block = appKey().signingBlock(contentDigest(entries, central, end))
	end.setU32le(16, u32(entries.len + block.len))   # the central directory's place, past the block
	apk = move entries
	apk.extend(block)
	apk.extend(central)
	apk.extend(end)
	match fs.writeBytes(path, apk):
		error: false
		_: true

# the package an app of this stem is: zap.<stem>, its letters lowered and what Java's names refuse
# made _
fn appPackage(stem str):
	word = stem.lower().bytes().map(str.fromCode(it) if .isWordByte() else "_").join("")
	"zap.{"app" if word == "" or word[0].isDigit() else ""}{word}"

# an entry's local header (central: its central directory's, the local one at offset)
fn zipHeader(central bool, name str, bytes u8[], offset i64):
	out = []
	out.pushU32le(0x0201_4B50 if central else 0x0403_4B50)
	if central:
		out.pushU16le(20)   # made by
	for half in [20, 0, 0, 0, zipDate]:   # needs 2.0, no flags, stored, at midnight of the date
		out.pushU16le(half)
	out.pushU32le(digest.crc32(bytes))
	out.pushU32le(bytes.len)
	out.pushU32le(bytes.len)
	out.pushU16le(name.len)
	out.pushU16le(0)   # no extra field
	if central:
		for half in [0, 0, 0]:   # no comment, disk 0, no internal attributes
			out.pushU16le(half)
		out.pushU32le(0)   # no external attributes
		out.pushU32le(offset)
	out.extend(name.bytes())
	out

# the end of the central directory: its entries, size and place
fn zipEnd(count i64, size i64, at i64):
	out = []
	out.pushU32le(0x0605_4B50)
	for half in [0, 0, count, count]:
		out.pushU16le(half)
	out.pushU32le(size)
	out.pushU32le(at)
	out.pushU16le(0)   # no comment
	out

# the bytes after their length (4 bytes)
fn lengthPrefixed(bytes u8[]):
	out = []
	out.pushU32le(bytes.len)
	out.extend(bytes)
	out

# an algorithm's id and its value, length-prefixed
fn algorithmPair(value u8[]):
	pair = []
	pair.pushU32le(apkAlgorithm)
	pair.extend(lengthPrefixed(value))
	lengthPrefixed(pair)

# The APK Signing Block of the zip's content digest: one signer, the key's
fn signingBlock(key AppKey, content u8[]):
	signed = lengthPrefixed(algorithmPair(content))
	signed.extend(lengthPrefixed(lengthPrefixed(key.certificate())))
	signed.extend(lengthPrefixed([]))   # no additional attributes
	signer = lengthPrefixed(signed)
	signer.extend(lengthPrefixed(algorithmPair(key.sign(signed))))
	signer.extend(lengthPrefixed(key.publicKeyInfo()))
	value = lengthPrefixed(lengthPrefixed(signer))
	pairs = []
	pairs.pushU64le(4 + value.len)
	pairs.pushU32le(apkSignatureId)
	pairs.extend(value)
	block = []
	block.pushU64le(pairs.len + 24)
	block.extend(pairs)
	block.pushU64le(pairs.len + 24)
	block.extend("APK Sig Block 42".bytes())
	block

# the digest of the zip's parts' chunks (its entries, central directory and end, which still
# places the directory right after the entries): each chunk's SHA-256 after 0xA5 and its length,
# then theirs after 0x5A and their count
fn contentDigest(entries u8[], central u8[], end u8[]):
	digests = []
	addChunkDigests(digests, entries)
	addChunkDigests(digests, central)
	addChunkDigests(digests, end)
	top u8[] = [0x5A]
	top.pushU32le(digests.len / 32)
	top.extend(digests)
	digest.sha256(top)

fn addChunkDigests(mut digests u8[], part u8[]):
	at = 0
	while at < part.len:
		chunk = part[at..(at + apkChunkBytes).min(len)]
		head u8[] = [0xA5]
		head.pushU32le(chunk.len)
		head.extend(chunk)
		digests.extend(digest.sha256(head))
		at += apkChunkBytes
