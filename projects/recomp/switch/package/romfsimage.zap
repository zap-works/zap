# The RomFS image of a dir of files, as a game reads one (romfs.zap reads the same layout): the
# header, the hash tables of dirs and files, their entries, then the files' data, each aligned.
# Only the tables are built in memory; a file's bytes are read from the dir when asked for.

import fs

romHeaderSize = 0x50
dirEntrySize = 24
fileEntrySize = 32
dataAlign = 0x10

# a dir (size -1) or file found under the root, the dir it is in, by index
type Node:
	name str
	parent i64
	size i64

pub type RomImage:
	root str   # the dir the files are read from
	head u8[] = []   # everything before the first file's data
	files RomFile[] = []   # in order of offset; their paths from the root

# the entries under `dir` (a path below the root), depth first: dirs first among the dirs and
# files of one dir, each dir's entries sorted by name
fn collect(root str, dir str, parent i64, mut dirs Node[], mut files Node[]):
	names = (fs.list(fs.join(root, dir)) ?? []).sorted()
	for name in names:
		path = fs.join(dir, name)
		if fs.isDir(fs.join(root, path)):
			dirs.push(Node(name = name.copy(), parent, size = -1))
			collect(root, path, dirs.len - 1, dirs, files)
		else:
			size = (fs.open(fs.join(root, path)) ?? return).len
			files.push(Node(name = name.copy(), parent, size))

# n copies of v
fn filled(n i64, v i64):
	out = []
	loop n:
		out.push(v)
	out

# the number of buckets a hash table of n entries has (as nn::fs sizes them)
fn bucketCount(n i64):
	if n < 3: return 3
	if n < 19: return n | 1
	b = n
	while [2, 3, 5, 7, 11, 13, 17].any(b % it == 0):
		b += 1
	b

# the hash of a name in the dir at `parentAt` of the dirs' table
fn nameHash(parentAt i64, name str):
	h = (parentAt ^ 123_456_789) & 0xFFFF_FFFF
	for c in name.bytes():
		h = (((h >> 5) | (h << 27)) & 0xFFFF_FFFF) ^ i64(c)
	h

fn entrySize(base i64, name str):
	base + name.len.alignUp(4)

# the offset of each entry in a table where entries have a fixed part of `base` bytes
fn offsetsOf(nodes Node[], base i64):
	at = 0
	out = []
	for n in nodes:
		out.push(at)
		at += entrySize(base, n.name)
	out

# the index of the next entry after i with the same parent, among entries sharing the dir; none32
# for the last
fn nextOf(nodes Node[], i i64):
	for j in i + 1..nodes.len:
		if nodes[j].parent == nodes[i].parent: return j
	-1

# the first entry from index `from` that is in the dir (the root is its own parent: dirs start at 1)
fn firstChild(nodes Node[], from i64, dir i64):
	for j in from..nodes.len:
		if nodes[j].parent == dir: return j
	-1

fn linkAt(offsets i64[], i i64):
	none32 if i < 0 else offsets[i]

fn pushName(mut t u8[], name str):
	t.pushU32le(name.len)
	t.extend(name.bytes())
	while t.len % 4 != 0:
		t.push(0)

# the buckets of a hash table over entries (name, parent dir's offset, entry's offset): the table
# and each entry's next link
fn hashTable(names str[], parents i64[], offsets i64[]):
	count = bucketCount(names.len)
	heads = filled(count, none32)
	chain = filled(offsets.len, none32)
	for i, name in names:
		b = nameHash(parents[i], name) % count
		chain[i] = heads[b]
		heads[b] = offsets[i]
	table = []
	for h in heads:
		table.pushU32le(h)
	(table, chain)

fn dirTable(dirs Node[], dirAt i64[], files Node[], chain i64[]):
	fileAt = offsetsOf(files, fileEntrySize)
	t = []
	for i, d in dirs:
		parent = 0 if i == 0 else dirAt[d.parent]
		t.pushU32le(parent)
		t.pushU32le(none32 if i == 0 else linkAt(dirAt, nextOf(dirs, i)))
		t.pushU32le(linkAt(dirAt, firstChild(dirs, 1, i)))
		t.pushU32le(linkAt(fileAt, firstChild(files, 0, i)))
		t.pushU32le(chain[i])
		t.pushName(d.name)
	t

