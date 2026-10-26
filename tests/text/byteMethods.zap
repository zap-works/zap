# u8[]'s byte methods: numbers in either byte order, a cursor, tags, names and tables.

test "numbers at an offset, in either byte order":
	d u8[] = [1, 2, 254, 255, 1, 2, 3, 4]
	print("{d.u16le(0)} {d.u16be(0)} {d.i16le(2)} {d.i16be(2)}")
	print("{d.u32le(4)} {d.u32be(4)} {d.i32le(0) & -16777216}")
	f = []
	f.pushF32le(f32(1.5))
	print(f.f32le(0))
	prints """
	    513 258 -2 -257
	    67305985 16909060 -16777216
	    1.5
	    """

test "pushed numbers read back":
	out = []
	out.pushU32le(0x1234_5678)
	out.pushU16be(0x1234)
	out.pushU32be(0x5678)
	out.pushU16le(-5)
	out.pushU64le(0x1122_3344_5566_7788)
	expect out.u32le(0) == 305_419_896
	expect out.u16be(4) == 4660
	expect out.u32be(6) == 22_136
	expect out.i16le(10) == -5
	expect out.i64le(12) == 1_234_605_616_436_508_552

test "every width and both orders, as the type the name says":
	out = []
	out.pushI32be(-7)
	out.pushI64le(-8)
	out.pushF64be(2.5)
	out.pushF32be(f32(-0.5))
	out.pushU64be(0x0102_0304_0506_0708)
	a = out.i32be(0)
	b = out.i64le(4)
	c = out.f64be(12)
	e = out.u64be(24)
	expect a == -7
	expect b == -8
	expect c == 2.5
	expect out.f32be(20) == -0.5
	expect e == 72_623_859_790_382_856
	expect out.i64be(24) == 72_623_859_790_382_856
	expect out.u16le(0) == 0xFFFF

test "a reader takes the next bytes and notes a read past the end":
	d u8[] = [1, 2, 4, 3, 0, 0, 0, 1, 65, 66, 0, 0]
	r = Reader(d, big = true)
	print("{r.u16()} {r.u16()} {r.u32() == 1} {r.short}")
	l = Reader(d)
	print("{l.u8()} {l.skip(20) == 1 and l.short} {l.u32()}")
	t = Reader(d, at = 8)
	name = t.cStringBytes(4)
	print("{str(move name)} {t.at - 10}")
	prints """
	    258 1027 true false
	    1 true 0
	    AB 2
	    """

test "varints read back, small ones in one byte":
	out = []
	for v in [
		0,
		1,
		-1,
		63,
		-64,
		64,
		300,
		-300,
		9_223_372_036_854_775_807,
		-9_223_372_036_854_775_808
	]:
		out.pushVarint(v)
	r = Reader(out)
	back = []
	loop 10:
		back.push(r.varint())
	print("{out.len} {back} {r.varint()} {r.short}")
	prints "31 [0, 1, -1, 63, -64, 64, 300, -300, 9223372036854775807, -9223372036854775808] 0 true"
