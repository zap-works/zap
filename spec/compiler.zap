# 14.2 Compiler
#
# The compiler is written in Zap and compiles itself; the parser is hand-written recursive descent.
# The pipeline is lexer, parser, checker (types, generics, ownership), layouts, the intermediate
# form (`ir.zap`: blocks of instructions over virtual registers, lowered from the checked tree,
# simplified, given registers), x64 code, PE file. A function the intermediate form cannot lower
# fails the build, naming it. The checker makes each type once (`types.zap`: the same parts give
# the same id) and each generic instance once, found by its arguments' ids.
#
# A build loads the program's own modules first, then the runtime's dirs they reach (8, *The
# prelude*), put before them. What each dir declares and names is an index made once for the
# compiler and the runtime's sources and kept under their stamp in `build/cache/`; the forms the
# compiler lowers to a dir's functions besides core are one table (`driver/runtimedirs.zap`). A
# dir of the core never names another dir's declaration: what the core does with a feature's
# state goes through a hook the feature sets (`threadsEnd`, set when the first thread starts).
#
# The checker checks a program in stages, each alone after the stages before it: the runtime's
# core, each other dir it loads after the dirs that dir reads, each std module after those it
# imports, then the program's own modules; then what reads the whole program (the effects, the
# order of main's statements). A stage's declarations, instances and types are numbered as they
# are whatever stages come after it, so a program that reaches every dir compiles to the bytes a
# check of the whole runtime gives.
#
# The intermediate form states where each owner begins and ends (`irOwn`, `irOwnEnd`), and a
# verifier (`irown.zap`) follows each one along every path: a leak, a double free, a read of a
# consumed value or a borrow read after its owner is consumed fails the build (`OwnershipBroken`),
# naming the function and the pass after which it showed (`ZAP_RUN=irown`).
#
# Printing, JSON and binary encoding are Zap functions the compiler writes per type (`derive.zap`)
# over typed pieces of the runtime (`runtime/core/value.zap`); nothing reads a type description at run
# time.
#
# What each type is in memory:
# - `i8`..`u64`, `f32`, `f64`, `bool`: their natural width; `bool` one byte.
# - `str`: `{ ptr, len, cap }`, 24 bytes; `cap` 0 for bytes not owned (literals live in the image).
#   A str of up to 22 bytes made at run time is short: its bytes in those 24, a NUL after them, its
#   last byte 128 + its length (`cap` negative), no block of its own; a window (`ref str`) is
#   `{ ptr, len }`, and a short str seen through one points into the str itself.
# - `T[]`: `{ ptr, len, cap }` over a contiguous block of `T`.
# - `{K: V}`: a pointer to a table, entry lists and an open-addressing index.
# - a struct: its fields widest alignment first (those of one alignment in their order), each at
#   its alignment, aligned as its widest field (a `Vec3` of `f32` is 12 bytes at 4; `{a u8, b i64,
#   c u8}` is 16 bytes). An `extern type`'s fields and a GPU file's structs' stay in their order,
#   as C and the shaders lay them out.
# - an enum: a tag, the variant's number (a byte up to 255 variants, two up to 65,535, four past
#   that or in a GPU file), then each variant's values, narrowest first; an enum whose variants
#   carry nothing is its tag alone (one byte).
# - `T?`: a tag byte (0 none) then `T` at its alignment (`i32?` is 8 bytes), or without a tag `T`
#   alone where `T` has a niche, bytes holding a value no `T` holds there, kept for none: a
#   `bool`'s 2, a range's value outside it, an enum's variant count, the address 0 of a `Box<T>`
#   or a reference, a window's length -1, an optional's tag 2 (`i64??` is 16 bytes), the last byte
#   0xA0 of a `str`'s or a list's `cap`, a struct's first field's with one that owns nothing,
#   else its first owning field's whose none is not zeroes (a `str`'s: a field moved out leaves
#   zeroes, and the struct stays some). An optional of one without a tag takes the niche's next
#   value (`bool??`'s 3, `str??`'s cap byte 0xA1, `i64???`'s tag 3). So `str?`, `T[]?` and `str??`
#   are 24 bytes, `bool?` and `bool??` one, `Handle<T>?` 8, `ref str?` 16, `i64???` 16,
#   `{name str, n i64}?` 32.
# - `T ? E`: a tag byte (1 ok) then `T` or `E` at the larger alignment.
# - `fn(A) R`: `{ code, env }`.
#
# The layout is one function's (`layout.zap`), which code, drops and copies of both machines read;
# a program sees it only in sizes (`byteSize`), never in what it computes.

type Mixed:
	a u8
	b i64
	c u8

type Named:
	name str
	n i64

type Light:
	Off
	On
	Blinking

# an optional of T, so that T can be an optional
fn some<T>(x T) T?:
	x

test "sizes: fields widest first, a tag byte, niches for none":
	print([Mixed(a = 1, b = 2, c = 3)].byteSize)
	ints i32?[] = [1]
	print(ints.byteSize)
	print([Light.On].byteSize)
	texts str?[] = ["a"]
	print(texts.byteSize)
	lists i64[]?[] = [[1]]
	print(lists.byteSize)
	flags bool?[] = [true]
	print(flags.byteSize)
	named Named?[] = [Named(name = "a", n = 1)]
	print(named.byteSize)
	print([some(flags[0])].byteSize)
	print([some(texts[0])].byteSize)
	print([some(some(some(4)))].byteSize)
	prints """
		16
		8
		1
		24
		24
		1
		32
		1
		24
		16
		"""
#
# Arguments go left to right. A function takes them in registers, the integers and addresses in
# four (x64's rcx, rdx, r8, r9; AArch64's x0..x3) and the floats in six (xmm0..xmm5; d0..d5), each
# kind in order: a read aggregate of up to four numbers (a `Vec3`, a `Quat`, a tuple of scalars, an
# optional number) spread over them as its leaves when they all fit in what is left, else as the
# caller's address, as any other read or `mut` aggregate; the words past their kind's registers
# go on the stack, in order. Its result comes back in rax (x0), or an aggregate of two to four
# numbers, at most two of them integers, in rax, rdx and xmm0..xmm3 (x0, x1 and d0..d3). A function
# with a `move` aggregate or a larger result, or used as a value, takes every word on the stack:
# scalars by value, read and `mut` aggregates as the caller's address, `move` aggregates by value,
# and an aggregate result is written through a hidden pointer. An `extern` function keeps the
# platform's C convention. Owned locals

# carry a drop flag cleared on move; temporaries are dropped at the end of their statement (per
# match arm and per conditionally evaluated operand); destruction and deep copies are functions
# generated per type.
