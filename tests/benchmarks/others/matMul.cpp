// matMul: the product of two n by n f64 matrices, loops in i, k, j order so each element sums in
// k order and every language prints the same digits.
#include <cstdio>
#include <cstdlib>
#include <vector>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

static std::vector<double> matrix(long long n) {
    double scale = 1.0 / n / n;
    std::vector<double> m(n * n);
    for (long long i = 0; i < n; i++)
        for (long long j = 0; j < n; j++)
            m[i * n + j] = scale * (i - j) * (i + j);
    return m;
}

static std::vector<double> product(const double *__restrict a, const double *__restrict b, long long n) {
    std::vector<double> c(n * n, 0.0);
    for (long long i = 0; i < n; i++) {
        double *__restrict ci = c.data() + i * n;
        for (long long k = 0; k < n; k++) {
            double aik = a[i * n + k];
            const double *__restrict bk = b + k * n;
            for (long long j = 0; j < n; j++)
                ci[j] += aik * bk[j];
        }
    }
    return c;
}

int main(int argc, char **argv) {
#ifdef _WIN32
    _setmode(1, _O_BINARY); // the runner compares bytes: no CRLF translation
#endif
    long long n = argc > 1 ? atoll(argv[1]) : 30;
    std::vector<double> a = matrix(n), b = matrix(n);
    std::vector<double> c = product(a.data(), b.data(), n);
    double trace = 0.0;
    for (long long i = 0; i < n; i++)
        trace += c[i * n + i];
    printf("%.9f\n%.9f\n", c[n / 2 * n + n / 2], trace);
    return 0;
}