fn fileTable(dirAt i64[], files Node[], dataAt i64[], chain i64[]):
	fileAt = offsetsOf(files, fileEntrySize)
	t = []
	for i, f in files:
		t.pushU32le(dirAt[f.parent])
		t.pushU32le(linkAt(fileAt, nextOf(files, i)))
		t.pushU64le(dataAt[i])
		t.pushU64le(f.size)
		t.pushU32le(chain[i])
		t.pushName(f.name)
	t

# the image of the files under `root`
pub fn buildRomImage(root str) RomImage:
	dirs = [Node(name = "", parent = 0, size = -1)]
	files = []
	collect(root, "", 0, dirs, files)
	dirAt = offsetsOf(dirs, dirEntrySize)
	fileAt = offsetsOf(files, fileEntrySize)
	dirHash, dirChain = hashTable(dirs.map(.name.copy()), dirs.map(dirAt[.parent]), dirAt)
	fileHash, fileChain = hashTable(files.map(.name.copy()), files.map(dirAt[.parent]), fileAt)
	dirMeta = dirTable(dirs, dirAt, files, dirChain)
	dirsAt = romHeaderSize
	dirMetaAt = dirsAt + dirHash.len
	filesAt = dirMetaAt + dirMeta.len
	fileMetaAt = filesAt + fileHash.len
	nodes = []
	dataAt = []
	at = 0
	for f in files:
		dataAt.push(at)
		at += f.size.alignUp(dataAlign)
	fileMeta = fileTable(dirAt, files, dataAt, fileChain)
	firstData = (fileMetaAt + fileMeta.len).alignUp(dataAlign)
	head = []
	for v in [
		romHeaderSize,
		dirsAt,
		dirHash.len,
		dirMetaAt,
		dirMeta.len,
		filesAt,
		fileHash.len,
		fileMetaAt,
		fileMeta.len,
		firstData
	]:
		head.pushU64le(v)
	head.extend(dirHash)
	head.extend(dirMeta)
	head.extend(fileHash)
	head.extend(fileMeta)
	while head.len < firstData:
		head.push(0)
	paths = romPaths(dirs, files)
	for i, f in files:
		nodes.push(RomFile(path = paths[i].copy(), at = firstData + dataAt[i], size = f.size))
	RomImage(root = root.copy(), head, files = nodes)

# each file's path from the root
fn romPaths(dirs Node[], files Node[]):
	dirPaths str[] = [""]
	for i in 1..dirs.len:
		dirPaths.push("{dirPaths[dirs[i].parent]}{dirs[i].name}/")
	files.map("{dirPaths[.parent]}{.name}")

# The image's size: where the last file's data ends.
pub fn romImageSize(img RomImage) i64:
	if img.files.isEmpty: return img.head.len
	last = img.files[len - 1]
	last.at + last.size

# n bytes of the image from `at`: the tables, then the files' data (zeros between), cut at the
# image's end
pub fn readRomImage(img RomImage, at i64, n i64) u8[]:
	end = at + n.min(img.romImageSize() - at)
	out = []
	pos = at
	while pos < end:
		if pos < img.head.len:
			upto = end.min(img.head.len)
			out.extend(img.head[pos..upto])
			pos = upto
			continue
		f = img.fileAt(pos)
		if f < 0:
			out.push(0)
			pos += 1
			continue
		file = img.files[f]
		upto = end.min(file.at + file.size)
		handle = fs.open(fs.join(img.root, file.path)) ?? return out
		out.extend(handle.readAt(pos - file.at, upto - pos) ?? return out)
		pos = upto
	out

# the file whose data holds the position, -1 for none
fn fileAt(img RomImage, pos i64):
	lo = 0
	hi = img.files.len - 1
	while lo <= hi:
		mid = (lo + hi) / 2
		f = img.files[mid]
		if pos < f.at: hi = mid - 1
		elif pos >= f.at + f.size: lo = mid + 1
		else: return mid
	-1
