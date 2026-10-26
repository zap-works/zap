/* strSort: n generated strings of 1 to 40 letters, each from an alphabet of 2 to 26 letters (long
 * shared prefixes among the small ones) sorted by bytes; prints how many are distinct, a hash of
 * the sorted sequence and the first and last. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

static uint64_t state = 1;

/* the next number, 31 bits */
static uint64_t next(void) {
    state = state * 6364136223846793005ull + 1442695040888963407ull;
    return state >> 33;
}

static int by_bytes(const void *a, const void *b) {
    return strcmp(*(char *const *)a, *(char *const *)b);
}

int main(int argc, char **argv) {
#ifdef _WIN32
    _setmode(1, _O_BINARY); /* the runner compares bytes: no CRLF translation */
#endif
    size_t n = argc > 1 ? (size_t)atoll(argv[1]) : 1000;
    /* every string in one block, each ending with a 0 */
    char *letters = malloc(n * 41);
    char **words = malloc(n * sizeof(char *));
    char *at = letters;
    for (size_t i = 0; i < n; i++) {
        size_t len = 1 + next() % 40;
        uint64_t letters_used = 2 + next() % 25;
        words[i] = at;
        for (size_t k = 0; k < len; k++)
            *at++ = (char)('a' + next() % letters_used);
        *at++ = 0;
    }
    qsort(words, n, sizeof(char *), by_bytes);
    size_t distinct = 0;
    uint64_t hash = 14695981039346656037ull;
    for (size_t i = 0; i < n; i++) {
        if (i == 0 || strcmp(words[i], words[i - 1]) != 0)
            distinct++;
        for (const char *c = words[i]; *c; c++)
            hash = (hash ^ (uint8_t)*c) * 1099511628211ull;
        hash = (hash ^ '\n') * 1099511628211ull;
    }
    printf("%zu strings, %zu distinct, hash %llx\n%s\n%s\n", n, distinct, (unsigned long long)hash, words[0], words[n - 1]);
    free(words);
    free(letters);
    return 0;
}
