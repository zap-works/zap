# matMul: the product of two n by n f64 matrices, loops in i, k, j order so each element sums in k
# order and every language prints the same digits
import sys


def matrix(n):
    scale = 1.0 / n / n
    return [[scale * (i - j) * (i + j) for j in range(n)] for i in range(n)]


def product(a, b, n):
    c = [[0.0] * n for _ in range(n)]
    for i in range(n):
        ci = c[i]
        for k in range(n):
            aik = a[i][k]
            bk = b[k]
            for j in range(n):
                ci[j] += aik * bk[j]
    return c


n = int(sys.argv[1]) if len(sys.argv) > 1 else 30
a = matrix(n)
b = matrix(n)
c = product(a, b, n)
trace = 0.0
for i in range(n):
    trace += c[i][i]
# bytes: no CRLF translation, the runner compares bytes
sys.stdout.buffer.write(("%.9f\n%.9f\n" % (c[n // 2][n // 2], trace)).encode())
