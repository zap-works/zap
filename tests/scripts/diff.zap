import fs

a = (fs.readFile(args[0]) ?? fail).lines()
b = (fs.readFile(args[1]) ?? fail).lines()
lcs i64[,] = zeros(a.len + 1, b.len + 1)
for i in a.len - 1..-1 step -1:
	for j in b.len - 1..-1 step -1:
		lcs[i][j] = lcs[i + 1][j + 1] + 1 if a[i] == b[j] else lcs[i + 1][j].max(lcs[i][j + 1])
i = 0
j = 0
while i < a.len or j < b.len:
	if i < a.len and j < b.len and a[i] == b[j]:
		i += 1
		j += 1
	elif j < b.len and (i == a.len or lcs[i][j + 1] >= lcs[i + 1][j]):
		print("+{j + 1:>4} {b[j]}")
		j += 1
	else:
		print("-{i + 1:>4} {a[i]}")
		i += 1
