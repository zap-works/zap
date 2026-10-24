import fs
import regex

# counts the functions per file under a dir, prints the top ten and a JSON line
re = regex.compile(r"^(pub )?fn \w+") ?? fail
counts {str: i64} = {}
for f in fs.walk(args[0], "*.zap"):
	text = fs.readFile(f) ?? continue
	counts[f] = text.lines().count(re.isMatch(it))
top = counts.keys().sortedBy((-counts[it], it))
for name in top[..10.min(len)]:
	print("{counts[name]:>5} {name}")
print("\{\"files\": {counts.len}, \"functions\": {counts.values().sum()}\}")
