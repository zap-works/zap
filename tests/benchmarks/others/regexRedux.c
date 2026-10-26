/* regex-redux for the Zap benchmarks game, in the manner of the Benchmarks Game's C program: PCRE2
   with its JIT. The toolchain here (WinLibs) ships libpcre2-8-0.dll but not pcre2.h or an import
   library, so the few functions used are declared below and loaded from the DLL at start-up;
   the calls are the ones the published program makes. The headers and newlines are taken out by
   a regular expression, the nine variants counted one thread each, five substitutions made in
   turn. On Linux it is libpcre2-8 and its header. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <omp.h>
#ifdef _WIN32
#include <io.h>
#include <fcntl.h>
#include <windows.h>

typedef struct pcre2_code pcre2_code;
typedef struct pcre2_match_data pcre2_match_data;
#define PCRE2_ERROR_NOMATCH (-1)
#define PCRE2_JIT_COMPLETE 1u

static pcre2_code *(*pcre2_compile)(const unsigned char *, size_t, unsigned, int *, size_t *, void *);
static int (*pcre2_jit_compile)(pcre2_code *, unsigned);
static pcre2_match_data *(*pcre2_match_data_create_from_pattern)(const pcre2_code *, void *);
static int (*pcre2_match)(const pcre2_code *, const unsigned char *, size_t, size_t, unsigned,
                          pcre2_match_data *, void *);
static size_t *(*pcre2_get_ovector_pointer)(pcre2_match_data *);

static void load_pcre2(void) {
  HMODULE dll = LoadLibraryA("libpcre2-8-0.dll");
  if (!dll) { fputs("libpcre2-8-0.dll not found\n", stderr); exit(1); }
#define LOAD(name) \
  *(void **)&name = (void *)GetProcAddress(dll, #name "_8"); \
  if (!name) { fputs("no " #name "\n", stderr); exit(1); }
  LOAD(pcre2_compile)
  LOAD(pcre2_jit_compile)
  LOAD(pcre2_match_data_create_from_pattern)
  LOAD(pcre2_match)
  LOAD(pcre2_get_ovector_pointer)
}
#else
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

static void load_pcre2(void) {}
#endif

static const char *variants[] = {
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

static const char *substitutions[][2] = {
  {"tHa[Nt]", "<4>"},
  {"aND|caN|Ha[DS]|WaS", "<3>"},
  {"a[NSt]|BY", "<2>"},
  {"<[^>]*>", "|"},
  {"\\|[^|][^|]*\\|", "-"},
};

static pcre2_code *compile(const char *pattern) {
  int error;
  size_t offset;
  pcre2_code *re = pcre2_compile((const unsigned char *)pattern, strlen(pattern), 0, &error, &offset, NULL);
  if (!re || pcre2_jit_compile(re, PCRE2_JIT_COMPLETE) != 0) {
    fprintf(stderr, "cannot compile %s\n", pattern);
    exit(1);
  }
  return re;
}

static size_t count_matches(const char *pattern, const char *text, size_t length) {
  pcre2_code *re = compile(pattern);
  pcre2_match_data *match = pcre2_match_data_create_from_pattern(re, NULL);
  size_t *ov = pcre2_get_ovector_pointer(match);
  size_t count = 0, from = 0;
  while (from <= length) {
    int rc = pcre2_match(re, (const unsigned char *)text, length, from, 0, match, NULL);
    if (rc == PCRE2_ERROR_NOMATCH) break;
    if (rc < 0) { fputs("match error\n", stderr); exit(1); }
    count++;
    from = ov[1] > ov[0] ? ov[1] : ov[1] + 1;
  }
  return count;
}

/* the text with every match of the pattern replaced; a new buffer, its length in *out_length */
static char *replace_all(const char *pattern, const char *by, const char *text, size_t length,
                         size_t *out_length) {
  pcre2_code *re = compile(pattern);
  pcre2_match_data *match = pcre2_match_data_create_from_pattern(re, NULL);
  size_t *ov = pcre2_get_ovector_pointer(match);
  size_t by_length = strlen(by);
  char *out = malloc(length + 1);
  size_t capacity = length + 1, used = 0, copied = 0, from = 0;
  while (from <= length) {
    int rc = pcre2_match(re, (const unsigned char *)text, length, from, 0, match, NULL);
    if (rc == PCRE2_ERROR_NOMATCH) break;
    if (rc < 0) { fputs("match error\n", stderr); exit(1); }
    size_t start = ov[0], end = ov[1];
    size_t need = used + (start - copied) + by_length;
    if (need > capacity) {
      capacity = need + capacity / 2;
      out = realloc(out, capacity);
    }
    memcpy(out + used, text + copied, start - copied);
    used += start - copied;
    memcpy(out + used, by, by_length);
    used += by_length;
    copied = end;
    from = end > start ? end : end + 1;
  }
  if (used + (length - copied) > capacity) out = realloc(out, used + (length - copied));
  memcpy(out + used, text + copied, length - copied);
  used += length - copied;
  *out_length = used;
  return out;
}

int main(void) {
#ifdef _WIN32
  _setmode(_fileno(stdin), _O_BINARY);
  _setmode(_fileno(stdout), _O_BINARY);
#endif
  load_pcre2();
  size_t capacity = 1 << 24, original = 0;
  char *input = malloc(capacity);
  size_t got;
  while ((got = fread(input + original, 1, capacity - original, stdin)) > 0) {
    original += got;
    if (original == capacity) {
      capacity *= 2;
      input = realloc(input, capacity);
    }
  }
  size_t sequence_length;
  char *sequence = replace_all(">.*\n|\n", "", input, original, &sequence_length);
  free(input);

  /* the substitutions are one task and each variant's count another, side by side on the processors */
  size_t counts[9];
  char *text = sequence;
  size_t text_length = sequence_length;
#pragma omp parallel
#pragma omp single
  {
#pragma omp task
    {
      for (int i = 0; i < 5; i++) {
        size_t next_length;
        char *next = replace_all(substitutions[i][0], substitutions[i][1], text, text_length, &next_length);
        if (text != sequence) free(text);
        text = next;
        text_length = next_length;
      }
    }
    for (int i = 0; i < 9; i++) {
#pragma omp task firstprivate(i)
      counts[i] = count_matches(variants[i], sequence, sequence_length);
    }
  }
  for (int i = 0; i < 9; i++) printf("%s %zu\n", variants[i], counts[i]);
  printf("\n%zu\n%zu\n%zu\n", original, sequence_length, text_length);
  return 0;
}
