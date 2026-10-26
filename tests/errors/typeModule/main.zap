test "a type does not repeat its module's name" refuses TypeRepeatsModule("name it Kind"):
	import shape
	print(shape.ShapeKind.Round)
