# RomFS, a section's file system (level 3 of its IVFC tree): a header of ten u64 (the tables'
# places, the files' data), a table of dirs (parent, next sibling, first child dir, first file,
# hash link, name) and one of files (parent, next sibling, data's offset and size, hash link,
# name). 0xFFFFFFFF links nothing.

none32 = 0xFFFF_FFFF

pub type RomFile:
	path str   # from the RomFS's root, '/' between parts
	at i64   # from the RomFS's start
	size i64

# a dir or file entry's name: its length at `lengthAt`, the bytes after it
fn entryName(table u8[], lengthAt i64):
	n = i64(table.u32le(lengthAt))
	table[lengthAt + 4..lengthAt + 4 + n].text().copy()

# the files under the dir at `dir` of the dirs' table, their paths starting with `prefix`
fn walkDir(dirs u8[], files u8[], dataAt i64, dir i64, prefix str, mut out RomFile[]):
	f = i64(dirs.u32le(dir + 12))
	while f != none32:
		name = entryName(files, f + 28)
		out.push(
			RomFile(
				path = "{prefix}{name}",
				at = dataAt + i64(files.u64le(f + 8)),
				size = i64(files.u64le(f + 16))
			)
		)
		f = files.u32le(f + 4)
	child = i64(dirs.u32le(dir + 8))
	while child != none32:
		walkDir(dirs, files, dataAt, child, "{prefix}{entryName(dirs, child + 20)}/", out)
		child = dirs.u32le(child + 4)

# Every file of a RomFS, read through `read(at, n)` (bytes from the RomFS's start).
pub fn romFiles(read fn(i64, i64) u8[]) RomFile[]:
	head = read(0, 0x50)
	if head.len < 0x50: return []
	dirs = read(i64(head.u64le(0x18)), i64(head.u64le(0x20)))
	files = read(i64(head.u64le(0x38)), i64(head.u64le(0x40)))
	out = []
	walkDir(dirs, files, i64(head.u64le(0x48)), 0, "", out)
	out
