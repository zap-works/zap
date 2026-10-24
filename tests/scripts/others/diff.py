import sys

a = open(sys.argv[1], encoding="utf-8").read().splitlines()
b = open(sys.argv[2], encoding="utf-8").read().splitlines()
n, m = len(a), len(b)
lcs = [[0] * (m + 1) for _ in range(n + 1)]
for i in range(n - 1, -1, -1):
    for j in range(m - 1, -1, -1):
        lcs[i][j] = lcs[i + 1][j + 1] + 1 if a[i] == b[j] else max(lcs[i + 1][j], lcs[i][j + 1])
i = j = 0
while i < n or j < m:
    if i < n and j < m and a[i] == b[j]:
        i += 1
        j += 1
    elif j < m and (i == n or lcs[i][j + 1] >= lcs[i + 1][j]):
        print(f"+{j + 1:>4} {b[j]}")
        j += 1
    else:
        print(f"-{i + 1:>4} {a[i]}")
        i += 1
