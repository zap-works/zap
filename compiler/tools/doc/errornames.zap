# long: a table, one entry per compile error
# The compile errors by name: the name a test gives one (`test "name" refuses AssignImmutable:`)
# and the code the report shows (error[assign-immutable]), with
# its message, $1, $2 ... standing for its parts (a part may appear more than once). Every error
# the compiler reports about a program is here, compiler/shader's through shader.nameError.

type NamedError:
	name str
	text str
	explain str   # what `zap doc` says of it: why the language refuses it and the form to write
	example str = ""   # a program it refuses, when no test of spec/, tests/ or std/ expects it

compileErrors = [
	NamedError(
		name = "AssignImmutable",
		text = "cannot assign to immutable '$1' (declare it 'mut' to mutate)",
		explain = "A local binding assigned again is mutable on its own, but a parameter, a loop's name and a match's or an is's name are immutable unless declared `mut`: a parameter's `mut` is a contract with its callers, and a loop's or a match's name with `mut` is the element itself, so assigning it changes the list or the matched value in place. Declare it `mut` (`fn f(mut n i64)`, `for mut x in xs`, `A(mut v)`) if it must change, or bind the new value to a new name."
	),
	NamedError(
		name = "NeedsMut",
		text = "$1 needs '$2' to be mut (declare it 'mut' to mutate)",
		explain = "The operation changes the value in place (a mutating method such as push, a field or element assignment), but the parameter, loop name or match name it changes was declared without `mut` (a local binding is mutable when it changes). Declare it `mut` or work on a copy of your own."
	),
	NamedError(
		name = "MutLoopNoElement",
		text = "'$1' is `mut` but names no element of a list: a range's, a text's or a sequence's values are not places",
		explain = "`for mut x in xs` makes x the element itself, so changing x changes the list or the array in place. A range, a text, a sequence, a table's rows, a grid's cells and a pool's places give values that are no element to change: write the loop without `mut` and bind a mutable copy of your own inside it if it must change."
	),
	NamedError(
		name = "MutLoopIndex",
		text = "a loop's index is never `mut`: write `for i, mut x in xs` to change the element",
		explain = "In `for i, x in xs` the index i counts the elements; changing it would not move the loop. Only the element may be `mut` (`for i, mut x in xs`), which changes the list in place."
	),
	NamedError(
		name = "MutNameNoPlace",
		text = "'$1' is `mut` but the value matched is no mutable place: a mut name changes it in place",
		explain = "A `mut` name in a match's or an is's pattern is a part of the value matched, so changing it changes that value in place. That needs the value to be a place that may change: a local, a `mut` parameter, their fields and elements, or a list, an optional, a struct or an enum from one. Match on such a place, or bind a mutable copy of your own inside the arm."
	),
	NamedError(
		name = "LanguageConstant",
		text = "$1 is a constant of the language: it is not declared",
		explain = "`pi` and `tau` are built into the language as floats of whatever type the place asks for, and they are declared nowhere, so a binding, parameter or constant cannot take either name. Pick another name, or use the built-in constant directly."
	),
	NamedError(
		name = "UseAfterMove",
		text = "use of moved value '$1' (moved at line $2)",
		explain = "Zap values have one owner: passing a value to a `move` parameter, storing it, or returning it gives it away, and the old name is empty from then on. The error names the line of the move. Use the value before the move, move a `.copy()` if both places need it, or restructure so the value is lent instead of moved."
	),
	NamedError(
		name = "UnusedVariable",
		text = "unused variable '$1' (every binding must be read)",
		explain = "Every binding must be read at least once; a binding that is never read usually means a mistake or dead code. Remove it, use it, or bind to `_` when the value is computed only for its effect."
	),
	NamedError(
		name = "MissingReturn",
		text = "$1 returns $2 but not every path ends in a return",
		explain = "A function (or lambda) with a declared result must produce it on every path, and the checker found a path, often an `if` without `else` or a loop, that falls off the end. Add a final `return` or make the last statement an expression that covers every case, such as an `if`/`else` or a match with every arm."
	),
	NamedError(
		name = "NonExhaustiveMatch",
		text = "non-exhaustive match$1",
		explain = "A match must cover every possible value of what it matches on: every enum variant, both sides of a result, `none` of an optional, or a catch-all for numbers and strings. The message names a value no arm takes. Add an arm for it, or end with `_:` when the remaining cases share one outcome."
	),
	NamedError(
		name = "InvalidNumber",
		text = "invalid number literal (only decimal digits with _ between them, '.', and an exponent are allowed)",
		explain = "The lexer read digits immediately followed by letters, as in `12abc`, which is neither a number nor a name. Separate the number from the word, or start an identifier with a letter."
	),
	NamedError(
		name = "UnreachableArm",
		text = "unreachable arm: $1",
		explain = "An earlier arm already takes every value this arm could match, such as a catch-all `_` or bare name before it, or a second arm for a result's value or error side, so this arm can never run. Move the specific arm above the general one, or delete it."
	),
	NamedError(
		name = "NeedsBound",
		text = "$1 on $2 needs the bound $3: declare <$2 $3> on $4",
		explain = "Inside a generic, an operator or built-in operation on a type parameter (such as `+`, `<`, `==` or printing) is only allowed when the parameter declares the bound that provides it, because the body must compile for every type it could be given. Add the bound the message names, for example `fn twice<T Num>(x T) T`."
	),
	NamedError(
		name = "LengthNotNumberParameter",
		text = "the length $1 of T[$1] is no number parameter: declare <$1 n64>",
		explain = "A fixed array's length in a generic signature, as in `T[N]`, must name a declared number parameter so the compiler can bind it from the argument. The name used was not declared as one. Declare it among the type parameters as a number, `<N n64>`, or use the name of the number parameter that is declared.",
		example = """
			fn f<N n64>(a i64[K]) i64:
				1

			print(f([1]))
			"""
	),
	NamedError(
		name = "BuiltinBoundName",
		text = "'$1' is a built-in bound: a declared one takes another name",
		explain = "Eq, Ord, Hash, Num, Show and Copy are the language's built-in bounds, and a program's `bound` declaration cannot reuse one of those names because a generic's bound would then be ambiguous. Give the declared bound a name of its own.",
		example = """
			bound Show:
				fn label(self Show) str
			"""
	),
	NamedError(
		name = "NumberParameterNotInteger",
		text = "a number parameter is of an integer type (<N n64>), not $1",
		explain = "A number parameter of a generic (`<N n64>`) stands for a length or count and must be of an integer type; a float or other type cannot size an array. Declare it with an integer type such as `n64`."
	),
	NamedError(
		name = "UnknownBound",
		text = r"unknown bound '$1' (the bounds are Eq, Ord, Hash, Num, Show, Copy and those a program declares: bound $1 { fn ... })",
		explain = "The bound written on a type parameter is neither a built-in one (Eq, Ord, Hash, Num, Show, Copy) nor a `bound` the program declares. Fix the spelling, use a built-in bound, or declare it with `bound Name:` and the methods it requires.",
		example = """
			fn show<T Shape>(x T) i64:
				1

			print(show(1))
			"""
	),
	NamedError(
		name = "MemberNeedsBound",
		text = r"'$1' on $2 needs a bound that declares it: bound B { fn $1(...) } and <$2 B> on $3",
		explain = "In a generic body, calling a method or reading a member on a type parameter needs a bound that declares that method, since nothing else promises every type argument has it. Declare a `bound` listing the method and put it on the parameter, as in `<T Sized>`."
	),
	NamedError(
		name = "BoundLacksMethod",
		text = "$1's bounds ($2) declare no method '$3': a generic calls on $1 the methods its bounds declare",
		explain = "The generic calls a method on a type parameter, but none of the bounds on that parameter declares a method of that name, so the call cannot be checked for every possible type. Add the method to the bound's declaration, add another bound that has it, or call only what the bounds declare."
	),
	NamedError(
		name = "UntypedNone",
		text = "no use decides the type of '$1': write it, `$1 T? = none`",
		explain = "A variable initialised with a bare `none` gets its type from a later assignment of a real value; when none ever comes, the compiler cannot tell what the optional holds. Write the type, as in `best i64? = none`, or assign it a value somewhere."
	),
	NamedError(
		name = "UntypedEmptyList",
		text = "no use decides the type of '$1': write it, `$1 T[] = []`",
		explain = "An empty list literal takes its element type from what is pushed later or from a place of a list type it is given to; this one never gets either, so its type is unknown. Write the type, as in `xs i64[] = []`, push a value, or pass it where a typed list is expected."
	),
	NamedError(
		name = "NestedLambdaChange",
		text = "cannot change '$1' from a lambda inside another lambda: change it in the outer one",
		explain = "A lambda may change a variable it captures from its enclosing function, but a lambda nested inside another lambda cannot change a variable from outside both, because the compiler tracks such changes one capture level deep. Do the change in the outer lambda, for example from a value the inner one returns, or use a plain loop.",
		example = """
			mut sum = 0
			add = (row i64[]):
				inner = (v i64):
					sum += v
				for v in row:
					inner(v)
			add([1, 2])
			print(sum)
			"""
	),
	NamedError(
		name = "FieldNameTaken",
		text = "'$1' is a field of $2, which its methods name bare: a local or a parameter takes another name",
		explain = "Inside a method (a function whose first parameter is `self`), fields are named bare, so a local, parameter, loop variable or lambda parameter with a field's name would hide it. Rename the local or parameter.",
		example = """
			type Counter:
				count i64
			fn add(mut self Counter, count i64):
				self.count += count
			mut c = Counter(0)
			c.add(2)
			"""
	),
	NamedError(
		name = "UnknownModule",
		text = "no module is named '$1'$2",
		explain = "A name was qualified with a prefix (as in `geo.Point`) that names no module: none of that name is imported or found under the program's root, the libraries or std, nor is one module's dir of that name. Fix the prefix's spelling (the message names the modules that come close), or import the module by its whole id (`import shapes.geo`) where several share the name.",
		example = """
			fn area(p geo.Point) f64:
				0.0
			"""
	),
	NamedError(
		name = "NotInModule",
		text = "module '$1' has no $2 '$3'",
		explain = "The module is imported, but it declares no function, type or constant of that name. Check the module's public declarations and correct the name.",
		example = """
			import json
			fn read(v json.Valu) i64:
				0
			"""
	),
	NamedError(
		name = "PrivateName",
		text = "'$1' is private to module '$2' (mark it pub)",
		explain = "Only declarations marked `pub` are visible outside their module; this one is private to the module it lives in. Mark the declaration `pub` in its module if it is meant to be used elsewhere, or use a public alternative."
	),
	NamedError(
		name = "NotInModuleBare",
		text = "module '$1' has no '$2'",
		explain = "In `module.name`, or a name of `from module import name`, the module has no function, type or constant called that name. Correct the name to one the module actually declares.",
		example = """
			import json
			v = json.nosuch("1")
			print(v)
			"""
	),
	NamedError(
		name = "AmbiguousImport",
		text = "'$1' from module '$2' is already a name of this file",
		explain = "A from-import brings a name into the file that the file's module already declares, or that another from-import of the file brought in, so a bare use of it could mean either. Import it under another name (`from m import name as other`), or read it through its module (`import m`, `m.name`).",
		example = """
			from json import parse
			fn parse() i64:
				0
			"""
	),
	NamedError(
		name = "TypeArgumentCount",
		text = "$1 needs $2 type argument(s), got $3",
		explain = "A generic type or function was written with the wrong number of type arguments for its declaration. Give exactly as many as its declaration lists, or leave them out where they can be inferred.",
		example = """
			fn twice(x i64) i64:
				x * 2

			print(twice<3>(1))
			"""
	),
	NamedError(
		name = "BoundNotMet",
		text = "$1 of $2",
		explain = "A generic was instantiated with a type argument that does not satisfy one of its bounds, for example a type without ordering where `Ord` is required. Use a type that has the bound, or loosen the generic's bound."
	),
	NamedError(
		name = "NumberNotType",
		text = "$1 is a number: a type is written here",
		explain = "A number parameter (`<N n64>`) or a numeric type argument is a value, not a type, so it cannot stand where a type is written. Use a real type there, and use the number parameter only as an array length or as a value.",
		example = """
			fn f<N n64>(a i64[N]) i64:
				x N = 3
				x

			print(f([1]))
			"""
	),
	NamedError(
		name = "EmptyFixedArray",
		text = "a T[N] holds at least one value",
		explain = "A fixed array `T[N]` must hold at least one element, so a length of 0 is refused. Use a length of one or more, or a list `T[]` when it may be empty.",
		example = """
			mut grid i32[0]
			print(grid)
			"""
	),
	NamedError(
		name = "ResultSidesAlike",
		text = "a result's value and error are of one type, $1: return could not tell which one leaves (an enum or a struct names the error)",
		explain = "When a result's value and error are of the same type, `return x` cannot tell whether it returns the value or the error. Give the error its own type, such as an enum or struct naming the failure, and write the result as `str ? ParseError`."
	),
	NamedError(
		name = "RefToRef",
		text = "a reference to a reference is not allowed",
		explain = "A reference already borrows its value, and a reference to a reference adds nothing the compiler tracks, so `ref ref T` is refused. Write a single `ref T`."
	),
	NamedError(
		name = "NotAListOfNumbers",
		text = "a $1 is a $2: the math operators work on lists of numbers",
		explain = "`Vector` and `Matrix` are not types in Zap: the math operators work directly on lists of numbers. Write a vector as `f64[]` and a matrix as `f64[,]`."
	),
	NamedError(
		name = "SeqTypeArity",
		text = "Seq needs one type argument: Seq<T>",
		explain = "`Seq<T>`, a generator's result, takes exactly one type argument: the type of the values it yields. Write `Seq<T>` with one element type.",
		example = """
			fn count(s Seq<i64, str>) i64:
				0
			"""
	),
	NamedError(
		name = "BoxTypeArity",
		text = "Box needs one type argument: Box<T>",
		explain = "`Box<T>` holds exactly one value on the heap, so it takes one type argument. Write `Box<T>` with the single type it holds.",
		example = """
			fn size(b Box<i64, str>) i64:
				0
			"""
	),
	NamedError(
		name = "TableTypeArity",
		text = "Table needs one type argument: Table<T>, T a struct",
		explain = "`Table<T>` stores rows of one struct type column by column, so it takes exactly one type argument, a struct. Write `Table<Row>` with your row struct.",
		example = """
			type Row:
				id i64
			fn count(t Table<Row, i64>) i64:
				0
			"""
	),
	NamedError(
		name = "MapKeyType",
		text = "a map's keys must be integers, strings, or structs of those and bools, found $1",
		explain = "A map's keys are hashed and compared exactly, so they must be integers, strings, or structs made of those and bools; floats, lists, optionals and similar are refused. Convert the key to one of those types, for example an integer id or a string."
	),
	NamedError(
		name = "UnknownType",
		text = "unknown type '$1'",
		explain = "No type of this name is declared in this module or its imports, and it is not a built-in type. Fix the spelling, declare the type, or import the module that declares it and qualify the name."
	),
	NamedError(
		name = "NotGeneric",
		text = "$1 is not generic",
		explain = "Type arguments were written on a type or function that takes none (a plain struct, enum or type alias). Remove the `<...>` after the name.",
		example = """
			type Point:
				x i64
			p Point<i64> = Point(1)
			print(p)
			"""
	),
	NamedError(
		name = "RangeTypeNotInteger",
		text = "a range type is an integer's: $1 has no range",
		explain = "Range types such as `i64 in 0..=100` restrict an integer type to an interval; a float, a string or a type that already has a range cannot take one. Use a plain integer type as the range's base.",
		example = """
			type Bad = str in 0..3
			x Bad = "a"
			print(x)
			"""
	),
	NamedError(
		name = "RangeTypeEmpty",
		text = "the range is empty or leaves $1",
		explain = "The interval written for a range type holds no values (its low end is above its high end) or reaches outside what the base type can hold. Fix the bounds so that the low end is at most the high end and both fit the base type.",
		example = """
			type Empty = i8 in 5..2
			x Empty = 5
			print(x)
			"""
	),
	NamedError(
		name = "RangeTypeBound",
		text = "a range type's bound is an integer literal or a constant",
		explain = "Each bound of a range type must be known when compiling: an integer literal (negative allowed) or the name of a constant. An expression, a call or a variable is refused. Compute the value into a top-level constant and name it, or write the literal.",
		example = """
			fn top() i64:
				9
			type Level = i64 in 0..top
			x Level = 3
			print(x)
			"""
	),
	NamedError(
		name = "TypeNamesItself",
		text = "the type '$1' is defined over itself",
		explain = "A defined type (`type Name = T`) is made over another type; one defined over itself, directly or through other defined types, has no layout. Define it over a real type, or declare a struct or enum if a recursive type is meant (recursion goes through a list, a map or a Box).",
		example = """
			type Loop = Loop
			x Loop = 1
			"""
	),
	NamedError(
		name = "DefinedMixed",
		text = "$1 and $2 are different types: a $3 is made with $3(x)",
		explain = "A defined type is a type of its own: its values and its base's never mix, so an operation between a `Meters` and an `f64` is refused rather than guessing which unit the result has. Convert the base's value with `Meters(x)`, or read the defined value back with `f64(m)`."
	),
	NamedError(
		name = "DefinedConversion",
		text = "$1(x) converts a $2 or a number, got $3",
		explain = "`Name(x)` makes a defined type's value from its base type, from another type defined over the same base, or from a number as the base's own conversion would. Any other value has no meaning as one: convert it to the base first, or build the value another way."
	),
	NamedError(
		name = "ConstantTypeMismatch",
		text = "constant '$1' declared $2 but value is $3",
		explain = "A top-level constant with a written type must have a value of that type, and the value given is of another type. Fix the value or change the declared type so they agree.",
		example = """
			limit i64 = "ten"
			fn cap(x i64) i64:
				limit if x > limit else x
			print(cap(9))
			"""
	),
	NamedError(
		name = "NotAReference",
		text = "$1 cannot be a reference",
		explain = "Some places cannot hold a reference because the compiler could not follow how long it lives there: an enum variant's field and a boxed value are such places. Store an owned value there (for example `str` instead of `ref str`).",
		example = """
			type Msg:
				Named(name ref str)
			m = Msg.Named("a")
			"""
	),
	NamedError(
		name = "NotAView",
		text = "$1 cannot be a view (a struct holding references)",
		explain = "A view is a struct holding references, and it is checked like a reference: it cannot be put in a place, such as an enum variant's field or a box, that could outlive what it borrows. Store an owned struct there instead, copying the borrowed data into owned fields.",
		example = """
			type Packet:
				bytes ref u8[]
				kind u8
			type Msg:
				Got(p Packet)
			"""
	),
	NamedError(
		name = "ListOfReferences",
		text = "$1 cannot be a $2: a list or map of references lives in a variable, where the compiler follows what it borrows",
		explain = "A list or map of references, such as `(ref str)[]`, borrows what its elements point to, and the compiler can only follow that borrow while the list lives in a variable. It cannot be a variant field, a box's content, or an element of another collection. Keep it in a local variable, or store owned values (`str[]`).",
		example = """
			type Msg:
				Words(ws (ref str)[])
			"""
	),
	NamedError(
		name = "SeqNotStored",
		text = "$1 cannot be a Seq: a Seq is a generator's result, walked where it is made",
		explain = "A `Seq<T>` is a generator's lazy result, walked where it is made; it cannot be a parameter, field, list element or other stored place. Walk it where it is produced, or call `.toList()` and pass the list."
	),
	NamedError(
		name = "MutRefNotAllowed",
		text = "$1 cannot be a mut reference (a read reference can)",
		explain = "Lists, maps and Seqs may hold read references, but not `mut ref`s: several exclusive borrows held together in a collection would break the one-writer rule. Store read references, or store indexes and change the elements through their owner."
	),
	NamedError(
		name = "ArgumentCount",
		text = "$1 expects $2 argument(s), got $3",
		explain = "A built-in method, intrinsic or generic function was called with a different number of arguments than it takes. Pass exactly the arguments its signature lists.",
		example = r"""
			ages = {"ana": 30}
			print(ages.get("ana", 1))
			"""
	),
	NamedError(
		name = "MutateThroughReadRef",
		text = "$1 cannot mutate through a read reference (take it with mut ref)",
		explain = "The change goes through a read reference (`ref T`), which only lends the value for reading. Take a `mut ref` to the place instead, or change the owner directly."
	),
	NamedError(
		name = "SharedHoldsReference",
		text = "a $1 cannot hold $2: what a shared value holds goes to other threads, so it is a value of its own",
		explain = "A shared value such as a `Channel` hands what it holds to other threads, which may outlive the place a reference borrows from, so its type argument is a value that owns its memory, never a reference or something holding references. Send owned values (`Channel<str>`, `.copy()` what you only borrow), or send indexes or Pool Handles."
	),
	NamedError(
		name = "MutateShared",
		text = "$1 cannot change a shared value: it changes only through its own methods",
		explain = "Shared values such as `Channel` and `Atomic` are owned by several threads at once, so they change only through their own methods, never by assigning their fields or calling a mutating built-in on their parts. Use the value's own methods (`send`, `store`, `add` and so on)."
	),
	NamedError(
		name = "MutateConstant",
		text = "$1 cannot mutate constant '$2' (declare it 'mut' at the top level to make it a module variable)",
		explain = "A top-level immutable binding that a function reads is a constant, built once and never changed, so calling a mutating method or assigning through it is refused. Declare it `mut` at the top level to make it a module variable that functions may change.",
		example = """
			primes = [2, 3, 5]
			fn grow():
				primes.push(7)
			grow()
			"""
	),
	NamedError(
		name = "MutArgTemporary",
		text = "$1 is a mut parameter and needs a variable, not a temporary value",
		explain = "A `mut` parameter changes the caller's variable in place, so its argument must be a place (a variable, a field, an element); a temporary such as a literal or a call's result would be changed and then thrown away. Bind the value to a `mut` variable first and pass that."
	),
	NamedError(
		name = "MutArgReadRef",
		text = "$1 is a mut parameter but the reference is not mut",
		explain = "The argument for a `mut` parameter is reached through a read reference, which does not allow changes. Pass the owner itself, or a place reached through a `mut ref`.",
		example = """
			fn bump(mut xs i64[]):
				xs.push(1)
			mut ys = [1]
			r ref i64[] = ys
			bump(r)
			"""
	),
	NamedError(
		name = "MutArgShared",
		text = "$1 is a mut parameter but a shared value changes only through its own methods",
		explain = "A shared value (Channel, Atomic) changes only through its own methods, so it or a part of it cannot be passed to a `mut` parameter that would change it directly. Use the shared value's own methods instead.",
		example = """
			fn fill(mut xs str[]):
				xs.push("x")
			log = Channel<str>()
			fill(log.items)
			"""
	),
	NamedError(
		name = "MutArgConstant",
		text = "$1 is a mut parameter but '$2' is a constant (declare it 'mut' at the top level to make it a module variable)",
		explain = "The argument for a `mut` parameter is a top-level constant, which is never changed after it is built. Declare it `mut` at the top level to make it a module variable, or pass a local copy."
	),
	NamedError(
		name = "MutArgImmutable",
		text = "$1 is a mut parameter but '$2' is immutable (declare it 'mut')",
		explain = "A `mut` parameter changes its argument in place, so the argument's variable must be declared `mut`. Add `mut` to the variable's declaration, or pass a `mut` copy."
	),
	NamedError(
		name = "ConversionNeedsInteger",
		text = "$1(x) converts an integer, got $2",
		explain = "The checked conversion into a range type, such as `n64(x)` or `Percent(x)`, accepts only an integer and stops the program when it falls outside the range. A float or other value cannot go straight in; convert it to an integer first, for example `n64(i64(x))`.",
		example = """
			x = 2.5
			print(n64(x))
			"""
	),
	NamedError(
		name = "ComparisonDecided",
		text = "a $1 is never below 0, so this comparison is always $2",
		explain = "A natural (n32, n64) or an unsigned integer holds no value below 0, so comparing it with 0 this way decides nothing. A sentinel below 0 that meant \"none\" is an optional (`n32?`, tested with `== none` or named with `is`); otherwise drop the comparison.",
		example = """
			fn found(at n64) bool:
				at >= 0
			print(found(3))
			"""
	),
	NamedError(
		name = "UnsignedQuantity",
		text = "'$1' is a $2 that is only counted, compared or indexed with: a quantity, written $3",
		explain = "Unsigned integers are bits: a hash, a mask, a file's bytes, arithmetic that wraps on purpose. A parameter, a local or a struct's field whose value no bit operation, shift, wrapping arithmetic or foreign call reads, and that goes into no other unsigned place, is a count or an index, which is a natural: `n32` or `n64`, never negative and never wrapping. Write that type.",
		example = """
			fn show(n u32, xs i64[]):
				if n < xs.len:
					print(xs[n])
			show(1, [1, 2])
			"""
	),
	NamedError(
		name = "NeedlessConversion",
		text = "the value is already $1: drop the conversion",
		explain = "The value already has the target type, so the conversion does nothing, yet it reads as if something happened. Remove the conversion call."
	),
	NamedError(
		name = "ConversionRoundTrip",
		text = "$1 has $2 itself: write x.$2(...) on the $1, not $1($3(x).$2(...))",
		explain = "The value is converted to another number type only to call a method its own type has, then converted back: the two conversions do nothing but cost. Call the method on the value as it is (`x.sqrt()` on an f32); a conversion stays where the method or one of its arguments needs the other type."
	),
	NamedError(
		name = "InterpolationNotConcat",
		text = "$1$2",
		explain = "Joining strings with `+` when a literal is among the pieces is refused, because an interpolated string says the same thing more plainly. The message shows the equivalent form, such as `\"(\{a\}, \{b\})\"`; write that instead. A `+` of names only, or `+=`, is still allowed."
	),
	NamedError(
		name = "InNotSupported",
		text = "`in` looks into a list, a str, a map (its keys) or a value whose type has a contains method, found $1",
		explain = "`x in y` looks into a list, a string, a map's keys, or a struct or enum that declares a `contains` method; the right side here is none of those. Use a collection on the right, or add a `contains` method to the type.",
		example = """
			print(1 in 2)
			"""
	),
	NamedError(
		name = "FallbackNotOptional",
		text = "'??' requires an optional on the left, found $1",
		explain = "`a ?? b` takes the value of an optional or a result, or `b` when it is missing; the left side here is neither, so there is nothing to fall back from. Remove the `??`, or make the left side an optional (`T?`) or a result."
	),
	NamedError(
		name = "FallbackType",
		text = "'??' needs a $1 on the right, found $2",
		explain = "The fallback on the right of `??` must be of the optional's inner type, since the expression gives one or the other. Give a fallback of that type (for example `name ?? \"\"` for a `str?`), or convert it.",
		example = """
			name str? = none
			print(name ?? 0)
			"""
	),
	NamedError(
		name = "LogicNeedsBool",
		text = "logical operator needs bool operands, found $1 and $2",
		explain = "`and` and `or` work only on bools; Zap has no truthiness for numbers, strings or optionals. Write an explicit comparison, such as `n != 0` or `x != none`.",
		example = """
			n = 1
			print(n and true)
			"""
	),
	NamedError(
		name = "NoneComparison",
		text = "only an optional can be compared with none, found $1",
		explain = "Only an optional value can be compared with `none`; a value of a non-optional type is always present, so the test is meaningless. Drop the comparison, or give the variable an optional type `T?` if it may be missing."
	),
	NamedError(
		name = "BitwiseNeedsIntegers",
		text = "bitwise operators need integers, found $1 and $2",
		explain = "`& | ^ << >>` operate on the bits of integers (and of integer vectors), not on floats, bools or other values. Convert the operands to integers first, or use `and`/`or` for bools.",
		example = """
			x = 1.5
			print(x & 2)
			"""
	),
	NamedError(
		name = "MixedTypes",
		text = "cannot mix $1 and $2 in one expression (convert explicitly)",
		explain = "Zap does not convert silently between number types that would lose information or mix roles, such as a signed integer with a `u64` or an `f32` with an `f64`. Convert one side explicitly, for example `i64(x) + y`, so both operands have one type."
	),
	NamedError(
		name = "CannotCompare",
		text = "cannot compare $1 with $2",
		explain = "`==` and `!=` compare two values of one type (integers widen automatically), and the two sides here have unrelated types. Convert one side, or compare the right fields.",
		example = """
			print(1 == "1")
			"""
	),
	NamedError(
		name = "NoEquality",
		text = "cannot compare $1 with '==': a part of it has no equality (a map, a function, a result)",
		explain = "`==` compares values part by part, and this type contains a part with no equality, such as a map, a function value or a result. Compare the fields that do have equality, or write a method that decides equality."
	),
	NamedError(
		name = "CannotOrder",
		text = "cannot order $1 and $2",
		explain = "`<`, `<=`, `>` and `>=` order numbers and strings of the same type only; structs, enums, bools and mixed types have no order. Compare a numeric or string field, or convert the sides to one type."
	),
	NamedError(
		name = "ProductNotMatrix",
		text = "'@' is only for matrices and vectors",
		explain = "The `@` operator is the matrix and vector product (and the dot product of number structs), so it needs lists of numbers, matrices or number structs on its sides, not plain numbers or other values. Use `*` to multiply numbers.",
		example = """
			a = 3
			print(a @ 4)
			"""
	),
	NamedError(
		name = "NoLaneOperator",
		text = "no lane-by-lane operator for $1 and $2 here",
		explain = "SIMD vectors apply an operator lane by lane only where the hardware has it for that element type: integer vectors have no division, and multiplication only for 32-bit lanes; both sides must also be the same vector type. Use a float vector, convert the lanes, or do the operation per element.",
		example = """
			a Simd<4, i64> = Simd<4>(1, 2, 3, 4)
			print(a / a)
			"""
	),
	NamedError(
		name = "ArithmeticNeedsNumbers",
		text = "arithmetic needs numbers, found $1 and $2",
		explain = "`+ - * / %` work on numbers (and on lists of numbers, number structs and vectors); one side here is not a number, such as a bool or an enum. Convert it to a number explicitly, or use the operation that fits that type.",
		example = """
			print(true + 1)
			"""
	),
	NamedError(
		name = "ArmMissingValue",
		text = "a block arm of an expression match must end with the value (or a return)",
		explain = "When a match is used as an expression, each arm gives its value; an arm written as a block must end with the value expression (or a `return`). Put the value on the block's last line."
	),
	NamedError(
		name = "ArmTypesDiffer",
		text = "match arms produce different types: $1 and $2",
		explain = "A match used as an expression has one type, so every arm must produce a value of the same type. Make the arms agree, for example by converting one arm's value, or use an optional or an enum when the cases really differ.",
		example = """
			n = 3
			s = match n:
				1: "one"
				_: 2
			print(s)
			"""
	),
	NamedError(
		name = "ArmConditionNotBool",
		text = "an arm's condition (pattern and ...) is a bool, found $1",
		explain = "The condition after `and` in an arm (`pattern and cond:`) decides whether the arm applies, so it must be a bool. Write an explicit comparison, such as `x and x > 0:`.",
		example = """
			n = 3
			print(match n:
				k and k: 1
				_: 0
			)
			"""
	),
	NamedError(
		name = "ArmBindingsDiffer",
		text = "the patterns of one arm bind the same names with the same types: ($1) beside ($2)",
		explain = "An arm with several alternative patterns runs one body, so every pattern must bind the same names with the same types; otherwise a name would be missing or of an unknown type in the body. Bind the same names in each alternative, or split them into separate arms."
	),
	NamedError(
		name = "MapAddKey",
		text = "add expects a $1 key, got $2",
		explain = "`m.add(k, delta)` counts at a key, and the key must be of the map's key type. Pass a key of that type, converting it if needed.",
		example = r"""
			mut counts = {"a": 0}
			counts.add(1, 1)
			print(counts)
			"""
	),
	NamedError(
		name = "MapAddValueType",
		text = "add needs an integer value type, this map holds $1",
		explain = "`add` grows the value at a key by a delta, starting from zero for a new key, so it only works on maps whose values are integers. Use indexing (`m[k] = v`) for other value types.",
		example = r"""
			mut names = {"a": "x"}
			names.add("a", 1)
			print(names)
			"""
	),
	NamedError(
		name = "MapAddDelta",
		text = "add expects a $1 delta, got $2",
		explain = "The delta given to `add` must be of the map's integer value type exactly. Convert it to that type, for example `m.add(k, i64(d))`.",
		example = r"""
			mut counts = {"a": 0}
			d = 1.5
			counts.add("a", d)
			print(counts)
			"""
	),
	NamedError(
		name = "MapKeyArgument",
		text = "$1 expects a $2 key, got $3",
		explain = "The key passed to `get` or `remove`, or tested with `in`, must be of the map's key type. Pass a key of that type, converting it if needed.",
		example = r"""
			ages = {"ana": 30}
			print(ages.get(1))
			"""
	),
	NamedError(
		name = "MapSetKey",
		text = "set expects a $1 key, got $2",
		explain = "The key of the compiler's internal `set` call on a map must be of the map's key type. A program cannot call `.set` on a map (that spelling is refused), so this arises only in code the compiler generates; in a program, write `m[k] = v` with a key of the map's type."
	),
	NamedError(
		name = "MapSetValue",
		text = "set expects a $1 value, got $2",
		explain = "The value of the compiler's internal `set` call on a map must fit the map's value type. A program cannot call `.set` on a map (that spelling is refused), so this arises only in code the compiler generates; in a program, write `m[k] = v` with a value of the map's type."
	),
	NamedError(
		name = "LambdaExpected",
		text = "expected a lambda (x => ...) or a fn($1) value, found $2",
		explain = "A pipeline step such as map or filter takes a lambda or a function value of exactly one parameter of the element's type; the value given is not a function of that shape. Pass a lambda (`x: ...` or an expression of `it`), or a function whose single parameter matches the element type.",
		example = """
			fn twice(s str) str:
				s + s
			xs = [1, 2]
			print(xs.map(twice))
			"""
	),
	NamedError(
		name = "OneArgument",
		text = "$1 expects 1 argument",
		explain = "`print` takes exactly one value. Join several values into one string with interpolation, as in `print(\"\{a\} \{b\}\")`.",
		example = """
			print("a", "b")
			"""
	),
	NamedError(
		name = "CannotPrint",
		text = "cannot print a value of type $1",
		explain = "Printing needs a value with a textual form, and function values and the empty result of a function with no return value have none. Print a value, or call the function and print its result.",
		example = """
			double = (x i64): x * 2
			print(double)
			"""
	),
	NamedError(
		name = "PipelineLambdaArity",
		text = "a pipeline lambda takes one parameter",
		explain = "Each pipeline step hands its lambda one element at a time, so the lambda takes exactly one parameter. Take one parameter and destructure inside if needed; `reduce` is the step that takes two.",
		example = """
			print([1, 2].map((a, b):
				a
			))
			"""
	),
	NamedError(
		name = "RangeNotList",
		text = "$1 works on a list: (lo..hi).map(...) makes one",
		explain = "A range `(lo..hi)` supports only some pipeline steps directly (map, filter, each, sum, find and others); steps like sortBy or findIndex need a real list. Make one first with `(lo..hi).map(it)`, then call the method.",
		example = """
			print((0..5).findIndex(it == 3))
			"""
	),
	NamedError(
		name = "OneLambda",
		text = "$1 expects one lambda",
		explain = "Pipeline steps such as map, filter or any take exactly one argument, the lambda. Pass a single lambda, combining conditions inside it with `and`.",
		example = """
			print([1, 2, 3].filter(it > 1, it < 3))
			"""
	),
	NamedError(
		name = "ZipOfOneList",
		text = "$1 pairs the elements with those of one list: xs.zip(ys)",
		explain = "`zip` walks two sequences side by side and gives their elements in pairs, so it takes exactly one other list. Pass one list (`xs.zip(ys)`); to pair three, zip twice or write a loop over the indexes."
	),
	NamedError(
		name = "FlatMapNotList",
		text = "flatMap's lambda must give a list, got $1",
		explain = "`flatMap` concatenates the lists its lambda returns, so the lambda must give a list for each element. Return a list (for example `[x, x * 2]`), or use `map` when each element gives one value.",
		example = """
			print([1, 2].flatMap(it * 2))
			"""
	),
	NamedError(
		name = "FlatMapBorrows",
		text = "flatMap's lambda builds a new list for each element (.copy() one that exists)",
		explain = "flatMap's lambda must build a new list for each element; returning an existing list would hand out the same owned list once per element. Return a fresh list literal, or `.copy()` the existing one."
	),
	NamedError(
		name = "SortKeyNotOrdered",
		text = "$1 needs a key in order (a number, a str, or a tuple or list of them), got $2",
		explain = "Sorting and minBy/maxBy compare the keys their lambda returns, so the key must have an order: a number, a string, or a tuple or list of those. A bool, an enum or a map has none. Return an ordered key, such as a numeric field or `if b: 1 else: 0`.",
		example = """
			print([1, 2, 3].sortedBy(it > 1))
			"""
	),
	NamedError(
		name = "PredicateNotBool",
		text = "$1's lambda must return bool, got $2",
		explain = "filter, any, all, count, find and findIndex keep or test elements by their lambda's answer, so it must return a bool. Write a comparison, for example `it > 0`, rather than a number or other value.",
		example = """
			print([1, 2].filter(it * 2))
			"""
	),
	NamedError(
		name = "SumNotNumbers",
		text = "sum adds numbers, not $1",
		explain = "`sum()` on a Seq, a generator's lazy result, adds the values it yields, so they must be numbers (on a list the same mistake is reported as a missing Num bound). Yield numbers, or map the values to numbers first, as in `s.map(if it: 1 else: 0).sum()`.",
		example = """
			fn flags(n i64) Seq<bool>:
				i = 0
				while i < n:
					yield i % 2 == 0
					i += 1
			print(flags(4).sum())
			"""
	),
	NamedError(
		name = "SeqLacksMethod",
		text = "a Seq has $1 and toList(), not '$2' (.toList() makes a list)",
		explain = "A Seq, a generator's lazy result, offers only a few steps (filter, map, each, all, any, count, reduce, sum) and toList(); other methods such as len need a list. Call `.toList()` first."
	),
	NamedError(
		name = "SeqMapOwns",
		text = "a Seq's map gives values that own nothing (a number, a field), not $1: make each in a for loop, or .toList() first",
		explain = "A Seq's map runs lazily, one value at a time, so its lambda may only give values that own nothing (a number, a plain field); a string or list built per element would have nowhere to live. Build those in a for loop, or call `.toList()` before mapping."
	),
	NamedError(
		name = "PipelineBlockValue",
		text = "the block of a pipeline lambda ends with its value",
		explain = "A pipeline step such as map or filter was given a lambda in block form whose last statement is not an expression with a value, so the step has nothing to collect for each element. The block may run statements first, but its last line must be the value the step uses. End the block with that expression, for example `y * 2` on its own line, or use each when you only want the side effects.",
		example = """
			xs = [1, 2, 3]
			ys = xs.map(x:
				y = x * 2
				print(y)
			)
			print(ys.len)
			"""
	),
	NamedError(
		name = "ReduceArguments",
		text = "reduce expects a start value and a lambda (acc, x) => next",
		explain = "reduce was called with a number of arguments other than two. It needs the start value of the accumulator first and then a lambda of two parameters that gives the next accumulator from the current one and an element. Write it as `xs.reduce(0, (acc, x): acc + x)`.",
		example = """
			xs = [1, 2, 3]
			print(xs.reduce((a, b): a + b))
			"""
	),
	NamedError(
		name = "ReduceAccumulator",
		text = "reduce accumulates a number or a bool, found $1",
		explain = "The start value given to reduce is not a number or a bool, for example a str or a list. reduce compiles to a loop in line that carries a plain accumulator, so it only folds into numbers and bools. Build strings or lists with map, join or a for loop instead."
	),
	NamedError(
		name = "ReduceLambda",
		text = "reduce expects a lambda (acc, x) => next",
		explain = "The second argument of reduce is not a lambda of exactly two parameters, for example a one-parameter lambda or a function passed by name. reduce calls it with the accumulator and the element, so both must be named. Write `xs.reduce(0, (acc, x): acc + x)`.",
		example = """
			xs = [1, 2, 3]
			print(xs.reduce(0, x: x * 2))
			"""
	),
	NamedError(
		name = "ReduceLambdaType",
		text = "reduce's lambda gives $1, the accumulator is $2",
		explain = "The lambda given to reduce returns a value of a different type than the accumulator, which is fixed by the start value. Every step must give back the next accumulator, so the two types must match. Change the lambda so it returns the accumulator's type, or start from a value of the type the lambda gives.",
		example = """
			words = ["a", "bb", "ccc"]
			print(words.reduce(0, (n, w): n > w.len))
			"""
	),
	NamedError(
		name = "IntegerArgument",
		text = "$1, got $2",
		explain = "A built-in method that takes an index, a count of decimals or bounds, such as lane, loadWord or a window's ends, was given a non-integer argument. These positions are integers because they count lanes or bytes. Pass an integer, converting with `i64(x)` when the value is a float.",
		example = """
			v = Simd<4>(1.0)
			print(v.lane(1.5))
			"""
	),
	NamedError(
		name = "StrArgument",
		text = "$1, got $2",
		explain = "A built-in method that needs a str argument, such as join's separator or fromJson's text, was given a value of another type. Pass a str, for example `\", \"`, or turn the value into one with interpolation like `\"\{n\}\"`.",
		example = """
			words = ["a", "b"]
			print(words.join(1))
			"""
	),
	NamedError(
		name = "PushArity",
		text = "push expects one value",
		explain = "push was called with no value or with more than one. A push appends exactly one element. Call push once per element, or use extend to append a whole list at once.",
		example = """
			mut xs = [1, 2]
			xs.push(3, 4)
			print(xs)
			"""
	),
	NamedError(
		name = "PushType",
		text = "push expects $1, got $2",
		explain = "The value pushed onto a list does not have the list's element type, which was fixed when the list was declared or first filled. A list holds elements of one type only. Convert the value first, for example `i64(x)` or `\"\{x\}\"`, or declare the list with the element type you need.",
		example = """
			mut xs = [1, 2]
			xs.push("three")
			print(xs)
			"""
	),
	NamedError(
		name = "PushIndexNeedsPlace",
		text = "the index push returns needs a list reached without calls: bind the list first",
		explain = "The index that push returns was used, but the list was reached through a function call, such as an element chosen by a call. The compiler needs a plain place, a variable, field or element path, to give back the new element's index safely. Bind the list to a variable first, push onto it, and use that index.",
		example = """
			fn last(n i64) i64: n - 1
			mut rows = [[1], [2]]
			k = rows[last(rows.len)].push(3)
			print(k)
			"""
	),
	NamedError(
		name = "NeedsBytes",
		text = "$1 needs a u8[], found $2[]",
		explain = "load16 or store16 was called on a list whose elements are not u8. These methods read or write sixteen bytes at once as a Simd<16, u8> vector, so they only exist on a u8[]. Call them on a list of bytes, for example one declared `xs u8[] = ...`.",
		example = """
			xs = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
			v = xs.load16(0)
			print(v.lane(0))
			"""
	),
	NamedError(
		name = "NeedsFloats",
		text = "$1 needs a f64[], found $2[]",
		explain = "load4 or store4 was called on a list of an element type that has no four-lane form of its own, such as f32, u8 or str. These methods move four lanes at once as a Simd<4, f64> vector, so they need an f64[] (an i64[] has its own Simd<4, i64> form). Use an `f64[]`, or the load of the vector width that matches the element type.",
		example = """
			xs f32[] = [1.0, 2.0, 3.0, 4.0]
			v = xs.load4(0)
			print(v)
			"""
	),
	NamedError(
		name = "ExtendNeedsList",
		text = "extend expects a list",
		explain = "extend was called with no argument or with more than one. It appends all the elements of exactly one other list. Pass a single list, calling extend again for each further list, or use push for one element.",
		example = """
			mut xs = [1, 2]
			xs.extend([3], [4])
			print(xs)
			"""
	),
	NamedError(
		name = "ExtendType",
		text = "extend expects $1[], got $2",
		explain = "extend was given something that is not a list with the same element type, often a single value or a list of another type. extend copies a whole list onto the end and does not convert its elements. Use push for one value, or convert the other list first, for example with map.",
		example = """
			mut xs = [1, 2]
			xs.extend(3)
			print(xs)
			"""
	),
	NamedError(
		name = "PopArity",
		text = "pop takes no arguments",
		explain = "pop was called with an argument, as if it could remove at an index. pop only takes the last element off the list and returns it. Call `xs.pop()` with no arguments.",
		example = """
			mut xs = [1, 2, 3]
			print(xs.pop(0))
			"""
	),
	NamedError(
		name = "JoinNeedsStrs",
		text = "join needs a str[], found $1[]",
		explain = "join was called on a list whose elements are not str. join only glues strings together and does not convert numbers or structs on its own. Turn the elements into strings first, for example `xs.map(\"\{it\}\").join(\", \")`.",
		example = """
			xs = [1, 2, 3]
			print(xs.join(", "))
			"""
	),
	NamedError(
		name = "ListOrElementMethod",
		text = "$1 on $2: the list's own takes $3 argument(s), each element's a $4; got $5",
		explain = "A method that exists both on the list itself and element by element, such as max, was called with an argument that fits neither reading. The list's own form takes one count of arguments and the element-wise form takes another type of argument, so the compiler cannot tell which was meant. Call the list's own form with its arguments, or pass a value of the element type for the element-wise one."
	),
	NamedError(
		name = "ArgumentsOfType",
		text = "$1 expects $2 arguments, got $3",
		explain = "A method of a SIMD vector, such as max, min, a comparison mask or a byte shuffle, was given an argument that is not a vector of the same kind. These methods work lane by lane between two vectors of one shape. Pass a vector of that type, for example `Simd<4>(2.0)`.",
		example = """
			xs u8[] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
			k = xs.load16(0)
			a = Simd<4>(1.0)
			print(a.max(k).sum())
			"""
	),
	NamedError(
		name = "DecimalsNeedFloat",
		text = r"decimals ({x:.2}) are a float's format, and the value is $1: convert it first ({f64(n):.2})",
		explain = r"An interpolation asked for a number of decimals, as in {x:.2}, on a value that is not a float. Decimals are only a float's format, and Zap does not convert an integer silently. Convert the value first, writing `{f64(n):.2}`."
	),
	NamedError(
		name = "MinMaxType",
		text = "$1 expects $2, got $3",
		explain = "min or max on a number was given an argument of a different numeric type. Both sides must be the same type because Zap never widens or narrows a number behind your back here. Convert one side explicitly, for example `i64(a).max(b)`.",
		example = """
			a i32 = 3
			b i64 = 4
			print(a.max(b))
			"""
	),
	NamedError(
		name = "NoMethod",
		text = "no method '$1' on $2",
		explain = "The method called does not exist on the value's type, neither as a built-in nor as a function of the program taking that type first. Check the spelling and the receiver's type, or declare `fn name(self T)` for the type."
	),
	NamedError(
		name = "CannotInferTypeParameter",
		text = "cannot infer type parameter $1 of $2",
		explain = "A generic function was called, but nothing in its arguments or in the place the result goes fixes one of its type parameters, typically one that appears only in the return type. The compiler needs every type parameter known to make the function's instance. Give the result a declared type, as in `xs i64[] = empty()`, or pass an argument that carries the type.",
		example = """
			fn empty<T>() T[]:
				[]
			xs = empty()
			print(xs.len)
			"""
	),
	NamedError(
		name = "ArgumentType",
		text = "$1 expects $2, got $3$4",
		explain = "An argument does not have the type the function's parameter declares, and no automatic widening applies. Zap converts only when a smaller number fits into a wider one of the same kind, or an integer's values are proven inside the parameter's type. Convert the value explicitly, for example `i64(x)` or `f64(n)`, or change the parameter's type."
	),
	NamedError(
		name = "IntrinsicNeedsList",
		text = "$1 needs a list, found $2",
		explain = "A list intrinsic of the runtime, such as __at, __zeroElem or __setAt, was given something that is not a list. These intrinsics exist only for the runtime module rt, which implements lists with them; a program calling one gets RuntimeIntrinsic first. Use indexing, `xs[i]` and `xs[i] = v`, in programs."
	),
	NamedError(
		name = "IntrinsicType",
		text = "__setAt expects $1, got $2",
		explain = "The runtime intrinsic __setAt was given a value whose type differs from the list's element type. It writes an element in place with no conversion, so the types must match exactly. It is only available inside the runtime module rt; programs write `xs[i] = v`."
	),
	NamedError(
		name = "IntrinsicNeedsType",
		text = "__cast needs an expected type",
		explain = "The runtime intrinsic __cast was used where no type is expected, so it does not know what to reinterpret its argument as. It takes its result type from the place it goes to, such as a declared variable or a return. It is only available inside the runtime module rt; programs use the conversions like `i64(x)`."
	),
	NamedError(
		name = "ArgumentTypeAt",
		text = "argument $1 of $2 expects $3, got $4",
		explain = "An argument of a built-in function, such as sleepMs or exit, or of a method call does not have the type its parameter expects. The message names the argument by position. Pass a value of the expected type, converting it explicitly if needed, for example `i64(x)`."
	),
	NamedError(
		name = "OptionalCallNotOptional",
		text = "'?.' needs an optional on the left, found $1",
		explain = "The `?.` operator was used on a value that is not optional. `?.` calls the method only when an optional holds a value, so on a plain value it means nothing. Use a normal `.` call, or give the value an optional type `T?` if it can be missing.",
		example = """
			s = "abc"
			print(s?.trim())
			"""
	),
	NamedError(
		name = "OptionalCallBorrow",
		text = "this '?.' call gives a reference into a value that ends with the expression: match the optional to borrow from its value",
		explain = "A `?.` call returns a reference, such as a window into a str, into the value held by the optional, but that unwrapped value is a temporary that ends with the expression. The reference would dangle, so only plain data can come out this way. Match the optional to bind its value to a name and borrow from that inside the arm, or call a method that returns an owned value.",
		example = """
			name str? = "  zap  "
			print(name?.trim() ?? "")
			"""
	),
	NamedError(
		name = "OutArgumentSpelling",
		text = "$1 is an out parameter: pass `out name`",
		explain = "An extern function's out parameter was passed a plain value. The system writes into the caller's variable, so the call must say which variable receives it. Write `out name` for a new or mutable variable, or `out _` to discard the value.",
		example = """
			extern fn QueryPerformanceCounter(out now i64) bool
			mut t = 0
			ok = QueryPerformanceCounter(t)
			print(ok)
			"""
	),
	NamedError(
		name = "OutTargetImmutable",
		text = "out $1 writes '$1', which is not mut (or use a new name)",
		explain = "`out name` named an existing variable that is not mutable. An out argument overwrites the variable, which Zap allows only for variables declared `mut`. Declare it `mut name = ...`, or use a name not yet bound so the call declares a new variable."
	),
	NamedError(
		name = "OutTargetType",
		text = "out $1: the parameter is $2, '$1' is $3",
		explain = "`out name` named an existing variable whose type differs from the out parameter's type. The system writes a value of the parameter's type into that variable, so the types must be exactly the same. Declare the variable with the parameter's type, or use a fresh name so the call declares it with the right type.",
		example = """
			extern fn QueryPerformanceCounter(out now i64) bool
			mut t = 0.0
			_ = QueryPerformanceCounter(out t)
			print(t)
			"""
	),
	NamedError(
		name = "BaseFirst",
		text = "..base comes first, the fields that differ after it: $1(..base, field = value)",
		explain = "In a struct literal that copies fields from another value with ..base, the base was not written first. The base gives every field not named, so it comes first and the fields that differ follow. Write `Point(..p, x = 3)`."
	),
	NamedError(
		name = "FieldGivenTwice",
		text = "the field '$1' is given twice",
		explain = "A struct literal gave the same field twice, for example once by name and once through a variable of the same name, which fills that field by itself. Each field takes exactly one value. Remove one of the two, or rename the variable if it was not meant to fill the field.",
		example = """
			type Point:
				x i64
				y i64
			x = 3
			p = Point(x = 1, x)
			print(p)
			"""
	),
	NamedError(
		name = "TooManyValues",
		text = "$1 has $2 field(s), this is value $3",
		explain = "A struct was built with more positional values than it has fields. Values given by position fill the fields in their declared order, so a value past the last field has nowhere to go. Remove the extra value, or check the type's declaration for a missing field.",
		example = """
			type Point:
				x i64
				y i64
			print(Point(1, 2, 3))
			"""
	),
	NamedError(
		name = "SizeIsField",
		text = "$1 reads as a field: xs.$2",
		explain = "A size such as len was called like a method with parentheses. Sizes read as fields in Zap. Write `xs.len`, without the parentheses."
	),
	NamedError(
		name = "ArgsIsValue",
		text = "the program's arguments are a value: args (args.len, for a in args)",
		explain = "The program's arguments were called like a function, as in args(). args is a plain value, the list of the command line's arguments. Write `args`, `args.len` or `for a in args`."
	),
	NamedError(
		name = "NotAFunction",
		text = "'$1' is a $2, not a function",
		explain = "A call names a local variable whose type is not a function, for example a number or a list. Only functions and variables holding a function value can be called. Check that the variable is not hiding a function of the same name, and rename it if it is.",
		example = """
			n = 3
			print(n(2))
			"""
	),
	NamedError(
		name = "NotCallable",
		text = "cannot call a value of type $1",
		explain = "An expression that is not a function value, such as an element of a list of numbers, was called with parentheses. Only values of a fn type can be called. Check that the expression gives a function, or remove the parentheses if you meant the value itself.",
		example = """
			xs = [1, 2]
			print(xs[0](1))
			"""
	),
	NamedError(
		name = "UnknownIntrinsic",
		text = "unknown intrinsic '$1'",
		explain = "A name starting with two underscores was called, but no intrinsic of that name exists. Names starting with __ are reserved for the runtime's intrinsics. Rename the function so it does not start with __.",
		example = """
			print(__frobnicate(1))
			"""
	),
	NamedError(
		name = "RuntimeIntrinsic",
		text = "'$1' is a runtime intrinsic, not available to programs",
		explain = "A program called one of the runtime's intrinsics, the low level operations whose names start with __. They are reserved for the runtime module, which builds the language's safe operations on them, and are not checked for safety the way programs are. Use the language's own form instead, such as indexing or the std library.",
		example = """
			print(__ld64(0))
			"""
	),
	NamedError(
		name = "WrapNeedsInteger",
		text = "$1.wrap takes an integer, got $2",
		explain = "A wrapping conversion such as u8.wrap(x) was given a value that is not an integer. wrap keeps the low bits of an integer, which has no meaning for a float. Convert the float to an integer first, for example `u8.wrap(i64(x))`.",
		example = """
			print(u8.wrap(1.5))
			"""
	),
	NamedError(
		name = "ZerosFillArguments",
		text = "$1 takes $2",
		explain = "`zeros(n)` is n zeros and `fill(n, v)` is n copies of v; more sizes make lists of lists, the outermost size first and the value of `fill` always last: `zeros(n, m)`, `fill(n, m, -1)`. A call with fewer arguments than that has no size, or no value to fill with.",
		example = """
			print(fill(3).len)
			"""
	),
	NamedError(
		name = "ZerosElement",
		text = "zeros makes numbers, bools and optionals, not $1: write fill(n, v) with the value wanted",
		explain = "`zeros(n)` is n of the element type's zero, which only a number (`0`), a bool (`false`) and an optional (`none`) has. A struct's zero would be its fields zeroed, bypassing the defaults its fields declare, so the value is written: `fill(n, Point())`. The element type comes from the type the place expects (`xs u8[] = zeros(n)`), an `i64` when nothing expects one."
	),
	NamedError(
		name = "CannotPackBits",
		text = "$1 cannot be packed into bits: field '$2' is $3 (a bool, an unsigned integer or a range type packs)",
		explain = "`v.toBits()` and `T.fromBits(w)` pack a struct's fields side by side in one word, each in the bits its values need, so every field must have a known number of bits: a bool takes one, an unsigned integer its width, a range type (`i32 in 0..=16`) the bits that hold its span. Give the field a range, or pack the value by hand."
	),
	NamedError(
		name = "BitsTooWide",
		text = "$1 takes $2 bits: toBits packs at most 64 (32 in a shader)",
		explain = "A struct's fields packed side by side take more bits than one word holds: a `u64` on the CPU, a `u32` on the GPU. Narrow the fields' ranges, or split the struct in two words.",
		example = """
			type Big:
				a u64
				b bool
			print(Big(a = 1, b = true).toBits())
			"""
	),
	NamedError(
		name = "FromBitsWord",
		text = "$1.fromBits takes the $2 its toBits gives, got $3",
		explain = "`T.fromBits(w)` reads back the word `v.toBits()` made: a `u32` for a struct whose fields take 32 bits or fewer, a `u64` past that. Pass that word, converting it first if needed.",
		example = """
			type Small:
				on bool
			w u64 = 1
			print(Small.fromBits(w))
			"""
	),
	NamedError(
		name = "BitsOutside",
		text = "bits $1 lie outside the bits of $2",
		explain = "`x.bit(n)`, `x.bits(from, count)`, `x.withBit(n, on)` and `x.withBits(from, count, v)` name bits from 0 (the lowest) up to the width of x's type, and so does a field of a `bits` type. A position whose value the compiler knows (a literal, a constant) must lie inside that width and a count be at least 1. Name bits the type holds, or widen x first (`u64(x).bits(0, 40)`)."
	),
	NamedError(
		name = "BitsBase",
		text = "a bits type is laid out in an unsigned integer (u8, u16, u32, u64), got $1",
		explain = "`type Status bits u8:` names the integer whose bits the fields are. The bits of a signed integer, a range or another defined type are not plain bits, so the base is one of u8, u16, u32 and u64.",
		example = """
			type Flags bits i8:
				on bool = 0
			print(Flags(on = true))
			"""
	),
	NamedError(
		name = "BitsField",
		text = "field '$1' of a bits type is a bool at one bit (`= 7`) or an unsigned integer over a range of bits (`= 0..3`)",
		explain = "Each field of a bits type names where it lies: a bool its one bit, an unsigned integer no wider than the base the bits from the first to the end left out, which its type holds. Write the bit or the range after `=`, and give the field the type its bits read as."
	),
	NamedError(
		name = "BitsOverlap",
		text = "fields '$1' and '$2' of a bits type share bits",
		explain = "A bits type's fields each own their bits: a write to one would change the other. Give each field bits of its own."
	),
	NamedError(
		name = "FromBitsType",
		text = "f$1.fromBits takes the u$1 of an f$1's bits, got $2",
		explain = "f32.fromBits or f64.fromBits was given an integer of a different width than the float. The bits of an f32 are a u32 and those of an f64 a u64, and the conversion reinterprets exactly those bits. Pass the unsigned integer of the float's own width, converting it first if needed.",
		example = """
			u u64 = 1
			print(f32.fromBits(u))
			"""
	),
	NamedError(
		name = "CannotDecode",
		text = "$1 cannot be decoded (it holds a non-serializable field)",
		explain = "Type.fromJson or Type.fromBytes was called on a type that holds a field that cannot be serialized, such as a function, a reference, a fixed array, a result or a shared box. Only plain data, numbers, strings, lists, maps, optionals and structs or enums of them, can be read back from text or bytes. Keep the non-serializable field out of the type you decode, or decode a plain type and build the full one from it.",
		example = r"""
			type Rule:
				name str
				test fn(i64) bool
			_ = Rule.fromJson("\{\}")
			"""
	),
	NamedError(
		name = "FromBytesArity",
		text = "fromBytes expects one u8[] argument (fromBytesAt, a u8[] and a position)",
		explain = "Type.fromBytes was called with no argument or with more than one. It decodes one value from exactly one u8[] of encoded bytes. Pass the bytes a toBytes() call made. Type.fromBytesAt takes the bytes and the position to read at.",
		example = """
			type Point:
				x i64
			_ = Point.fromBytes()
			"""
	),
	NamedError(
		name = "FromBytesAtPosition",
		text = "fromBytesAt expects an integer position, got $1",
		explain = "Type.fromBytesAt(bytes, at) reads one value from the bytes at the position at, so the position is an integer. Pass the offset of the value in the list.",
		example = """
			type Point:
				x i64
			bytes u8[] = []
			_ = Point.fromBytesAt(bytes, "x")
			"""
	),
	NamedError(
		name = "FromBytesType",
		text = "fromBytes expects a u8[], got $1",
		explain = "Type.fromBytes was given something that is not a u8[], such as a str. It decodes the binary form that toBytes() makes, which is a list of bytes. Pass that u8[], or use fromJson for text.",
		example = """
			type Point:
				x i64
			_ = Point.fromBytes("x")
			"""
	),
	NamedError(
		name = "FromJsonArity",
		text = "fromJson expects one str argument",
		explain = "Type.fromJson was called with no argument or with more than one. It decodes one value from exactly one str of JSON. Pass the text only, and handle the none it gives on bad input with `??` or a match.",
		example = """
			type Point:
				x i64
			_ = Point.fromJson()
			"""
	),
	NamedError(
		name = "StrOneValue",
		text = "str(x) takes one value: the text of x, or a str of the bytes of a u8[]",
		explain = "str(...) was called with no value or with several. str(x) is the text of one value, as an interpolation writes it; of a u8[] it is a str of its bytes (copied from a place, taken without a copy with str(move bytes)). Pass one value, or join texts with an interpolation.",
		example = """
			print(str(1, 2))
			"""
	),
	NamedError(
		name = "BoxArity",
		text = "Box takes one value",
		explain = "Box was called with no value or with more than one. A Box moves exactly one value to the heap. Pass a single value, wrapping several in a struct or a tuple first.",
		example = """
			b = Box(1, 2)
			print(b)
			"""
	),
	NamedError(
		name = "UnknownFunction",
		text = "unknown function '$1'",
		explain = "No function of that name is declared in the program, its imports or the built-ins. Check the spelling, import the module that declares it, or call it through its module."
	),
	NamedError(
		name = "GpuFunction",
		text = "'$1' is a GPU function: the CPU names it in shader(...) only",
		explain = "CPU code called a function declared in a .gpu.zap file. Functions of GPU files are compiled by the shader compiler for the GPU only and have no CPU code to call. Name them in shader(...) to build a shader from them, and keep logic the CPU also needs in a normal file. It takes two files, a .gpu.zap module and the CPU program importing it, so no one-file example shows it."
	),
	NamedError(
		name = "RangeLacksMethod",
		text = "a range has no method '$1' (map, filter, flatMap, each, all, any, count, find, reduce, sum)",
		explain = "A method or field that ranges do not have, such as len, was used on a range. A range is not a list; it only offers the pipeline steps that run in line over its numbers. Use one of those, for example count or sum, or make a list with `(lo..hi).map(it)` first."
	),
	NamedError(
		name = "TakeNeedsPlace",
		text = "take needs a variable, field or element to take from",
		explain = "`move` was used to take a Box out of something that is not a variable, field or element, such as a field of a call's result. Taking out leaves the empty value behind in the place, so the place must be one the program owns and names. Bind the result to a mutable variable first and move the box out of that.",
		example = """
			type Holder:
				b Box<i64>
			fn make() Holder:
				Holder(b = Box(1))
			x = move make().b
			print(x)
			"""
	),
	NamedError(
		name = "CopyArity",
		text = "copy takes no arguments",
		explain = "copy() was called with an argument. copy makes a full copy of the value it is called on and takes nothing else. Call `x.copy()`, and use a window like `xs[a..b].copy()` to copy only a part.",
		example = """
			xs = [1, 2, 3]
			ys = xs.copy(2)
			print(ys)
			"""
	),
	NamedError(
		name = "DropTypeNotCopied",
		text = "a $1 releases what it holds when dropped (a drop function), so it is not copied: it moves, or its type declares `fn copy(self T) T`",
		explain = "A value whose type has a drop function, or a list of such values, was copied with copy(). Such a value releases what it holds when destroyed, so two copies would release it twice. Move the value instead, or declare `fn copy(self T) T` on the type to say how a copy is made."
	),
	NamedError(
		name = "IntoStrArity",
		text = "intoStr takes no arguments",
		explain = "The compiler's internal intoStr, which str(move bytes) becomes, received arguments. Programs never write intoStr themselves; it is produced only by the str(move bytes) form, so this error should not arise from ordinary code. Write `str(move bytes)` to make a str of a u8[]."
	),
	NamedError(
		name = "IntoStrNeedsPlace",
		text = "intoStr needs a variable, field or element to take the bytes from",
		explain = "str(move ...) was given an expression that is not a variable, field or element, such as a call. move takes the bytes out of a place and leaves it empty, which a temporary does not need. Drop the move: `str(makeBytes())` already takes a list made by a call without copying.",
		example = """
			fn greeting() u8[]:
				[104, 105]
			s = str(move greeting())
			print(s)
			"""
	),
	NamedError(
		name = "TakeArity",
		text = "take takes no arguments",
		explain = "The compiler's internal take, which `move place` becomes, received arguments. Programs do not call take; they write `move place`, which never carries arguments, so this error should not arise from ordinary code. Write `move x`, `move p.field` or `move xs[i]`."
	),
	NamedError(
		name = "MoveNeedsPlace",
		text = "move needs a variable, field or element to take the value from",
		explain = "move was applied to something that is not a variable, field or element, such as a call or a field of a call's result. move takes a value out of a place and leaves the empty value there, and a temporary has no place. Remove the move, since a call's result is already owned, or bind it to a mutable variable and move out of that.",
		example = """
			fn names() str[]:
				["a", "b"]
			xs = move names()
			print(xs)
			"""
	),
	NamedError(
		name = "NoArguments",
		text = "$1 takes no arguments",
		explain = "toBytes (or a method that takes no arguments) was called with an argument. toBytes turns the whole value into a u8[] and takes no options; only toJson takes an indent. Call `x.toBytes()` with nothing between the parentheses.",
		example = """
			type Point:
				x i64
			p = Point(x = 1)
			print(p.toBytes(2))
			"""
	),
	NamedError(
		name = "CannotEncode",
		text = "$1 cannot be encoded",
		explain = "toJson or toBytes was called on a value whose type holds something that cannot be serialized, such as a function, a reference, a fixed array, a result or a shared box. Only plain data can be written out and read back. Encode a type made of numbers, strings, lists, maps, optionals and structs or enums of them, leaving the other fields out.",
		example = """
			fn double(x i64) i64: x * 2
			type Rule:
				apply fn(i64) i64
			r = Rule(apply = double)
			print(r.toJson())
			"""
	),
	NamedError(
		name = "FixedArrayLacksMethod",
		text = "a $1 has len(), indexing, for loops and $2 and sum, not '$3' (a.map(x => x) makes a list)",
		explain = "A method that a fixed-size array does not offer, such as find or filter, was called on one. An array like i64[4] keeps its elements in place and only has len, indexing, for loops and a few reductions, so nothing hands out references into it. Make a list first with `a.map(x: x)` and call the method on that."
	),
	NamedError(
		name = "DropCalled",
		text = "drop runs where the value is destroyed, never by a call: let the value's last use end it, or store over it",
		explain = "A value's drop function was called directly. drop runs by itself exactly once, where the value is destroyed, so calling it would release the value twice. Let the value's last use end it, or assign a new value over it."
	),
	NamedError(
		name = "AmbiguousFunction",
		text = "$1.$2 could be $3.$2 or $4.$2: call one by its module",
		explain = "A call written Type.f(...) matches functions f that return Type in two different modules, so the compiler cannot choose. Such calls look for a function giving the type in its own module, the current one and the imported ones. Call the one you mean through its module, as in `extra.f(...)`."
	),
	NamedError(
		name = "TypeFormCall",
		text = "'$1' of the standard library is written $2, its type's form",
		explain = "A function of the standard library that takes a value of its own module's type, or of a language type, first was called as a free function (`math.rotate` given the quaternion first), or one that makes a language type (`perspective`, a `Mat4`) was called on its module. A method goes before a free function: write the call on the value (`q.rotate(v)`, `img.crop(0, 0, 8, 8)`) or on the type (`Mat4.perspective(fovY, aspect, near, far)`)."
	),
	NamedError(
		name = "NoTypeFunction",
		text = "$1 has no function '$2' here: $1.$2(...) calls `fn $2(...) $1` taking no $1 first, of its module, this one or one imported",
		explain = "A call written Type.f(...) found no function f that gives a Type without taking one first, in the type's module, the current module or an import. This form is for functions that make a value of the type, like constructors. Declare `fn f(...) Type` in one of those modules, or call a method on a value with `x.f(...)`."
	),
	NamedError(
		name = "RandomRange",
		text = "random takes a range with both ends and no step: random(0..10), random(1..=6), random(0.0..1.0)",
		explain = "random was given something other than a range with both ends and no step, such as a step range, an open range or a plain number. random draws one number from a bounded set of values. Write `random(0..10)`, `random(1..=6)` or `random(0.0..1.0)`."
	),
	NamedError(
		name = "RandomNotNumbers",
		text = "random draws from a range of numbers, found $1",
		explain = "random was given a range whose ends are not numbers, such as strings. random draws an integer or a float uniformly between two numeric ends. Use number ends, or pick from a list with an index drawn by `random(0..xs.len)`.",
		example = """
			print(random("a".."z"))
			"""
	),
	NamedError(
		name = "RandomEndsDiffer",
		text = "a range's ends have one type: $1 and $2",
		explain = "The two ends of the range given to random have different types, for example an i32 and an i64. The drawn number takes the range's type, so both ends must share it, and Zap does not convert silently. Convert one end, as in `random(i64(lo)..hi)`.",
		example = """
			lo i32 = 1
			hi i64 = 6
			print(random(lo..hi))
			"""
	),
	NamedError(
		name = "ArgIndexNotInteger",
		text = "arg takes the argument's position, an integer",
		explain = "The first value given to arg is not an integer. arg(i, default) reads the i-th command-line argument, counting from 0. Write `arg(0, 100)`.",
		example = """
			print(arg("a", 100))
			"""
	),
	NamedError(
		name = "ArgDefaultType",
		text = "arg's default is $1: a number or text gives the type the argument is read as",
		explain = "The default given to arg is not a number or text. arg(i, default) reads the i-th command-line argument as the default's type, which parses an integer, a float or text only. Write the default as `100`, `1.5` or `\"name\"`, or parse the argument yourself.",
		example = """
			print(arg(0, true))
			"""
	),
	NamedError(
		name = "AmbiguousMethod",
		text = "$1 on $2 could be $3.$1 or $4.$1: call one by its module",
		explain = "A method call matches functions of that name taking the value's type first in two different modules, so the compiler cannot choose. Methods are the functions of the type's module, the current module and the imported ones. Call the one you mean through its module, as in `other.spin(o)`."
	),
	NamedError(
		name = "NotAVariant",
		text = "'$1' is not a variant of $2",
		explain = "A variant name was used that the enum does not declare, for example `.Square` on a Shape that has only Circle and Point. Check the spelling against the enum's declaration, or add the variant to the type.",
		example = """
			type Shape:
				Circle(radius f32)
				Point

			s Shape = .Square
			print(s)
			"""
	),
	NamedError(
		name = "VariantArgumentCount",
		text = "variant $1 expects $2 argument(s), got $3",
		explain = "An enum variant was built with a different number of values than it declares fields. Each field of the variant takes one value, given in order. Pass exactly as many values as the variant has fields.",
		example = """
			type Shape:
				Circle(r i64)
				Box(w i64, h i64)
			s = Shape.Box(2)
			print(s)
			"""
	),
	NamedError(
		name = "VariantFieldType",
		text = "variant $1 field '$2' expects $3, got $4",
		explain = "A value given to an enum variant does not have the type of the field it fills. Variant fields are typed like struct fields and do not convert implicitly. Pass a value of the field's type, converting it if needed.",
		example = """
			type Shape:
				Circle(r i64)
				Box(w i64, h i64)
			s = Shape.Circle("big")
			print(s)
			"""
	),
	NamedError(
		name = "EnumUnknown",
		text = "'.$1' takes its enum from the place it goes to, and none is known here: write Type.$1",
		explain = "A variant was written in the short form `.Name`, but nothing around it says which enum it belongs to, for example when it initializes a variable with no declared type. The short form takes its enum from the place it goes to. Write the type, `Shape.Circle(1.0)`, or declare the variable as `s Shape = .Circle(1.0)`."
	),
	NamedError(
		name = "EnumValueNumber",
		text = "the value of variant $1 is not an integer that fits an i64",
		explain = "A variant's value, written after `=`, must be an integer literal, negative or in hex too, that an i64 holds. Write a smaller number.",
		example = """
			type Op:
				Add = 99999999999999999999
				Sub = 2
			print(Op.Add)
			"""
	),
	NamedError(
		name = "EnumValueMissing",
		text = "variant $1 has no value, but the other variants of $2 have one",
		explain = "An enum with integer values gives one to every variant, or to none. Write `= n` after this variant, or take the values away from the others.",
		example = """
			type Op:
				Add = 1
				Sub
			print(Op.Add)
			"""
	),
	NamedError(
		name = "EnumValuePayload",
		text = "variant $1 has an integer value and carries values",
		explain = "A variant with an integer value (`Add = 1`) carries nothing: the value is all it holds. Take the parentheses off the variant, or the value.",
		example = """
			type Op:
				Add(x i64) = 1
				Sub = 2
			print(Op.Sub)
			"""
	),
	NamedError(
		name = "EnumValueDuplicate",
		text = "variants $1 and $2 both have the value $3",
		explain = "The integers of an enum's variants are distinct, so that Type.from(n) names one variant. Give each variant its own integer.",
		example = """
			type Op:
				Add = 1
				Sub = 1
			print(Op.Add)
			"""
	),
	NamedError(
		name = "PatternNotStruct",
		text = "the pattern $1(...) takes apart a struct, found $2",
		explain = "A struct pattern such as `Point(x, y) = value` was used on a value that is not a struct, like a list or a number. This pattern takes a struct apart into its fields. Destructure only a value of that struct type, or index the list instead.",
		example = """
			type Point:
				x i64
				y i64
			Point(x, y) = [3, 4]
			print(x + y)
			"""
	),
	NamedError(
		name = "PatternTypeDiffers",
		text = "the pattern is $1(...) but the value is a $2",
		explain = "A struct pattern names one type but the value is a struct of another type. A pattern's fields are those of the type it names, so the two must be the same. Write the pattern with the value's own type, or convert the value first.",
		example = """
			type Point:
				x i64

			type Named:
				name str

			Point(x) = Named(name = "a")
			print(x)
			"""
	),
	NamedError(
		name = "PatternTooManyFields",
		text = "$1 has $2 fields, the pattern names more",
		explain = "A struct pattern lists more parts than the struct has fields. Each part by position binds one field in order, so an extra part matches nothing. Remove the extra names so there is at most one per field.",
		example = """
			type Point:
				x i64
				y i64
			Point(x, y, z) = Point(3, 4)
			print(x + y + z)
			"""
	),
	NamedError(
		name = "VariantValueCount",
		text = "variant $1 holds no value or several: test it with `is`, take its values apart with `is` or match",
		explain = "`e.Variant` is the one value a variant holds, or none when the enum holds another variant. A variant without values has nothing to give, and one of several values gives no single value. Test a variant with `e is Variant`, and take several values apart with `if e is Variant(a, b):` or a match."
	),
	NamedError(
		name = "VariantNeedsArguments",
		text = "variant $1 needs arguments",
		explain = "An enum variant that declares fields was used bare, without values. A variant with fields only exists together with those values. Pass them, as in `Shape.Circle(2)`, or use a variant without fields.",
		example = """
			type Shape:
				Circle(r i64)
				Point
			s = Shape.Circle
			print(s)
			"""
	),
	NamedError(
		name = "FieldOfTypeParameter",
		text = "$1 stands for a type of its bounds, which declare methods, not fields: '$2' is no field of it",
		explain = "A generic function read a field of a value whose type is a type parameter. A type parameter only promises what its bounds declare, and bounds declare methods, not fields. Add a method to the bound that returns the value, and call it, for example `x.radius()`."
	),
	NamedError(
		name = "TypeHasNoFields",
		text = "type $1 has no fields",
		explain = "A field was read from a value that is not a struct, such as a number, a str or a list. Only structs have named fields. Check the value's type, or call a method with parentheses if that is what you meant.",
		example = """
			n = 42
			print(n.value)
			"""
	),
	NamedError(
		name = "NoField",
		text = "$1 has no field '$2'",
		explain = "A struct value or pattern names a field the struct does not declare. Fields are fixed by the type's declaration. Check the spelling against the declaration, or add the field to the type.",
		example = """
			type Point:
				x i64
				y i64

			p = Point(1, 2)
			print(match p:
				Point(z = 0): 1
				_: 2
			)
			"""
	),
	NamedError(
		name = "CPointerField",
		text = "'$1' of $2 is a C pointer: it is given when the value is made, and is not read or changed after",
		explain = "A field of an extern type that is a C pointer, such as a `ref str`, was read or changed after the value was made. Such a field is given only when the value is built and then belongs to C, so Zap cannot safely see it as a Zap value again. Keep your own copy of the value you passed in, and read that instead."
	),
	NamedError(
		name = "MethodNeedsCall",
		text = "$1 is a method: write .$1() (a method is always called with parentheses)",
		explain = "A method was named without parentheses, as if it were a field. In Zap a method is always called with parentheses, while sizes like len read as fields. Write `.name()`."
	),
	NamedError(
		name = "CallbackNotFunction",
		text = "argument $1 of $2 is called back by the system: it must name a top-level function, not a lambda or a variable",
		explain = "An extern function that the system calls back, such as a window procedure, was given a lambda or a variable holding a function. The system calls it through a plain address with the system's convention, which only a top-level function has. Declare a top-level `fn` and pass it by name."
	),
	NamedError(
		name = "CannotInferTypeParameterHint",
		text = "cannot infer type parameter $1 of $2: write $2<...>",
		explain = "A generic struct was built without type arguments, and no field value fixes one of its type parameters, for example an empty list given to a T[] field. The compiler infers a parameter only from a field declared as exactly that type parameter. Write the type arguments, as in `Stack<i64>(items = [])`, or declare the variable's type.",
		example = """
			type Stack<T>:
				items T[]
			s = Stack(items = [])
			print(s.items.len)
			"""
	),
	NamedError(
		name = "NotAStruct",
		text = "'$1' is not a struct type",
		explain = "A struct literal names a type that is not a struct, such as an enum or a name with no declaration. This arises from literals the compiler itself forms, like those for tuples, a field's default or a value of another module, so ordinary code does not reach it directly. Build an enum's value through one of its variants, and a struct by its own name."
	),
	NamedError(
		name = "TupleValueType",
		text = "value $1 of the tuple expects $2, got $3$4",
		explain = "A tuple stands where a tuple type is expected, and one of its values (counted from 1) does not have the type at that position. Each position takes a value of its own type, widened only when a smaller number fits a wider one of the same kind, or an integer narrowed where its values are proven inside. Convert the value, or change the tuple type.",
		example = """
			fn pair() (i64, str):
				(1, 2)
			print(pair())
			"""
	),
	NamedError(
		name = "FieldType",
		text = "field '$1' expects $2, got $3$4",
		explain = "A value given to a struct field does not have the field's declared type. Fields take values of their own type, widened only when a smaller number fits a wider one of the same kind, or an integer narrowed where its values are proven inside. Convert the value, for example `f64(n)` or `\"\{n\}\"`, or change the field's type.",
		example = """
			type Point:
				x i64
				y i64
			p = Point(x = "one", y = 2)
			print(p)
			"""
	),
	NamedError(
		name = "FieldDefaultType",
		text = "the default of field '$1' is $2, the field $3",
		explain = "A struct field's default value does not have the field's type, which shows when a literal leaves that field out and the default fills it. The default is copied into each new value, so it must be a value of that type. Fix the default in the type's declaration, or change the field's type.",
		example = """
			type Hero:
				name str
				hp i64 = "full"
			h = Hero(name = "a")
			print(h.name)
			"""
	),
	NamedError(
		name = "MissingFields",
		text = "$1 is missing $2 $3 (give them values, or defaults in the type)",
		explain = "A struct was built without values for fields that have no default. Every field must be set when a value is made, since Zap has no uninitialized memory. Give those fields values in the literal, or add defaults in the type's declaration."
	),
	NamedError(
		name = "BaseTypeDiffers",
		text = "..base gives the fields of a $1, and it is a $2",
		explain = "The ..base of a struct literal is a value of another type. The base supplies the fields not named, which only works when it is the same struct type. Use a base of the literal's type, or name every field yourself.",
		example = """
			type Point:
				x i64
				y i64
			type Size:
				x i64
				y i64
			s = Size(x = 1, y = 2)
			print(Point(..s, x = 3))
			"""
	),
	NamedError(
		name = "LiteralOutsideRange",
		text = "integer literal $1 lies outside $2",
		explain = "An integer literal was given to a range type such as `i64 in 0..=100`, but the value lies outside that range. A range type only holds values within its bounds, and a literal is checked at compile time. Use a value within the bounds, or widen the type's range."
	),
	NamedError(
		name = "NegativeUnsigned",
		text = "integer literal $1 is negative but the type is $2",
		explain = "A negative integer literal was given to an unsigned type such as u32. Unsigned types hold no negative values and Zap does not wrap a literal silently. Use a signed type like i64, write the intended positive value, or use `u32.wrap(-1)` if you really want the wrapped bits.",
		example = """
			x u32 = -1
			print(x)
			"""
	),
	NamedError(
		name = "LiteralDoesNotFit",
		text = "integer literal $1 does not fit in $2$3",
		explain = "An integer literal is too large, or too small, for the type it goes to, such as 2147483648 for an i32. Zap checks literals against their type's range at compile time instead of truncating them. Use a wider type like i64, or a value within the type's range."
	),
	NamedError(
		name = "LambdaArity",
		text = "lambda takes $1 parameter(s) but a $2 is expected",
		explain = "A lambda declares a different number of parameters than the function type it is given to expects. The caller will pass exactly as many arguments as that type has parameters. Write the lambda with that many parameters, using `_` for one you do not need.",
		example = """
			fn apply(f fn(i64) i64) i64:
				f(1)
			print(apply((a, b): a + b))
			"""
	),
	NamedError(
		name = "CannotInferLambdaParameter",
		text = "cannot infer the type of lambda parameter '$1' (annotate it: ($1 i64): ...)",
		explain = "A lambda written `x: ...` takes its parameter types from the `fn` type the place expects; bound to a name with no type, or passed where nothing expects a function, there is nothing to take them from. Give the parameter its type, `(x i64): x + 1`, or give the binding a function type, `f fn(i64) i64 = x: x + 1`."
	),
	NamedError(
		name = "LambdaReturnType",
		text = "lambda returns $1 but $2 is expected",
		explain = "The lambda stands where a function type is expected, and the value its body gives cannot be assigned to that type's result. Change the body so it gives the expected result type, or change the declared `fn(...) R` to the type the lambda really returns.",
		example = r"""
			fn apply(f fn(i64) i64) i64:
				f(1)

			print(apply(x: "n{x}"))
			"""
	),
	NamedError(
		name = "FunctionValueArity",
		text = "function value $1 expects $2 argument(s), got $3",
		explain = "A function value (a lambda or a function passed by name) is called with a different number of arguments than its type declares. A function value has no defaults or named parameters, so every call gives exactly its parameters, in order.",
		example = """
			add = (a i64, b i64): a + b
			print(add(1))
			"""
	),
	NamedError(
		name = "FunctionValueArgument",
		text = "argument $1 expects $2, got $3",
		explain = "An argument of a call through a function value does not have the type of that parameter in the value's `fn` type. Calls through function values convert nothing; pass a value of the declared type, converting it first if needed (`i64(x)`, `\"\{x\}\"`).",
		example = """
			add = (a i64, b i64): a + b
			print(add(1, "two"))
			"""
	),
	NamedError(
		name = "SeqWalkedWhereMade",
		text = "a Seq is only walked where it is made: by a for, a step ($1) or .toList(); it is not stored, passed, returned or indexed",
		explain = "A generator's `Seq<T>` is not a value: its body is inlined into the loop that walks it, so it exists only at the place it is made. Walk it there with a `for` or a step (`filter`, `map`, `count`, `sum`...), or turn it into a list with `.toList()` when it must be stored, passed, returned or indexed."
	),
	NamedError(
		name = "GeneratorRecursion",
		text = "'$1' walks itself: a generator's body is inlined into the loop that walks it, so it cannot recurse; keep what is left to walk in a list (a stack) and loop over it",
		explain = "A generator is compiled by inlining its body into each loop that walks it, so a generator that walks itself, directly or through another generator, would inline forever. Keep what is left to visit in a list used as a stack and loop while it is not empty, yielding as you pop."
	),
	NamedError(
		name = "CannotInterpolate",
		text = "cannot interpolate a value of type $1",
		explain = r"Only values that can be shown (numbers, strings, bools, and structs, enums, lists, maps and optionals made of them) can go inside `{...}` in a string. Interpolate a field or a value computed from it instead.",
		example = r"""
			double = (x i64): x * 2
			print("double is {double}")
			"""
	),
	NamedError(
		name = "BaseOutsideLiteral",
		text = "..base gives a struct's literal the fields it leaves out: Point(..base, x = 1)",
		explain = "`..base` fills the fields a struct literal leaves out from another value of that struct, so it means something only among a struct literal's arguments. Write it inside the literal, `Point(..p, x = 1)`, and pass the struct itself elsewhere.",
		example = """
			type Point:
				x i64
				y i64

			p = Point(x = 1, y = 2)
			print(..p)
			"""
	),
	NamedError(
		name = "NamedArgumentMisplaced",
		text = "a named argument ('$1 = ...') is for a function or method declared with that parameter",
		explain = "A named argument `name = value` is matched against the parameters a function or method declares; built-in calls and calls that take no such parameter have nothing to match it to. Pass the value by position, or use the name only with a function whose parameter has it.",
		example = """
			mut xs = [1]
			xs.push(value = 2)
			print(xs)
			"""
	),
	NamedError(
		name = "LenOutsideIndex",
		text = "len stands inside an index's brackets for the indexed list's length (xs[length - 1]); elsewhere write xs.len",
		explain = "Inside an index's brackets a bare `len` is replaced by the indexed list's length (`xs[len - 1]`); this error is the guard for a `len` left over where no indexed list stands to give it. Write the length explicitly as `xs.len`. Outside brackets `len` is an ordinary name, so a plain program does not reach this error."
	),
	NamedError(
		name = "GenericAsValue",
		text = "generic function '$1' cannot be used as a value (call it with concrete types)",
		explain = "A generic function is compiled once per set of concrete types, so on its own it is not one function that a value could point to. Wrap a call in a lambda with concrete types, `(x i64): same(x)`, or write a non-generic function to pass around.",
		example = """
			fn same<T>(x T) T:
				x

			fns = [same]
			print(fns.len)
			"""
	),
	NamedError(
		name = "MutParameterAsValue",
		text = "'$1' has a mut parameter and cannot be used as a value",
		explain = "A function with a `mut` parameter changes its caller's variable in place, which a function value's `fn(...)` type cannot express, so such a function is not a value. Make the function return the new value instead, or wrap the work in a lambda that changes a captured variable.",
		example = """
			fn bump(mut n i64):
				n += 1

			fns = [bump]
			print(fns.len)
			"""
	),
	NamedError(
		name = "ReadBeforeSet",
		text = "$1 is read before it gets a value (an immutable T[N] declared without values binds each element once; a mut one starts from zeros)",
		explain = "An immutable fixed array declared without values gets each element once, by assignment, and this element is read before it is assigned. Assign it first, give the array its values in the declaration (`c i64[2] = [0, 0]`), or declare it `mut`, which starts every element from zero."
	),
	NamedError(
		name = "NoCallArgument",
		text = "$1 stands for a call argument's value: here there is none",
		explain = "`it` and a leading-dot field such as `.age` stand for the argument of the innermost call argument that takes a function of one value; here there is no such argument, either because the code is outside a call or because it sits inside a lambda that names its own parameter. Write a lambda with a named parameter, `p: p.age`, or move the expression into the call's argument."
	),
	NamedError(
		name = "ErrorOutsideFallback",
		text = "'$1' is a result's error: it is read on the right of ?? after a value that can fail and in a match's error: arm",
		explain = "The name `error` reads a result's error, so it exists only on the right of `??` after a `T ? E` and in a match's `error:` arm; a plain optional has no error to read. Use a fallback value with the optional (`o ?? 0`), or match the result and read `error` in its error arm."
	),
	NamedError(
		name = "UnknownVariable",
		text = "unknown variable '$1'",
		explain = "The name is not a variable, parameter or constant visible here: it may be misspelled, declared later, declared inside another block, or belong to a module, whose names are read through it. Declare it before use in this scope, or import the module (`import m`) and write `m.name`."
	),
	NamedError(
		name = "OutOutsideExtern",
		text = "out $1 is the argument of an extern fn's out parameter",
		explain = "`out x` hands a variable to an extern function's out parameter for the system to fill; any other call has no out parameter to receive it. Pass the value plainly, or have the function return the value and bind it, `k = count()`.",
		example = """
			fn show(n i64):
				print(n)

			show(out k)
			"""
	),
	NamedError(
		name = "RefNeedsPlace",
		text = "ref needs a variable, field or element to point to",
		explain = "A reference points into storage that already exists, so `mut ref` needs a variable, a field or an element; a literal or a call's result is a temporary with nowhere to point. Bind the value to a `mut` variable first and lend that, `mut xs = [1, 2]` then `r = mut ref xs`.",
		example = """
			r = mut ref [1, 2, 3]
			r.push(4)
			print(r)
			"""
	),
	NamedError(
		name = "AlreadyReference",
		text = "the value is already a reference",
		explain = "The value under `mut ref` is already a reference, and references are not stacked: a reference to a reference is never made. Use the existing reference directly, or lend the original place again under a new name.",
		example = """
			mut xs = [1, 2]
			r = mut ref xs
			r2 = mut ref r
			r2.push(3)
			print(xs)
			"""
	),
	NamedError(
		name = "ComplementNeedsInteger",
		text = "'~' needs an integer, found $1",
		explain = "`~` flips the bits of an integer, and the operand is of another type (a float, a bool, a string...). Convert it to an integer first, `~i64(x)`, or use `not` for a bool.",
		example = """
			x = 1.5
			print(~x)
			"""
	),
	NamedError(
		name = "NotNeedsBool",
		text = "'!' needs a bool, found $1",
		explain = "`not` negates a bool, and Zap has no truthiness: a number, string, list or optional is never read as a condition. Write the comparison you mean, such as `n == 0`, `s.isEmpty` or `o == none`."
	),
	NamedError(
		name = "NegateNeedsNumber",
		text = "unary '-' needs a number, found $1",
		explain = "Unary minus works on numbers (and on structs and lists of numbers, element by element); the operand here is neither. Negate a number, or convert the value into one first.",
		example = """
			s = "5"
			print(-s)
			"""
	),
	NamedError(
		name = "CannotMatch",
		text = "cannot match on type $1",
		explain = "`match` works on enums, optionals, results, numbers, strings, bools, structs, tuples, lists and maps; the value here is of a type it cannot take apart, such as a function value or a fixed array. Match on a value derived from it, or use an `if` chain.",
		example = """
			double = (x i64): x * 2
			match double:
				_: print("a function")
			"""
	),
	NamedError(
		name = "TryNeedsOptionalResult",
		text = "try requires the function to return an optional",
		explain = "`try` on an optional returns none from the current function when the value is absent, so the function itself must return an optional. Give the function a `T?` result, or handle the absence in place with `x ?? fallback` or a match.",
		example = """
			fn firstDoubled(xs i64[]) i64:
				v = try xs.first
				v * 2

			print(firstDoubled([1]))
			"""
	),
	NamedError(
		name = "TryNeedsResult",
		text = "try requires the function to return a result with the same error type",
		explain = "`try` on a result returns its error from the current function, so that function must return a result whose error type is the same `E`. Change the function's return type to `T ? E` with that error, or handle the error in place with `??` or a match.",
		example = """
			fn unwrap(r str ? i64) str:
				return try r
			print("x")
			"""
	),
	NamedError(
		name = "TryNeedsFallible",
		text = "try needs an optional or result, found $1",
		explain = "`try` unwraps an optional or a result and passes absence or the error up; the expression here can never fail, so there is nothing to try. Remove `try` and use the value directly.",
		example = """
			fn twice(n i64) i64?:
				x = try n
				x * 2

			print(twice(2) ?? 0)
			"""
	),
	NamedError(
		name = "GridCellSpelling",
		text = "a grid's cell is g[x, y], its row g[.., y]",
		explain = "A `Grid<T>` is indexed by both coordinates at once, so one index alone names neither a cell nor a row. Write `g[x, y]` for a cell, or `g[.., y]` for a whole row."
	),
	NamedError(
		name = "IndexNotInteger",
		text = "index must be an integer, found $1",
		explain = "Lists, strings and fixed arrays are indexed by integers, and this index is of another type (a float, a string...). Convert it, `xs[i64(f)]`, or use a map if the value is meant to be a key.",
		example = """
			xs = [10, 20]
			print(xs[1.0])
			"""
	),
	NamedError(
		name = "IndexOutside",
		text = "index $1 is outside the $2",
		explain = "The index is a literal known when compiling, and it falls outside the fixed array's length, so the access could only fail. Use an index from 0 to N - 1, or make the array longer."
	),
	NamedError(
		name = "FieldIndexOutside",
		text = "index $1 is outside $2, whose $3 fields are 0..$4",
		explain = "A struct whose fields are all one number type can be indexed by its fields' order (`v[0]` is its first field), and this literal index is past the last field. Use an index within the field count, or name the field.",
		example = """
			type Vec3:
				x f32
				y f32
				z f32
			v = Vec3(x = 1.0, y = 2.0, z = 3.0)
			print(v[3])
			"""
	),
	NamedError(
		name = "CannotIndex",
		text = "cannot index a value of type $1",
		explain = "Brackets index lists, strings, maps, fixed arrays, grids and structs of one number type; this value is of a type that has no elements. Index the collection it holds (a field or a method's result), or drop the brackets.",
		example = """
			n = 5
			print(n[0])
			"""
	),
	NamedError(
		name = "MapKeysDiffer",
		text = "map keys must share a type: $1 vs $2",
		explain = "A map literal's keys all have the map's one key type, and this key has a different type from the first one. Write every key with the same type, converting where needed (`\"\{n\}\"` or `i64(x)`).",
		example = r"""
			ages = {"ann": 30, 7: 40}
			print(ages)
			"""
	),
	NamedError(
		name = "MapValuesDiffer",
		text = "map values must share a type: $1 vs $2",
		explain = "A map literal's values all have the map's one value type, and this value's type differs from the first one's. Make the values one type, or use an enum or struct as the value type to hold different kinds.",
		example = r"""
			ages = {"ann": 30, "bob": "forty"}
			print(ages)
			"""
	),
	NamedError(
		name = "RangeOutsideFor",
		text = "a range (lo..hi) is the iterable of a for loop, or an index: a slice (xs[lo..hi])",
		explain = "A range `lo..hi` is not a value on its own: it is the iterable of a `for`, the receiver of a pipeline step, or a slice inside an index. Loop over it, call a step on it such as `(0..n).map(f)`, or slice with `xs[lo..hi]`.",
		example = """
			r = 0..10
			print(r)
			"""
	),
	NamedError(
		name = "UntypedEmptyListLiteral",
		text = "empty list literal needs a type annotation (e.g. items i32[] = [])",
		explain = "An empty `[]` gives no element to take a type from, and nothing around it says which list it is. Write the type on the binding, `items i64[] = []`, or pass it where a typed list is expected.",
		example = """
			print([])
			"""
	),
	NamedError(
		name = "ListElementsDiffer",
		text = "list elements must share a type: $1 vs $2",
		explain = "A list's elements all have one type, and this element's type differs from the first one's (only number literals widen to fit). Convert the elements to one type, or use an enum or struct to hold different kinds.",
		example = """
			xs = [1, "two"]
			print(xs)
			"""
	),
	NamedError(
		name = "FixedArrayCount",
		text = "a $1 takes $2 values, got $3 (fill($2, a) repeats one)",
		explain = "A `T[N]` literal must give exactly N values, and this one gives a different number. Write all N values, or repeat one value with `fill(N, x)`.",
		example = """
			xs i64[3] = [1, 2]
			print(xs)
			"""
	),
	NamedError(
		name = "FixedArrayElement",
		text = "an element of a $1 is a $2, got $3",
		explain = "Every element of a fixed array `T[N]` is a `T`, and this value of the literal has another type. Give values of the element type, converting where needed.",
		example = """
			xs i64[2] = [1, "two"]
			print(xs)
			"""
	),
	NamedError(
		name = "FixedArrayRepeat",
		text = "a $1 repeats its value $2 times: fill($2, x)",
		explain = "Where a `T[N]` is expected, `fill(k, x)` fills the array with one value, so the count must be the array's own length N written as that literal (or its number parameter). Write `fill(N, x)` with the declared length.",
		example = """
			zs f64[5] = fill(4, 0.5)
			print(zs)
			"""
	),
	NamedError(
		name = "ParallelSourceUnbound",
		text = "a parallel pipeline reads its source once for each part: bind it to a name first (or use a range lo..hi)",
		explain = "A parallel pipeline splits its source into parts and reads it once for each part, so the source must be something read again cheaply: a variable, a field or a range. Bind a computed list to a name first, `xs = [1, 2, 3]` then `xs.parallel().map(f)`.",
		example = """
			print([1, 2, 3].parallel().map(x: x * 2))
			"""
	),
	NamedError(
		name = "ParallelNeedsName",
		text = "$1 runs in parallel over a list bound to a name: xs.parallel().$1(f)",
		explain = "In parallel, minBy, maxBy and sortedBy work directly on a list bound to a name, not on the output of earlier steps. Bind the list first (for example the filtered one) and call `xs.parallel().minBy(f)` on it."
	),
	NamedError(
		name = "NotParallel",
		text = "$1 does not run in parallel: $2, sortedBy, minBy and maxBy do",
		explain = "Only some pipeline steps have a parallel form (map, filter, sum, count and the like, plus sortedBy, minBy and maxBy); this one, such as reduce, runs in order and cannot be split across threads. Drop `.parallel()` for it, or use a step that does run in parallel, such as `sum`."
	),
	NamedError(
		name = "OperatorUndefined",
		text = "operator '$1' not defined for $2 and $3",
		explain = "The math operators on lists of numbers work element by element between two lists of the same type, and `*` or `/` with a number of the element type; these two operands are not such a pair, for example an `i64[]` and an `f64[]`. Convert one side so both have the same element type, `a.map(f64(it))`.",
		example = """
			a = [1, 2]
			b = [1.0, 2.0]
			print(a + b)
			"""
	),
	NamedError(
		name = "BindExternArguments",
		text = "bindExtern takes an extern loaded fn and an address",
		explain = "`bindExtern` gives one `extern loaded fn` its address at run time, so it takes exactly two arguments: the function's name and the address. Call it as `bindExtern(f, address)`.",
		example = """
			extern loaded fn tick() i64

			bindExtern(tick)
			"""
	),
	NamedError(
		name = "BindExternTarget",
		text = "the first argument of bindExtern must name an `extern loaded fn`",
		explain = "`bindExtern` sets the address of a function declared `extern loaded fn`, and its first argument names something else, such as an ordinary function. Declare the target as `extern loaded fn name(...)` and pass that name.",
		example = """
			fn plain() i64:
				1
			bindExtern(plain, 0)
			"""
	),
	NamedError(
		name = "BindExternAddress",
		text = "the address given to bindExtern must be an integer, found $1",
		explain = "The second argument of `bindExtern` is the machine address of the code to call, an integer such as the one GetProcAddress or vkGetDeviceProcAddr returns. Pass that `i64` address.",
		example = """
			extern loaded fn tick() i64

			bindExtern(tick, "tick")
			"""
	),
	NamedError(
		name = "BindExternsArgument",
		text = "bindExterns takes the function that finds an address by name (fn(str) i64)",
		explain = "`bindExterns` takes exactly one argument: a function that, given a name, returns that function's address (`fn(str) i64`). Pass such a loader, for example a function that calls GetProcAddress.",
		example = """
			extern loaded fn tick() i64

			bindExterns()
			"""
	),
	NamedError(
		name = "BindExternsNone",
		text = "bindExterns: this module declares no `extern loaded fn`",
		explain = "`bindExterns` binds every `extern loaded fn` of the module that calls it, and this module declares none, so the call would do nothing. Declare the loaded externs in this module, or remove the call.",
		example = """
			fn find(name str) i64:
				0

			bindExterns(find)
			"""
	),
	NamedError(
		name = "BindExternsLoader",
		text = "the loader given to bindExterns must return an address (i64), found $1",
		explain = "The loader passed to `bindExterns` is called with each extern's name and must give its address as an integer. Make it return `i64`.",
		example = """
			extern loaded fn tick() i64

			fn find(name str) str:
				name

			bindExterns(find)
			"""
	),
	NamedError(
		name = "BaseOfFunction",
		text = "..base gives a struct's literal the fields it leaves out (Point(..base, x = 1)); $1 is a function",
		explain = "`..base` copies the fields a struct literal leaves out, so it belongs to a struct's literal, and here it is given to a call of a function. Build the struct with `Point(..base, x = 1)` and pass that, or pass the arguments the function declares.",
		example = """
			fn f(a i64, b i64) i64:
				a + b
			x = 1
			print(f(..x, b = 2))
			"""
	),
	NamedError(
		name = "NoParameter",
		text = "$1 has no parameter '$2'",
		explain = "A named argument must match one of the parameters the called function declares, and none has this name. Fix the spelling to the declared parameter name, or pass the value by position."
	),
	NamedError(
		name = "ArgumentGivenTwice",
		text = "the argument of '$1' is given twice",
		explain = "The same parameter gets two values: once by position and again by name, or by name twice. Give each parameter one value; after positional arguments, name only the parameters they did not fill.",
		example = """
			fn area(w i64, h i64) i64:
				w * h

			print(area(2, w = 3))
			"""
	),
	NamedError(
		name = "MissingArgument",
		text = "$1 needs $2 for $3",
		explain = "The call leaves out parameters that have no default value, so the function cannot run. Pass a value for each listed parameter, by position or by name, or give those parameters defaults in the declaration."
	),
	NamedError(
		name = "FloatMethod",
		text = "'$1' is a method of floats: $2 holds $3",
		explain = "Number methods applied to a struct of numbers run field by field, and this one (such as floor, sqrt or round) exists only for floats, while the struct's fields are integers. Use a struct with float fields, or convert the fields first."
	),
	NamedError(
		name = "ArgumentKind",
		text = "$1 takes a $2$3, got $4",
		explain = "A number's method applied to a struct of numbers runs field by field, so each argument must be the same struct type or, for most methods, a number of the fields' type; this argument is neither. Pass a struct of the same type or a number of the field type (a literal takes that type).",
		example = """
			type Point:
				x f64
				y f64

			p = Point(x = 1.0, y = 2.0)
			print(p.min("a"))
			"""
	),
	NamedError(
		name = "OperatorNotDefined",
		text = "'$1' is not defined on $2",
		explain = "Structs whose fields are all one number type get only `+ - * /` element by element and `@` as a product; other operators such as `%`, `**` or bitwise ones have no fixed meaning on them. Apply the operator to the fields one by one, or write a method that does it.",
		example = """
			type Point:
				x f64
				y f64

			p = Point(x = 1.0, y = 2.0)
			print(p % p)
			"""
	),
	NamedError(
		name = "NoArithmetic",
		text = "$1 has no arithmetic: + - * / work element by element on a struct whose fields are all one number type",
		explain = "`+ - * /` work on a struct only when every field has one and the same number type, and this struct mixes types or holds non-numbers. Compute on the fields explicitly, or write a method such as `fn add(self M, o M) M`."
	),
	NamedError(
		name = "ShapesDiffer",
		text = "'$1' is element by element: $2 and $3 have different shapes (a product is written a @ b)",
		explain = "`+ - * /` on vectors and matrices work element by element, so both sides must have the same shape, and these differ (for example a matrix and a vector). For the matrix or dot product, write `a @ b`."
	),
	NamedError(
		name = "StructScalarType",
		text = "a $1 meets a number of its fields' type $2, got $3",
		explain = "A struct of numbers can meet a single number in `+ - * /`, which applies to every field, but the number must have the fields' type exactly. Convert it, for example `f32(n)`, or write a literal that takes the fields' type."
	),
	NamedError(
		name = "ProductShapes",
		text = "'@' needs the sizes to meet: $1 @ $2 (R x K @ K x C, R x K @ K or N @ N)",
		explain = "The operands of `@` are fixed arrays of numbers, or structs holding one, whose shapes are their types, and the inner sizes differ: a product of an R x K matrix needs K rows or K values on its right, a dot product two arrays of one length, and one number type on both sides. Give operands of matching sizes.",
		example = """
			a f32[3, 2] = [[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]]
			b f32[3, 3] = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
			print(a @ b)
			"""
	),
	NamedError(
		name = "ProductOperands",
		text = "'@' is a product: matrix @ matrix, matrix @ vector, quaternion @ quaternion or vector @ vector (their dot product), found $1 and $2",
		explain = "`@` is a product with fixed meanings: matrix @ matrix, matrix @ vector, quaternion @ quaternion, or vector @ vector giving their dot product, with matching sizes. These operands fit none of them; use `*` for element-by-element multiplication, or pass operands of matching shapes."
	),
	NamedError(
		name = "DefaultBeforePlain",
		text = "parameter '$1' comes after one with a default, so it needs a default too",
		explain = "A call leaves defaulted parameters out from the end and fills the rest by position, so once a parameter has a default every parameter after it has one. Give this parameter a default, or move the defaulted parameters to the end of the list.",
		example = """
			fn f(a i64 = 1, b i64) i64:
				a + b
			print(f(1, 2))
			"""
	),
	NamedError(
		name = "DefaultReadsVariable",
		text = "the default of $1 '$2' reads a variable (a default is a value of its own: literals, constants, calls)",
		explain = "A default value of a field or parameter is evaluated on its own at each place it is used, so it cannot read a local or module variable whose value depends on where or when it runs. Use a literal, a constant or a call, or pass the value explicitly."
	),
	NamedError(
		name = "NonePatternNotOptional",
		text = "'none' pattern is only valid on optionals",
		explain = "The `none` pattern tests an optional for absence, and the matched value is not an optional, so it can never be none. Remove that arm, or match on a value of type `T?`.",
		example = """
			n = 5
			match n:
				none: print("nothing")
				_: print(n)
			"""
	),
	NamedError(
		name = "PatternDoesNotFit",
		text = "the pattern $1(...) does not fit a $2",
		explain = "A pattern `Name(...)` must name a variant of the matched enum or the matched struct's own type, and this name is neither for the matched value's type. Use the struct's real name or one of the enum's variants.",
		example = """
			type Point:
				x i64
				y i64

			p = Point(1, 2)
			print(match p:
				Size(0, 0): 1
				_: 2
			)
			"""
	),
	NamedError(
		name = "TuplePatternDoesNotFit",
		text = "a pattern of a tuple of $1 does not fit a $2",
		explain = "A tuple pattern `(a, b, ...)` fits only a tuple with the same number of parts, and the matched value is not one, or has a different count. Write one pattern per part of the tuple, or match the value with a pattern of its own type.",
		example = """
			p = (1, 2)
			match p:
				(a, b, c): print(a)
				_: print("other")
			"""
	),
	NamedError(
		name = "EnumPatternLiteral",
		text = "a match on $1 takes its variants (Circle(r), Point), not literals",
		explain = "An enum is matched by its variants, `Circle(r)` or `Point`, not by numbers or strings: its values have no literal form. Write the variant names in the arms.",
		example = """
			type Color:
				Red
				Green

			c = Color.Red
			match c:
				0: print("red")
				_: print("other")
			"""
	),
	NamedError(
		name = "PatternType",
		text = "pattern is $1 but the matched value is $2",
		explain = "A literal pattern is compared with the matched value, so it must have the value's type, and this one does not (a string arm on a number, for instance). Write literals of the matched type, or match on a value converted to the literal's type."
	),
	NamedError(
		name = "RangePatternNotNumber",
		text = "a range pattern is for numbers; the matched value is $1",
		explain = "A range pattern `lo..hi` tests where a number lies, so it fits only integers and floats. Match strings, bools and other values with literals or other patterns, or compute a number to match on.",
		example = """
			s = "x"
			print(match s:
				1..3: 1
				_: 0
			)
			"""
	),
	NamedError(
		name = "ListPatternDoesNotFit",
		text = "a list's pattern does not fit a $1",
		explain = "A list pattern such as `[]` or `[x, ..rest]` takes apart a list, and the matched value is not one. Match a list value, or use a pattern of the value's own type.",
		example = """
			n = 5
			match n:
				[]: print("empty")
				_: print("other")
			"""
	),
	NamedError(
		name = "StrPatternDoesNotFit",
		text = "a string's pattern does not fit a $1",
		explain = "A string pattern with captures, such as `\"GET \{path\}\"`, takes a string apart, and the matched value is not a string. Match on a `str`, converting the value with `\"\{x\}\"` if that is the intent.",
		example = r"""
			n = 5
			match n:
				"id {rest}": print(rest)
				_: print("other")
			"""
	),
	NamedError(
		name = "MapPatternDoesNotFit",
		text = "a map's pattern does not fit a $1",
		explain = "A map pattern such as `\{\"k\": v\}` looks keys up in a map, and the matched value is not a map. Match a `\{K: V\}` value, or use a pattern of the value's own type.",
		example = r"""
			n = 5
			match n:
				{"a": x}: print(x)
				_: print("other")
			"""
	),
	NamedError(
		name = "PatternDoesNotFitValue",
		text = "this pattern does not fit a $1",
		explain = "This is the pattern checker's fallback for a pattern whose form fits none of the ways the matched type can be taken apart; the ordinary mismatches (a list, string, map, tuple or none pattern on the wrong type) have errors of their own, so a plain program rarely reaches it. Rewrite the arm with a pattern of the matched type: a variant, a literal, a range, a tuple, a list, a string or a map pattern as the value calls for."
	),
	NamedError(
		name = "VariantBindingCount",
		text = "$1 expects $2 binding(s), got $3 (or none and no parentheses: $1 alone matches whatever it holds)",
		explain = "A variant's pattern written with parentheses binds its fields by position, so it must list exactly as many names as the variant has fields. List one name or `_` per field, or write the variant alone, without parentheses, to match it whatever it holds.",
		example = """
			type Shape:
				Rect(w f64, h f64)
				Point

			s = Shape.Rect(1.0, 2.0)
			match s:
				Rect(w): print(w)
				Point: print(0)
			"""
	),
	NamedError(
		name = "MutRefLendsOnce",
		text = "'$1' lends one place for as long as it is used: lend another under a name of its own (other = mut ref ...)",
		explain = "A name bound to `mut ref place` keeps lending that one place while it is used, so assigning it another `mut ref` would re-point it. Lend the other place under its own name, `other = mut ref b`.",
		example = """
			mut a = [1]
			mut b = [2]
			r = mut ref a
			r = mut ref b
			r.push(3)
			print(a)
			"""
	),
	NamedError(
		name = "AssignType",
		text = "'$1' is $2, cannot assign $3$4",
		explain = "The value assigned has a type that the variable's declared or inferred type cannot hold; Zap converts no numbers implicitly except literals. Convert the value explicitly (`i64(x)`), or declare the variable with the type you need."
	),
	NamedError(
		name = "MutBindingOfReference",
		text = "'$1' is mut, so it needs a value of its own, but this is a reference into a value that belongs to someone else: bind it without mut, or give a value of its own (.copy())",
		explain = "The value bound is a reference into storage that belongs to something else, such as a lookup (`xs.first`, `m.get(k)`) or a function returning `ref T`, and a `mut` binding must own what it changes; only plain data is copied for it automatically. Bind it without `mut` to read it in place, or take a value of its own with `.copy()` to change it.",
		example = """
			rows = [[1], [2]]
			mut first = rows.first
			print(first)
			"""
	),
	NamedError(
		name = "InitializerType",
		text = "'$1' declared $2 but initializer is $3$4",
		explain = "The declared type of the binding and the type of the value it is initialized with differ, and Zap does not convert between them implicitly. Convert the value (`f64(n)`, `\"\{n\}\"`) or declare the type the value really has."
	),
	NamedError(
		name = "AlreadyDeclared",
		text = "'$1' is already declared in this scope",
		explain = "A new binding (with `mut` or a written type) reuses a name already declared in the same scope; a name is declared once per scope, and plain `x = value` on a `mut` name is how it gets a new value. Assign the existing variable, or choose another name.",
		example = """
			count = 1
			count i64 = 2
			print(count)
			"""
	),
	NamedError(
		name = "ParallelChange",
		text = "a parallel loop's body runs on several threads at once: it cannot change '$1', declared outside it",
		explain = "The body of a parallel loop runs on several threads at once, so assigning a variable declared outside it would be a data race. Compute per-iteration values into a list at the loop's own index, or use a parallel pipeline (`map`, `sum`) or an `Atomic` to combine results."
	),
	NamedError(
		name = "ParallelIndex",
		text = "a parallel loop's body runs on several threads at once: it changes '$1' (declared outside it) only at an index made from '$2'",
		explain = "A parallel loop may write a list declared outside it only at an index made from the loop's own variable, so each thread touches its own element; this write uses some other index, which threads could share. Write `xs[i] = ...` with the loop variable `i`."
	),
	NamedError(
		name = "ParallelChangeBy",
		text = "a parallel loop's body runs on several threads at once: it cannot $1 '$2', declared outside it",
		explain = "A parallel loop's body runs on several threads at once, so it cannot grow, shrink or otherwise call a changing method on a variable declared outside it (push, insert, remove...). Collect results with a parallel `map` or `filter` instead, or write into preallocated slots at the loop's own index."
	),
	NamedError(
		name = "YieldOutsideGenerator",
		text = "yield is in the body of a generator, a function whose result is a Seq<T> (not in a lambda)",
		explain = "`yield` gives the next element of a generator, a function whose result type is `Seq<T>`, and it is used in a function with another result type or in a lambda. Declare the function's result as `Seq<T>`, or build and return a list with `push`.",
		example = """
			fn f() i64:
				yield 1
				2
			print(f())
			"""
	),
	NamedError(
		name = "GeneratorType",
		text = "the generator gives $1, not $2",
		explain = "Each `yield` gives an element of the generator's `Seq<T>`, so its value must be a `T`, and this one has another type. Yield a value of the declared element type, converting it if needed, or change the `Seq<T>` in the signature.",
		example = """
			fn names() Seq<str>:
				yield 1

			for n in names():
				print(n)
			"""
	),
	NamedError(
		name = "LambdaMissingValue",
		text = "missing return value (the lambda returns $1)",
		explain = "The lambda's result type is inferred from its returns, and an earlier `return` gave a value, so a bare `return` here leaves the result undefined. Return a value of the same type on every path.",
		example = """
			f = (x i64):
				if x > 0:
					return x
				return

			print(f(1))
			"""
	),
	NamedError(
		name = "LambdaReturnsDiffer",
		text = "lambda returns $1 here but $2 earlier",
		explain = "A lambda without a declared result type takes its type from its first `return`, and this `return` gives a value of another type. Make every return give the same type, or give the lambda an expected `fn(...) R` type so the values are checked against it.",
		example = """
			f = (x i64):
				if x > 0:
					return x
				return "negative"

			print(f(1))
			"""
	),
	NamedError(
		name = "ResultsDiffer",
		text = "'$1' returns $2 here but $3 earlier: write its result",
		explain = "A function that is not `pub` and writes no result has the type its `return`s and trailing expression give, and they give one type: a value is never widened to meet another, as it would be to meet a written result. Write the result (`fn f(x i64) i64:`) to have every value checked against it."
	),
	NamedError(
		name = "ResultUntold",
		text = "'$1' returns only values whose type their place tells (none, an empty list or map): write its result",
		explain = "A function that writes no result takes the type its `return`s give, and `none`, an empty list or map, or a choice of one (`none if c else x`) has the type of the place it goes to: with no other return to give that type, the result is not known. Write it (`fn find(xs i64[]) i64?:`)."
	),
	NamedError(
		name = "ResultRecursive",
		text = "'$1' calls itself, directly or through other functions, and gives $2: write its result",
		explain = "The result of a function that writes none is found by checking its body, and a call of the function inside that body (or inside a function it calls) needs the result before it is found. A recursive function that gives a value writes its result: `fn depth(n Node) i64:`."
	),
	NamedError(
		name = "ResultWidened",
		text = "'$1' gives an integer widened to f64: write its result",
		explain = "A function that writes no result takes the type of what it returns, and an integer widened to f64 there (`a * 1.5` of an i64 `a`) would make it, and every caller that uses it, a float one, which is more often a typo than a choice. Write `f64` as the result when a float is meant, or keep the arithmetic in integers."
	),
	NamedError(
		name = "ResultReference",
		text = "'$1' gives $2, which points into what it was given: write its result",
		explain = "A function that writes no result gives a value (a reference it returns is copied out, as for a written result), but an optional reference cannot be told apart from an optional value without the result written. Write the result type the callers should see."
	),
	NamedError(
		name = "GenericResult",
		text = "the generic '$1' gives $2: write its result",
		explain = "A generic function or a method of a generic type is checked once for every type, and its result, when it gives one, is written in terms of its type parameters: `fn first<T>(xs T[]) T:`. Only the plain functions that are not `pub` have their result found from the body."
	),
	NamedError(
		name = "MissingValue",
		text = "missing return value (function returns $1)",
		explain = "A bare `return` gives no value, but the function declares a result type that needs one. Return a value of that type, `return 0`, or change the result to an optional and `return none`.",
		example = """
			fn half(n i64) i64:
				if n < 0:
					return
				n / 2

			print(half(4))
			"""
	),
	NamedError(
		name = "GeneratorReturn",
		text = "a generator gives its values by yield: a bare return ends it",
		explain = "A generator gives its elements with `yield`, and `return` only ends it, so a `return` with a value has nowhere for the value to go. Write `yield v` to give the value, then a bare `return` if the generator should stop there."
	),
	NamedError(
		name = "ReturnType",
		text = "return must be $1 or $2, got $3",
		explain = "A function returning `T ? E` accepts a `T` (the value), an `E` (the error) or the whole result passed through, and one returning `T?` accepts a `T`, `none` or the optional; this value is none of them. Return the value type or the error, converting as needed.",
		example = """
			type Oops:
				Odd

			fn half(n i64) i64 ? Oops:
				return "odd"

			print(half(3) ?? 0)
			"""
	),
	NamedError(
		name = "NoValueExpected",
		text = "function returns no value but got $1",
		explain = "The function declares no result type, so it gives no value, but this `return` carries one. Remove the value from the `return`, or declare the result type in the signature.",
		example = r"""
			fn greet(name str):
				print("hi {name}")
				return 1

			greet("ann")
			"""
	),
	NamedError(
		name = "ReturnMismatch",
		text = "return type mismatch: expected $1, got $2$3",
		explain = "The value returned (or the body's last expression) does not have the function's declared result type, and no implicit conversion exists. Convert the value, or change the declared result type."
	),
	NamedError(
		name = "OpenRange",
		text = "a range without an end is a slice's alone (xs[lo..])",
		explain = "A range without an end, `lo..`, means up to the end only in a slice, where the indexed list supplies the end; a loop has no end to take. Give it an end, `lo..hi`, or slice with `xs[lo..]`.",
		example = """
			for i in 0.. step 2:
				print(i)
			"""
	),
	NamedError(
		name = "RangeNotInteger",
		text = "range bounds must be integers, found $1",
		explain = "A range counts by integers, so its bounds must be integers, and this one is not (a float, for example). Loop over integers and compute the other value in the body, such as `f64(i) * 0.1`.",
		example = """
			for x in 0.0..1.0:
				print(x)
			"""
	),
	NamedError(
		name = "RangeBoundsDiffer",
		text = "range bounds must share a type: $1 vs $2",
		explain = "A range's bounds share one integer type, and these two differ, for example an `i32` and an `i64`. Convert one bound so both match, `i64(a)..b`.",
		example = """
			a i32 = 0
			b i64 = 5
			for i in a..b:
				print(i)
			"""
	),
	NamedError(
		name = "RangeStepType",
		text = "the step of a range has the type of its bounds: $1, found $2",
		explain = "The step of a range is added to the counter, so it has the bounds' integer type, and this step has another type. Write an integer step of the bounds' type, or convert it.",
		example = """
			for i in 0..10 step 0.5:
				print(i)
			"""
	),
	NamedError(
		name = "RangeStepZero",
		text = "a range step is never 0 (a negative literal counts down: n..0 step -1)",
		explain = "A range step of 0 would never advance, so the loop would never end. Use a positive step to count up or a negative literal to count down, `n..0 step -1`.",
		example = """
			for i in 0..3 step 0:
				print(i)
			"""
	),
	NamedError(
		name = "ForNeedsPlace",
		text = "for over $1 needs a variable (or a field or an element of one): bind it to a name first",
		explain = "A `for` over a fixed array or a string is compiled as a loop by index that names the collection on each turn, so the collection must be a variable, or a field or an element of one at an index the loop does not change (`for c in cols[r]:`), not a literal or a call's result. Bind it to a name first, `s = \"hello\"` then `for b in s:`.",
		example = """
			for b in "hello":
				print(b)
			"""
	),
	NamedError(
		name = "SplitSeparator",
		text = "split needs a str separator, found $1",
		explain = "In `for part in text.split(sep)`, the separator is the text between parts, so it must be a `str`. Pass the separator as a string, `text.split(\",\")`.",
		example = """
			text = "a,b"
			for part in text.split(1):
				print(part)
			"""
	),
	NamedError(
		name = "LinesNeedsStr",
		text = "lines needs a str, found $1",
		explain = "`for line in x.lines()` walks a string's lines in place, and the receiver here is not a `str`. Call `lines()` on a string, converting the value or reading the text first.",
		example = """
			n = 5
			for line in n.lines():
				print(line)
			"""
	),
	NamedError(
		name = "ForNotIterable",
		text = "for needs a list, a range (lo..hi) or a Seq, found $1",
		explain = "A `for` walks a list, a range `lo..hi`, a generator's `Seq`, a string, a fixed array, a table, a grid or a map, and this value is none of them. Loop over a range such as `0..n` for a count, or over the collection the value holds.",
		example = """
			n = 5
			for x in n:
				print(x)
			"""
	),
	NamedError(
		name = "IndexAssignNotSupported",
		text = "only elements of a list, a T[N], a map, a pool or a struct of one number type can be assigned by index, found $1",
		explain = "An assignment `v[i] = x` was written on a value that has no indexed slots. Only lists, fixed arrays `T[N]`, maps, pools (and types with a `set` method) or a struct whose fields all share one number type can be written by index; a struct with mixed fields or other values cannot. Assign the field by name (`p.id = 2`) or keep the values in a list.",
		example = """
			type Named:
				id i64
				name str
			mut n = Named(1, "a")
			n[0] = 2
			"""
	),
	NamedError(
		name = "AssignThroughReadRef",
		text = "cannot assign through a read reference (take it with mut ref)",
		explain = "The assignment changes something reached through a read reference (`ref T`), which only lends the value for reading. Changing the owner's data through it would break the guarantee that a shared borrow sees a value that does not change under it. Take the reference as `mut ref T` (or a `mut` parameter) where the change is meant.",
		example = """
			type Counter:
				n i64
			type Holder:
				c ref Counter
			fn reset(mut h Holder):
				h.c.n = 0
			"""
	),
	NamedError(
		name = "AssignThroughShared",
		text = "cannot assign through a shared value: it changes only through its own methods",
		explain = "The assignment writes into a value of a shared type (a runtime type such as Channel or Atomic, which several threads hold at once). Such a value has no fields to assign: every change goes through its own methods, which do the locking or atomic work. Call the type's method instead of assigning."
	),
	NamedError(
		name = "AssignConstant",
		text = "cannot assign to constant '$1' (declare it 'mut' at the top level to make it a module variable)",
		explain = "The code changes a field or element of a name declared at the top level without `mut`, which makes it a constant of the module. Constants never change after their one assignment, so no function may write into them (a plain `limit = 20` inside a function would instead make a new local). Declare it `mut origin = ...` at the top level to make it a module variable, or work on a local copy.",
		example = """
			type Point:
				x i64
				y i64
			origin = Point(0, 0)
			fn shift():
				origin.x = 5
			shift()
			print(origin.x)
			"""
	),
	NamedError(
		name = "AssignThroughImmutable",
		text = "cannot assign through immutable '$1' (declare it 'mut')",
		explain = "The assignment changes a variable (or a field or element of it) that was bound without `mut`. Bindings are immutable unless declared otherwise, so the compiler can rely on their value never changing. Declare the variable as `mut p = ...`, or a parameter as `mut p T`.",
		example = """
			type Point:
				x i64
				y i64
			p = Point(1, 2)
			p.x = 3
			"""
	),
	NamedError(
		name = "AssignTypeMismatch",
		text = "cannot assign $1 to $2$3",
		explain = "A value is assigned into a field, element or other place whose type cannot hold it, even after the usual widening of numbers (a plain variable gets the assign-type error instead). Fields and elements keep their declared type and nothing is converted implicitly. Convert the value explicitly (`i64(x)`, `\"\{n\}\"`), or change the field's type.",
		example = """
			type Point:
				x i64
				y i64
			mut p = Point(1, 2)
			p.x = "three"
			print(p.x)
			"""
	),
	NamedError(
		name = "ResultIgnored",
		text = "a result is handled (v = f() ?? ..., a match) or dropped knowingly (_ = f())",
		explain = "A call that returns a result (`T ? E`) is used as a statement, so its possible error would be silently lost. Zap makes every failure be handled or dropped on purpose. Handle it with `try f()`, `v = f() ?? fallback` or a `match`, or write `_ = f()` to drop it knowingly."
	),
	NamedError(
		name = "CopyIgnored",
		text = "this makes a new $1 and changes nothing, and the value is not used (xs.sortedBy(f) is a sorted copy: xs = xs.sortedBy(f))",
		explain = "The statement computes a new value (an operator, or a method like `sortedBy` that returns a changed copy) and throws it away, so it has no effect. This usually means the copying method was taken for one that changes in place. Assign the result, as in `xs = xs.sortedBy(f)`, or call the in-place method."
	),
	NamedError(
		name = "ConditionNotBool",
		text = "$1 condition must be bool, found $2",
		explain = "The condition of an `if` or `while` is not a bool. Zap has no truthiness: numbers, strings, lists and optionals are not taken as true or false. Write the comparison you mean, such as `if n > 0:`, `if not xs.isEmpty:` or `if x is v:` for an optional.",
		example = """
			n = 3
			if n:
				print(n)
			"""
	),
	NamedError(
		name = "BreakOutsideLoop",
		text = "'break' outside of a loop",
		explain = "A `break` stands where no loop of the same function encloses it (a loop around a call or a lambda does not count). There is nothing for it to leave. Move it inside a `for`, `while` or `loop`, or use `return` to leave the function."
	),
	NamedError(
		name = "ContinueOutsideLoop",
		text = "'continue' outside of a loop",
		explain = "A `continue` stands where no loop of the same function encloses it, so there is no next turn to go to. Loops around a call or a lambda do not count. Move it inside a `for`, `while` or `loop`, or use `return` to leave the function early.",
		example = """
			x = 1
			if x > 0:
				continue
			"""
	),
	NamedError(
		name = "ChangedCopyLost",
		text = "'$1' is a copy of $2, and nothing reads it after it is changed: the changes are lost. To change $2 itself: `$1 = mut ref $2`, or write it back (`$2 = $1`)",
		explain = "A `mut` local was made from a list element or a field of plain data, which copies it, and the following code only changes that copy without ever reading it. The changes would vanish with the local, which is almost always a mistake about copy versus reference. Bind it with `mut ref` to change the element itself, or write the copy back afterwards."
	),
	NamedError(
		name = "ExternTypeGeneric",
		text = "an extern type cannot be generic",
		explain = "An `extern type` was declared with type parameters. An extern type mirrors a C struct whose layout must be fixed and known to the system it is passed to, and C has no generic structs. Declare one concrete extern type per layout. It is reported by the check of extern types' fields; a short program declaring one does not currently reach that check."
	),
	NamedError(
		name = "ExternFieldType",
		text = "field '$1' of extern type $2: a C field is a number, a bool, an extern type, an array of those, or a reference to one, to a str or to a list of them (found $3)",
		explain = "A field of an `extern type` has a type C cannot hold in a struct, such as a list, a map, a str or an ordinary Zap struct owned by value. An extern type is laid out exactly as C would lay it out, so it holds only numbers, bools, other extern types, fixed arrays of those, or references (C pointers) to such values, a str's bytes or a list's elements. Use one of those types, for example a `ref str`."
	),
	NamedError(
		name = "SharedTypeOfRuntime",
		text = "a shared type belongs to the runtime (Channel, Atomic): to name one value from many places, keep it in a Pool and hold its Handle",
		explain = "A program declared a `shared type`, a type whose values have many owners. Only the runtime defines these (Channel, Atomic), because each needs carefully written thread-safe code. To refer to one value from many places, keep it in a `Pool` and pass its `Handle` around."
	),
	NamedError(
		name = "TypeContainsItself",
		text = "type '$1' contains itself by value and would be infinitely large (hold the nested value in a list or a map)",
		explain = "A type holds a value of its own type directly (or through other types held by value), so its size would be infinite. Lists, maps and functions are references and break the cycle, while optionals and results do not. Hold the nested value in a list (`children Node[]`) or a map, or refer to it by a Pool Handle."
	),
	NamedError(
		name = "LiteralOnlyFunction",
		text = "$1 only writes $2's literal: write $2(...) where it is called, its constants as the fields' defaults",
		explain = "The function's whole body only builds a struct literal from constants and its own parameters, so it adds a name without adding behavior. Zap prefers the type's constructor at the call site, with the constants moved into the fields' defaults. Delete the function, give the fields defaults, and call `T(...)` where it was called."
	),
	NamedError(
		name = "ReadBeforeAssigned",
		text = "'$1' is read before line $2 assigns it (a top-level binding is assigned where it stands)",
		explain = "A top-level binding is read (directly or by a function called) before the line that assigns it has run. Top-level statements run in order, so the value does not exist yet at that point. Move the binding above its first use, or pass the value as a parameter."
	),
	NamedError(
		name = "InitCycle",
		text = "the value of '$1' is computed from itself: its initializer reads, directly or through the functions it calls, a module variable whose initializer reads '$1' back",
		explain = "Module variables get their values before the program runs, each after the ones its initializer reads, whichever file of the module holds them. Two whose initializers read each other have no order. Give one of them a value that does not depend on the other."
	),
	NamedError(
		name = "OutParameterOutsideExtern",
		text = "out parameter '$1': out is for an extern fn (a function of the program returns its values, several as a tuple)",
		explain = "An ordinary function declared an `out` parameter. `out` exists only for extern functions, to receive what a C function writes through a pointer. A Zap function returns its values instead, several at once as a tuple: `fn count() (i64, bool)` and `(n, ok) = count()`."
	),
	NamedError(
		name = "MutParameterType",
		text = "mut parameter '$1' must be a struct, a fixed array, a list or a map (for a $2, return the new value instead)",
		explain = "A `mut` parameter has a plain value type such as a number, bool or str. A `mut` parameter lends the caller's place for in-place change, which the language allows only for a struct, fixed array, list or map. For a plain value, return the new value and let the caller assign it: `x = inc(x)`."
	),
	NamedError(
		name = "GenericGenerator",
		text = "a generator has no type parameters (it is inlined into each loop that walks it): write it for one element type",
		explain = "A generator (a function returning `Seq<T>` whose body yields) was declared with type parameters. A generator is inlined into each loop that walks it rather than compiled as a function, so it is not instantiated per type. Write it for one concrete element type, or a separate generator for each type you need.",
		example = """
			fn same<T>(x T) Seq<T>:
				yield x
			for v in same(1):
				print(v)
			"""
	),
	NamedError(
		name = "MissingBody",
		text = "'$1' has no body (only an extern fn is declared without one)",
		explain = "A function was declared without a body, ending at its signature. Only an `extern fn`, which names a function provided by the system, is declared that way. Add the indented body after a `:`, or mark it `extern fn` if it is a C function.",
		example = """
			fn f() i64

			print(f())
			"""
	),
	NamedError(
		name = "ExternWithBody",
		text = "extern fn '$1' cannot have a body",
		explain = "An `extern fn` was given a body. An extern function names code that lives outside the program (a C or system function), so its declaration is the signature alone. Remove the body, or drop `extern` if you meant an ordinary Zap function.",
		example = """
			extern fn GetTickCount() u32:
				0
			"""
	),
	NamedError(
		name = "ExternGeneric",
		text = "extern fn '$1' cannot be generic",
		explain = "An `extern fn` was declared with type parameters. A C function has one fixed signature, so the compiler cannot make copies of it per type. Declare one extern per concrete signature.",
		example = """
			extern fn Identity<T>(x T) T
			print(Identity(1))
			"""
	),
	NamedError(
		name = "ExternOutParameter",
		text = "extern fn '$1': out parameter '$2' must be an integer or a float (found $3)",
		explain = "An `out` parameter of an extern function has a type other than an integer or a float. The compiler gives the C function the address of a plain numeric slot to write into, and cannot do that for a str, list or struct. Use an integer or float out parameter, or pass a buffer (a `u8[]` or a `mut` struct) as an ordinary parameter.",
		example = """
			extern fn GetUserNameA(out name str, out size u32) bool
			"""
	),
	NamedError(
		name = "ExternParameter",
		text = "extern fn '$1': parameter '$2' must be an integer, a bool, an f32, an f64, a str, a list, a struct or a function over plain words (found $3)",
		explain = "A parameter of an extern function has a type that cannot cross into C, such as a map, an optional or a capturing lambda. Only machine words (integers, bools, floats), strs and lists (passed as pointers), structs (passed by address) and plain top-level functions as callbacks can be passed. Convert the value to one of those before the call."
	),
	NamedError(
		name = "ExternPlainStruct",
		text = "extern fn '$1': parameter '$2' holds $3, a plain struct whose fields may be reordered: declare it `extern type`",
		explain = "A struct, or a list of structs, crosses into an extern function as its bytes, which C reads in the order it declares the fields. A plain struct's fields are laid out widest alignment first, so C would read them at the wrong offsets; an `extern type` keeps its fields in order, as C lays them out. Declare the struct `extern type`."
	),
	NamedError(
		name = "ExternResult",
		text = "extern fn '$1' must return an integer, a bool, an f32, an f64 or nothing (found $2)",
		explain = "An extern function declares a result type C cannot return in a register, such as a str, list or struct. A C function's result comes back as one machine word, so only an integer, a bool, an f32, an f64 or nothing is accepted. Return an integer (a pointer or handle) and read the data from it, or receive it through a buffer parameter.",
		example = """
			extern fn GetCommandLineA() str
			"""
	),
	NamedError(
		name = "AlreadyDeclaredInModule",
		text = "'$1' is already declared in this module ($2)",
		explain = "Two top-level declarations of the same kind (two functions, or two types) share one name in the same module, possibly in different files of it. Zap has no overloading by parameter types, so a use of the name could not tell them apart. Rename one of them, or merge them into a single function with a default parameter.",
		example = """
			fn area(w i64) i64:
				w * w
			fn area(w i64, h i64) i64:
				w * h
			print(area(2))
			"""
	),
	NamedError(
		name = "TypeRepeatsModule",
		text = "'$1' repeats its module's name, read as $2.$1: name it $3",
		explain = "A public type's name begins with its module's name, so every use outside reads the module twice (`json.Node`). A type is read with its module, `m.T`: name it by what it is in that module (`json.Node`). A type named the same as its module (`image.Image`) stays."
	),
	NamedError(
		name = "BoolNameSpelling",
		text = "'$1' gives a bool: its name says what holds (is, has or can and a word, or a verb such as contains)",
		explain = "A public function that gives a bool and changes nothing is a question about its arguments, and its name reads as one: `isDone`, `hasAlpha`, `canWrite`, or a verb of the third person (`contains`, `startsWith`). A function that changes something or acts and tells with a bool how it went is named by what it does."
	),
	NamedError(
		name = "GetterMethod",
		text = "'$1' only reads the field '$2': read the field, named for what it is",
		explain = "A method that takes nothing and gives one of its value's fields is the field under another name. What is looked up is a field: rename the field to what it is and read it (`img.width`), dropping the method."
	),
	NamedError(
		name = "RefusedWord",
		text = "'$1' holds a word the names do not use ($2)",
		explain = "One word for each idea, everywhere: a directory is a `dir` (never a folder), and the count of a value's elements is its `len`, read as a field. Rename the declaration with the word the language uses, or with one for what it measures."
	),
	NamedError(
		name = "UnderscoreInName",
		text = "'$1' has '_': names are camelCase (functions, bindings) or PascalCase (types), and the compiler makes its own names with '_'",
		explain = "A declared name contains an underscore. Zap names are camelCase for functions and bindings and PascalCase for types, and the compiler reserves `_` for the names it generates itself, so a user name with `_` could collide with them. Rename it, as in `maxSpeed` instead of `max_speed`."
	),
	NamedError(
		name = "FieldOfReferences",
		text = "the field '$1' cannot be a $2: a list or map of references lives in a variable, where the compiler follows what it borrows",
		explain = "A struct field was declared as a list or map of references (such as `List<ref T>`). The compiler tracks what such a collection borrows only while it lives in a local variable, not when it is stored in a struct. Keep the list of references in a local, or store the values themselves or Pool Handles in the field."
	),
	NamedError(
		name = "UnknownSelfType",
		text = "self is of an unknown type '$1'",
		explain = "A method's `self` parameter names a type that is not declared in reach. Methods are attached to the type of `self`, so the compiler has nothing to attach this one to. Fix the type's name, import it, or declare the type.",
		example = """
			fn area(self Rectangel) i64:
				0
			print(1)
			"""
	),
	NamedError(
		name = "LentAndChanged",
		text = "'$1' is lent to this call, which changes '$2': read what the call needs from it into a value first, or pass a value of its own (.copy())",
		explain = "A value is lent to a call (passed for reading), and the same call also changes it through another path, such as a `mut` argument or a module variable. Reading and changing the same data in one call would let the borrowed view see the change midway. Read what the call needs into a value of its own first, or pass `x.copy()`."
	),
	NamedError(
		name = "ShaderStages",
		text = "shader takes a program's stages: shader(module.vertex, module.pixel), or shader(module.pixel) for a pass over a whole target",
		explain = "The `shader(...)` call was given no stages or more than two. A shader is built from a vertex and a pixel stage, `shader(module.vertex, module.pixel)`, or from a pixel stage alone, `shader(module.pixel)`, for a pass over a whole target. Pass one or two GPU functions.",
		example = """
			print(shader().len)
			"""
	),
	NamedError(
		name = "ShaderModule",
		text = "shader: no module '$1' is imported here",
		explain = "A stage given to `shader` is written `alias.function`, but no module imported by this file has that alias. The stages must be functions of a module the file imports (or of its own module). Add the `import` of that module, or fix its name.",
		example = """
			print(shader(nowhere.pixel).len)
			"""
	),
	NamedError(
		name = "ShaderTakesFunctions",
		text = "shader takes functions: shader(module.vertex, module.pixel)",
		explain = "An argument of `shader(...)` is not the name of a function but a string, a call or another expression. The stages are named statically so the compiler can translate them to GPU code at build time. Pass the functions themselves, as `shader(module.vertex, module.pixel)`.",
		example = """
			print(shader("pixel").len)
			"""
	),
	NamedError(
		name = "ShaderNoFunction",
		text = "shader: no fn $1 in a GPU file (.gpu.zap) of $2",
		explain = "A stage given to `shader` names a function that does not exist in any GPU file (`.gpu.zap`) of that module. Only functions in GPU files are compiled for the GPU, so an ordinary CPU function cannot be a stage. Fix the name, or move the function into a `.gpu.zap` file of the module.",
		example = """
			print(shader(missing).len)
			"""
	),
	NamedError(
		name = "GpuMethod",
		text = "a GPU file (.gpu.zap) holds types, constants and functions: a function taking self is a method, the CPU's",
		explain = "A GPU file (`.gpu.zap`) declares a method, a function taking `self`. GPU files hold only types, constants and free functions; methods belong to the CPU's code. Write it as a plain function that takes the value as an ordinary parameter, `fn scaled(l Light) f32`. It arises only in a GPU file (.gpu.zap) of a module whose functions a shader(...) call compiles, so it cannot be shown in a one-file program."
	),
	NamedError(
		name = "TextureRead",
		text = "a $1 has no such read: a texture reads by sample, sampleLevel, sampleBias, sampleGrad, gather, lod or size, a shadow map by compare, gatherCompare or size",
		explain = "A texture was read with a method it does not have, or a shadow map with a texture's method. A texture reads by `sample(uv)`, `sampleLevel(uv, lod)`, `sampleBias(uv, bias)`, `sampleGrad(uv, dx, dy)`, `gather(uv, component)`, `lod(uv)` or `size()`; a shadow map by `compare(uv, depth)`, `gatherCompare(uv, depth)` or `size()`; an array texture takes the layer after `uv` (spec 11). Call one of those methods. It arises only in a GPU file (.gpu.zap) of a module whose functions a shader(...) call compiles, so it cannot be shown in a one-file program."
	),
	NamedError(
		name = "TextureConstant",
		text = "$1's $2 is a constant: gather's component a literal 0 to 3, an offset IVec2(x, y) of literals -8 to 7",
		explain = "A texture read's gather component or texel offset is not a constant the compiler can read. The GPU takes both as constants of the instruction: the component a literal from 0 to 3 (x to w), the offset `IVec2(x, y)` of integer literals from -8 to 7, the range both Vulkan and Direct3D guarantee. Write them as literals. It arises only in a GPU file (.gpu.zap) of a module whose functions a shader(...) call compiles, so it cannot be shown in a one-file program."
	),
	NamedError(
		name = "GpuRangeConversion",
		text = "a shader cannot stop the program: $1(x) needs x proven inside the range",
		explain = "A range type's conversion, `Percent(x)`, stops the program when the value lies outside the range, and a shader cannot stop. In GPU code the value must be proven inside instead, by a check just made (`if x >= 0 and x <= 100: p Percent = x`) or a range that lies inside, where no conversion is written; or clamp it first. It arises only in a GPU file (.gpu.zap) of a module whose functions a shader(...) call compiles, so it cannot be shown in a one-file program."
	),
	NamedError(
		name = "GpuArgumentType",
		text = "$1 takes a $2 here, got $3",
		explain = "An argument to a texture method has the wrong type, for example a float where a `Vec2` coordinate is expected. Texture reads take fixed GPU types (a `Vec2` uv, an `f32` lod, depth or layer, an `i32` level). Pass a value of the type named in the message, converting with `Vec2(...)` or `f32(...)` if needed. It arises only in a GPU file (.gpu.zap) of a module whose functions a shader(...) call compiles, so it cannot be shown in a one-file program."
	),
	NamedError(
		name = "GpuArrayLength",
		text = "an array's length is a number above 0",
		explain = "A fixed array type in GPU code has a length of 0 or less. A GPU array must have a positive length known when compiling. Give it a length of at least 1, as in `f32[4]`. It arises only in a GPU file (.gpu.zap) of a module whose functions a shader(...) call compiles, so it cannot be shown in a one-file program."
	),
	NamedError(
		name = "GpuArrayOfArrays",
		text = "an array of arrays",
		explain = "GPU code uses an array whose elements are arrays (`f32[4, 4]`). The shader translation supports only one dimension of arrays. Flatten it to one array (`f32[16]` indexed `y * 4 + x`), or use a matrix or a struct holding the inner array. It arises only in a GPU file (.gpu.zap) of a module whose functions a shader(...) call compiles, so it cannot be shown in a one-file program."
	),
	NamedError(
		name = "GpuType",
		text = "a GPU's types are numbers, vectors, matrices, textures, structs, enums, arrays, lists and tuples",
		explain = "A type written in GPU code is not one the GPU has, such as an optional, a reference, a map or a function type. GPU code works only with numbers, vectors, matrices, textures, structs, enums, arrays, lists and tuples. Use one of those, for example a bool flag beside a value instead of an optional. It arises only in a GPU file (.gpu.zap) of a module whose functions a shader(...) call compiles, so it cannot be shown in a one-file program."
	),
	NamedError(
		name = "GpuDoubleFunction",
		text = "'$1' has no f64 form on the GPU: an f64 there takes + - * /, comparisons, conversions, abs, sign, min, max, clamp, mulAdd, lowWord and highWord",
		explain = "GPU code called a function of an f64 that the GPUs' doubles lack: Vulkan's have no sine or exponential, Direct3D's no square root or floor either, so an f64 on the GPU does what both have. Compute the rest in f32 (`f32(x).sqrt()`), or build it from what an f64 has. Its bits are two words: `f64.fromWords(low, high)` and `x.lowWord()`, `x.highWord()` (the GPU's integers are 32-bit, so `fromBits` and `toBits` of an f64 are not its). It arises only in a GPU file (.gpu.zap) of a module whose functions a shader(...) or compute(...) call compiles, so it cannot be shown in a one-file program."
	),
	NamedError(
		name = "GpuDoubleStored",
		text = "an f64 is a value of the GPU's code, not of a struct: parameters, buffers and a stage's inputs and outputs hold its two words (u32)",
		explain = "A struct the GPU code uses has an f64 field (or a list or array of them). A struct is how the program's parameters, storage buffers and a stage's inputs and outputs are laid out, and their f64s would need a layout of their own on each API; on the GPU an f64 lives in locals, arguments and results. Store its two words instead (`x.lowWord()`, `x.highWord()`) and make it again with `f64.fromWords(low, high)`. It arises only in a GPU file (.gpu.zap) of a module whose functions a shader(...) or compute(...) call compiles, so it cannot be shown in a one-file program."
	),
	NamedError(
		name = "GpuTupleOfArray",
		text = "a tuple of an array",
		explain = "A tuple type in GPU code has an array as one of its parts. Tuples become small GPU structs, which cannot carry arrays here. Pass the array separately, or wrap it in a named struct. It arises only in a GPU file (.gpu.zap) of a module whose functions a shader(...) call compiles, so it cannot be shown in a one-file program."
	),
	NamedError(
		name = "GpuListOfArrays",
		text = "a list of arrays",
		explain = "GPU code declares a list whose elements are arrays (a list of `f32[4]`). A list becomes a GPU buffer of one element type, and a buffer of arrays is not supported. Make the element a struct holding the array, or flatten it into a list of numbers. It arises only in a GPU file (.gpu.zap) of a module whose functions a shader(...) call compiles, so it cannot be shown in a one-file program."
	),
	NamedError(
		name = "GpuVariantWithValues",
		text = "a variant with values is not a GPU's: $1.$2",
		explain = "An enum used in GPU code has a variant carrying values (`Circle(radius f32)`). On the GPU an enum is just an integer, so its variants cannot hold data. Keep only plain variants in GPU enums and put the values in a struct beside the enum. It arises only in a GPU file (.gpu.zap) of a module whose functions a shader(...) call compiles, so it cannot be shown in a one-file program."
	),
	NamedError(
		name = "GpuReadOnly",
		text = "'$1' is read only on the GPU: a stage writes its locals, a compute stage its group's memory and its storage buffers",
		explain = "GPU code assigned to something it only reads: a parameter of the program (the parameter block, a texture), a constant, or a value the GPU gives. A stage changes its own locals; a compute stage also writes its group's memory (a `mut` variable of a GPU file) and the elements of its storage buffers (`p.out[i] = v`). Compute the value into a local instead. It arises only in a GPU file (.gpu.zap) of a module whose functions a shader(...) or compute(...) call compiles, so it cannot be shown in a one-file program."
	),
	NamedError(
		name = "GpuMutParameter",
		text = "a GPU function's parameter '$1' is not mut: a function gives back what it changes",
		explain = "A function the GPU runs takes a `mut` parameter. GPU functions take their arguments as values (the GPU's functions copy them in), so a change could not reach the caller. Return the changed value instead (a tuple for several), and assign it where the function is called. It arises only in code a shader(...) or compute(...) call compiles, so it cannot be shown in a one-file program."
	),
	NamedError(
		name = "GpuStageOnly",
		text = "$1 belongs to a $2 stage, and this code runs in a $3 stage",
		explain = "A value or an operation only one kind of stage has was reached from a stage of another kind: the pixel's position and discard() are a pixel stage's; globalId, localId, groupId, localIndex, lane and laneCount, a GPU file's `mut` variables (a group's memory), barrier() and writes to storage buffers are a compute stage's. Move that code to a function only the right stage calls. It arises only in code a shader(...) or compute(...) call compiles, so it cannot be shown in a one-file program."
	),
	NamedError(
		name = "ComputeStage",
		text = "a compute stage takes its parameters struct (or nothing) and gives nothing: it writes its storage buffers",
		explain = "The function named in compute(...) takes more than one parameter, or gives a result. A compute stage is run by many invocations at once, each of which reads what it needs from the program's parameters (its own place is `globalId`) and writes its results to storage buffers. Declare it as `fn kernel(p Params)` and write `p.out[i] = v`. It arises only in a GPU file (.gpu.zap) given to compute(...), so it cannot be shown in a one-file program."
	),
	NamedError(
		name = "ComputeSize",
		text = "compute(kernel, x[, y[, z]]) runs groups of x * y * z invocations: whole numbers from 1, written as literals, 1024 at most in all",
		explain = "A compute(...) call gives no group size, a size that is not an integer literal of at least 1, more than three, or sizes whose product passes 1024, the most invocations a group may have on every GPU. Write the size of the groups the kernel's code is made for, as `compute(kernels.sum, 64)` or `compute(kernels.blur, 8, 8)`.",
		example = """
			import shaders.kernels

			print(compute(kernels.sum, 64, 32).len)
			"""
	),
	NamedError(
		name = "GpuStatement",
		text = "this statement is not a GPU's: its code has if, while, loop, for over a range, match on an enum, assignments, return, break, continue and discard()",
		explain = "A statement in GPU code is of a kind the GPU translation does not support, such as a nested function, an arena or a `use` line. GPU code has only if, while, loop, for over a range, match on an enum, assignments, return, break, continue and `discard()`. Rewrite it with those forms, moving helpers to top-level GPU functions. It arises only in a GPU file (.gpu.zap) of a module whose functions a shader(...) call compiles, so it cannot be shown in a one-file program."
	),
	NamedError(
		name = "GpuMatch",
		text = "a GPU's match is over an enum's variants: Variant => ..., _ => ...",
		explain = "A `match` in GPU code uses a pattern other than a plain enum variant or `_`, such as a number, a range, or a variant with bindings. On the GPU a match becomes a chain of comparisons against an enum's variants. Match over an enum's variants, or write an `if` chain for numbers. It arises only in a GPU file (.gpu.zap) of a module whose functions a shader(...) call compiles, so it cannot be shown in a one-file program."
	),
	NamedError(
		name = "GpuFor",
		text = "a GPU's for loop counts over a range by 1: for i in a..b",
		explain = "A `for` loop in GPU code goes over something other than a plain range counting by 1, such as a list or a range with a `step`. Shader loops are translated only to a counting loop. Write `for i in a..b` and compute the stepped value inside, or use a `while` loop. It arises only in a GPU file (.gpu.zap) of a module whose functions a shader(...) call compiles, so it cannot be shown in a one-file program."
	),
	NamedError(
		name = "GpuOperator",
		text = "'$1' is not a GPU's operator",
		explain = "GPU code uses an operator the GPU does not have, such as `**` or `??`. Only arithmetic, comparison, logical, bitwise, shift and matrix multiplication operators translate to shader code. Call a function such as `pow(x, 2.0)` or write the multiplication out. It arises only in a GPU file (.gpu.zap) of a module whose functions a shader(...) call compiles, so it cannot be shown in a one-file program."
	),
	NamedError(
		name = "GradTakesFunction",
		text = "grad takes a function: grad(f)",
		explain = "`grad(f)` is the derivative of function f, which the compiler writes: it is given the name of a function, not a value or an expression. Name the function whose derivative is wanted.",
		example = """
			print(grad(2.0))
			"""
	),
	NamedError(
		name = "GradParameter",
		text = "grad of $1 differentiates its first parameter, a $2: it takes a number, a tensor, or a struct or list of those",
		explain = "The gradient grad(f) gives is of f's first parameter, so that parameter's type must have one: a float, a std/tensor Tensor, or a struct or list made of those (plain data carried along). Put the parameters to differentiate first, in a struct when there are several."
	),
	NamedError(
		name = "GradResult",
		text = "grad of $1 differentiates a number or a tensor, not a $2",
		explain = "The function grad differentiates gives the value whose gradient is taken: a float or a Tensor (a loss). Return that value; give anything else to the caller another way."
	),
	NamedError(
		name = "GradUnsupported",
		text = "grad of $1 cannot differentiate $2",
		explain = "The compiler differentiates bindings, assignments, the math operators on numbers and tensors, calls (of functions it differentiates in turn, or with a hand derivative `fGrad`), fields and elements, a tail if or match, and for loops over a list or a range that change values bound before them. Another form on the path from the differentiated parameter to the result is refused where it is written: write it in those forms, or give its function a hand derivative."
	),
	NamedError(
		name = "GpuValue",
		text = "this is not a GPU's value: its code has numbers, bools, names, fields, indexes, calls, operators, c ? a : b, lists and tuples",
		explain = "An expression in GPU code is of a kind the GPU cannot compute, such as a string, a lambda, an interpolation or a map. GPU code has numbers, bools, names, fields, indexes, calls, operators, `c ? a : b`, lists and tuples. Rewrite the value with those, encoding text or choices as numbers or enums. It arises only in a GPU file (.gpu.zap) of a module whose functions a shader(...) call compiles, so it cannot be shown in a one-file program."
	),
	NamedError(
		name = "GpuCall",
		text = "a GPU's call names a function, a type or a method",
		explain = "A call in GPU code calls something other than a named function, type or method, such as an indexed value or the result of another call. Shader code has no function values, so every call must name its target statically. Call the function by name, choosing between functions with an `if`. It arises only in a GPU file (.gpu.zap) of a module whose functions a shader(...) call compiles, so it cannot be shown in a one-file program."
	),
	NamedError(
		name = "GridSliceInList",
		text = "a range among an index's commas slices a Grid: a list's layers are sliced one at a time (rows[a..b])",
		explain = "An index with a range among commas was applied to a list, as `rows[0.., 1]`. That form slices a Grid in two dimensions; a list of lists is sliced one level at a time. Slice the outer list first (`rows[a..b]`), then each row, or store the data in a Grid."
	),
	NamedError(
		name = "GridCellCoordinates",
		text = "a grid's cell is g[x, y]: two coordinates, found $1",
		explain = "A Grid was indexed with a number of coordinates other than two. A grid cell is addressed `g[x, y]`, with one coordinate for the column and one for the row. Pass exactly two coordinates, or index `g.cells[i]` for the flat position.",
		example = """
			g = Grid(2, 2, fill = 0)
			print(g[1, 1, 0])
			"""
	),
	NamedError(
		name = "GridViewSliced",
		text = "a GridView is not sliced again: slice its grid",
		explain = "A GridView (itself a slice of a grid) was sliced again with ranges. A view is a borrowed window and is not sliced further. Slice the original grid with the combined bounds, or take `v.grid()` (a copy) and slice that.",
		example = """
			g = Grid(4, 4, fill = 0)
			v = g[0..2, 0..2]
			print(v[0..1, 0])
			"""
	),
	NamedError(
		name = "GridSliceStep",
		text = "a grid's slice has no step",
		explain = "A range used to slice a Grid has a `step`. A grid view covers a contiguous block of cells, so it cannot skip columns or rows. Slice without a step, and skip cells in the loop that reads the view.",
		example = """
			g = Grid(4, 4, fill = 0)
			print(g[0..4 step 2, 1])
			"""
	),
	NamedError(
		name = "GridSliceNeedsPlace",
		text = "a slice to the grid's edge needs a grid reached without calls: bind the grid first",
		explain = "A grid slice leaves out a range's end (to the edge) on a grid obtained through a call. The compiler fills the end from the grid's width or height, which would mean evaluating the call again, so it needs the grid reachable without calls. Bind the grid to a name first, then slice the name.",
		example = """
			fn make() Grid<i64>:
				Grid(4, 4, fill = 0)
			print(make()[1.., 0])
			"""
	),
	NamedError(
		name = "GridForNotGrid",
		text = "for (x, y), v in g goes over a Grid, found $1",
		explain = "A loop `for (x, y), v in ...` with coordinates goes over something that is not a Grid or GridView. Only grids have two-dimensional coordinates for their cells. Use `for i, v in xs` for a list, or loop over a Grid."
	),
	NamedError(
		name = "GridLiteral",
		text = "a grid is made by Grid(width, height), Grid(width, height, fill = v) or Grid(width, height, cells = xs), which checks their count",
		explain = "A Grid was built by naming its width or height, by a third value without its name, or by fields of its own. A grid is made by calling its type, what it is made from said by a named argument: `Grid(width, height)` (every cell its type's zero), `Grid(width, height, fill = v)`, or `Grid(width, height, cells = xs)` (the list's cells, row after row, their count checked)."
	),
	NamedError(
		name = "GridSizeFixed",
		text = "a grid's $1 is fixed (its cells fill width x height): make a new grid",
		explain = "The code changes a grid's width, height or its cells list as a whole (assigning, pushing). A grid's cells always fill exactly width times height, so these cannot change on their own. Make a new grid of the size you want and copy or paste the cells into it."
	),
	NamedError(
		name = "GridForNeedsPlace",
		text = "for over a grid's cells by their coordinates needs a variable (or a field of one): bind it to a name first",
		explain = "A loop over a grid's cells with their coordinates goes over a grid given by an expression (a call or a constructor) rather than a variable or a field of one. The loop reads the grid's size at each step, which needs a stable place. Bind the grid to a name first, then loop over the name.",
		example = """
			for (x, y), v in Grid(2, 2, fill = 0):
				print(v)
			"""
	),
	NamedError(
		name = "DoubleUnderscore",
		text = "'$1' has '__': the compiler joins a module and a name with it",
		explain = "A name in the source contains `__`. The compiler joins a module and a name with `__` to make global names, so writing one by hand could reach another module's private declarations. Rename it without the double underscore."
	),
	NamedError(
		name = "LiteralTooLarge",
		text = "$1 literal does not fit in 64 bits",
		explain = "A hexadecimal or binary integer literal has more than 64 bits of digits. Zap integers are at most 64 bits wide, so the value cannot be represented. Remove the extra digits, or split the value into several numbers.",
		example = """
			x = 0x1_0000_0000_0000_0000
			print(x)
			"""
	),
	NamedError(
		name = "InvalidLiteral",
		text = "invalid $1 literal",
		explain = "A hexadecimal or binary literal has no digits after its prefix, or a letter or digit not valid in that base runs into it, as in `0b102` or `0xZZ`. Write only digits of the base (0 and 1 for binary, 0 to 9 and a to f for hexadecimal), separated by `_` if wanted.",
		example = """
			print(0b102)
			"""
	),
	NamedError(
		name = "UnterminatedString",
		text = "unterminated string literal",
		explain = "A string literal reached the end of its line (or of the file) without a closing quote. One-line strings cannot span lines. Close the string with `\"`, or use a multi-line string opened with `\"\"\"`.",
		example = """
			print("hello)
			"""
	),
	NamedError(
		name = "InvalidEscape",
		text = "invalid escape '\\$1'",
		explain = "A string has a backslash followed by a character that is not an escape. Strings recognize `\\n`, `\\t`, `\\r`, `\\0`, `\\\\`, `\\\"`, `\\\{` and `\\\}`. Write `\\\\` for a literal backslash, or use a raw string `r\"...\"` for paths and patterns.",
		example = r"""
			print("C:\data\query")
			"""
	),
	NamedError(
		name = "InterpolationTooDeep",
		text = "string interpolation nested too deeply",
		explain = r"String interpolations are nested inside each other more than 64 levels deep (a string inside `{...}` inside a string, and so on). The lexer limits the nesting depth, and no real program needs that much. Build the inner parts into named values first and interpolate those."
	),
	NamedError(
		name = "MultilineStringStart",
		text = "a multi-line string starts on the line after its opening \"\"\"",
		explain = "A multi-line string has text on the same line as its opening `\"\"\"`. The text of such a string starts on the line after the opening quotes, so that its indentation can be measured against the closing quotes. Break the line right after `\"\"\"`, or use an ordinary one-line string.",
		example = "s = \"\"\"hello\n\tworld\n\t\"\"\"\nprint(s)"
	),
	NamedError(
		name = "UnterminatedMultilineString",
		text = "unterminated multi-line string: its closing \"\"\" goes on a line of its own",
		explain = "A multi-line string has no closing `\"\"\"` on a line of its own. The closing quotes must stand alone on their line, and their indentation is taken off every line of the string. Add the closing `\"\"\"` line where the text ends.",
		example = "s = \"\"\"\n\thello\nprint(s)"
	),
	NamedError(
		name = "ByteHexEscape",
		text = "'\\x' needs two hex digits",
		explain = "A byte literal's `\\x` escape is not followed by two hexadecimal digits. A hex escape names one byte with exactly two digits, as `'\\x41'`. Write both digits, padding with a leading 0 if needed (`'\\x0A'`).",
		example = r"""
			b = '\xG1'
			print(b)
			"""
	),
	NamedError(
		name = "ByteEscape",
		text = "unknown escape in a byte literal (\\n \\t \\r \\0 \\\\ \\' \\\" \\xHH)",
		explain = "A byte literal uses an escape that is not one of the known ones. Byte literals accept `\\n`, `\\t`, `\\r`, `\\0`, `\\\\`, `\\'`, `\\\"` and `\\xHH`. Use one of those, or write the byte's number with `\\xHH`.",
		example = r"""
			b = '\q'
			print(b)
			"""
	),
	NamedError(
		name = "EmptyByte",
		text = "empty byte literal",
		explain = "A byte literal `''` has no character between its quotes (or is cut by the end of the line). A byte literal must hold exactly one character. Put the character in, or use `'\\0'` for a zero byte.",
		example = """
			b = ''
			print(b)
			"""
	),
	NamedError(
		name = "ByteNotAscii",
		text = "a byte literal holds one ASCII character (use a string for the rest)",
		explain = "A byte literal holds a character outside ASCII, such as an accented letter. Such characters take several bytes in UTF-8, so they do not fit in one `u8`. Use a string for the character, or its individual bytes with `\\xHH`.",
		example = """
			b = 'é'
			print(b)
			"""
	),
	NamedError(
		name = "ByteUnclosed",
		text = "a byte literal holds one character: close it with '",
		explain = "A byte literal holds more than one character before its closing quote, or the quote is missing. Single quotes make one byte, not a string. Use double quotes for text (`\"ab\"`), or close the byte after one character.",
		example = """
			b = 'ab'
			print(b)
			"""
	),
	NamedError(
		name = "TestSourceIndent",
		text = "the source of a test that refuses or stops is the lines indented after the ':'",
		explain = "A test of the form `test \"...\" refuses Name:` (or `stops Name:`, or such a case in a test's body) has code after the colon on the same line, or no indented lines below it. The program such a test checks is taken as the raw lines indented after the colon. Put the program on the following lines, each indented one tab more than the header.",
		example = """
			test "bad" refuses BreakOutsideLoop: break
			"""
	),
	NamedError(
		name = "FirstLineIndented",
		text = "the first line of a file is not indented",
		explain = "The first line of code in the file is indented (comments before it do not count). Indentation marks a block opened by a line ending in `:`, and nothing opens a block before the first line. Remove the leading tabs or spaces from that line.",
		example = """
			# a note
				x = 1
			print(x)
			"""
	),
	NamedError(
		name = "BlockNotIndented",
		text = "a line ending in ':' opens a block: the next line is indented one tab more",
		explain = "A line ends in `:`, which opens a block, but the next line is not indented further. Every block needs at least one line indented one tab more than its opening line. Indent the block's lines, or write `pass` indented if the block is meant to be empty.",
		example = """
			if true:
			print(1)
			"""
	),
	NamedError(
		name = "SpaceIndent",
		text = "a line is indented with tabs, not spaces",
		explain = "A line is indented with spaces. Zap indents only with tabs, so the depth of each block is unambiguous. Replace the leading spaces with tabs.",
		example = """
			x = 1
			  print(x)
			"""
	),
	NamedError(
		name = "UnexpectedIndent",
		text = "unexpected indentation: only the line after one ending in ':' is indented more",
		explain = "A line is indented deeper than the line before it, though that line does not end in `:`. Only a line ending in `:` opens an indented block (a line starting with `.` may continue a chain). Remove the extra indentation, or end the previous line with `:` if it should open a block.",
		example = """
			x = 1
				print(x)
			"""
	),
	NamedError(
		name = "IndentMismatch",
		text = "the line's indentation matches no open block",
		explain = "A line ends a block but its indentation matches none of the blocks still open, for example it is indented one tab when the open levels are zero and two tabs. The lexer cannot tell which block the line belongs to. Indent it to the same depth as the block it continues.",
		example = """
			if true:
					print(1)
				print(2)
			"""
	),
	NamedError(
		name = "InterpolationCharacter",
		text = r"unexpected character '$1' inside a string interpolation (in a string, '{' starts an interpolation; write \{ for a literal brace)",
		explain = "A character that cannot start any token appeared inside a `\{...\}` of a string, often a backslash-escaped quote or text meant as a literal brace. In a string, `\{` always starts an interpolation of an expression. Write `\\\{` for a literal brace, or use a raw string `r\"...\"` for text like JSON.",
		example = r"""
			print("{\"a\": 1}")
			"""
	),
	NamedError(
		name = "UnexpectedCharacter",
		text = "unexpected character '$1'",
		explain = "The source has a character that starts no token of the language, such as `$`, a backtick or a stray non-ASCII symbol outside a string. Remove it or replace it with the operator you meant; text belongs inside a string."
	),
	NamedError(
		name = "FormatEnd",
		text = "a format ends at the interpolation's closing brace: \"\{x:.2}\"",
		explain = "An interpolation's format (the part after `:` in `\{x:.2\}`) runs into a quote, a newline or another `\{` before its closing `\}`. A format spec ends exactly at the interpolation's closing brace. Close it with `\}`, as in `\"\{x:.2\}\"`.",
		example = r"""
			x = 1.5
			print("{x:.2")
			"""
	),
	NamedError(
		name = "ImportCycle",
		text = "import cycle through module '$1'",
		explain = "Modules import each other in a cycle (a imports b, which imports a, directly or through others). Modules are loaded along their imports, which a cycle makes endless. Move what both need into a third module that both import, or reverse one dependency. It needs two module dirs, so it cannot be shown in one file: a/a.zap with `import b` and b/b.zap with `import a`."
	),
	NamedError(
		name = "ModuleNotFound",
		text = "module '$1' not found (expected a dir '$2$3' with .zap files under the project root or a dir above it, beside the standard library (engine, rhi), or in it)",
		explain = "An `import` names a module the compiler cannot find. It looks for a dir of that name with .zap files under the project root or a dir above it, beside the standard library (the libraries engine and rhi), and in the standard library. Fix the module's name or create the dir.",
		example = """
			import nowhere
			print(nowhere.x)
			"""
	),
	NamedError(
		name = "PartNotFound",
		text = "part '$1' not found (expected the file $2.zap or the dir $2/ beside this file)",
		explain = "A `parts` line names a part that is neither a .zap file nor a dir of .zap files beside the file that names it. Fix the name, or create the file or the dir.",
		example = r"""
			parts nowhere
			print(1)
			"""
	),
	NamedError(
		name = "PartTwice",
		text = "part '$1' is both the dir $2/ and the file $2.zap: keep one",
		explain = "A `parts` line names a part found twice beside the file: as a dir of .zap files and as a .zap file of the same name. A part is one or the other. Move the file into the dir, or rename one of them.",
		example = """
			parts lex
			print(1)
			"""
	),
	NamedError(
		name = "OptionBroken",
		text = "`use $1` is broken$2$3",
		explain = "A scope declared a promise with `use` (such as `noAllocation`, `noLocks` or `noStops`) and the code in it, or a function it calls, breaks that promise. The message names the operation and the chain of calls that leads to it. Remove the operation from the scope (preallocate, prove the bounds, avoid the call), or drop the `use` line."
	),
	NamedError(
		name = "DropSignature",
		text = "a drop function is `fn drop(mut self T)`: no other parameter, no result",
		explain = "A function named `drop` has the wrong shape. A drop function runs when a value of its struct is destroyed, so it must be exactly `fn drop(mut self T)`, with no other parameter and no result. Fix the signature, or rename the function if it is not meant as a destructor."
	),
	NamedError(
		name = "DropGeneric",
		text = "a drop function belongs to a struct without type parameters",
		explain = "A drop function was declared for a generic struct. Drop functions are attached only to structs without type parameters. Move the resource that needs releasing into a non-generic struct with its own drop, and hold that inside the generic one."
	),
	NamedError(
		name = "ChangeAfterMove",
		text = "$1 '$2' after it was moved (moved at line $3)",
		explain = "A variable is changed (assigned into, passed as `mut`, mutated through a lambda) after its value was moved away, for example to a `move` parameter. Its storage is empty, so there is nothing to change in place. Give the variable a whole new value first, change it before the move, or move a `.copy()`. It comes from the ownership pass; in short programs the same mistake is usually reported first as use-after-given, since the change also reads the variable."
	),
	NamedError(
		name = "UseAfterBase",
		text = "'$1' is used here, but ..$1 gave its fields to the struct made at line $2: write ..$1.copy() to keep it, or use it before that",
		explain = "A value used as the base of a struct update (`T(..x, f = v)`) gave its remaining fields to the new struct, and is used afterwards. Those fields were moved, not copied, so the original is incomplete. Write `..x.copy()` to keep `x`, or finish using `x` before the update."
	),
	NamedError(
		name = "UseOfPartGiven",
		text = "'$1' is used as a whole here, but '$2' was given away at line $3: use '$1' before that, or give the part a value again first",
		explain = "A field (or other part) of a variable was given away, and later the variable is used as a whole. Its moved part is empty at that point. Use the variable before giving away the part, assign the part a new value first, or give away a copy of the part."
	),
	NamedError(
		name = "UseAfterCapture",
		text = "'$1' is used here, but the closure made at line $2 took it: use it before the closure, or let the closure take a value of its own",
		explain = "A variable was taken by a closure (moved into it), and the code uses it again after the closure was made. The closure now owns the value. Use the variable before creating the closure, or let the closure capture a copy of its own."
	),
	NamedError(
		name = "UseAfterGiven",
		text = "'$1' is used here, but its value was given away at line $2: use it before that, or give away a value of its own there ($1.copy())",
		explain = "A variable's value was given away, to a `move` parameter or another owner, and the variable is read later. Values move rather than copy, so the variable is empty after the move. Use it before that point, or give away `x.copy()` to keep the original."
	),
	NamedError(
		name = "ChangeWhileCaptured",
		text = "cannot change '$1' while the lambda '$2' captures it (made at line $3, still called at line $4): change it before the lambda is made or after its last call, or change it inside the lambda",
		explain = "A variable is changed while a lambda that captures it is still alive and called later. The lambda borrows the variable, and a change in between would make it see a different value than the one it was made with. Change the variable before the lambda is made or after its last call, or do the change inside the lambda."
	),
	NamedError(
		name = "ChangeWhileLooped",
		text = "cannot change '$1' while the loop at line $2 goes over it: it would go on over what is added (go by index, for i in 0..n, or collect the changes and apply them after the loop)",
		explain = "A list was changed (pushed to, removed from, reassigned), directly or through a function the body calls, while a `for` loop is walking over it. The loop reads the list in place, so growing or shrinking it under the loop would make it visit added elements or step past the end. Loop by index over a fixed count (`for i in 0..n`), or collect the changes in another list and apply them after the loop."
	),
	NamedError(
		name = "ReadWhileLent",
		text = "cannot read '$1' while '$2' changes it (lent to it at line $3, still used at line $4): read it through '$2', or before or after '$2' is used",
		explain = "A place is lent to a name for changing (a `mut ref`, or a for loop's name over a mut place, which changes the element), and the code reads the same place by another way while that name is still used. A change through the name could land between the reads. Read through the name itself, or move the read before the name is made or after its last use."
	),
	NamedError(
		name = "TakenNotGivenBack",
		text = "'$1' was moved out at line $2 and is still empty where the function returns: its owner, the caller's, would hold no value there; give '$1' a value again before returning",
		explain = "A part of a value this function only changes (a mut parameter, the receiver) was moved out with `move`, and a return is reached before the part gets a value again. A map or a box has no empty value, so the caller would find nothing valid there. Assign the part again before every return, or move a copy (`.copy()`)."
	),
	NamedError(
		name = "UseAfterPartGiven",
		text = "'$1' is used here, but '$2' was given away at line $3: use it before that, or give it a value again first",
		explain = "A variable is read whole after one of its parts (a field or an element) was moved out of it earlier, so what remains is incomplete. Zap tracks which parts were given away and refuses any later use that would see the empty slot. Read the variable before the move, move a copy of the part instead (`.copy()`), or assign the part a new value before using the whole again."
	),
	NamedError(
		name = "MoveOfBorrowed",
		text = "'$1' is borrowed, so its value cannot be given away here: take it as a `move` parameter, keep a reference instead, or give a value of its own ($1.copy())",
		explain = "A value that this function only borrows (a plain parameter, a field of self, a loop element lent by the list) is used where an owned value is needed, such as a push, a return or a `move` parameter. Zap never copies a value that owns memory behind your back, and a borrow cannot give away what belongs to its owner. Declare the parameter `move`, keep a reference instead, or pass `x.copy()`."
	),
	NamedError(
		name = "MoveOfPart",
		text = "$1, so it cannot be given away here: give away the owner as a whole, move the value out of it (move x.field), keep a reference instead, or give a value of its own (.copy())",
		explain = "A field or element of something (or the value behind a reference) is used where an owned value is needed, but it belongs to its owner, which stays alive. Giving it away would leave a hole in the owner, and Zap does not copy it silently. Move the whole owner, take the part out explicitly with `move x.field` (leaving the empty value), keep a reference, or pass `.copy()`."
	),
	NamedError(
		name = "FallbackBorrow",
		text = "the value of '??' is a borrow here (copy() it to keep it)",
		explain = "`opt ?? fallback` with a variable or field on the left is used where an owned value is needed (pushed, returned, passed to a `move` parameter). With a place on the left the result only borrows the value the optional holds, so it cannot be given away. Call `.copy()` on the result, or put a fresh value on the left (a call's result) so the `??` owns what it gives.",
		example = """
			nick str? = "ann".repeat(2)
			mut names str[] = []
			names.push(nick ?? "anon")
			print(names.len)
			"""
	),
	NamedError(
		name = "MoveNotOwned",
		text = "cannot move '$1': it is not an owned value",
		explain = "`move x` names a variable this function does not own, such as a plain parameter, which only borrows the caller's value. Only an owned local (or a mut variable, field or element, which keeps the empty value) can be moved out. Declare the parameter `move s` so the function owns it, or pass `s.copy()`.",
		example = """
			fn keep(s str) str[]:
				[move s]
			print(keep("ab".repeat(2)))
			"""
	),
	NamedError(
		name = "TryMovesBorrowed",
		text = r"try would give away the value inside, but $1: match it to borrow the value (match x { v => ..., none => return none }), or move it out (try move x.field)",
		explain = "`try` unwraps an optional or a result that is a field, element or borrowed variable, and unwrapping gives away the value inside, which belongs to the place. Zap does not copy it implicitly. Match on it to borrow the value (`match x: v: ... none: return none`), or take it out with `try move x.field` when the place may be left empty.",
		example = """
			type Pet:
				name str?
			fn shout(p Pet) str?:
				return try p.name
			print(shout(Pet(name = "a".repeat(2))) ?? "")
			"""
	),
	NamedError(
		name = "RefToTemporary",
		text = "'$1' would keep a reference into a temporary that is destroyed before it (a list a loop goes over, a call's result): bind the temporary to a variable first",
		explain = "A reference (a ref element in a map or list, a window) is kept into a temporary that dies before the reference does, typically the list a `for` loop walks over or the result of a call. Keeping it would leave a dangling reference once the temporary is destroyed. Bind the temporary to a variable before the loop so it outlives the references, or store copies of the values."
	),
	NamedError(
		name = "CallerKeepsLocal",
		text = "'$1' belongs to the caller, so it cannot keep a reference into '$2': make the list here and return it",
		explain = "A function was given a list of references owned by the caller and pushes into it a reference to one of its own locals. The local is destroyed when the function returns, but the caller's list would still point at it. Build the list inside the function and return it, or push values (copies) instead of references."
	),
	NamedError(
		name = "RefOutlivesLocal",
		text = "'$1' would keep a reference into '$2', which is destroyed at the end of its block before '$1' is: bind '$2' outside the block, or keep values",
		explain = "A list of references (or a view) declared outside a block, such as a loop's body, is given a reference into a local of that block. The local is destroyed at the block's end (a loop's body ends at every turn) while the list lives on, so the reference would dangle. Declare the local outside the block, or keep the values themselves in a list of values."
	),
	NamedError(
		name = "LentTwice",
		text = "'$1' is lent to this call as mut while '$2' is too: one call cannot change a place through two names",
		explain = "The same place is passed to one call through two `mut` arguments, for example `s.a` as both parameters. A function may assume its two mutable parameters do not overlap, so changing one place through two names is refused. Pass distinct places, or restructure the call so only one argument is mutable and the other is a copy."
	),
	NamedError(
		name = "CapturedChangeLost",
		text = "the lambda changes '$1', which it captures, but it is kept (stored, returned or passed on), so it holds a copy and the change would be lost: call it only by its name in this function, where it borrows what it captures, or return the new value",
		explain = "A lambda changes a variable it captures, but the lambda is stored, returned or passed on, so it holds its own copy of the captured value and the change would never reach the original. Zap refuses rather than silently losing the update. Call the lambda only by its local name in the same function (where it borrows its captures), or have it return the new value and assign that."
	),
	NamedError(
		name = "ClosureKeepsReferences",
		text = "the closure keeps '$1', a list of references: a closure that outlives the expression owns what it keeps, so let it take values",
		explain = "A closure that outlives the expression it is made in captures a list of references. Such a closure owns what it captures, but the references point into values it does not own and that may die first. Capture values (copies) instead of references, or use the closure only within the expression."
	),
	NamedError(
		name = "ClosureTakesLoopValue",
		text = "the closure takes '$1', which the next iteration of the loop reads again: make the closure after the loop, or let it take a value of its own made in this iteration",
		explain = "A closure made inside a loop takes ownership of a variable declared outside it, but the next iteration reads that variable again, which would then be gone. Make the closure after the loop, or give it a value made fresh in this iteration (a copy) so the outer variable stays intact."
	),
	NamedError(
		name = "ClosureKeepsBorrow",
		text = "the closure keeps '$1', which is borrowed here: a closure that outlives the expression owns what it keeps, so let it take an owned value",
		explain = "A closure that is kept beyond the expression (returned, stored or pushed) captures a variable this function only borrows, such as a plain parameter. A kept closure must own what it captures, and a borrowed value cannot be given to it. Capture an owned value instead: take the parameter as `move`, or bind a copy (`s.copy()`) and let the closure capture that.",
		example = """
			fn later(s str) fn() i64:
				(): s.len
			print(later("abc".repeat(2))())
			"""
	),
	NamedError(
		name = "ArenaEscape",
		text = "'$1' is made in the arena at line $2, which frees it at the block's end: it cannot go to a place outside the block ($3)",
		explain = "A value allocated inside an `arena:` block is assigned, pushed, captured or returned to something that lives outside the block. The arena frees all its values at once when the block ends, so the outside place would hold freed memory. Make the value outside the arena, or copy out only plain data (a length, a number) before the block ends."
	),
	NamedError(
		name = "YieldInArena",
		text = "`yield` cannot be inside the arena at line $1: the loop walking the generator may stop at it, before the block's end",
		explain = "A generator yields from inside an `arena:` block. The loop consuming the generator may stop after any yield and never resume it, so the arena's end, where its memory is freed, might never run. Move the `yield` outside the arena block.",
		example = """
			fn words() Seq<str>:
				arena:
					yield "a".repeat(2)
			for w in words():
				print(w)
			"""
	),
	NamedError(
		name = "ReturnLocalRef",
		text = "cannot return a reference into '$1': it is destroyed when the function returns",
		explain = "A function whose return type is a reference returns a reference into one of its own locals. The local is destroyed when the function returns, so the caller would receive a dangling reference. Return the value itself (an owned return type), or return a reference into a parameter that the caller owns."
	),
	NamedError(
		name = "ReturnTemporaryRef",
		text = "cannot return references into a temporary's elements: it is destroyed when the function returns",
		explain = "A function returns references (such as lent strings from a map over a list) into the elements of a temporary created inside it. The temporary is destroyed at the return, so the references would dangle. Return owned values instead, for example by copying them (`m => m.name.copy()`), or take the source list as a parameter."
	),
	NamedError(
		name = "AssignBorrowing",
		text = "'$1' borrows '$2', so it cannot be given another value: declare it `mut` with a value of its own, or bind a new name",
		explain = "A mutable variable that was bound to a place without writing `ref` (so it borrows that place) is given a new value. A borrow cannot take a value of its own, and for a value that owns memory Zap will not silently turn the binding into a copy. Bind it with a value of its own from the start (`mut x = place.copy()`), or bind a new name for the new value. It is a safety net of the ownership pass, which runs after type checking: in a short program the checker refuses such a reassignment first (AssignImmutable or AssignType), so there is no short example."
	),
	NamedError(
		name = "AssignBorrow",
		text = "cannot assign to '$1': it is a borrow",
		explain = "A variable bound explicitly as a reference (`mut ref place`) is assigned a plain value. A borrow only points at its place, so it cannot be given another value by assignment. Assign to the place itself, or use a new variable that owns the value. It is a safety net of the ownership pass, which runs after type checking: in a short program the checker refuses such a reassignment first (MutRefLendsOnce or AssignImmutable), so there is no short example."
	),
	NamedError(
		name = "RefToStatementTemporary",
		text = "'$1' would reference a temporary that is destroyed at the end of the statement: bind the temporary to a variable first, or keep the value itself",
		explain = "A binding would hold a reference into a temporary (such as the result of a call) that is destroyed at the end of the statement, so the binding would dangle on the next line. For plain data Zap copies the value out, but a value that owns memory is never copied silently. Bind the temporary to a variable first and reference that, or make the function return the value instead of a reference.",
		example = """
			type Item:
				name str
			fn firstOf(xs Item[]) ref Item:
				xs[0]
			found = firstOf([Item(name = "a".repeat(2))])
			print(found.name)
			"""
	),
	NamedError(
		name = "RefToStatementTemporaryCopy",
		text = "'$1' would reference a temporary that is destroyed at the end of the statement (copy() the value, or reference a variable)",
		explain = "A binding of a view type (a struct holding references, such as one with a `ref str` field), or one written with `mut ref`, points into a temporary that is destroyed at the end of the statement, typically a call's argument or result. The view would outlive what it looks at. Bind the temporary to a variable first and make the view from that, or call `.copy()` to keep an owned value; a plain `ref T` result gets RefToStatementTemporary instead.",
		example = """
			type Word:
				text ref str
			fn wordOf(s str) Word:
				Word(text = s)
			w = wordOf("ab".repeat(2))
			print(w.text)
			"""
	),
	NamedError(
		name = "RefToTemporaryElements",
		text = "'$1' would reference the elements of a temporary that is destroyed at the end of the statement: bind the list to a variable first, or copy the values (m => m.name.copy())",
		explain = "A binding holds references to the elements of a temporary list (for example a call's result mapped to its strings), and the list is destroyed at the end of the statement. The references would then point into freed memory. Bind the list to a variable first so it lives on, or copy the values in the map (`m => m.name.copy()`)."
	),
	NamedError(
		name = "MutBindingNotOwned",
		text = "'$1' is mut, so it needs a value of its own, but this value belongs to someone else: bind it without mut, give away the owner, or give a value of its own (.copy())",
		explain = "A `mut` binding is given `place ?? fallback` where the left side is a variable or field, so the result only borrows the optional's value. A mutable variable must own its value, since changing a borrowed one would change someone else's. Bind it without `mut`, give the owner away (`move`), or call `.copy()` on the result.",
		example = r"""
			nick str? = "ann".repeat(2)
			mut name = nick ?? "anon"
			name = "{name}!"
			print(name)
			"""
	),
	NamedError(
		name = "TakeApartBorrowed",
		text = "taking a value apart moves its parts out, but $1: read the parts where they are (p.name, xs[0]), or take apart a value of its own (.copy())",
		explain = "A tuple or struct that this function only borrows (a parameter, an element, a field) is destructured with `a, b = t`. Taking a value apart moves its parts out, which a borrower cannot do. Read the parts in place (`p.name`, `xs[0]`), destructure a value of its own (`t.copy()`), or take the parameter as `move`."
	),
	NamedError(
		name = "MutBindingOfBorrowed",
		text = "'$1' is mut, so it needs a value of its own, but $2: bind it without mut, give away the owner (or move the value out of it), or give a value of its own (.copy())",
		explain = "A `mut` binding is given a value that belongs to something else, such as an element of a list or a field (`mut p = ps[0]`). A mutable variable needs its own value, and Zap does not copy behind your back. Bind it without `mut` to borrow it, move the value out of its owner, or bind `.copy()`."
	),
	NamedError(
		name = "Expected",
		text = "expected $1, found $2",
		explain = "The parser needed a specific token at this point (such as `in`, `:`, `)` or a name) and found another one. The message names both; the cause is usually a missing keyword or punctuation, or an extra token. Write the expected token where the message points."
	),
	NamedError(
		name = "TypeSize",
		text = "a type's size is a whole number, a number parameter, or nothing for a list: T[], T[4], T[N]",
		explain = "Inside a type's brackets there is something other than a whole number, a capitalised number parameter, or nothing. A size must be known when compiling: a literal (`f32[4]`), a number parameter of a generic (`T[N]`), or empty for a list (`T[]`). Use a literal or a number parameter, or a list when the size is known only at run time.",
		example = """
			n = 4
			mut a f32[n]
			print(a)
			"""
	),
	NamedError(
		name = "TupleTypeSize",
		text = "a tuple type holds 2 to 8 types",
		explain = "A tuple type lists more than 8 types (or none). Tuples are for small groups of values whose meaning is their position, and one type in parentheses is just that type. For more values declare a `type` with named fields.",
		example = """
			fn many() (i64, i64, i64, i64, i64, i64, i64, i64, i64):
				(1, 2, 3, 4, 5, 6, 7, 8, 9)
			"""
	),
	NamedError(
		name = "ExpectedType",
		text = "expected a type, found $1",
		explain = "A type was expected here (after a parameter's name, in a binding's declared type, after a function's parameters), but another token came. A type is a name such as `i64` or `Point`, possibly with brackets and `?`, or a tuple in parentheses. Write the type, or remove the stray token."
	),
	NamedError(
		name = "RangeTypeSpelling",
		text = "a range type is written T in a..b, a..=b or a..",
		explain = "A range type `T in ...` was started, but its first bound is not followed by `..` or `..=`. A range type restricts T to the values `a..b` (end excluded), `a..=b` (included) or `a..` (no end). Write the range with one of those operators, for example `n i64 in 1..=10`.",
		example = """
			fn level(n i64 in 1 to 10) i64:
				n
			"""
	),
	NamedError(
		name = "OptionalResultParentheses",
		text = "an optional on a result's value side is written in parentheses: (T?) ? E",
		explain = "A result type whose value side is optional was written `T? ? E`, which reads ambiguously. Zap requires parentheses around the optional value type so the two question marks are not confused. Write `(T?) ? E`."
	),
	NamedError(
		name = "MalformedInterpolation",
		text = "malformed string interpolation",
		explain = r"Inside a string's `{...}` the parser read an expression and then found something other than the closing brace or a format spec. Each pair of braces holds exactly one expression, optionally followed by `:format`. Put a single expression in each pair of braces, or join values with an operator.",
		example = r"""
			a = 1
			b = 2
			print("total {a b}")
			"""
	),
	NamedError(
		name = "UnknownFormat",
		text = "the format ':$1' is none of .2 (decimals), 04 (zeros), x or X (hexadecimal), >8 or <8 (aligned; ->8 fills with -), # first (an integer as its literal: #08X), or those combined (>8.2, 08x)",
		explain = r"The format after `:` in an interpolation is not one Zap knows. The accepted formats are decimals (`.2`), zero padding (`04`), hexadecimal (`x`, `X`), alignment with a width (`>8`, `<8`, `->8` to fill with -), an integer as its literal (`#08X`), and combinations of these. Rewrite the spec using those forms, such as `{x:>8.2}` or `{n:08x}`.",
		example = r"""
			print("{3.0:.2x}")
			"""
	),
	NamedError(
		name = "WidthAligned",
		text = r"a width is aligned: {x:>$1} to the right, {x:<$1} to the left, {x:0$1} with zeros",
		explain = r"A width was given without saying how to align, as in `{x:5}`. Zap requires the width to say where the padding goes, since a bare number is ambiguous. Write `{x:>5}` for right alignment, `{x:<5}` for left, or `{x:05}` to pad with zeros."
	),
	NamedError(
		name = "PositionalAfterNamed",
		text = "a part by position comes before those by name: Point(0, y = 1)",
		explain = "In a variant pattern, a part given by position comes after one given by name, as in `Rect(width = w, h)`. Positions count from the start, so they would be ambiguous after named parts. Put positional parts first (`Rect(w, height = h)`) or name every part.",
		example = """
			type Shape:
				Rect(width f32, height f32)
			s = Shape.Rect(2.0, 3.0)
			match s:
				Rect(width = w, h): print(w * h)
			"""
	),
	NamedError(
		name = "TupleSize",
		text = "a tuple holds 2 to 8 values",
		explain = "A tuple pattern in a match has more than 8 parts. Tuples hold 2 to 8 values, so no value could match such a pattern. Match fewer parts, or declare a type with named fields and match that.",
		example = """
			t = (1, 2)
			match t:
				(a, b, c, d, e, f, g, h, i): print(a)
				_: print(0)
			"""
	),
	NamedError(
		name = "ListPatternRests",
		text = "a list's pattern has one ..rest at most",
		explain = "A list pattern contains more than one `..rest`, as in `[..a, ..b]`. With two rests the split point is ambiguous. Keep at most one rest and name the fixed elements around it, for example `[first, ..rest]` or `[..init, last]`."
	),
	NamedError(
		name = "MapPatternKeys",
		text = "a map's pattern names its keys as literals: \{\"type\": \"move\", \"x\": x}",
		explain = "A map pattern used a name or expression as a key, as in `\{k: 1\}`. A map pattern can only look up fixed keys, so each key must be a literal, while the value side can capture. Write `\{\"type\": \"move\", \"x\": x\}`."
	),
	NamedError(
		name = "StrPatternCaptures",
		text = "a string's pattern captures names: \"GET \{path}\" (no format, no expression)",
		explain = "A string pattern has an interpolation that is not a plain name, such as a format or an expression (`\"\{a:>4\}\"`). In a pattern the braces capture part of the string into a new name, so they hold only that name. Write `\"GET \{path\}\"` and format or compute after matching."
	),
	NamedError(
		name = "StrPatternAdjacentCaptures",
		text = "two captures side by side cannot tell where one ends: put text between them",
		explain = "A string pattern has two captures with no text between them, like `\"\{a\}\{b\}\"`. The matcher splits the string at the literal text between captures, so with none it cannot tell where one ends. Put fixed text between them (`\"\{a\}-\{b\}\"`), or capture once and split afterwards."
	),
	NamedError(
		name = "RangePatternSpelling",
		text = "a range pattern is lo..hi (or lo..=hi, or lo..) of number literals: 1..20 matches 1 to 19",
		explain = "A range pattern starts with something other than a number literal, for example a string or a byte. Range patterns compare numbers, so both ends must be integer or float literals. Write `lo..hi`, `lo..=hi` or `lo..` with numbers, or list the other values to match exactly.",
		example = """
			c = "m"
			match c:
				"a".."z": print("lower")
				_: print("other")
			"""
	),
	NamedError(
		name = "RangePatternEnds",
		text = "a range's ends are numbers of one kind: 1..20, 0.0..1.0",
		explain = "The two ends of a range pattern are of different kinds, one integer and one float. A range compares the matched value with both ends, so they must be the same kind of number. Write both as integers (`1..20`) or both as floats (`0.0..1.0`).",
		example = """
			n = 5
			match n:
				1..2.5: print("low")
				_: print("other")
			"""
	),
	NamedError(
		name = "RangePatternInclusiveEnd",
		text = "lo..= takes its end: 1..=20",
		explain = "A range pattern was written `lo..=` with no end. An inclusive range must say which end it includes; only the exclusive form can be open (`lo..`). Write `lo..=hi`, or `lo..` for no upper end.",
		example = """
			n = 5
			match n:
				1..=: print("positive")
				_: print("other")
			"""
	),
	NamedError(
		name = "FloatPattern",
		text = "a float is matched by a range (0.0..1.0): exact equality of floats misleads",
		explain = "A match arm compares a float with an exact literal. Exact float equality is misleading because of rounding, so Zap only matches floats by ranges. Write a range such as `0.0..1.0`, or compare with a tolerance in an arm condition."
	),
	NamedError(
		name = "ExpectedPattern",
		text = "expected a pattern, found $1",
		explain = "A match arm starts with a token that cannot begin a pattern. A pattern is a literal, a range, a name to bind, `_`, `none`, a variant, a tuple, a list, a map or a string pattern. Write one of those; a comparison goes in the arm's condition after `and` (`x and x < 0:`).",
		example = """
			n = 5
			match n:
				< 0: print("negative")
				_: print("other")
			"""
	),
	NamedError(
		name = "ArmConditionOr",
		text = "an arm's condition joins its parts with and: an or goes in parentheses",
		explain = "An arm's condition contains a bare `or`, as in `x and x > 9 or x < 0:`. The pattern and its condition are already joined by `and`, so an unparenthesized `or` would leave unclear whether the pattern still applies. Put the `or` in parentheses: `x and (x > 9 or x < 0):`.",
		example = """
			n = 5
			match n:
				x and x > 9 or x < 0: print(x)
				_: print(0)
			"""
	),
	NamedError(
		name = "IfValueNeedsElse",
		text = "a choice of values ends with else: a if c else b",
		explain = "A value picked by a condition, `a if c`, has no `else`. A value must exist in every case, so the choice needs a branch for when the condition is false. Write `a if c else b`, and chain `a if c else b if d else e` for more cases.",
		example = """
			n = 3
			label = "pos" if n > 0
			print(label)
			"""
	),
	NamedError(
		name = "ExpectedExpression",
		text = "expected an expression, found $1",
		explain = "A value was expected here (after `=`, as an argument, after an operator), but the next token cannot start one. Usually something is missing, such as an operand before an operator. Write the missing value or remove the stray token.",
		example = """
			total = * 2
			print(total)
			"""
	),
	NamedError(
		name = "ConstructorListType",
		text = "a list type before a constructor is a type's name and its brackets: Item[]",
		explain = "A list type used as the receiver of a constructor (such as `.fromJson`) has something other than a type's name before its brackets, for example a call. Only a type name (`Item`, or `models.Item` of a module) with brackets is read as a type there: write `Item[].fromJson(text)`.",
		example = """
			items = make().Item[].fromJson("[]")
			"""
	),
	NamedError(
		name = "CsvRowType",
		text = "$1 cannot be a CSV's rows: they are a list of structs of plain data",
		explain = "fromCsv or toCsv was called on something other than a list of structs whose fields can be serialized. A CSV is read into rows of one struct, its header's names matched to the fields. Write `Row[].fromCsv(text)` or call `toCsv` on a `Row[]`.",
		example = """
			type Row:
				name str
			rows = Row.fromCsv("name")
			"""
	),
	NamedError(
		name = "ConstructorReceiver",
		text = "a constructor is called on a named type, a list or a map: Item[].fromJson(text)",
		explain = r"A constructor like `.fromJson` was called on a type expression that is neither a named type, a list nor a map, such as an optional or a fixed array built with type suffixes. Only those three can be constructed this way. Call it on `Item`, `Item[]` or `{K: V}` and handle the optional result with `??`.",
		example = """
			type Item:
				id i64
			xs = Item[]?[2].fromJson("[]")
			"""
	),
	NamedError(
		name = "NamedTupleNeedsType",
		text = "a tuple with named values has no type of its own: it needs a struct type from its place",
		explain = "A tuple written with names, `(name = \"Zapdos\", level = 50)`, is the literal of the struct type its place expects (an annotated binding, a list's element, an argument, a field's value or a return). Here nothing tells which struct that is. Write the type's name, `Pokemon(name = \"Zapdos\", level = 50)`, or annotate the place.",
		example = """
			x = (a = 1, b = 2)
			"""
	),
	NamedError(
		name = "TupleTooLarge",
		text = "a tuple holds 2 to 8 values: declare a type for more",
		explain = "A tuple value has more than 8 elements. Tuples are meant for small groups whose meaning is their position, and the runtime defines them only up to 8. Declare a `type` with named fields for more values.",
		example = """
			print((1, 2, 3, 4, 5, 6, 7, 8, 9))
			"""
	),
	NamedError(
		name = "EmbedPath",
		text = "embed takes the path of a file as a string literal: embed(\"table.txt\")",
		explain = "`embed` was called with something other than one string literal, such as a variable or several arguments. The file is read when compiling, so its path must be known in the source text. Write `embed(\"table.txt\")` with the path relative to the source file.",
		example = """
			file = "table.txt"
			text = embed(file)
			print(text)
			"""
	),
	NamedError(
		name = "EmbedUnreadable",
		text = "embed: cannot read $1",
		explain = "`embed(\"path\")` names a file the compiler could not read, usually because it does not exist beside the source file or the path is wrong. The path is relative to the file that contains the `embed`. Fix the path or add the file.",
		example = """
			print(embed("missing.txt"))
			"""
	),
	NamedError(
		name = "LenNeedsPlace",
		text = "len inside brackets needs a list reached without calls: bind the list first",
		explain = "Inside an index, `len` was used on a list produced by a call, as in `scores()[len - 1]`. `len` stands for the indexed list's length, which would need the call to run twice or its result to be kept. Bind the list first (`s = scores()`) and write `s[len - 1]`.",
		example = """
			fn scores() i64[]:
				[3, 1, 2]
			print(scores()[len - 1])
			"""
	),
	NamedError(
		name = "SliceToEndNeedsPlace",
		text = "a slice to the end needs a list reached without calls: bind the list first",
		explain = "A slice open at the end (`[1..]`) was taken of a list produced by a call. The open end means the list's length, which would need the call's result to be kept for the slice. Bind the list to a name first and slice that.",
		example = """
			fn scores() i64[]:
				[3, 1, 2]
			print(scores()[1..])
			"""
	),
	NamedError(
		name = "IsBlank",
		text = "'is _' binds nothing: a test for a value is written opt != none",
		explain = "A condition tested `opt is _`, which matches any value but binds nothing. Testing whether an optional holds a value is a comparison with none. Write `opt != none`, or `opt is v` when you need the value."
	),
	NamedError(
		name = "IsNone",
		text = "a test for none is written opt == none",
		explain = "A condition tested `opt is none`. `is` binds names from a pattern and none has nothing to bind, so Zap tests for it by comparison. Write `opt == none`."
	),
	NamedError(
		name = "IsJoinedByOr",
		text = "a condition that tests with 'is' joins its parts with and only: past or, the names it binds would not always be there",
		explain = "A condition that binds a name with `is` also contains `or`, as in `if o is v or flag:`. When the other side of the `or` is true, the `is` may not have matched, so the name it binds would not exist in the body. Join the parts with `and` only, or test the alternative in a separate branch."
	),
	NamedError(
		name = "AliasRebound",
		text = "'$1' is an alias: bind another name",
		explain = "A name declared with `alias` is assigned or reused (as a variable or a parameter name). An alias is a fixed second name for something, not a variable, so it cannot be bound again. Choose a different name for the new binding."
	),
	NamedError(
		name = "LoopVariable",
		text = "a loop with no variable is written `loop n`",
		explain = "A `for` loop has the variable `_` over `0..n`, so the counter is never used. Zap has a direct form for repeating a block n times. Write `loop n:`."
	),
	NamedError(
		name = "TupleTargetParentheses",
		text = "a tuple is taken apart without parentheses: a, b = v",
		explain = "A tuple was taken apart with parentheses on the left, `(a, b) = v`. Zap writes tuple destructuring without them. Write `a, b = v`."
	),
	NamedError(
		name = "InvalidTarget",
		text = "invalid assignment target",
		explain = "The left side of `=` or `op=` is not something that can be assigned: not a name, field, element, list of names or struct pattern (for example an arithmetic expression). Assign to a variable, a field (`p.x = 1`) or an element (`xs[i] = 1`) instead.",
		example = """
			mut a = 1
			a + 1 = 2
			print(a)
			"""
	),
	NamedError(
		name = "TuplePosition",
		text = "a tuple's values are read by taking it apart (a, b = t), not by position; values with a meaning of their own get a type with named fields",
		explain = "A tuple's element was read by position, as in `t.0`. Zap tuples have no positional fields; their values are named where they are taken apart. Write `a, b = t`, or declare a type with named fields when the values have their own meaning."
	),
	NamedError(
		name = "TupleField",
		text = "the field '$1' of type $2 holds a tuple: declare a type with named fields for the values it keeps",
		explain = "A struct or variant field's type is a tuple, or a list, optional, array or map value of tuples. A tuple is a function's result or a sort key, taken apart where it is made; values a field keeps have a meaning of their own. Declare a `type` with named fields and hold that (`path Cell[]` with `type Cell: x i64, y i64`). A tuple stays legal as a map's key, a local and a test table."
	),
	NamedError(
		name = "TupleTargetNames",
		text = "a tuple is taken apart into names: (a, b) = value",
		explain = "A tuple destructuring has something other than a name among its targets, such as a literal (`a, 1 = 1, 2`). Taking a tuple apart binds each part to a name; it does not test values. Use names (or `_` to skip a part), and use `match` to compare parts with values."
	),
	NamedError(
		name = "TargetPattern",
		text = "a pattern is (a, b) or a struct's Type(a, b): found something else",
		explain = "A destructuring target (in `for ... in`, or on the left of `=`) is neither a tuple `(a, b)` nor a struct pattern `Type(a, b)`, for example a list in brackets. Only tuples and structs can be taken apart there. Use `(a, b)` or `Point(x, y)`, and take lists apart with `match`.",
		example = """
			pairs = [[1, 2], [3, 4]]
			for [a, b] in pairs:
				print(a + b)
			"""
	),
	NamedError(
		name = "StructTargetNames",
		text = "a struct is taken apart into names: Point(x = px) = value",
		explain = "A struct destructuring by field name has something other than a name after a field's `=`, as in `Point(x = 0) = p`. Taking a struct apart binds each named field to a new name; it does not test values. Write `Point(x = px) = p`, and use `match` to compare a field with a value.",
		example = """
			type Point:
				x i64
				y i64
			p = Point(x = 1, y = 2)
			Point(x = 0) = p
			"""
	),
	NamedError(
		name = "StructTargetPositions",
		text = "a struct is taken apart into names: Point(x, y) = value",
		explain = "A struct destructuring by position has a part that is not a name, such as a literal or an expression (`Point(1, y) = p`). Each position binds the matching field to a new name. Write names only (`Point(x, y) = p`), using `_` to skip a field.",
		example = """
			type Point:
				x i64
				y i64
			p = Point(x = 1, y = 2)
			Point(1, y) = p
			print(y)
			"""
	),
	NamedError(
		name = "CompoundOnCall",
		text = "the target of '$1=' is the result of a call: it would change a temporary",
		explain = "A compound assignment such as `+=` targets a place reached through a call's result, as in `items()[0] += 1`. The call returns a temporary, so the change would be lost immediately. Bind the result to a `mut` variable first and change that, or change the original list."
	),
	NamedError(
		name = "ForIndexNeedsPlace",
		text = "for i, x in needs a list variable (or a field of one): bind the list to a name first",
		explain = "`for i, x in ...` was used over something that is not a list variable or a field of one, such as an element or a call's result. The indexed form reads the list by index on each round, so it needs a stable place. Bind the list to a name first, then loop over that name."
	),
	NamedError(
		name = "GridForSpelling",
		text = "a grid's cells are visited as for (x, y), v in g",
		explain = "A `for` over a grid's cells has a coordinate part that is not a pair of names, as in `for (x, y, z), v in g`. A grid's cells are visited with their two coordinates and the value. Write `for (x, y), v in g:`.",
		example = """
			g = Grid(2, 2, fill = 0)
			for (x, y, z), v in g:
				print(v)
			"""
	),
	NamedError(
		name = "RangeStepWord",
		text = "a range's step is written lo..hi step s",
		explain = "A range's step was given with a method, such as `(0..10).by(3)`. Zap writes the step as part of the range with the word `step`. Write `for i in 0..10 step 3:`."
	),
	NamedError(
		name = "TestCases",
		text = "a test's cases are `for x in cases:` or `for (a, b) in cases:`",
		explain = "A test written as `test \"name\" for ...` has a loop that is not a plain `for x in cases:` or `for (a, b) in cases:`, for example an indexed `for i, x in` over a list made right there, which the parser rewrites into more than a plain loop. Each element of the cases list becomes its own case, so the loop must go over the elements only. Use `for x in cases:` or a tuple pattern, and put an index inside the cases if you need one.",
		example = """
			test "each case" for i, x in [3, 4].reversed():
				expect x > i
			"""
	),
	NamedError(
		name = "UnknownCompileError",
		text = "no compile error is named $1: they are $2",
		explain = "A test's `refuses Name` names an error the compiler does not have, usually a typo or an error that was renamed. The message lists every valid name. Pick the error the program should trigger from that list."
	),
	NamedError(
		name = "RuntimeErrorMessage",
		text = "only Failure carries a message, not $1",
		explain = "A test expects a runtime error with a message in parentheses, but that error is not `Failure`. Only a `fail(...)` carries a text of the program's choosing; other runtime errors are identified by name alone. Remove the parentheses, or write `stops Failure(\"text\")` when the program calls `fail`.",
		example = """
			test "out of range" stops IndexOutOfBounds("index 5"):
				xs = [1, 2]
				print(xs[5])
			"""
	),
	NamedError(
		name = "UnknownRuntimeError",
		text = "no runtime error is named $1: they are $2",
		explain = "A test's `stops Name` names a runtime error that does not exist, usually a typo. The message lists the valid names. Pick the error the program should stop on from that list."
	),
	NamedError(
		name = "UnknownOption",
		text = "'$1' is not an option: the options are $2",
		explain = "A `use` line names an option the compiler does not know, such as `use fastMath`. The set of options is closed, and each one has a precise meaning. Pick one of the options the message lists, or remove the line.",
		example = """
			fn f(x f64) f64:
				use fastMath
				x * 2.0 + 1.0

			print(f(1.0))
			"""
	),
	NamedError(
		name = "ExpectedLineEnd",
		text = "expected the end of the line: the block is the lines indented after the ':'",
		explain = "Something was written on the same line after the `:` that opens a block which must be on indented lines, such as a type's fields, a match's arms or a bound's methods. These blocks are always the lines indented after the colon. Move the content to the next line, indented.",
		example = """
			type Point: x i64
			p = Point(x = 1)
			"""
	),
	NamedError(
		name = "AlreadyAlias",
		text = "'$1' is already an alias",
		explain = "A second `alias` reused a name that an alias in scope already stands for. An alias is a textual stand-in (every later use of the name is the aliased expression written again), so one name cannot stand for two expressions at once. Give the second alias another name, or bind a value with `name = expr` instead.",
		example = """
			xs = [1, 2, 3]
			alias first = xs[0]
			alias first = xs[1]
			print(first)
			"""
	),
	NamedError(
		name = "MainDeclared",
		text = "a file's top-level statements are its program: write main's body at the top level",
		explain = "The file declares a function named `main`. In Zap a file's top-level statements are the program itself, so the compiler builds main from them and refuses a hand-written one. Move main's body to the top level of the file, outdented."
	),
	NamedError(
		name = "GenericDefinedType",
		text = "a defined type (type Name = T) takes no type parameters",
		explain = "A defined type `type Name<T> = ...` declared type parameters. A defined type is one existing type under a name of its own, so it cannot be generic. Define it over a concrete type (`type Pair = (i64, i64)`), or declare a generic struct with `type Pair<T>:` and its fields."
	),
	NamedError(
		name = "BoundSelfFirst",
		text = "a bound's function takes the value first: fn $1(self $2, ...), or mut self $2 to change it",
		explain = "A function declared in a `bound` does not take the bound's value first. Every function of a bound is a method on the type standing for it, so its first parameter must be exactly `self B` or `mut self B`, B being the bound's own name (not another type, not generic, not `move`). Add that parameter in front of the others."
	),
	NamedError(
		name = "SelfLent",
		text = "the receiver is lent: `fn` reads it, `mut fn` changes it",
		explain = "A method is written `move fn`. The receiver of a method is always lent, never given away: a method reads it, and a `mut fn` changes it. Drop `move`, and if the function must consume the value make it a plain function taking it as a `move` parameter."
	),
	NamedError(
		name = "FieldAfterMethods",
		text = "a field of $1 after its methods: the fields come first",
		explain = "A type's block lists its fields (or variants), then the methods written in it. A field after a method reads as part of that method; move it up with the other fields."
	),
	NamedError(
		name = "PubMethodChanges",
		text = "'$1' changes its receiver: a pub method writes `mut fn $1`",
		explain = "A method written in its type's block borrows its receiver to change it when its body changes it, but a `pub` one is a contract with other modules, which compile against its signature: it writes `mut fn` as a `pub` function writes its result."
	),
	NamedError(
		name = "ReceiverUntold",
		text = "'$1' changes its receiver $2: write `mut fn $1`",
		explain = "A method written in its type's block changes its receiver when its body does so where it runs: an assignment of a field, a call of a method that changes it, the receiver lent to a `mut` parameter. A change inside a lambda (which may be stored and run later), or one met after another method had already read this one as reading it, is not told by the body alone: write `mut fn`."
	),
	NamedError(
		name = "ExpectedDeclaration",
		text = "expected a declaration, found $1",
		explain = "A top-level line starts like a declaration (pub, mut, fn, type, import, extern) but what follows is not one, for example `pub` before a statement. Modifiers such as `pub` and `mut` only apply to declarations: a function, a type, a constant or a module variable. Remove the modifier, or complete the declaration it was meant for.",
		example = """
			pub for i in 0..3:
				print(i)
			"""
	),
	NamedError(
		name = "ParallelEffect",
		text = "parallel() runs this on several threads at once: it cannot $1 ($2)",
		explain = "A step of a `parallel()` pipeline or loop, directly or through a function it calls, prints or does other I/O, or changes a module variable. Those steps run on several threads at once, so such effects would race or interleave; the message names the call chain that leads to it. Return values from the step and do the printing or the update afterwards on one thread."
	),
	NamedError(
		name = "JobEffect",
		text = "background() runs this beside the thread that started it: it cannot $1 ($2)",
		explain = "A background job, directly or through a function it calls, changes or reads a module variable that can change, or prints. The job runs on a system thread of its own while the thread that started it goes on, so both would touch the same memory at once (a list read while it grows is freed memory). Capture what the job needs when it starts (the closure owns its captures), and hand results back as the job's result or through a Channel; print on the thread that started it."
	),
	NamedError(
		name = "JobBodyUnseen",
		text = "background() takes a lambda or a function's name, whose body it checks",
		explain = "The job is a function value made elsewhere, so the compiler cannot see what it does and check that it touches nothing the starting thread is changing. Write the lambda at the call (`background((): work(x))`) or name the function."
	),
	NamedError(
		name = "RegisterArrayZeros",
		text = "a [$1]T of this type starts from zeros in memory",
		explain = "A mutable fixed array declared without values (`mut r T[N]`) has an element type with no zero value to start from, so the compiler cannot make each element a register-kept local. In practice the compiler first tries the body on a copy and silently keeps any array it cannot take apart in memory as an ordinary T[N] value, so this error only surfaces when that fallback cannot apply. Give the array its values: `[a, b, ...]` or `fill(N, a)`."
	),
	NamedError(
		name = "RegisterArrayValues",
		text = "a [$1]T starts from $1 values ([a, b, ...] or fill($1, a)), or from none",
		explain = "A fixed array `name T[N] = ...` was initialised with something other than exactly N values in a list literal or `fill(N, x)` with a literal N, so its elements cannot be turned into N separate locals. In practice the compiler first tries the body on a copy and silently keeps any array it cannot take apart in memory as an ordinary T[N] value, so this error only surfaces when that fallback cannot apply. Write N values, or `fill(N, x)` with the same N as the type."
	),
	NamedError(
		name = "RegisterLoopRange",
		text = "a loop that indexes a register array runs over a range",
		explain = "A `for` loop whose variable indexes a register array does not run over a range. Such loops are unrolled so each index becomes a constant, which needs a `lo..hi` range. In practice the compiler first tries the body on a copy and silently keeps any array it cannot take apart in memory as an ordinary T[N] value, so this error only surfaces when that fallback cannot apply. Loop over `0..N` and index inside the body."
	),
	NamedError(
		name = "RegisterLoopConstant",
		text = "a loop that indexes a register array runs over a range known when compiling",
		explain = "A `for` loop whose variable indexes a register array runs over a range whose bounds are not compile-time numbers. Unrolling needs to know how many copies to make. In practice the compiler first tries the body on a copy and silently keeps any array it cannot take apart in memory as an ordinary T[N] value, so this error only surfaces when that fallback cannot apply. Use literal bounds, such as `for i in 0..4:`."
	),
	NamedError(
		name = "RegisterLoopSteps",
		text = "a loop that indexes a register array is unrolled: at most 64 steps of a positive step",
		explain = "A `for` loop whose variable indexes a register array would unroll into more than 64 copies, or its step is not positive. Unrolling is limited to keep code size reasonable. In practice the compiler first tries the body on a copy and silently keeps any array it cannot take apart in memory as an ordinary T[N] value, so this error only surfaces when that fallback cannot apply. Shorten the range or index a regular list instead."
	),
	NamedError(
		name = "RegisterLoopBreak",
		text = "a loop that indexes a register array is unrolled: it cannot break or continue",
		explain = "A `for` loop whose variable indexes a register array contains `break` or `continue`. The loop is unrolled into straight-line copies, which have no loop to leave or skip. In practice the compiler first tries the body on a copy and silently keeps any array it cannot take apart in memory as an ordinary T[N] value, so this error only surfaces when that fallback cannot apply. Express the condition with `if` inside the body instead."
	),
	NamedError(
		name = "RegisterIndexConstant",
		text = "the index of the register array '$1' must be known when compiling (a literal or a variable of a loop over a literal range)",
		explain = "An element of a register array is indexed with a value only known while the program runs. Each element is a separate local, so the index must be a literal, an expression of literals, or the variable of a `for` loop over a literal range. In practice the compiler first tries the body on a copy and silently keeps any array it cannot take apart in memory as an ordinary T[N] value, so this error only surfaces when that fallback cannot apply."
	),
	NamedError(
		name = "RegisterIndexOutside",
		text = "index $1 is outside the register array '$2' of $3",
		explain = "A register array is indexed with a compile-time index that is negative or not below its length. Since the index is known when compiling, the out-of-range access is reported then instead of stopping the program at run time. In practice the compiler first tries the body on a copy and silently keeps any array it cannot take apart in memory as an ordinary T[N] value, so this error only surfaces when that fallback cannot apply. Fix the index or the array's length."
	),
	NamedError(
		name = "RegisterArrayWhole",
		text = "the register array '$1' is used element by element: $1[i]",
		explain = "A register array is used as a whole value (passed, returned, assigned or bound again) rather than element by element. Its elements are separate locals with no array behind them, so only `a[i]` reads are possible. In practice the compiler first tries the body on a copy and silently keeps any array it cannot take apart in memory as an ordinary T[N] value, so this error only surfaces when that fallback cannot apply."
	),
	NamedError(
		name = "TableElement",
		text = "a Table's element is a struct with fields, each a column: found $1",
		explain = "A `Table<T>` was made with an element type that is not a struct with fields, such as `Table<i64>`. A Table stores one column per field of its element, so it needs a struct to split into columns. Use `T[]` for plain values, or wrap them in a struct type."
	),
	NamedError(
		name = "TableFieldName",
		text = "$1 has a field '$2', which a Table answers itself (t.$2): rename the field",
		explain = "The struct given to `Table<T>` has a field whose name the table already answers itself, such as `len` or `isEmpty`. Columns are read as `t.field`, so that field would clash with the table's own member. Rename the field in the struct."
	),
	NamedError(
		name = "TableEmpty",
		text = "$1() is empty: its elements come by push",
		explain = "`Table<T>(...)` was called with arguments. A table is always created empty and filled by `push`, so its constructor takes nothing. Write `mut t = Table<T>()` and push each element, or assign a list literal where a table type is expected.",
		example = """
			type Body:
				mass f64

			t = Table<Body>([Body(mass = 1.0)])
			print(t.len)
			"""
	),
	NamedError(
		name = "TableNoMethod",
		text = "no method '$1' on $2: a Table has len, isEmpty, t[i], for, its columns by their fields' names, $3 and the steps $4",
		explain = "A method was called on a Table that tables do not have, such as `sort`. A Table is a set of columns that must stay the same length and order, so it only offers its own small vocabulary (listed in the message) plus pipeline steps like map and filter. Use one of those, or copy the rows into a `T[]` to sort or reshape them.",
		example = """
			type Vec2:
				x f64
				y f64

			mut t = Table<Vec2>()
			t.sort()
			print(t.len)
			"""
	),
	NamedError(
		name = "TableRowUnbound",
		text = "a row of a Table names its table at each use: bind the table to a name first",
		explain = "A row of a table was lent with `r = mut ref t[i]` where t is not a table bound to a name. A row is rewritten as the table plus a hidden index at each use, so the table expression would be evaluated again every time. Bind the table to a name first, then take `mut ref t[i]` from it. In practice only tables named by a variable or a field are recognized as rows at all, so other forms (an element of a list of tables, a call's result) are refused earlier as indexing errors and this message is rarely seen."
	),
	NamedError(
		name = "TableElementChange",
		text = "a Table's element changes field by field: t[i].f op= v",
		explain = "A whole table element was changed with a compound assignment such as `t[i] += v`. A table keeps its elements as separate columns, so there is no whole element in place to update. Change it field by field (`t[i].x += v.x`) or assign a whole new element with `t[i] = v`."
	),
	NamedError(
		name = "TableColumnLength",
		text = "a Table's column keeps the table's length: change its elements (t.$1[i] = v), or the table",
		explain = "A table's column was replaced by assigning a whole list to it (`t.mass = [...]`). Every column must keep the table's length, which a new list could break. Change the column's elements one by one (`t.mass[i] = v`), or change the table itself."
	),
	NamedError(
		name = "TableColumnChange",
		text = "$1 would change the column '$2' of a $3, which keeps the table's length and order: change its elements (t.$2[i] = v), or the table",
		explain = "A table's column was given to something that could change its length or order, such as `t.mass.push(x)` or passing it as a `mut` argument. All columns move together, so one cannot grow or shuffle alone. Change single elements with `t.col[i] = v`, or use the table's own push and pop."
	),
	NamedError(
		name = "VectorArgument",
		text = "$1 expects an $2, got $3",
		explain = "A vector method or a store got an argument of the wrong type, for example `a.min(b)` where b is a vector of another element type or lane count, or `xs.store8(i, v)` with a mismatched vector. These operations work lane by lane on two vectors of the same type. Convert or build the argument as the same `Simd<N, T>` as the receiver.",
		example = """
			a = Simd<8>(1.0)
			b = Simd<8>(1)
			print(a.min(b))
			"""
	),
	NamedError(
		name = "VectorNoMethod",
		text = "$1 has no method '$2'",
		explain = "A method was called on a vector that its type does not offer. Vectors have a small fixed vocabulary (lane, sum, min, max, the comparison masks and a few type-specific ones) that maps directly to SIMD instructions. Use one of those, or take lanes out with `v.lane(i)` and work on numbers.",
		example = """
			v = Simd<8>(1)
			print(v.reverse())
			"""
	),
	NamedError(
		name = "VectorLanes",
		text = "$1 takes $2 lanes, got $3",
		explain = "A vector built from its lanes got a number of values that does not match its lane count. In source this is normally caught earlier by the Simd<N>(...) constructor (VectorValueCount); this message comes from the internal lane form that constructor rewrites to. Give exactly N values, or one value for every lane."
	),
	NamedError(
		name = "VectorLaneType",
		text = "a lane here is $1, found $2",
		explain = "A value given as a lane of a vector, or a number spread across one, has a type that cannot become the vector's element type, such as a bool or a str in a float vector. Numbers widen to the lane type where that loses nothing, but nothing else converts. Pass numbers of the lane's type, converting explicitly with `f64(x)` and the like when needed.",
		example = """
			v = Simd<4>(1.0, 2.0, 3.0, true)
			print(v)
			"""
	),
	NamedError(
		name = "VectorTypeForm",
		text = "a vector is Simd<lanes, element> (Simd<4, f64>), built as Simd<4>(x) or Simd<16, u8>(x)",
		explain = "Simd was written with no type arguments or with more than two. A vector type always says its lane count and element type, and a constructor at least its lane count. Write `Simd<4, f64>` as a type, and `Simd<4>(x)` or `Simd<16, u8>(x)` as a value.",
		example = """
			print(Simd(1.0))
			"""
	),
	NamedError(
		name = "VectorLaneCountFirst",
		text = "a vector's first type argument is its lane count, a number known when compiling: Simd<4, f64>",
		explain = "The first type argument of Simd is not a compile-time number, for example a type such as `Simd<f64, f64>`. The lane count comes first because it decides the register width. Write the count first and the element second: `Simd<4, f64>`.",
		example = """
			v Simd<f64, f64> = Simd<4>(1.0)
			print(v)
			"""
	),
	NamedError(
		name = "VectorElementMissing",
		text = "a vector type names its element: Simd<$1, f64>",
		explain = "A vector type was written with only its lane count, as in `v Simd<4> = ...`. A constructor may infer its element type, but a type annotation must name it since several element types share the same lane count. Write `Simd<4, f64>` (or i64, and so on).",
		example = """
			v Simd<4> = Simd<4>(1.0)
			print(v)
			"""
	),
	NamedError(
		name = "NoSuchVector",
		text = "there is no Simd<$1, $2>: the vector types are $3",
		explain = "The lane count and element type asked for do not form one of the supported vector types, for example 8 lanes of f64. Only the combinations listed in the message exist, because each maps to one native SIMD register type. Pick one of them, converting the values to its element type if needed."
	),
	NamedError(
		name = "VectorValueCount",
		text = "$1 takes one value (in every lane) or $2 (one per lane), got $3",
		explain = "A Simd constructor got a number of values that is neither one nor its lane count. A vector is built from one value repeated in every lane, or from exactly one value per lane. Pass a single value or all N of them.",
		example = """
			print(Simd<4>(1.0, 2.0))
			"""
	),
	NamedError(
		name = "VectorRepeatType",
		text = "Simd<$1, $2> repeats a $2, found $3",
		explain = "A vector filled from one non-literal value got a value whose type is not the vector's element type, for example an f32 or a bool variable in `Simd<4, f64>(x)`. A variable is not converted for you. Convert it yourself: `Simd<4, f64>(f64(x))`.",
		example = """
			x = f32(2.0)
			v = Simd<4, f64>(x)
			print(v)
			"""
	),
	NamedError(
		name = "VectorOneValue",
		text = "Simd<$1, $2> is made from one value: Simd<$1, $2>(x)",
		explain = "A vector type that can only be filled from one value, such as `Simd<16, u8>`, was given one value per lane. The backend has no lane-by-lane literal for that type. Build it from one value with `Simd<16, u8>(x)`, or load its bytes from a list.",
		example = """
			v = Simd<16, u8>(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)
			print(v)
			"""
	),
	NamedError(
		name = "TextureArrayRead",
		text = "a texture array is read where it is declared: pass the index, not the array",
		explain = "A whole texture array was passed to a function in a GPU stage, or declared as a function parameter. Neither SPIR-V nor HLSL can pass a texture array as a value; it can only be read where it is declared, in the parameter struct. Pass the index (or the coordinates) to the helper and read `p.textures[i]` in the stage, or give the helper the parameter struct itself."
	),
	NamedError(
		name = "TextureOfArrayRead",
		text = "a texture of an array is read where it is indexed: pass the index to $1",
		explain = "An element of a texture array (`p.textures[i]`) was passed as an argument to a helper function in a GPU stage. The GPU cannot pass a texture picked from an array; it must be sampled where it is indexed. Pass the index to the helper along with the parameter struct, and index and sample inside it."
	),
	NamedError(
		name = "ShaderUnknownFunction",
		text = "unknown function '$1'",
		explain = "A call in a GPU stage is neither a function of the stage's module, nor a GPU built-in, nor a texture method. It is raised by the shader compiler on a .gpu.zap module passed to shader(...); the language checker normally reports unknown functions first, so this mostly catches a CPU-only function reached from GPU code. Call only GPU functions (in .gpu.zap files) and the built-in methods."
	),
	NamedError(
		name = "ShaderParameterType",
		text = "unknown parameter type '$1'",
		explain = "A stage's parameter struct could not be found among the structs the shader compiler lowered. It is raised by the shader compiler on a .gpu.zap module passed to shader(...) and is an internal guard: the stage's parameters argument is checked to be a struct before this point. Declare the parameter struct with `pub type` in the GPU module and use it by that name."
	),
	NamedError(
		name = "ShaderBoolArray",
		text = "$1.$2 is an array of bools: the block holds a bool at the struct's top only",
		explain = "A field of a stage's parameter struct is an array of bools. It is raised by the shader compiler on a .gpu.zap module passed to shader(...); the parameter block stores a bool as a uint only at the struct's top level, and has no layout for bool arrays. Use an `i32[N]` or `u32[N]` of 0 and 1, or separate bool fields.",
		example = """
			# post/post.gpu.zap, given to shader(...)
			pub type Params:
				flags bool[4]

			pub fn pixel(uv Vec2, p Params) Vec4:
				Vec4(1.0, 0.0, 0.0, 1.0) if p.flags[0] else Vec4(uv.x, uv.y, 0.0, 1.0)
			"""
	),
	NamedError(
		name = "StorageBufferElement",
		text = "$1.$2 holds $3: a storage buffer's elements are f32, i32, u32, Vec2 and Vec4, or structs of them",
		explain = "A storage buffer field (`xs T[]` in the parameter struct) holds an element type the GPU cannot read as the CPU list lays it out, such as a Vec3, a matrix, a bool, an enum or an array. It is raised by the shader compiler on a .gpu.zap module passed to shader(...); only f32, i32, u32, Vec2 and Vec4, or structs of those, have the same bytes on both sides. Pad Vec3 to Vec4 and store other values as numbers.",
		example = """
			# post/post.gpu.zap, given to shader(...)
			pub type Params:
				points Vec3[]

			pub fn pixel(uv Vec2, p Params) Vec4:
				p.points[0].withW(1.0)
			"""
	),
	NamedError(
		name = "ShaderMemberOffset",
		text = "$1.$2 is at byte $3 for Vulkan and $4 for Direct3D: order the members Vec4s, Vec2s, then scalars",
		explain = "A struct held in a storage buffer places a member where Vulkan's std430 layout and Direct3D's packed structured buffer disagree, typically a Vec4 or Vec2 after a scalar. Both backends read the same bytes the CPU wrote, so the offsets must match. Order the struct's members Vec4s first, then Vec2s, then scalars."
	),
	NamedError(
		name = "ShaderBlockSize",
		text = "$1 is $2 bytes, $3 for Vulkan: add members up to a multiple of $4 bytes",
		explain = "A struct held in a storage buffer has a total size that Vulkan rounds up to its widest member's alignment while Direct3D does not, so the element strides would differ. It is raised by the shader compiler on a .gpu.zap module passed to shader(...). Add padding members (for example f32 fields) until the size is a multiple of the alignment named in the message.",
		example = """
			# post/post.gpu.zap, given to shader(...)
			pub type Record:
				tint Vec4
				weight f32

			pub type Records:
				records Record[]

			pub fn pixel(uv Vec2, p Records) Vec4:
				p.records[0].tint * p.records[0].weight
			"""
	),
	NamedError(
		name = "ShaderParameterField",
		text = "$1.$2 is a $3, which holds $4 $5: a bool, a texture or a storage buffer is a field of the parameter struct itself",
		explain = "A struct nested inside a stage's parameter struct contains a bool, a texture or a storage buffer. It is raised by the shader compiler on a .gpu.zap module passed to shader(...); the parameter block only stores bools at its top level, and textures and buffers get bindings of their own only as direct fields. Move that field up into the parameter struct itself, or use an i32 instead of the bool.",
		example = """
			# post/post.gpu.zap, given to shader(...)
			pub type Light:
				on bool
				color Vec4

			pub type Params:
				light Light

			pub fn pixel(uv Vec2, p Params) Vec4:
				p.light.color
			"""
	),
	NamedError(
		name = "VertexStageParameters",
		text = "a vertex stage takes its vertex, then its instance or its parameters, or both: fn vertex(v Vertex, i Instance, p Params)",
		explain = "The vertex stage function has no parameters or more than three. It is raised by the shader compiler on a .gpu.zap module passed to shader(...); a vertex stage reads its vertex first, then optionally its instance and its parameter struct, in that order. Declare it as `fn vertex(v Vertex)`, `fn vertex(v Vertex, p Params)` or `fn vertex(v Vertex, i Instance, p Params)`.",
		example = """
			# post/post.gpu.zap, given to shader(...)
			pub fn vertex() Vec4:
				Vec4(0.0, 0.0, 0.0, 1.0)

			pub fn pixel() Vec4:
				Vec4(1.0, 1.0, 1.0, 1.0)
			"""
	),
	NamedError(
		name = "VertexStageInput",
		text = "a vertex stage's $1 is a struct of attributes or an i32 (its number), not $2",
		explain = "The vertex stage's vertex (or instance) parameter is neither a struct of attributes nor an i32 vertex number. It is raised by the shader compiler on a .gpu.zap module passed to shader(...); each field of that struct becomes one vertex attribute at its own location. Wrap the attributes in a struct (`type Vertex:` with a `position Vec3` field), or take an `i32` to draw without vertex buffers.",
		example = """
			# post/post.gpu.zap, given to shader(...)
			pub fn vertex(v Vec3) Vec4:
				v.withW(1.0)

			pub fn pixel() Vec4:
				Vec4(1.0, 1.0, 1.0, 1.0)
			"""
	),
	NamedError(
		name = "VertexAttribute",
		text = "$1.$2 is a $3: an attribute is a number or a vector of f32, i32 or u32",
		explain = "A field of the vertex (or instance) struct is not a number or a vector of f32, i32 or u32, for example a matrix or a fixed array. It is raised by the shader compiler on a .gpu.zap module passed to shader(...); each field is a single attribute read from the vertex buffer. Split a matrix into Vec4 columns and arrays into separate fields.",
		example = """
			# post/post.gpu.zap, given to shader(...)
			pub type Vertex:
				position Vec3
				transform Mat4

			pub fn vertex(v Vertex) Vec4:
				v.transform @ v.position.withW(1.0)

			pub fn pixel() Vec4:
				Vec4(1.0, 1.0, 1.0, 1.0)
			"""
	),
	NamedError(
		name = "PixelStageInputFirst",
		text = "the pixel stage takes what the vertex stage gives after the position first",
		explain = "The vertex stage passes values on to the pixel stage, but the pixel stage takes no parameters to receive them. It is raised by the shader compiler on a .gpu.zap module passed to shader(...) with both stages. Add the type the vertex stage gives after the position as the pixel stage's first parameter: `fn pixel(b Between)`.",
		example = """
			# post/post.gpu.zap, given to shader(...)
			pub fn vertex(v i32) (Vec4, Vec2):
				(Vec4(0.0, 0.0, 0.0, 1.0), Vec2(0.0, 0.0))

			pub fn pixel() Vec4:
				Vec4(1.0, 1.0, 1.0, 1.0)
			"""
	),
	NamedError(
		name = "PixelStageInput",
		text = "the pixel stage takes a $1 first, what the vertex stage gives after the position, not a $2",
		explain = "The vertex stage passes on a single value, and the pixel stage's first parameter has a different type. It is raised by the shader compiler on a .gpu.zap module passed to shader(...); the value the rasterizer interpolates must be received with exactly the type it was sent with. Make the pixel stage's first parameter the same type as the second element of the vertex stage's result.",
		example = """
			# post/post.gpu.zap, given to shader(...)
			pub fn vertex(v i32) (Vec4, Vec2):
				(Vec4(0.0, 0.0, 0.0, 1.0), Vec2(0.0, 0.0))

			pub fn pixel(uv Vec3) Vec4:
				uv.withW(1.0)
			"""
	),
	NamedError(
		name = "PixelStageInputDiffers",
		text = "the pixel stage's $1 is not the $2 the vertex stage gives: their fields differ",
		explain = "The pixel stage takes a struct whose fields differ, in names, types or order, from the struct the vertex stage passes on. It is raised by the shader compiler on a .gpu.zap module passed to shader(...); each field is linked to the vertex output of the same name, so they must match exactly. Use the same struct type in both stages.",
		example = """
			# post/post.gpu.zap, given to shader(...)
			type Between:
				uv Vec2

			type Other:
				color Vec4

			pub fn vertex(v i32) (Vec4, Between):
				(Vec4(0.0, 0.0, 0.0, 1.0), Between(uv = Vec2(0.0, 0.0)))

			pub fn pixel(b Other) Vec4:
				b.color
			"""
	),
	NamedError(
		name = "PixelStageParameters",
		text = "a pixel stage takes what the vertex stage gives, then its parameters: fn pixel(b Between, p Params)",
		explain = "The pixel stage takes more parameters than what the vertex stage passes on plus one parameter struct. It is raised by the shader compiler on a .gpu.zap module passed to shader(...). Put every extra value into the parameter struct and declare the stage as `fn pixel(b Between, p Params)`.",
		example = """
			# post/post.gpu.zap, given to shader(...)
			pub type Params:
				tint Vec4

			pub fn pixel(uv Vec2, p Params, q Params) Vec4:
				p.tint * q.tint
			"""
	),
	NamedError(
		name = "StageParameters",
		text = "a stage's parameters are a struct, not $1",
		explain = "A stage's parameters argument is not a struct, for example a lone f32 or an array. It is raised by the shader compiler on a .gpu.zap module passed to shader(...); the parameters become one uniform block plus texture and buffer bindings, laid out from the struct's fields. Wrap the values in a struct (`type Params:` with a `scale f32` field) and take that.",
		example = """
			# post/post.gpu.zap, given to shader(...)
			pub type Vertex:
				position Vec3

			pub fn vertex(v Vertex, scale f32) Vec4:
				(v.position * scale).withW(1.0)

			pub fn pixel() Vec4:
				Vec4(1.0, 1.0, 1.0, 1.0)
			"""
	),
	NamedError(
		name = "ShaderNoField",
		text = "$1 has no field '$2'",
		explain = "A stage read `p.name` from its parameter struct, but the struct has no field of that name. It is raised by the shader compiler on a .gpu.zap module passed to shader(...); the language checker normally reports an unknown field first, so this guards the rewrite of parameter reads into block members. Read a field the struct declares, or add it to the struct."
	),
	NamedError(
		name = "StageParametersRead",
		text = "'$1' is the program's parameters: read its fields (a function given it takes the struct too)",
		explain = "A stage or one of its helpers used its parameter struct as a whole value, for example binding it to another name. It is raised by the shader compiler on a .gpu.zap module passed to shader(...); the parameters are not a value on the GPU, each `p.field` is rewritten to read its block member or binding in place. Read the fields you need, or pass `p` straight to a helper declared to take the same struct.",
		example = """
			# post/post.gpu.zap, given to shader(...)
			pub type Params:
				tint Vec4

			pub fn pixel(uv Vec2, p Params) Vec4:
				q = p
				q.tint
			"""
	),
	NamedError(
		name = "VertexStageResult",
		text = "a vertex stage gives its clip position (Vec4), or that and what the pixel stage reads: (Vec4, Between)",
		explain = "The vertex stage returns something other than its clip position (a Vec4) or a pair of that position and what it passes on. It is raised by the shader compiler on a .gpu.zap module passed to shader(...). Return `Vec4`, or `(Vec4, Between)` with the position first.",
		example = """
			# post/post.gpu.zap, given to shader(...)
			pub fn vertex(v i32) Vec3:
				Vec3(0.0, 0.0, 0.0)

			pub fn pixel() Vec4:
				Vec4(1.0, 1.0, 1.0, 1.0)
			"""
	),
	NamedError(
		name = "VertexOutputField",
		text = "$1.$2 is a $3: what the vertex stage passes on is numbers and vectors",
		explain = "A field of the struct the vertex stage passes on is not a number or a vector, such as a bool, a matrix or an array. It is raised by the shader compiler on a .gpu.zap module passed to shader(...); each field becomes one interpolated output, which only numbers and vectors can be. Store a bool as an i32 and split matrices or arrays into vector fields.",
		example = """
			# post/post.gpu.zap, given to shader(...)
			type Between:
				lit bool

			pub fn vertex(v i32) (Vec4, Between):
				(Vec4(0.0, 0.0, 0.0, 1.0), Between(lit = true))

			pub fn pixel(b Between) Vec4:
				Vec4(1.0, 1.0, 1.0, 1.0)
			"""
	),
	NamedError(
		name = "VertexOutput",
		text = "what the vertex stage passes on is a struct of numbers and vectors, or one, not $1",
		explain = "The single value the vertex stage passes on is not a number, a vector, or a struct of them, for example a bool or a matrix. It is raised by the shader compiler on a .gpu.zap module passed to shader(...); it becomes an interpolated output to the pixel stage. Pass a number or a vector, or a struct of those.",
		example = """
			# post/post.gpu.zap, given to shader(...)
			pub fn vertex(v i32) (Vec4, bool):
				(Vec4(0.0, 0.0, 0.0, 1.0), true)

			pub fn pixel(b bool) Vec4:
				Vec4(1.0, 1.0, 1.0, 1.0)
			"""
	),
	NamedError(
		name = "PixelStageResult",
		text = "a pixel stage gives a color (Vec4), a struct of its targets' colors and its depth, or nothing",
		explain = "The pixel stage returns something other than a color, a struct of outputs, or nothing, for example a Vec3 or a tuple. It is raised by the shader compiler on a .gpu.zap module passed to shader(...); its result is written to the render targets. Return a Vec4 (use `.withW(1.0)` on a Vec3), a struct of a Vec4 per target (and an f32, the depth), or nothing when it only discards.",
		example = """
			# post/post.gpu.zap, given to shader(...)
			pub fn pixel(uv Vec2) Vec3:
				Vec3(uv.x, uv.y, 0.0)
			"""
	),
	NamedError(
		name = "PixelTargetType",
		text = "$1.$2 is a $3: a target's color is a Vec4, the depth an f32",
		explain = "The pixel stage returns a struct of outputs with a field that is neither a Vec4, a target's color, nor an f32, the depth. It is raised by the shader compiler on a .gpu.zap module passed to shader(...); each Vec4 field is written to one render target, the f32 to the depth. Make every color field a Vec4.",
		example = """
			# post/post.gpu.zap, given to shader(...)
			type Targets:
				color Vec3

			pub fn pixel(uv Vec2) Targets:
				Targets(color = Vec3(uv.x, uv.y, 0.0))
			"""
	),
	NamedError(
		name = "PixelOutputTwice",
		text = "$1.$2 writes $3, which another field writes",
		explain = "Two fields of a pixel stage's struct of outputs write the same place: two f32 fields (the depth is one), or two Vec4 fields on one target. A Vec4 field writes the target its place among the struct's Vec4 fields names, or N when it is named `targetN` (N from 0 to 7), so `color` first and `target0` both write target 0. Rename the field or drop one.",
		example = """
			# post/post.gpu.zap, given to shader(...)
			type Targets:
				color Vec4
				target0 Vec4

			pub fn pixel(uv Vec2) Targets:
				Targets(color = Vec4(uv.x, uv.y, 0.0, 1.0), target0 = Vec4(1.0, 1.0, 1.0, 1.0))
			"""
	),
	NamedError(
		name = "ShaderUnknownType",
		text = "unknown type '$1'",
		explain = "A type name in the lowered GPU code is not a GPU number, vector, matrix, texture kind or a struct of the stage. It is raised by the shader compiler on a .gpu.zap module passed to shader(...) and is an internal guard: the GPU lowering refuses unsupported types first (GpuType). Use only types a GPU function can hold."
	),
	NamedError(
		name = "ChangeWhileBorrowed",
		text = "cannot change '$1' while '$2' borrows it (borrowed at line $3, still used at line $4): read what is needed from '$2' before the change, read it again after the change, or bind '$2' to a value of its own (.copy())",
		explain = "A value was changed while a reference into it (an explicit `ref`, a struct field holding a ref, a lambda capture, or a value like `xs.first`) is still used later. The change could move or free what the reference points to. Read what you need before the change, look it up again after, or take an owned copy with `.copy()`."
	),
	NamedError(
		name = "ChangeWhileRead",
		text = "cannot change '$1' while $2, reading '$3' in place: collect the changes and apply them after it",
		explain = "A list (or other value) is changed while a loop, a pipeline lambda, or a generator is reading it in place, for example pushing to xs inside `for x in xs.filter(...)`. The iteration reads the elements without copying, so changing the collection under it is refused. Collect the changes in another list and apply them after the loop."
	),
	NamedError(
		name = "GivenAwayInLoop",
		text = "'$1' is given away inside a loop, but the next iteration reads it again: give it away after the loop, give it a new value in each iteration before it is read, or give away a value of its own ($1.copy())",
		explain = "A value is moved (given away) inside a loop body, but the next iteration would read it again. After the first iteration it would no longer exist. Move it after the loop, give the variable a fresh value in each iteration before it is read, or give away a copy with `.copy()`."
	),
	NamedError(
		name = "NamedAfterBase",
		text = "after ..base the fields that differ are named: field = value",
		explain = "A struct value built from a base (`T(..base, ...)`) has an unnamed value after the base. With `..base` every other field comes from the base, so the ones that differ must say which field they replace. Write them as `field = value`.",
		example = """
			type Point:
				x i64
				y i64

			a = Point(x = 1, y = 2)
			b = Point(..a, 5)
			print(b.x)
			"""
	),
	NamedError(
		name = "ValueAfterNamed",
		text = "a value without its name comes before the named ones",
		explain = "A struct's value or a call's argument without a name follows one that has a name. Values by position fill the fields or parameters in order, which is ambiguous once names have started. Put the values by position first, or name every value after the first named one."
	),
	NamedError(
		name = "AmbiguousCall",
		text = "'$1' is both a method of $2 and $3: write self.$1(...) for the method, or $4",
		explain = "Inside a method, a bare call names both a method of the receiver's type and a top-level or built-in function. A reader cannot tell which one is meant, so neither is picked. Write `self.name(...)` for the method, or rename one of the two."
	),
	NamedError(
		name = "ItIsNoName",
		text = "it stands for a call argument's value: a binding takes another name",
		explain = "A binding or a parameter was named `it`. `it` is reserved for the argument of a shorthand lambda (`xs.map(it * 2)`), so it cannot also be an ordinary name. Choose another name."
	),
	NamedError(
		name = "UseNotFirst",
		text = "`use` is the first line of its scope: a file (after its imports), a function or a block",
		explain = "A `use` directive (such as `use fusedMultiplyAdd`) appears after other statements in its scope. It changes how the whole scope compiles, so it must come first: at the top of a file after its imports, or as the first line of a function or block. Move it up."
	),
	NamedError(
		name = "UntoldList",
		text = "'$1' is read before its element type is told: write it, `$1 T[] = []`",
		explain = "An empty list was read (iterated, indexed, or used in an expression) before its element type was known. `mut xs = []` gets its type from a later push or use, but reading it earlier gives nothing to check against. Write the type on the binding (`mut xs i64[] = []`) or push before reading."
	),
	NamedError(
		name = "MultiplyAdd",
		text = "a multiply and an add are written as they read (x * y + z): `use fusedMultiplyAdd` as the first line of the file, the function or the block rounds them once",
		explain = "The program called mulAdd, mulSub or subMul directly. A fused multiply-add is written as the plain expression `x * y + z`; adding `use fusedMultiplyAdd` at the top of the file, function or block makes the compiler round such expressions once. Write the arithmetic as it reads and add the `use` line where fusion is wanted."
	),
	NamedError(
		name = "ParallelRangeBounds",
		text = "a parallel pipeline reads the bounds of its range once for each part: bind a bound that calls a function to a name first",
		explain = "A parallel pipeline runs over a range whose bound calls a function, as in `(0..top()).parallel()`. Each parallel part reads the bounds again, so the function would run several times. Bind the bound to a name first (`n = top()`) and use `0..n`."
	),
	NamedError(
		name = "StrNotInPlace",
		text = "a str cannot be changed in place (build the bytes in a u8[] and make it a str with str(move bytes))",
		explain = "A character of a str was assigned through an index (`s[i] = ...`). Strings are immutable UTF-8 text and cannot be changed in place. Build the bytes in a `u8[]`, change them there, and turn them into a str with `str(move bytes)`.",
		example = """
			mut s = "abc"
			s[0] = 'x'
			print(s)
			"""
	),
	NamedError(
		name = "UnreadTest",
		text = "'$1' is never read: a test for a value is written opt != none",
		explain = "An optional was tested with `if o is x:` but x is never read. When only presence matters, binding a name is noise. Write the test as `if o != none:`."
	),
	NamedError(
		name = "MapTypeArity",
		text = r"a map has a key type and a value type: {K: V}",
		explain = r"The map type was written as a bare `Map` (or with the wrong number of type arguments). A map type needs both a key type and a value type, and is spelled with braces. Write `{K: V}`, such as `{str: i64}`.",
		example = r"""
			m Map = {"a": 1}
			print(m)
			"""
	),
	NamedError(
		name = "UntypedEmptyMap",
		text = r"no use decides the type of '$1': write it, `$1 {K: V} = {}`",
		explain = r"An empty map literal `{}` is bound to a name, and nothing tells its key and value types. Unlike an empty list, an empty map does not wait for later uses to learn its type. Annotate the binding, as in `mut counts {str: i64} = {}`, or pass it where a map type is expected.",
		example = r"""
			mut counts = {}
			counts["a"] = 1
			print(counts)
			"""
	),
	NamedError(
		name = "UntypedEmptyMapLiteral",
		text = r"empty map literal needs a type annotation (e.g. scores {str: i32} = {})",
		explain = r"An empty map literal `{}` appears where nothing tells its key and value types. Pass it where a map type is expected, or bind it with its type, as in `counts {str: i64} = {}`.",
		example = r"""
			print({}.len)
			"""
	),
	NamedError(
		name = "ParallelStartsPipeline",
		text = r"parallel() starts a pipeline: xs.parallel().map(f), xs.parallel().filter(p).sum(f), for x in xs.parallel() { ... }",
		explain = "`parallel()` was used on its own, bound to a name or not followed by a pipeline step or a for loop. It only marks the start of a parallel pipeline and has no value by itself. Chain the steps directly, as in `xs.parallel().map(f)` or `for x in xs.parallel():`."
	),
	NamedError(
		name = "ParallelEachParams",
		text = "each after parallel() takes a lambda of one parameter: the element",
		explain = "`xs.parallel().each(f)` runs f on every processor, the elements in no order, so f has no index to count by. Write `xs.parallel().each(x: ...)`, or `for i in (0..xs.len).parallel()` to work by index."
	),
	NamedError(
		name = "ParallelEachSource",
		text = "each after parallel() takes the list or range itself: put the filter and the map inside f",
		explain = "`xs.parallel().each(f)` runs f on every processor over the elements of `xs`. Steps between `parallel()` and `each` are not folded into it; write them as an `if` and a `let` in f's body."
	),
	NamedError(
		name = "NoEntryPoint",
		text = "no entry point: a program is a file with statements at its top level",
		explain = "The program file has declarations but no top-level statements. A Zap program is the statements at the top level of its file, so with none there is nothing to run. Add the statements that should run, outdented at the top level."
	),
	NamedError(
		name = "BackendRefused",
		text = "$1: the intermediate form cannot take it: $2",
		explain = "The IR backend, the only code generator for the CPU, could not lower a function; the message names the function and the construct that failed. This is a limitation of the compiler, not an error in the program, and is reported as a build error rather than silently miscompiled. Rewrite the named function to avoid that construct and report the case."
	),
	NamedError(
		name = "OwnershipBroken",
		text = "$1: after $2, the intermediate form's ownership is broken: $3",
		explain = "The ownership verifier of the intermediate form (irown.zap) found a value that owns memory used after it was consumed, consumed twice, never consumed (a leak), or a borrow used past its owner, after the named pass of the compiler. This is a bug of the compiler, not of the program: the build stops rather than emit code that may free memory twice or leak it. Report the case with the function and the pass named."
	),
	NamedError(
		name = "InRangeNeedsName",
		text = "x in lo..hi reads x twice (lo <= x and x < hi): x is a name, a field or a literal; bind the value to a name first",
		explain = "`x in lo..hi` was used with x being a computed expression, such as a call or arithmetic. The test reads x twice (`lo <= x and x < hi`), which would evaluate it twice. Bind the value to a name first (`v = n + 1`) and test `v in 0..n`."
	),
	NamedError(
		name = "MarkupUnclosed",
		text = "<$1> is never closed (write </$1>, or end the tag with />)",
		explain = "A .zapx file reached its end inside markup: an element opened by a tag has no closing tag. Every element is closed by `</tag>` or written self-closing (`<tag />`); only the void elements of HTML (`<br>`, `<img>`) end with their tag. Close the element where its children end.",
		example = """
			x = <div>
				<b>a</b>
			print(x.render())
			"""
	),
	NamedError(
		name = "MarkupMismatch",
		text = "</$1> closes <$2>, opened at line $3",
		explain = "A closing tag names another element than the one open, as in `<p><b>x</p>`. Elements nest: the innermost one closes first. Close the inner element before the outer one, or fix the tag's name."
	),
	NamedError(
		name = "MarkupCloseTag",
		text = "the closing tag </$1 ends with '>'",
		explain = "A closing tag holds only its element's name, as in `</div>`; attributes and other text belong to the opening tag. End the closing tag with `>` right after the name.",
		example = """
			print(<p>a</p class="x">.render())
			"""
	),
	NamedError(
		name = "MarkupTagCharacter",
		text = "unexpected '$1' in the tag <$2>: a tag holds attributes (name, name=\"text\", name=\{value}) and ends with > or />",
		explain = "Inside a tag the markup reads attributes up to the tag's end: a name alone, a name with a string (`class=\"x\"`) or with a value in braces (`data-n=\{n}`). Anything else there is an error. Quote the text or put the value in braces, and end the tag with `>` or `/>`.",
		example = """
			print(<p $x />.render())
			"""
	),
	NamedError(
		name = "MarkupBrace",
		text = "a '}' in markup text closes nothing: write \{\"}\"} for the character",
		explain = "Between tags, `\{` opens a Zap expression and `}` closes it, so a lone `}` in text is a mistake, usually a brace too many. Remove it, or write the character as the string `\{\"}\"}`.",
		example = """
			print(<p>a } b</p>.render())
			"""
	),
	NamedError(
		name = "MarkupAttributeValue",
		text = "the attribute '$1' takes a string or a value in braces: $1=\"text\" or $1=\{value}",
		explain = "After an attribute's `=` comes its value: a string literal (`class=\"x\"`, with interpolation) or a Zap expression in braces (`data-n=\{n}`). Write the value in one of the two forms.",
		example = """
			print(<p width=3 />.render())
			"""
	),
	NamedError(
		name = "MarkupDuplicateAttribute",
		text = "the attribute '$1' is given twice",
		explain = "A tag names the same attribute twice, and only one value can be its. Keep one, or join the values (`class=\"a b\"`).",
		example = """
			print(<p class="a" class="b" />.render())
			"""
	),
	NamedError(
		name = "MarkupChildType",
		text = "a child of markup is a Node, a list of them, a str or a number, not $1",
		explain = "A value in braces between tags becomes a child of the element: a `Node` (an element, a component's result), a list of nodes, or text (a `str`, or a number written as text). Another type has no text of its own. Make it one of these, such as a string interpolating it (`\{\"\{x}\"}`)."
	),
	NamedError(
		name = "MarkupAttributeType",
		text = "the attribute '$1' is a str, a number or a bool, not $2",
		explain = "An element's attribute holds text: a value in braces is a `str`, a number (written as text) or a `bool` (written bare when true, left out when false). Convert another type to a string first.",
		example = r"""
			print(<p title={[1]} />.render())
			"""
	),
	NamedError(
		name = "MarkupForName",
		text = r"a markup for names one element: {for x in xs: ...}",
		explain = "A `for` in markup braces makes a child of each element it walks, the body's value, and binds one name, the element (it is the `map` of a pipeline, 7.2). Walk the indices with a range (`for i in 0..xs.len:`) when the body needs them."
)]

