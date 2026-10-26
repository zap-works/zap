# A call in tail position, its result returned as it is with nothing left to drop and its
# arguments in registers, is a jump once the frame is given back: a recursion that only calls
# itself last runs in constant stack, however deep.

fn countDown(n i64, acc i64) i64:
	if n == 0: return acc
	countDown(n - 1, acc + n % 7)

fn isEven(n i64) bool:
	if n == 0: return true
	isOdd(n - 1)

fn isOdd(n i64) bool:
	if n == 0: return false
	isEven(n - 1)

# a local list owned here: dropped after the call, so the call is no tail call (and still right)
fn sumAfter(n i64) i64:
	xs = [n, n + 1]
	if n == 0: return xs[0]
	sumAfter(n - 1) + xs[1] - xs[0]

test "tail calls run in constant stack":
	expect countDown(50_000_000, 0) == 149_999_998
	expect not isEven(10_000_001)
	expect sumAfter(1000) == 1000
