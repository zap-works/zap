/* wordFreq: n generated words counted in a hash map keyed by the words; prints the distinct
 * count and the ten most frequent. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

#include <khash.h>

KHASH_MAP_INIT_STR(words, uint32_t)

typedef struct {
    const char *word;
    uint32_t count;
} Entry;

static char *generate(long long n, size_t *size) {
    size_t cap = 1 << 16, len = 0;
    char *text = malloc(cap);
    uint64_t state = 1;
    for (long long i = 0; i < n; i++) {
        if (len + 8 > cap) {
            cap *= 2;
            text = realloc(text, cap);
        }
        state = state * 6364136223846793005ull + 1442695040888963407ull;
        uint64_t k = (state >> 44) % ((state >> 24 & 1048575) + 1);
        do {
            text[len++] = (char)('a' + k % 26);
            k /= 26;
        } while (k > 0);
        text[len++] = i % 20 == 19 || i == n - 1 ? '\n' : ' ';
    }
    *size = len;
    return text;
}

static int by_count_then_word(const void *pa, const void *pb) {
    const Entry *a = pa, *b = pb;
    if (a->count != b->count)
        return a->count > b->count ? -1 : 1;
    return strcmp(a->word, b->word);
}

int main(int argc, char **argv) {
#ifdef _WIN32
    _setmode(1, _O_BINARY); /* the runner compares bytes: no CRLF translation */
#endif
    long long n = argc > 1 ? atoll(argv[1]) : 1000;
    size_t size;
    char *text = generate(n, &size);
    khash_t(words) *table = kh_init(words);
    size_t start = 0;
    for (size_t i = 0; i < size; i++) {
        if (text[i] == ' ' || text[i] == '\n') {
            text[i] = 0;
            int absent;
            khiter_t k = kh_put(words, table, text + start, &absent);
            kh_value(table, k) = absent ? 1 : kh_value(table, k) + 1;
            start = i + 1;
        }
    }
    size_t distinct = 0;
    Entry *entries = malloc(kh_size(table) * sizeof(Entry));
    for (khiter_t k = kh_begin(table); k != kh_end(table); k++)
        if (kh_exist(table, k))
            entries[distinct++] = (Entry){kh_key(table, k), kh_value(table, k)};
    qsort(entries, distinct, sizeof(Entry), by_count_then_word);
    printf("%lld words, %zu distinct\n", n, distinct);
    for (size_t i = 0; i < distinct && i < 10; i++)
        printf("%8u %s\n", entries[i].count, entries[i].word);
    free(entries);
    kh_destroy(words, table);
    free(text);
    return 0;
}
