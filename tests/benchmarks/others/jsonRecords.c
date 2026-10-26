/* jsonRecords: n generated records written as {"records": [...]} and parsed back; prints the
 * JSON's size and byte sum, sums over the parsed records and whether they equal the originals. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

typedef struct {
    int64_t id;
    char *name;
    char *email;
    int64_t score;
    int active;
    size_t tag_count;
    char **tags;
} Record;

typedef struct {
    Record *items;
    size_t len, cap;
} Records;

static const char *tag_names[] = {"red", "green", "blue", "admin", "guest", "beta"};

static uint64_t state = 7;

/* the next number, 31 bits */
static int64_t next(void) {
    state = state * 6364136223846793005ull + 1442695040888963407ull;
    return (int64_t)(state >> 33);
}

static char *copy_of(const char *s, size_t len) {
    char *c = malloc(len + 1);
    memcpy(c, s, len);
    c[len] = 0;
    return c;
}

static void push_record(Records *rs, Record r) {
    if (rs->len == rs->cap) {
        rs->cap = rs->cap ? rs->cap * 2 : 16;
        rs->items = realloc(rs->items, rs->cap * sizeof(Record));
    }
    rs->items[rs->len++] = r;
}

static Records generate(int64_t n) {
    Records rs = {0};
    char word[16], text[64];
    for (int64_t i = 0; i < n; i++) {
        Record r;
        size_t letters = 5 + next() % 8;
        for (size_t k = 0; k < letters; k++)
            word[k] = (char)('a' + next() % 26);
        word[letters] = 0;
        r.id = i;
        r.score = next() % 100000 - 50000;
        r.active = next() % 3 != 0;
        r.tag_count = next() % 4;
        r.tags = malloc(r.tag_count * sizeof(char *) + 1);
        for (size_t t = 0; t < r.tag_count; t++) {
            const char *tag = tag_names[next() % 6];
            r.tags[t] = copy_of(tag, strlen(tag));
        }
        int len = i % 10 == 0 ? snprintf(text, sizeof text, "%s \"jr\"", word) : snprintf(text, sizeof text, "%s", word);
        r.name = copy_of(text, len);
        len = snprintf(text, sizeof text, "%s%lld@mail.test", word, (long long)i);
        r.email = copy_of(text, len);
        push_record(&rs, r);
    }
    return rs;
}

static void free_records(Records *rs) {
    for (size_t i = 0; i < rs->len; i++) {
        Record *r = &rs->items[i];
        free(r->name);
        free(r->email);
        for (size_t t = 0; t < r->tag_count; t++)
            free(r->tags[t]);
        free(r->tags);
    }
    free(rs->items);
}

/* ---------- writing ---------- */

typedef struct {
    char *bytes;
    size_t len, cap;
} Buffer;

static void reserve(Buffer *b, size_t more) {
    if (b->len + more > b->cap) {
        while (b->len + more > b->cap)
            b->cap = b->cap ? b->cap * 2 : 4096;
        b->bytes = realloc(b->bytes, b->cap);
    }
}

static void put(Buffer *b, const char *s, size_t len) {
    reserve(b, len);
    memcpy(b->bytes + b->len, s, len);
    b->len += len;
}

static void put_int(Buffer *b, int64_t v) {
    char digits[24];
    put(b, digits, (size_t)snprintf(digits, sizeof digits, "%lld", (long long)v));
}

/* s as a JSON string: " \ and the control characters escaped */
static void put_string(Buffer *b, const char *s) {
    reserve(b, 1);
    b->bytes[b->len++] = '"';
    for (; *s; s++) {
        unsigned char c = (unsigned char)*s;
        if (c == '"' || c == '\\') {
            char e[2] = {'\\', (char)c};
            put(b, e, 2);
        } else if (c < ' ') {
            char e[8];
            int len = c == '\n' ? snprintf(e, sizeof e, "\\n") : c == '\r' ? snprintf(e, sizeof e, "\\r") : c == '\t' ? snprintf(e, sizeof e, "\\t") : snprintf(e, sizeof e, "\\u%04x", c);
            put(b, e, (size_t)len);
        } else {
            reserve(b, 1);
            b->bytes[b->len++] = (char)c;
        }
    }
    reserve(b, 1);
    b->bytes[b->len++] = '"';
}

#define PUT(b, literal) put(b, literal, sizeof literal - 1)

