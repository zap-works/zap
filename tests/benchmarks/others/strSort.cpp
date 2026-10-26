// strSort: n generated strings of 1 to 40 letters, each from an alphabet of 2 to 26 letters (long
// shared prefixes among the small ones) sorted by bytes; prints how many are distinct, a hash of the sorted sequence and the
// first and last.
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

static uint64_t state = 1;

// the next number, 31 bits
static uint64_t next() {
    state = state * 6364136223846793005ull + 1442695040888963407ull;
    return state >> 33;
}

int main(int argc, char **argv) {
#ifdef _WIN32
    _setmode(1, _O_BINARY); // the runner compares bytes: no CRLF translation
#endif
    size_t n = argc > 1 ? (size_t)atoll(argv[1]) : 1000;
    std::vector<std::string> words(n);
    for (std::string &word : words) {
        size_t len = 1 + next() % 40;
        uint64_t letters = 2 + next() % 25;
        for (size_t k = 0; k < len; k++)
            word += (char)('a' + next() % letters);
    }
    std::sort(words.begin(), words.end());
    size_t distinct = 0;
    uint64_t hash = 14695981039346656037ull;
    for (size_t i = 0; i < n; i++) {
        if (i == 0 || words[i] != words[i - 1])
            distinct++;
        for (char c : words[i])
            hash = (hash ^ (uint8_t)c) * 1099511628211ull;
        hash = (hash ^ '\n') * 1099511628211ull;
    }
    printf("%zu strings, %zu distinct, hash %llx\n%s\n%s\n", n, distinct, (unsigned long long)hash, words[0].c_str(), words[n - 1].c_str());
    return 0;
}
