# exprTree: n generated lines of arithmetic (+, -, *, unary minus, parentheses), each parsed by
# recursive descent into a tree and evaluated modulo 1000000007; prints the text's size, the
# nodes made and the sum of the values.
import sys

MOD = 1000000007
MASK = (1 << 64) - 1
state = 1
nodes = 0


class Node:
    __slots__ = ("op", "value", "left", "right")

    def __init__(self, op, value, left, right):
        self.op = op
        self.value = value
        self.left = left
        self.right = right


def next_number():
    global state
    state = (state * 6364136223846793005 + 1442695040888963407) & MASK
    return state >> 33


def gen_factor(out, depth):
    r = next_number() % 10
    if depth > 0 and r < 4:
        out.append("(")
        gen_expr(out, depth - 1)
        out.append(")")
    elif r == 4:
        out.append("-")
        gen_factor(out, depth)
    else:
        out.append(str(next_number() % 1000))


def gen_term(out, depth):
    for i in range(1 + next_number() % 3):
        if i > 0:
            out.append(" * ")
        gen_factor(out, depth)


def gen_expr(out, depth):
    for i in range(1 + next_number() % 3):
        if i > 0:
            out.append(" + " if next_number() % 2 else " - ")
        gen_term(out, depth)


def parse_factor(text, at):
    global nodes
    c = text[at]
    if c == "(":
        inner, at = parse_expr(text, at + 1)
        return inner, at + 1
    if c == "-":
        inner, at = parse_factor(text, at + 1)
        nodes += 1
        return Node("~", 0, inner, None), at
    start = at
    while "0" <= text[at] <= "9":
        at += 1
    nodes += 1
    return Node("0", int(text[start:at]), None, None), at


def parse_term(text, at):
    global nodes
    left, at = parse_factor(text, at)
    while text[at] == " " and text[at + 1] == "*":
        right, at = parse_factor(text, at + 3)
        nodes += 1
        left = Node("*", 0, left, right)
    return left, at


def parse_expr(text, at):
    global nodes
    left, at = parse_term(text, at)
    while text[at] == " " and (text[at + 1] == "+" or text[at + 1] == "-"):
        op = text[at + 1]
        right, at = parse_term(text, at + 3)
        nodes += 1
        left = Node(op, 0, left, right)
    return left, at


def evaluate(node):
    op = node.op
    if op == "0":
        return node.value
    if op == "~":
        return (MOD - evaluate(node.left)) % MOD
    if op == "+":
        return (evaluate(node.left) + evaluate(node.right)) % MOD
    if op == "-":
        return (evaluate(node.left) - evaluate(node.right) + MOD) % MOD
    return evaluate(node.left) * evaluate(node.right) % MOD


n = int(sys.argv[1]) if len(sys.argv) > 1 else 100
out = []
for _ in range(n):
    gen_expr(out, 8)
    out.append("\n")
text = "".join(out) + "\0"
total = 0
at = 0
for _ in range(n):
    tree, at = parse_expr(text, at)
    at += 1
    total = (total + evaluate(tree)) % MOD
sys.stdout.buffer.write(b"%d bytes, %d nodes, sum %d\n" % (len(text) - 1, nodes, total))
