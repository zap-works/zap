// exprTree: n generated lines of arithmetic (+, -, *, unary minus, parentheses), each parsed by
// recursive descent into a tree and evaluated modulo 1000000007; prints the text's size, the
// nodes made and the sum of the values.
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <string>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

const int64_t MOD = 1000000007;

struct Node {
    char op; // '0' a number, '~' a negation, or the operator
    int64_t value;
    std::unique_ptr<Node> left, right;

    int64_t eval() const {
        switch (op) {
        case '0':
            return value;
        case '~':
            return (MOD - left->eval()) % MOD;
        case '+':
            return (left->eval() + right->eval()) % MOD;
        case '-':
            return (left->eval() - right->eval() + MOD) % MOD;
        default:
            return left->eval() * right->eval() % MOD;
        }
    }
};

struct Generator {
    uint64_t state = 1;
    std::string text;

    // the next number, 31 bits
    uint64_t next() {
        state = state * 6364136223846793005ull + 1442695040888963407ull;
        return state >> 33;
    }

    void expr(int depth) {
        uint64_t terms = 1 + next() % 3;
        for (uint64_t i = 0; i < terms; i++) {
            if (i > 0)
                text += next() % 2 ? " + " : " - ";
            term(depth);
        }
    }

    void term(int depth) {
        uint64_t factors = 1 + next() % 3;
        for (uint64_t i = 0; i < factors; i++) {
            if (i > 0)
                text += " * ";
            factor(depth);
        }
    }

    void factor(int depth) {
        uint64_t r = next() % 10;
        if (depth > 0 && r < 4) {
            text += '(';
            expr(depth - 1);
            text += ')';
        } else if (r == 4) {
            text += '-';
            factor(depth);
        } else {
            text += std::to_string(next() % 1000);
        }
    }
};

struct Parser {
    const char *at; // the text ends with a 0
    int64_t nodes = 0;

    std::unique_ptr<Node> make(char op, int64_t value, std::unique_ptr<Node> left, std::unique_ptr<Node> right) {
        nodes++;
        return std::unique_ptr<Node>(new Node{op, value, std::move(left), std::move(right)});
    }

    std::unique_ptr<Node> expr() {
        auto left = term();
        while (at[0] == ' ' && (at[1] == '+' || at[1] == '-')) {
            char op = at[1];
            at += 3;
            auto right = term();
            left = make(op, 0, std::move(left), std::move(right));
        }
        return left;
    }

    std::unique_ptr<Node> term() {
        auto left = factor();
        while (at[0] == ' ' && at[1] == '*') {
            at += 3;
            auto right = factor();
            left = make('*', 0, std::move(left), std::move(right));
        }
        return left;
    }

    std::unique_ptr<Node> factor() {
        if (*at == '(') {
            at++;
            auto inner = expr();
            at++; // the ')'
            return inner;
        }
        if (*at == '-') {
            at++;
            return make('~', 0, factor(), nullptr);
        }
        int64_t value = 0;
        while (*at >= '0' && *at <= '9')
            value = value * 10 + (*at++ - '0');
        return make('0', value, nullptr, nullptr);
    }
};

int main(int argc, char **argv) {
#ifdef _WIN32
    _setmode(1, _O_BINARY); // the runner compares bytes: no CRLF translation
#endif
    long long n = argc > 1 ? atoll(argv[1]) : 100;
    Generator generator;
    for (long long i = 0; i < n; i++) {
        generator.expr(8);
        generator.text += '\n';
    }
    Parser parser{generator.text.c_str()};
    int64_t sum = 0;
    for (long long i = 0; i < n; i++) {
        auto tree = parser.expr();
        parser.at++; // the line break
        sum = (sum + tree->eval()) % MOD;
    }
    printf("%zu bytes, %lld nodes, sum %lld\n", generator.text.size(), (long long)parser.nodes, (long long)sum);
    return 0;
}
