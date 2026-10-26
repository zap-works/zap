# An element of another module's map, bound to a name, is a borrow of the map kept in the data
# area, not of a fresh copy that ends with the statement.

import forms

test "an element of another module's map keeps its strings":
	f = forms.table[1]
	print("{f.name} {f.operands}")
	prints "name1 [\"Ev\", \"Gv\"]"
