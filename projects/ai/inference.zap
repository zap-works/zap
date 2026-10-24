# What a transformer's inference adds to std/tensor (rotary positions, a cache written in place,
# one position's attention), the same on the CPU and the GPU; and std/gguf reading a file this test
# writes (the GPU's part skipped where there is none).

import fs
import gguf
import gpu
import tensor

fn near(a f32[], b f32[], tol f32 = 0.0001):
	a.len == b.len and (0..a.len).all((a[it] - b[it]).abs() <= tol * (1.0 + b[it].abs()))

test "rotary positions turn each head's pairs by the position's angles":
	x = tensor.fromList([2, 4], [1.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0])
	# heads of 4: the first pair turns by the position, the second by position / 100
	turned = x.rope(1, 1, 10000.0).toList()
	print("{(f64(turned[0]) - 1.0.cos()).abs() < 0.00001} {(f64(turned[1]) - 1.0.sin()).abs() < 0.00001} {(f64(turned[4]) - 2.0.cos()).abs() < 0.00001}")
	if gpu.available():
		big = tensor.randomNormal([3, 64], seed = 1)
		expect near(big.gpu().rope(4, 7).toList(), big.rope(4, 7).toList(), 0.0005)
	prints "true true true"

test "a cache written in place and one position's attention over it":
	keys = tensor.zeros([4, 8])
	values = tensor.zeros([4, 8])
	k = tensor.randomNormal([2, 8], seed = 2)
	v = tensor.randomNormal([2, 8], seed = 3)
	keys.writeRows(1, k)
	values.writeRows(1, v)
	q = tensor.randomNormal([1, 16], seed = 4)
	# four heads of 4 over two of the keys': heads 0 and 1 read the first, 2 and 3 the second
	a = q.attend(keys, values, 2, 4, 2)
	print("{keys.toList()[8..16] == k.toList()[..8]} {a.shape}")
	if gpu.available():
		gk = tensor.zeros([4, 8]).gpu()
		gv = tensor.zeros([4, 8]).gpu()
		gk.writeRows(1, k.gpu())
		gv.writeRows(1, v.gpu())
		expect near(gk.toList(), keys.toList())
		expect near(q.gpu().attend(gk, gv, 2, 4, 2).toList(), a.toList(), 0.0005)
		# three positions at once, each over the rows up to its own, as each alone
		rows = tensor.randomNormal([3, 16], seed = 5)
		together = rows.gpu().attend(gk, gv, 1, 4, 2).toList()
		for r in 0..3:
			alone = rows.rows(r, 1).attend(keys, values, 1 + r, 4, 2).toList()
			expect near(together[r * 16..(r + 1) * 16], alone, 0.0005)
	prints "true [1, 16]"

# a GGUF file of version 3: a text, a number and a list of texts, an f32 tensor [2, 3] and a Q8_0
# one [1, 32] whose numbers are 0..31 (its scale 31 / 127)
fn sample():
	b = "GGUF".bytes().copy()
	b.pushU32le(3)
	b.pushU64le(2)
	b.pushU64le(3)
	for (key, kind) in [
		("general.architecture", 8),
		("llama.block_count", 4),
		("tokenizer.ggml.tokens", 9)
	]:
		b.pushU64le(key.len)
		b.extend(key.bytes())
		b.pushU32le(kind)
		if kind == 8:
			b.pushU64le(5)
			b.extend("llama".bytes())
		elif kind == 4:
			b.pushU32le(22)
		else:
			b.pushU32le(8)
			b.pushU64le(2)
			for t in ["<s>", "a"]:
				b.pushU64le(t.len)
				b.extend(t.bytes())
	for (name, dims, kind, offset) in [("w", [3, 2], 0, 0), ("q", [32, 1], 8, 32)]:
		b.pushU64le(name.len)
		b.extend(name.bytes())
		b.pushU32le(2)
		for d in dims:
			b.pushU64le(d)
		b.pushU32le(kind)
		b.pushU64le(offset)
	while b.len % 32 != 0:
		b.push(0)
	for x in [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]:
		b.extend([f32(x)].bytes())
	while b.len % 32 != 0:
		b.push(0)
	half = halfBits(31.0 / 127.0)
	b.push(half & 0xFF)
	b.push(u8(half >> 8))
	for i in 0..32:
		b.push(u8((f32(i) / (31.0 / 127.0)).round()))
	b

test "a GGUF file's metadata and tensors":
	path = "{testDir()}sample.gguf"
	_ = fs.writeBytes(path, sample())
	g = gguf.open(path) ?? fail("{error}")
	print("{g.text("general.architecture")} {g.int("llama.block_count")} {g.texts("tokenizer.ggml.tokens")}")
	print("{g.tensors.map(.name)} {g.tensors.map(.shape.copy())}")
	q = g.rows("q", 0, 1) ?? fail("{error}")
	print("{(q[31] - 31.0).abs() < 0.02} {(q[10] - 10.0).abs() < 0.2}")
	print(g.rows("w", 1, 1) ?? fail("{error}"))
	short = "{testDir()}short.gguf"
	_ = fs.writeBytes(short, sample()[..40])
	match gguf.open(short):
		g2: print("opened {g2.size}")
		error: print(error)
	prints """
		some("llama") some(22) some(["<s>", "a"])
		["w", "q"] [[2, 3], [1, 32]]
		true true
		[4, 5, 6]
		{testDir()}short.gguf's header is damaged
		"""
