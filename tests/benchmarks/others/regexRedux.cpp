// regex-redux for the Zap benchmarks game, in C++: PCRE2 with its JIT, as the C program calls it
// (WinLibs ships libpcre2-8-0.dll but neither pcre2.h nor an import library, so the functions used
// are declared here and loaded from the DLL; std::regex is far too slow for this input and
// boost is not in the toolchain). On Linux it is libpcre2-8 and its header. The headers and newlines
// are taken out by a regular expression, the nine variants counted one thread each beside the five
// substitutions made in turn.
#ifdef _WIN32
#include <windows.h>
#include <fcntl.h>
#include <io.h>
#else
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>
#endif

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

namespace {

#ifdef _WIN32
struct pcre2_code;
struct pcre2_match_data;
constexpr int no_match = -1;
constexpr unsigned jit_complete = 1;

struct Pcre2 {
    pcre2_code *(*compile)(const unsigned char *, size_t, unsigned, int *, size_t *, void *);
    int (*jit_compile)(pcre2_code *, unsigned);
    pcre2_match_data *(*match_data_create)(const pcre2_code *, void *);
    int (*match)(const pcre2_code *, const unsigned char *, size_t, size_t, unsigned,
                 pcre2_match_data *, void *);
    size_t *(*ovector)(pcre2_match_data *);
};

Pcre2 pcre2;

template <typename F>
void load(HMODULE dll, F &fn, const char *name) {
    fn = reinterpret_cast<F>(reinterpret_cast<void *>(GetProcAddress(dll, name)));
    if (!fn) {
        std::fprintf(stderr, "no %s\n", name);
        std::exit(1);
    }
}

void load_pcre2() {
    HMODULE dll = LoadLibraryA("libpcre2-8-0.dll");
    if (!dll) {
        std::fputs("libpcre2-8-0.dll not found\n", stderr);
        std::exit(1);
    }
    load(dll, pcre2.compile, "pcre2_compile_8");
    load(dll, pcre2.jit_compile, "pcre2_jit_compile_8");
    load(dll, pcre2.match_data_create, "pcre2_match_data_create_from_pattern_8");
    load(dll, pcre2.match, "pcre2_match_8");
    load(dll, pcre2.ovector, "pcre2_get_ovector_pointer_8");
}
#else
constexpr int no_match = PCRE2_ERROR_NOMATCH;
constexpr unsigned jit_complete = PCRE2_JIT_COMPLETE;

// the library's own functions, called through the same names
struct Pcre2 {
    decltype(&pcre2_compile_8) compile = pcre2_compile_8;
    decltype(&pcre2_jit_compile_8) jit_compile = pcre2_jit_compile_8;
    decltype(&pcre2_match_data_create_from_pattern_8) match_data_create = pcre2_match_data_create_from_pattern_8;
    decltype(&pcre2_match_8) match = pcre2_match_8;
    decltype(&pcre2_get_ovector_pointer_8) ovector = pcre2_get_ovector_pointer_8;
};

Pcre2 pcre2;

void load_pcre2() {}
#endif

const char *variants[] = {
    "agggtaaa|tttaccct",
    "[cgt]gggtaaa|tttaccc[acg]",
    "a[act]ggtaaa|tttacc[agt]t",
    "ag[act]gtaaa|tttac[agt]ct",
    "agg[act]taaa|ttta[agt]cct",
    "aggg[acg]aaa|ttt[cgt]ccct",
    "agggt[cgt]aa|tt[acg]accct",
    "agggta[cgt]a|t[acg]taccct",
    "agggtaa[cgt]|[acg]ttaccct",
};

struct Substitution {
    const char *pattern;
    const char *by;
};

const Substitution substitutions[] = {
    {"tHa[Nt]", "<4>"},
    {"aND|caN|Ha[DS]|WaS", "<3>"},
    {"a[NSt]|BY", "<2>"},
    {"<[^>]*>", "|"},
    {"\\|[^|][^|]*\\|", "-"},
};

class Matcher {
public:
    explicit Matcher(const std::string &pattern) {
        int error;
        size_t offset;
        code_ = pcre2.compile(reinterpret_cast<const unsigned char *>(pattern.data()), pattern.size(), 0,
                              &error, &offset, nullptr);
        if (!code_ || pcre2.jit_compile(code_, jit_complete) != 0) {
            std::fprintf(stderr, "cannot compile %s\n", pattern.c_str());
            std::exit(1);
        }
        data_ = pcre2.match_data_create(code_, nullptr);
    }

    // the next match at or after `from`: its bounds, false when there is none
    bool next(const std::string &text, size_t from, size_t &start, size_t &end) {
        int rc = pcre2.match(code_, reinterpret_cast<const unsigned char *>(text.data()), text.size(), from, 0,
                             data_, nullptr);
        if (rc == no_match) return false;
        if (rc < 0) {
            std::fputs("match error\n", stderr);
            std::exit(1);
        }
        size_t *ov = pcre2.ovector(data_);
        start = ov[0];
        end = ov[1];
        return true;
    }

    size_t count(const std::string &text) {
        size_t n = 0, from = 0, start, end;
        while (from <= text.size() && next(text, from, start, end)) {
            n++;
            from = end > start ? end : end + 1;
        }
        return n;
    }

    std::string replace(const std::string &text, const char *by) {
        std::string out;
        out.reserve(text.size());
        size_t copied = 0, from = 0, start, end;
        const size_t by_length = std::strlen(by);
        while (from <= text.size() && next(text, from, start, end)) {
            out.append(text, copied, start - copied);
            out.append(by, by_length);
            copied = end;
            from = end > start ? end : end + 1;
        }
        out.append(text, copied, std::string::npos);
        return out;
    }

private:
    pcre2_code *code_;
    pcre2_match_data *data_;
};

}  // namespace

int main() {
#ifdef _WIN32
    _setmode(_fileno(stdin), _O_BINARY);
    _setmode(_fileno(stdout), _O_BINARY);
#endif
    load_pcre2();

    std::string original;
    {
        std::vector<char> chunk(1 << 20);
        size_t got;
        while ((got = std::fread(chunk.data(), 1, chunk.size(), stdin)) > 0) original.append(chunk.data(), got);
    }
    std::string sequence = Matcher(">.*\n|\n").replace(original, "");
    const size_t original_length = original.size();
    original = std::string();

    // the substitutions go on in this thread while one thread for each variant counts it
    size_t counts[9];
    std::vector<std::thread> threads;
    for (int i = 0; i < 9; i++)
        threads.emplace_back([&counts, &sequence, i] { counts[i] = Matcher(variants[i]).count(sequence); });
    std::string text = sequence;
    for (const auto &s : substitutions) text = Matcher(s.pattern).replace(text, s.by);
    for (auto &t : threads) t.join();
    for (int i = 0; i < 9; i++) std::printf("%s %zu\n", variants[i], counts[i]);
    std::printf("\n%zu\n%zu\n%zu\n", original_length, sequence.size(), text.size());
    return 0;
}
