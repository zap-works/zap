# A module's binding set by a call is given its value once, before the program runs (spec 5),
# however often it is read.
import counted

test "a module binding set by a call is computed once":
	expect counted.value == 10
	expect counted.value == 10
	expect counted.label == "made 20"
	expect counted.label == "made 20"
