/* matMul: the product of two n by n f64 matrices, loops in i, k, j order so each element sums in
 * k order and every language prints the same digits. */
#include <stdio.h>
#include <stdlib.h>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

static double *matrix(long long n) {
    double scale = 1.0 / n / n;
    double *m = malloc(sizeof(double) * n * n);
    for (long long i = 0; i < n; i++)
        for (long long j = 0; j < n; j++)
            m[i * n + j] = scale * (i - j) * (i + j);
    return m;
}

static double *product(const double *restrict a, const double *restrict b, long long n) {
    double *restrict c = calloc(n * n, sizeof(double));
    for (long long i = 0; i < n; i++) {
        for (long long k = 0; k < n; k++) {
            double aik = a[i * n + k];
            const double *restrict bk = b + k * n;
            double *restrict ci = c + i * n;
            for (long long j = 0; j < n; j++)
                ci[j] += aik * bk[j];
        }
    }
    return c;
}

int main(int argc, char **argv) {
#ifdef _WIN32
    _setmode(1, _O_BINARY); /* the runner compares bytes: no CRLF translation */
#endif
    long long n = argc > 1 ? atoll(argv[1]) : 30;
    double *a = matrix(n);
    double *b = matrix(n);
    double *c = product(a, b, n);
    double trace = 0.0;
    for (long long i = 0; i < n; i++)
        trace += c[i * n + i];
    printf("%.9f\n%.9f\n", c[n / 2 * n + n / 2], trace);
    free(a);
    free(b);
    free(c);
    return 0;
}