static void write_records(Buffer *b, const Records *rs) {
    PUT(b, "{\"records\":[");
    for (size_t i = 0; i < rs->len; i++) {
        const Record *r = &rs->items[i];
        if (i)
            PUT(b, ",");
        PUT(b, "{\"id\":");
        put_int(b, r->id);
        PUT(b, ",\"name\":");
        put_string(b, r->name);
        PUT(b, ",\"email\":");
        put_string(b, r->email);
        PUT(b, ",\"score\":");
        put_int(b, r->score);
        if (r->active)
            PUT(b, ",\"active\":true,\"tags\":[");
        else
            PUT(b, ",\"active\":false,\"tags\":[");
        for (size_t t = 0; t < r->tag_count; t++) {
            if (t)
                PUT(b, ",");
            put_string(b, r->tags[t]);
        }
        PUT(b, "]}");
    }
    PUT(b, "]}");
}

/* ---------- reading ---------- */

typedef struct {
    const char *at, *end;
    int failed;
} Parser;

static void space(Parser *p) {
    while (p->at < p->end && (*p->at == ' ' || *p->at == '\n' || *p->at == '\r' || *p->at == '\t'))
        p->at++;
}

/* the byte c next (after white space): consumed when it is */
static int next_is(Parser *p, char c) {
    space(p);
    if (p->at < p->end && *p->at == c) {
        p->at++;
        return 1;
    }
    return 0;
}

static void expect(Parser *p, char c) {
    if (!next_is(p, c))
        p->failed = 1;
}

static int hex_value(char c) {
    return c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
}

/* a string's bytes, unescaped (\u below 0x80 only, as these records hold) */
static char *read_string(Parser *p, size_t *size) {
    expect(p, '"');
    const char *start = p->at;
    while (p->at < p->end && *p->at != '"' && *p->at != '\\')
        p->at++;
    size_t len = (size_t)(p->at - start);
    if (p->at < p->end && *p->at == '"') {
        p->at++;
        if (size)
            *size = len;
        return copy_of(start, len);
    }
    /* an escape: the rest is copied byte by byte */
    size_t cap = len + 16;
    char *s = malloc(cap);
    memcpy(s, start, len);
    while (p->at < p->end && *p->at != '"') {
        if (len + 2 > cap)
            s = realloc(s, cap *= 2);
        char c = *p->at++;
        if (c == '\\' && p->at < p->end) {
            char e = *p->at++;
            if (e == 'n')
                c = '\n';
            else if (e == 'r')
                c = '\r';
            else if (e == 't')
                c = '\t';
            else if (e == 'b')
                c = '\b';
            else if (e == 'f')
                c = '\f';
            else if (e == 'u' && p->end - p->at >= 4) {
                int v = 0;
                for (int k = 0; k < 4; k++)
                    v = v * 16 + hex_value(*p->at++);
                c = (char)v;
            } else
                c = e;
        }
        s[len++] = c;
    }
    if (p->at < p->end)
        p->at++;
    else
        p->failed = 1;
    s[len] = 0;
    if (size)
        *size = len;
    return s;
}

static int64_t read_int(Parser *p) {
    space(p);
    int negative = p->at < p->end && *p->at == '-';
    if (negative)
        p->at++;
    if (p->at >= p->end || *p->at < '0' || *p->at > '9')
        p->failed = 1;
    int64_t v = 0;
    while (p->at < p->end && *p->at >= '0' && *p->at <= '9')
        v = v * 10 + (*p->at++ - '0');
    return negative ? -v : v;
}

static int read_literal(Parser *p, const char *word) {
    space(p);
    size_t len = strlen(word);
    if ((size_t)(p->end - p->at) >= len && memcmp(p->at, word, len) == 0) {
        p->at += len;
        return 1;
    }
    return 0;
}

static int read_bool(Parser *p) {
    if (read_literal(p, "true"))
        return 1;
    if (!read_literal(p, "false"))
        p->failed = 1;
    return 0;
}

static void skip_value(Parser *p) {
    space(p);
    if (p->at >= p->end) {
        p->failed = 1;
    } else if (*p->at == '"') {
        free(read_string(p, NULL));
    } else if (next_is(p, '[')) {
        if (!next_is(p, ']')) {
            do
                skip_value(p);
            while (!p->failed && next_is(p, ','));
            expect(p, ']');
        }
    } else if (next_is(p, '{')) {
        if (!next_is(p, '}')) {
            do {
                free(read_string(p, NULL));
                expect(p, ':');
                skip_value(p);
            } while (!p->failed && next_is(p, ','));
            expect(p, '}');
        }
    } else if (!read_literal(p, "true") && !read_literal(p, "false") && !read_literal(p, "null")) {
        while (p->at < p->end && strchr("+-.0123456789eE", *p->at))
            p->at++;
    }
}

