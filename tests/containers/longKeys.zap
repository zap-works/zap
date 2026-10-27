# Keys of 32 bytes or more are hashed by four chains at once (runtime/core/strings.zap's
# bytesHash): every length from 1 to 100 keeps its entries apart, a byte changed anywhere changes
# the hash, and equal text hashes alike.

test "long keys stay distinct in a map":
	m {str: i64} = {}
	for n in 1..101:
		for k in 0..20:
			m["{"x".repeat(n)}{k}"] = n * 100 + k
	expect m.len == 100 * 20
	for n in 1..101:
		for k in 0..20:
			expect m["{"x".repeat(n)}{k}"] == n * 100 + k

test "a byte changed anywhere in a long key changes its hash":
	base = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_"
	for i in 0..base.len:
		changed = "{base[..i]}#{base[i + 1..]}"
		expect changed.hash() != base.hash()
	expect base.copy().hash() == base.hash()
