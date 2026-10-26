// jsonRecords: n generated records written as {"records": [...]} and parsed back; prints the
// JSON's size and byte sum, sums over the parsed records and whether they equal the originals.
#include <charconv>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <string_view>
#include <vector>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

struct Record {
    int64_t id = 0;
    std::string name, email;
    int64_t score = 0;
    bool active = false;
    std::vector<std::string> tags;

    bool operator==(const Record &o) const {
        return id == o.id && name == o.name && email == o.email && score == o.score && active == o.active && tags == o.tags;
    }
};

static constexpr const char *tagNames[] = {"red", "green", "blue", "admin", "guest", "beta"};

class Random {
    uint64_t state = 7;

public:
    // the next number, 31 bits
    int64_t next() {
        state = state * 6364136223846793005ull + 1442695040888963407ull;
        return static_cast<int64_t>(state >> 33);
    }
};

static std::vector<Record> generate(int64_t n) {
    Random random;
    std::vector<Record> records;
    records.reserve(n);
    for (int64_t i = 0; i < n; i++) {
        Record r;
        size_t letters = 5 + random.next() % 8;
        std::string word;
        for (size_t k = 0; k < letters; k++)
            word.push_back(static_cast<char>('a' + random.next() % 26));
        r.id = i;
        r.score = random.next() % 100000 - 50000;
        r.active = random.next() % 3 != 0;
        size_t tagCount = random.next() % 4;
        for (size_t t = 0; t < tagCount; t++)
            r.tags.emplace_back(tagNames[random.next() % 6]);
        r.name = i % 10 == 0 ? word + " \"jr\"" : word;
        r.email = word + std::to_string(i) + "@mail.test";
        records.push_back(std::move(r));
    }
    return records;
}

// ---------- writing ----------

static void putInt(std::string &out, int64_t v) {
    char digits[24];
    auto end = std::to_chars(digits, digits + sizeof digits, v).ptr;
    out.append(digits, end);
}

// s as a JSON string: " \ and the control characters escaped
static void putString(std::string &out, std::string_view s) {
    out.push_back('"');
    for (char ch : s) {
        unsigned char c = static_cast<unsigned char>(ch);
        if (c == '"' || c == '\\') {
            out.push_back('\\');
            out.push_back(ch);
        } else if (c < ' ') {
            if (c == '\n') out += "\\n";
            else if (c == '\r') out += "\\r";
            else if (c == '\t') out += "\\t";
            else {
                char e[8];
                snprintf(e, sizeof e, "\\u%04x", c);
                out += e;
            }
        } else {
            out.push_back(ch);
        }
    }
    out.push_back('"');
}

static std::string writeRecords(const std::vector<Record> &records) {
    std::string out = "{\"records\":[";
    for (size_t i = 0; i < records.size(); i++) {
        const Record &r = records[i];
        if (i) out.push_back(',');
        out += "{\"id\":";
        putInt(out, r.id);
        out += ",\"name\":";
        putString(out, r.name);
        out += ",\"email\":";
        putString(out, r.email);
        out += ",\"score\":";
        putInt(out, r.score);
        out += r.active ? ",\"active\":true,\"tags\":[" : ",\"active\":false,\"tags\":[";
        for (size_t t = 0; t < r.tags.size(); t++) {
            if (t) out.push_back(',');
            putString(out, r.tags[t]);
        }
        out += "]}";
    }
    out += "]}";
    return out;
}

// ---------- reading ----------

class Parser {
public:
    explicit Parser(std::string_view text) : at(text.data()), end(text.data() + text.size()) {}

    bool failed = false;

    void space() {
        while (at < end && (*at == ' ' || *at == '\n' || *at == '\r' || *at == '\t'))
            at++;
    }

    // the byte c next (after white space): consumed when it is
    bool nextIs(char c) {
        space();
        if (at < end && *at == c) {
            at++;
            return true;
        }
        return false;
    }

    void expect(char c) {
        if (!nextIs(c)) failed = true;
    }

    bool atEnd() {
        space();
        return at == end;
    }

    // a string's bytes, unescaped (\u below 0x80 only, as these records hold)
    std::string readString() {
        expect('"');
        const char *start = at;
        while (at < end && *at != '"' && *at != '\\')
            at++;
        std::string s(start, at);
        if (at < end && *at == '"') {
            at++;
            return s;
        }
        while (at < end && *at != '"') {
            char c = *at++;
            if (c == '\\' && at < end) {
                char e = *at++;
                if (e == 'n') c = '\n';
                else if (e == 'r') c = '\r';
                else if (e == 't') c = '\t';
                else if (e == 'b') c = '\b';
                else if (e == 'f') c = '\f';
                else if (e == 'u' && end - at >= 4) {
                    int v = 0;
                    for (int k = 0; k < 4; k++)
                        v = v * 16 + hexValue(*at++);
                    c = static_cast<char>(v);
                } else c = e;
            }
            s.push_back(c);
        }
        if (at < end) at++;
        else failed = true;
        return s;
    }

