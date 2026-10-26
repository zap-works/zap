// exprTree: n generated lines of arithmetic (+, -, *, unary minus, parentheses), each parsed by
// recursive descent into a tree and evaluated modulo 1000000007; prints the text's size, the
// nodes made and the sum of the values.
use std::fmt::Write;

const MOD: i64 = 1000000007;

enum Expr {
    Num(i64),
    Neg(Box<Expr>),
    Add(Box<Expr>, Box<Expr>),
    Sub(Box<Expr>, Box<Expr>),
    Mul(Box<Expr>, Box<Expr>),
}

impl Expr {
    fn eval(&self) -> i64 {
        match self {
            Expr::Num(v) => *v,
            Expr::Neg(a) => (MOD - a.eval()) % MOD,
            Expr::Add(a, b) => (a.eval() + b.eval()) % MOD,
            Expr::Sub(a, b) => (a.eval() - b.eval() + MOD) % MOD,
            Expr::Mul(a, b) => a.eval() * b.eval() % MOD,
        }
    }
}

struct Generator {
    state: u64,
    text: String,
}

impl Generator {
    // the next number, 31 bits
    fn next(&mut self) -> u64 {
        self.state = self.state.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        self.state >> 33
    }

    fn expr(&mut self, depth: u32) {
        let terms = 1 + self.next() % 3;
        for i in 0..terms {
            if i > 0 {
                let op = if self.next() % 2 == 1 { " + " } else { " - " };
                self.text.push_str(op);
            }
            self.term(depth);
        }
    }

    fn term(&mut self, depth: u32) {
        let factors = 1 + self.next() % 3;
        for i in 0..factors {
            if i > 0 {
                self.text.push_str(" * ");
            }
            self.factor(depth);
        }
    }

    fn factor(&mut self, depth: u32) {
        let r = self.next() % 10;
        if depth > 0 && r < 4 {
            self.text.push('(');
            self.expr(depth - 1);
            self.text.push(')');
        } else if r == 4 {
            self.text.push('-');
            self.factor(depth);
        } else {
            let value = self.next() % 1000;
            write!(self.text, "{}", value).unwrap();
        }
    }
}

struct Parser<'a> {
    text: &'a [u8],
    at: usize,
    nodes: i64,
}

impl Parser<'_> {
    fn peek(&self, offset: usize) -> u8 {
        *self.text.get(self.at + offset).unwrap_or(&0)
    }

    fn expr(&mut self) -> Expr {
        let mut left = self.term();
        while self.peek(0) == b' ' && (self.peek(1) == b'+' || self.peek(1) == b'-') {
            let op = self.peek(1);
            self.at += 3;
            let right = Box::new(self.term());
            left = if op == b'+' { Expr::Add(Box::new(left), right) } else { Expr::Sub(Box::new(left), right) };
            self.nodes += 1;
        }
        left
    }

    fn term(&mut self) -> Expr {
        let mut left = self.factor();
        while self.peek(0) == b' ' && self.peek(1) == b'*' {
            self.at += 3;
            left = Expr::Mul(Box::new(left), Box::new(self.factor()));
            self.nodes += 1;
        }
        left
    }

    fn factor(&mut self) -> Expr {
        match self.peek(0) {
            b'(' => {
                self.at += 1;
                let inner = self.expr();
                self.at += 1; // the ')'
                inner
            }
            b'-' => {
                self.at += 1;
                self.nodes += 1;
                Expr::Neg(Box::new(self.factor()))
            }
            _ => {
                let mut value = 0;
                while self.peek(0).is_ascii_digit() {
                    value = value * 10 + (self.peek(0) - b'0') as i64;
                    self.at += 1;
                }
                self.nodes += 1;
                Expr::Num(value)
            }
        }
    }
}

fn main() {
    let n: usize = std::env::args().nth(1).and_then(|a| a.parse().ok()).unwrap_or(100);
    let mut generator = Generator { state: 1, text: String::new() };
    for _ in 0..n {
        generator.expr(8);
        generator.text.push('\n');
    }
    let text = generator.text;
    let mut parser = Parser { text: text.as_bytes(), at: 0, nodes: 0 };
    let mut sum = 0;
    for _ in 0..n {
        let tree = parser.expr();
        parser.at += 1; // the line break
        sum = (sum + tree.eval()) % MOD;
    }
    println!("{} bytes, {} nodes, sum {}", text.len(), parser.nodes, sum);
}
