# exprTree: n generated lines of arithmetic (+, -, *, unary minus, parentheses), each parsed by
# recursive descent into a tree and evaluated modulo 1000000007; prints the text's size, the
# nodes made and the sum of the values.
import problems

modulus = 1_000_000_007

type Expr:
	Num(value i64)
	Neg(arg Box<Expr>)
	Add(left Box<Expr>, right Box<Expr>)
	Sub(left Box<Expr>, right Box<Expr>)
	Mul(left Box<Expr>, right Box<Expr>)

	fn eval() i64:
		match self:
			Num(v): v
			Neg(a): (modulus - a.eval()) % modulus
			Add(a, b): (a.eval() + b.eval()) % modulus
			Sub(a, b): (a.eval() - b.eval() + modulus) % modulus
			Mul(a, b): a.eval() * b.eval() % modulus

type Generator:
	state u64
	text u8[]

	# the next number, 31 bits
	fn next():
		state = state * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407
		state >> 33

	fn expr(depth i64):
		terms = 1 + next() % 3
		term(depth)
		for _ in 1..terms:
			text.extend(" + ".bytes() if next() % 2 == 1 else " - ".bytes())
			term(depth)

	fn term(depth i64):
		factors = 1 + next() % 3
		factor(depth)
		for _ in 1..factors:
			text.extend(" * ".bytes())
			factor(depth)

	fn factor(depth i64):
		r = next() % 10
		if depth > 0 and r < 4:
			text.push('(')
			expr(depth - 1)
			text.push(')')
		elif r == 4:
			text.push('-')
			factor(depth)
		else:
			text.extend("{next() % 1000}".bytes())

type Parser:
	text ref str
	at i64
	nodes i64

	mut fn expr():
		left = term()
		while text[at] == ' ':   # a + or a - (term took every *)
			plus = text[at + 1] == '+'
			at += 3
			right = Box(term())
			left = .Add(Box(left), right) if plus else .Sub(Box(left), right)
			nodes += 1
		left

	mut fn term():
		left = factor()
		while text[at] == ' ' and text[at + 1] == '*':
			at += 3
			left = .Mul(Box(left), Box(factor()))
			nodes += 1
		left

	fn factor() Expr:
		if text[at] == '(':
			at += 1
			inner = expr()
			at += 1   # the ')'
			return inner
		nodes += 1
		if text[at] == '-':
			at += 1
			return .Neg(Box(factor()))
		value = 0
		while text[at] - '0' < 10:   # a digit (below '0' wraps past 9)
			value = value * 10 + (text[at] - '0')
			at += 1
		.Num(value)

n = i64.parse(args.first ?? "100") ?? 100
mut generator = Generator(state = 1, text = [])
loop n:
	generator.expr(8)
	generator.text.push('\n')
text = str(move generator.text)
mut parser = Parser(text, at = 0, nodes = 0)
mut sum = 0
loop n:
	sum = (sum + parser.expr().eval()) % modulus
	parser.at += 1   # the line break
print("{text.len} bytes, {parser.nodes} nodes, sum {sum}")

test "generated lines of arithmetic parse into trees and evaluate modulo 1000000007":
	main()
	prints """
		460681 bytes, 147605 nodes, sum 223470007
		"""

test "the C, Rust and Python programs print the same bytes":
	expect problems.agree("exprTree")