# The message of the named error with its parts, led by its code ("error[code]: message"), which
# errorAtFile shows
pub fn compileError(name str, parts str[]) str:
	text = ""
	for e in compileErrors:
		if e.name == name:
			text = e.text.copy()
	if text == "":
		fail("no compile error is named {name}")
	for i, part in parts:
		text = text.replace("${i + 1}", part)
	"error[{kebabCase(name)}]: {text}"

# whether a compile error has that name
pub fn isCompileError(name str) bool:
	compileErrors.any(.name == name)

# the names of the compile errors, for a message about one that does not exist
pub fn compileErrorNames() str:
	compileErrors.map(.name).join(", ")

# a message's code and its text: ("assign-immutable", "cannot ...") from compileError's form, or
# ("", msg) for an error without a name
pub fn errorCode(msg str) (str, str):
	if msg.startsWith("error[") and msg.indexOf("]: ") is end:
		return (msg[6..end].copy(), msg[end + 3..].copy())
	("", msg.copy())

# AssignImmutable gives assign-immutable
pub fn kebabCase(name str) str:
	out = []
	for i, b in name.bytes():
		if b >= 'A' and b <= 'Z':
			if i > 0:
				out.push('-')
			out.push(b + 32)
		else:
			out.push(b)
	str(out)
