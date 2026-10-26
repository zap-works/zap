/* exprTree: n generated lines of arithmetic (+, -, *, unary minus, parentheses), each parsed by
 * recursive descent into a tree and evaluated modulo 1000000007; prints the text's size, the
 * nodes made and the sum of the values. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

#define MOD 1000000007

typedef struct Node {
    char op; /* '0' a number, '~' a negation, or the operator */
    int64_t value;
    struct Node *left, *right;
} Node;

typedef struct {
    char *bytes;
    size_t len, cap;
} Text;

static uint64_t state = 1;

/* the next number, 31 bits */
static uint64_t next(void) {
    state = state * 6364136223846793005ull + 1442695040888963407ull;
    return state >> 33;
}

static void put(Text *t, const char *s, size_t len) {
    if (t->len + len > t->cap) {
        t->cap = t->cap ? t->cap * 2 : 4096;
        t->bytes = realloc(t->bytes, t->cap);
    }
    memcpy(t->bytes + t->len, s, len);
    t->len += len;
}

static void gen_expr(Text *t, int depth);

static void gen_factor(Text *t, int depth) {
    uint64_t r = next() % 10;
    if (depth > 0 && r < 4) {
        put(t, "(", 1);
        gen_expr(t, depth - 1);
        put(t, ")", 1);
    } else if (r == 4) {
        put(t, "-", 1);
        gen_factor(t, depth);
    } else {
        char digits[8];
        put(t, digits, (size_t)sprintf(digits, "%d", (int)(next() % 1000)));
    }
}

static void gen_term(Text *t, int depth) {
    uint64_t factors = 1 + next() % 3;
    for (uint64_t i = 0; i < factors; i++) {
        if (i > 0)
            put(t, " * ", 3);
        gen_factor(t, depth);
    }
}

static void gen_expr(Text *t, int depth) {
    uint64_t terms = 1 + next() % 3;
    for (uint64_t i = 0; i < terms; i++) {
        if (i > 0)
            put(t, next() % 2 ? " + " : " - ", 3);
        gen_term(t, depth);
    }
}

static int64_t nodes = 0;

static Node *node(char op, int64_t value, Node *left, Node *right) {
    Node *n = malloc(sizeof(Node));
    n->op = op;
    n->value = value;
    n->left = left;
    n->right = right;
    nodes++;
    return n;
}

static Node *parse_expr(const char **at);

static Node *parse_factor(const char **at) {
    const char *p = *at;
    if (*p == '(') {
        *at = p + 1;
        Node *inner = parse_expr(at);
        (*at)++; /* the ')' */
        return inner;
    }
    if (*p == '-') {
        *at = p + 1;
        return node('~', 0, parse_factor(at), NULL);
    }
    int64_t value = 0;
    while (*p >= '0' && *p <= '9')
        value = value * 10 + (*p++ - '0');
    *at = p;
    return node('0', value, NULL, NULL);
}

static Node *parse_term(const char **at) {
    Node *left = parse_factor(at);
    while ((*at)[0] == ' ' && (*at)[1] == '*') {
        *at += 3;
        left = node('*', 0, left, parse_factor(at));
    }
    return left;
}

static Node *parse_expr(const char **at) {
    Node *left = parse_term(at);
    while ((*at)[0] == ' ' && ((*at)[1] == '+' || (*at)[1] == '-')) {
        char op = (*at)[1];
        *at += 3;
        left = node(op, 0, left, parse_term(at));
    }
    return left;
}

static int64_t eval(const Node *n) {
    switch (n->op) {
    case '0':
        return n->value;
    case '~':
        return (MOD - eval(n->left)) % MOD;
    case '+':
        return (eval(n->left) + eval(n->right)) % MOD;
    case '-':
        return (eval(n->left) - eval(n->right) + MOD) % MOD;
    default:
        return eval(n->left) * eval(n->right) % MOD;
    }
}

static void release(Node *n) {
    if (n->left)
        release(n->left);
    if (n->right)
        release(n->right);
    free(n);
}

int main(int argc, char **argv) {
#ifdef _WIN32
    _setmode(1, _O_BINARY); /* the runner compares bytes: no CRLF translation */
#endif
    long long n = argc > 1 ? atoll(argv[1]) : 100;
    Text text = {0};
    for (long long i = 0; i < n; i++) {
        gen_expr(&text, 8);
        put(&text, "\n", 1);
    }
    put(&text, "", 1); /* a final 0 ends the last line's scan */
    text.len--;
    int64_t sum = 0;
    const char *at = text.bytes;
    for (long long i = 0; i < n; i++) {
        Node *tree = parse_expr(&at);
        at++; /* the line break */
        sum = (sum + eval(tree)) % MOD;
        release(tree);
    }
    printf("%zu bytes, %lld nodes, sum %lld\n", text.len, (long long)nodes, (long long)sum);
    free(text.bytes);
    return 0;
}
