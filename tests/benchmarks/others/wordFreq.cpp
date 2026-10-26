// wordFreq: n generated words counted in a hash map keyed by the words; prints the distinct
// count and the ten most frequent.
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

static std::string generate(long long n) {
    std::string text;
    uint64_t state = 1;
    for (long long i = 0; i < n; i++) {
        state = state * 6364136223846793005ull + 1442695040888963407ull;
        uint64_t k = (state >> 44) % ((state >> 24 & 1048575) + 1);
        do {
            text.push_back(static_cast<char>('a' + k % 26));
            k /= 26;
        } while (k > 0);
        text.push_back(i % 20 == 19 || i == n - 1 ? '\n' : ' ');
    }
    return text;
}

int main(int argc, char **argv) {
#ifdef _WIN32
    _setmode(1, _O_BINARY); // the runner compares bytes: no CRLF translation
#endif
    long long n = argc > 1 ? atoll(argv[1]) : 1000;
    std::string text = generate(n);
    std::unordered_map<std::string_view, uint32_t> counts;
    std::string_view view = text;
    size_t start = 0;
    for (size_t i = 0; i < view.size(); i++) {
        if (view[i] == ' ' || view[i] == '\n') {
            counts[view.substr(start, i - start)]++;
            start = i + 1;
        }
    }
    std::vector<std::pair<std::string_view, uint32_t>> entries(counts.begin(), counts.end());
    std::sort(entries.begin(), entries.end(), [](const auto &a, const auto &b) {
        return a.second != b.second ? a.second > b.second : a.first < b.first;
    });
    printf("%lld words, %zu distinct\n", n, entries.size());
    for (size_t i = 0; i < entries.size() && i < 10; i++)
        printf("%8u %.*s\n", entries[i].second, static_cast<int>(entries[i].first.size()), entries[i].first.data());
    return 0;
}
