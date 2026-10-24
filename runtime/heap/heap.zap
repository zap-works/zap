# Heap<T>: a min-heap (4-ary), values pushed in any order come out smallest first (a priority
# queue); for the largest first, push a key that orders the other way (-x, or a tuple).
# mut h = Heap<i64>(), h.push(5), h.pop() (an i64?). The indexes it swaps lie inside
# the list, so it swaps without a check.

pub type Heap<T Ord>:
	items T[] = []

	fn len() n64:
		items.len

	fn isEmpty() bool:
		items.isEmpty

	# the smallest value, borrowed; none when empty
	fn first() ref T?:
		items.first

	mut fn push(move v T):
		items.push(__zeroElem(items))   # room, written over by the sift
		heapSiftUp(items, v)

	# the smallest value, taken out; none when empty. The last value fills the hole the
	# smallest leaves
	mut fn pop() T?:
		if items.isEmpty: return none
		heapTake(items)
