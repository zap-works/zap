# 5.4 Derivatives: `grad`
#
# `grad(f)` is the derivative of function f, which the compiler writes (`compiler/tensors/grad.zap`):
# a function taking f's parameters and giving f's value and its gradient with respect to the first
# parameter, of the first parameter's type. That parameter is a number (a float), a `tensor.Tensor`
# (7.8), or a struct or list made of those (plain data in a struct is carried along unchanged).
# f gives a float or a tensor; for a tensor, its gradient starts as ones (a loss of one number).
# The derivative is reverse mode, written as Zap and checked as any code (ZAP_RUN=derived prints
# it): the body read forward, each value kept, then each operation's derivative last first.

import tensor

fn cubic(x f32):
	x * x * x - 2.0 * x

test "the derivative of a function of a number":
	value, slope = grad(cubic)(2.0)
	expect value == 4
	expect slope == 10

# What it differentiates: bindings and assignments, the math operators on numbers and tensors,
# fields and elements, calls of functions (each differentiated in turn, its derivative a function
# of its own the caller calls), the methods of a number `exp ln sqrt tanh sin cos abs max min` and
# conversions between floats, a tail `if` or `match` (each arm its own forward and backward pass:
# a condition on a value it does not differentiate), and `for` over a list or a range that changes
# values bound before it (each step's start kept; backward, each step computed again from it). A
# function that keeps the derivative's form apart gives its own: `fGrad` of its module, taking f's
# parameters and the gradient of f's value, giving the gradients of f's first tensor parameters,
# as many as it gives (std/tensor's functions all have one). What reads only what is not
# differentiated (the data, the labels, a number given as a constant) is computed as it is.

type Layer:
	w tensor.Tensor
	b tensor.Tensor
	name str = "dense"

fn squaredError(l Layer, x tensor.Tensor, y tensor.Tensor):
	d = x @ l.w + l.b - y
	(d * d).mean()

test "the gradient of a struct of tensors, of the same struct":
	l = Layer(w = tensor.fromList([2, 1], [1.0, -1.0]), b = tensor.zeros([1]))
	x = tensor.fromList([2, 2], [1.0, 2.0, 3.0, 4.0])
	y = tensor.fromList([2, 1], [0.0, 1.0])
	loss, g = grad(squaredError)(l, x, y)
	print("{loss.item()} {g.w.toList()} {g.b.toList()} {g.name}")
	prints "2.5 [-7, -10] [-3] dense"

fn chained(xs f32[], k f32):
	total = 0.0
	for x in xs:
		total = (total + x * k).tanh()
	total

test "a loop over a list, differentiated through every step":
	value, g = grad(chained)([0.5, 1.0, -0.25], 0.8)
	e f32 = 0.001
	numeric = (chained([0.5 + e, 1.0, -0.25], 0.8) - chained([0.5 - e, 1.0, -0.25], 0.8)) /
		(2.0 * e)
	expect g.len == 3
	expect (g[0] - numeric).abs() < 0.001
	expect value == chained([0.5, 1.0, -0.25], 0.8)

test "the first parameter has a gradient" refuses GradParameter:
	fn count(n i64) f32:
		f32(n)
	print(grad(count)(3))

test "the value is a number or a tensor" refuses GradResult:
	fn twice(x f32) (f32, f32):
		(x, x)
	print(grad(twice)(3.0))

test "what it cannot differentiate is refused where it is written" refuses GradUnsupported:
	fn wobble(x f32) f32:
		y = x
		while y < 10.0:
			y = y * 2.0
		y
	print(grad(wobble)(1.0))

# **Optimisers.** For each struct holding tensors (in fields, lists of them, nested structs) the
# compiler writes, in its module, what std/tensor's `Learnable` asks: `tensorCount()`,
# `tensorAt(k)` and `tensorAtMut(k)`, its tensors numbered in the order it declares them (a module
# declaring tensorCount for it writes the three itself). `tensor.Optimiser` (SGD with momentum,
# Adam, AdamW) walks a model and its gradient together, changing each tensor in place.

test "an optimiser fits a layer by its gradients":
	l = Layer(w = tensor.zeros([2, 1]), b = tensor.zeros([1]))
	x = tensor.fromList([3, 2], [1.0, 0.0, 0.0, 1.0, 1.0, 1.0])
	y = tensor.fromList([3, 1], [2.0, -1.0, 1.0])
	opt = tensor.Optimiser(method = .Sgd, rate = 0.2)
	loop 200:
		_, g = grad(squaredError)(l, x, y)
		opt.step(l, g)
	expect l.tensorCount() == 2
	expect (l.w.toList()[0] - 2.0).abs() < 0.01
	expect (l.w.toList()[1] + 1.0).abs() < 0.01