    int64_t readInt() {
        space();
        bool negative = at < end && *at == '-';
        if (negative) at++;
        if (at >= end || *at < '0' || *at > '9') failed = true;
        int64_t v = 0;
        while (at < end && *at >= '0' && *at <= '9')
            v = v * 10 + (*at++ - '0');
        return negative ? -v : v;
    }

    bool readBool() {
        if (readLiteral("true")) return true;
        if (!readLiteral("false")) failed = true;
        return false;
    }

    void skipValue() {
        space();
        if (at >= end) {
            failed = true;
        } else if (*at == '"') {
            readString();
        } else if (nextIs('[')) {
            if (!nextIs(']')) {
                do skipValue();
                while (!failed && nextIs(','));
                expect(']');
            }
        } else if (nextIs('{')) {
            if (!nextIs('}')) {
                do {
                    readString();
                    expect(':');
                    skipValue();
                } while (!failed && nextIs(','));
                expect('}');
            }
        } else if (!readLiteral("true") && !readLiteral("false") && !readLiteral("null")) {
            while (at < end && std::string_view("+-.0123456789eE").find(*at) != std::string_view::npos)
                at++;
        }
    }

private:
    const char *at, *end;

    static int hexValue(char c) {
        return c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
    }

    bool readLiteral(std::string_view word) {
        space();
        if (static_cast<size_t>(end - at) >= word.size() && std::string_view(at, word.size()) == word) {
            at += word.size();
            return true;
        }
        return false;
    }
};

static Record readRecord(Parser &p) {
    Record r;
    int seen = 0;
    p.expect('{');
    if (!p.nextIs('}')) {
        do {
            std::string key = p.readString();
            p.expect(':');
            if (key == "id") { r.id = p.readInt(); seen |= 1; }
            else if (key == "name") { r.name = p.readString(); seen |= 2; }
            else if (key == "email") { r.email = p.readString(); seen |= 4; }
            else if (key == "score") { r.score = p.readInt(); seen |= 8; }
            else if (key == "active") { r.active = p.readBool(); seen |= 16; }
            else if (key == "tags") {
                r.tags.clear();
                p.expect('[');
                if (!p.nextIs(']')) {
                    do r.tags.push_back(p.readString());
                    while (!p.failed && p.nextIs(','));
                    p.expect(']');
                }
                seen |= 32;
            } else p.skipValue();
        } while (!p.failed && p.nextIs(','));
        p.expect('}');
    }
    if (seen != 63) p.failed = true;
    return r;
}

static std::vector<Record> readRecords(Parser &p) {
    std::vector<Record> records;
    p.expect('{');
    if (!p.nextIs('}')) {
        do {
            std::string key = p.readString();
            p.expect(':');
            if (key == "records") {
                p.expect('[');
                if (!p.nextIs(']')) {
                    do records.push_back(readRecord(p));
                    while (!p.failed && p.nextIs(','));
                    p.expect(']');
                }
            } else p.skipValue();
        } while (!p.failed && p.nextIs(','));
        p.expect('}');
    }
    if (!p.atEnd()) p.failed = true;
    return records;
}

int main(int argc, char **argv) {
#ifdef _WIN32
    _setmode(1, _O_BINARY); // the runner compares bytes: no CRLF translation
#endif
    int64_t n = argc > 1 ? atoll(argv[1]) : 100;
    std::vector<Record> records = generate(n);
    std::string text = writeRecords(records);
    long long sum = 0;
    for (char c : text)
        sum += static_cast<unsigned char>(c);
    printf("json %zu bytes, checksum %lld\n", text.size(), sum);
    Parser parser(text);
    std::vector<Record> back = readRecords(parser);
    if (parser.failed) back.clear();
    long long scores = 0, active = 0, tags = 0;
    for (const Record &r : back) {
        scores += r.score;
        active += r.active;
        tags += static_cast<long long>(r.tags.size());
    }
    printf("read %zu records: scores %lld, active %lld, tags %lld, %s\n", back.size(), scores, active, tags, back == records ? "same" : "DIFFERENT");
    return 0;
}
