# A field a method names bare (`items.len`) is not a module's prefix, though a module of that
# name is under the program's root (shelf.items, which imports bag: imported, it would make a
# cycle through bag).
import bag
import shelf.items

test "a method's field named like a module is the field":
	b = bag.Bag(items = [3, 4])
	expect b.count() == 2
	expect items.inBag() == 1
