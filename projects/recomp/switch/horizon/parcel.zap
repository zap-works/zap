# Android parcels (switchbrew: Display services), the container of the binder relay: a header
# (data size, data offset, objects size, objects offset) and the data, words and strings
# aligned to four bytes. A flattened object is its length, its file descriptor count and its
# bytes.

parcelHeaderSize = 0x10

# The data of the parcel `bytes`, read word by word.
pub type ParcelReader:
	data u8[]
	at i64 = 0

	# the next word, zero past the end
	fn read32():
		if at + 4 > data.len: return 0
		v = i64(data.u32le(at))
		at += 4
		v

	# the interface token: the strict mode word and the UTF-16 name
	fn skipToken():
		read32()
		characters = read32()
		at += ((characters + 1) * 2 + 3) & ~3

	# the bytes of a flattened object
	fn flattened():
		length = read32()
		read32()
		if at + length > data.len: return []
		out = data[at..at + length].copy()
		at += (length + 3) & ~3
		out

pub fn readParcel(bytes u8[]) ParcelReader:
	if bytes.len < parcelHeaderSize: return ParcelReader(data = [])
	size = i64(bytes.u32le(0))
	offset = i64(bytes.u32le(4))
	if offset + size > bytes.len: return ParcelReader(data = [])
	ParcelReader(data = bytes[offset..offset + size].copy())

pub type ParcelWriter:
	data u8[] = []

	fn write32(v i64):
		data.pushU32le(v & 0xFFFF_FFFF)

	# a flattened object of these bytes, with no file descriptors
	fn flattened(bytes u8[]):
		write32(bytes.len)
		write32(0)
		data.extend(bytes)
		while data.len % 4 != 0:
			data.push(0)

	# the header and the data, then the objects: `objects` bytes of zeros (a binder's offset table)
	fn finish(objects i64):
		out = []
		out.pushU32le(data.len)
		out.pushU32le(parcelHeaderSize)
		out.pushU32le(objects)
		out.pushU32le(parcelHeaderSize + data.len)
		out.extend(data)
		out.extend(zeros(objects))
		out
