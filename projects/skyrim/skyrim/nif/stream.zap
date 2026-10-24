# What NIF blocks read beside a Reader's own reads (runtime/bytes/bytes.zap): references, names,
# transforms. A block is read inside the window [at, end) of the file's bytes, and a read past it
# sets `short`, which the caller turns into an error once.

# a count then that many references (-1 for none)
fn readRefs(mut s Reader):
	s.numbers(s.recordCount(4), i32(0)).map(i64(it))

# a name: an index into the string table, "" for -1
fn readName(mut s Reader, names str[]):
	k = s.i32()
	names[k].copy() if k >= 0 and k < names.len else ""

# Gamebryo's 3 x 3 rotation, rows first, for a matrix that turns a column vector (NiMatrix3's
# own layout), with the translation and the uniform scale: one Mat4.
fn placed(at Vec3, r f32[], scale f32):
	Mat4(
		Vec4(r[0] * scale, r[3] * scale, r[6] * scale, 0.0),
		Vec4(r[1] * scale, r[4] * scale, r[7] * scale, 0.0),
		Vec4(r[2] * scale, r[5] * scale, r[8] * scale, 0.0),
		Vec4(at.x, at.y, at.z, 1.0)
	)

# a node's transform: the translation, the rotation, the scale
fn readTransform(mut s Reader):
	at = s.vec3()
	r = s.numbers(9, f32(0))
	at.placed(r, s.f32())

# NiTransform's order (NiSkinData's): the rotation, the translation, the scale
fn readSkinTransform(mut s Reader):
	r = s.numbers(9, f32(0))
	at = s.vec3()
	at.placed(r, s.f32())