static int key_is(const char *key, size_t len, const char *name) {
    return len == strlen(name) && memcmp(key, name, len) == 0;
}

static Record read_record(Parser *p) {
    Record r = {0};
    int seen = 0;
    expect(p, '{');
    if (!next_is(p, '}')) {
        do {
            size_t len;
            char *key = read_string(p, &len);
            expect(p, ':');
            if (key_is(key, len, "id")) {
                r.id = read_int(p);
                seen |= 1;
            } else if (key_is(key, len, "name")) {
                free(r.name);
                r.name = read_string(p, NULL);
                seen |= 2;
            } else if (key_is(key, len, "email")) {
                free(r.email);
                r.email = read_string(p, NULL);
                seen |= 4;
            } else if (key_is(key, len, "score")) {
                r.score = read_int(p);
                seen |= 8;
            } else if (key_is(key, len, "active")) {
                r.active = read_bool(p);
                seen |= 16;
            } else if (key_is(key, len, "tags")) {
                size_t cap = 4;
                r.tags = malloc(cap * sizeof(char *));
                expect(p, '[');
                if (!next_is(p, ']')) {
                    do {
                        if (r.tag_count == cap)
                            r.tags = realloc(r.tags, (cap *= 2) * sizeof(char *));
                        r.tags[r.tag_count++] = read_string(p, NULL);
                    } while (!p->failed && next_is(p, ','));
                    expect(p, ']');
                }
                seen |= 32;
            } else {
                skip_value(p);
            }
            free(key);
        } while (!p->failed && next_is(p, ','));
        expect(p, '}');
    }
    if (seen != 63)
        p->failed = 1;
    if (!r.tags)
        r.tags = malloc(1);
    if (!r.name)
        r.name = copy_of("", 0);
    if (!r.email)
        r.email = copy_of("", 0);
    return r;
}

static Records read_records(Parser *p) {
    Records rs = {0};
    expect(p, '{');
    if (!next_is(p, '}')) {
        do {
            size_t len;
            char *key = read_string(p, &len);
            expect(p, ':');
            if (key_is(key, len, "records")) {
                expect(p, '[');
                if (!next_is(p, ']')) {
                    do
                        push_record(&rs, read_record(p));
                    while (!p->failed && next_is(p, ','));
                    expect(p, ']');
                }
            } else {
                skip_value(p);
            }
            free(key);
        } while (!p->failed && next_is(p, ','));
        expect(p, '}');
    }
    space(p);
    if (p->at != p->end)
        p->failed = 1;
    return rs;
}

static int same_records(const Records *a, const Records *b) {
    if (a->len != b->len)
        return 0;
    for (size_t i = 0; i < a->len; i++) {
        const Record *x = &a->items[i], *y = &b->items[i];
        if (x->id != y->id || x->score != y->score || x->active != y->active || x->tag_count != y->tag_count || strcmp(x->name, y->name) || strcmp(x->email, y->email))
            return 0;
        for (size_t t = 0; t < x->tag_count; t++)
            if (strcmp(x->tags[t], y->tags[t]))
                return 0;
    }
    return 1;
}

int main(int argc, char **argv) {
#ifdef _WIN32
    _setmode(1, _O_BINARY); /* the runner compares bytes: no CRLF translation */
#endif
    int64_t n = argc > 1 ? atoll(argv[1]) : 100;
    Records records = generate(n);
    Buffer text = {0};
    write_records(&text, &records);
    long long sum = 0;
    for (size_t i = 0; i < text.len; i++)
        sum += (unsigned char)text.bytes[i];
    printf("json %zu bytes, checksum %lld\n", text.len, sum);
    Parser p = {text.bytes, text.bytes + text.len, 0};
    Records back = read_records(&p);
    if (p.failed) {
        free_records(&back);
        back = (Records){0};
    }
    long long scores = 0, active = 0, tags = 0;
    for (size_t i = 0; i < back.len; i++) {
        scores += back.items[i].score;
        active += back.items[i].active;
        tags += (long long)back.items[i].tag_count;
    }
    printf("read %zu records: scores %lld, active %lld, tags %lld, %s\n", back.len, scores, active, tags, same_records(&back, &records) ? "same" : "DIFFERENT");
    free_records(&back);
    free_records(&records);
    free(text.bytes);
    return 0;
}
