# A copy of a window in a generic instance (T = ref str) is the window itself: no text made
# and freed under it.
fn lastOf<T>(xs T[]) T?:
	if xs.len == 0: return none
	xs[len - 1].copy()

test "last of windows":
	s0 = "a"
	t = "bb"
	h (ref str)[] = [s0, t]
	g (ref str)[] = [t, s0]
	expect (lastOf(h) ?? "x") == "bb"
	expect (lastOf(g) ?? "x") == "a"
