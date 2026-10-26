# regex-redux: the FASTA text read from stdin has its headers and newlines taken out by a regular
# expression, nine variants of a pattern are counted in what is left (one task each, on every
# processor), while five substitutions are made in turn, each over the previous one's text. The
# regular expressions are std/regex's: a lazy DFA, so every scan reads the text once.

import problems
import regex

variants = [
	"agggtaaa|tttaccct",
	"[cgt]gggtaaa|tttaccc[acg]",
	"a[act]ggtaaa|tttacc[agt]t",
	"ag[act]gtaaa|tttac[agt]ct",
	"agg[act]taaa|ttta[agt]cct",
	"aggg[acg]aaa|ttt[cgt]ccct",
	"agggt[cgt]aa|tt[acg]accct",
	"agggta[cgt]a|t[acg]taccct",
	"agggtaa[cgt]|[acg]ttaccct"
]

type Substitution:
	pattern str
	by str

substitutions = [
	Substitution("tHa[Nt]", "<4>"),
	Substitution("aND|caN|Ha[DS]|WaS", "<3>"),
	Substitution("a[NSt]|BY", "<2>"),
	Substitution("<[^>]*>", "|"),
	Substitution("\\|[^|][^|]*\\|", "-")
]

fn compiled(pattern str):
	regex.compile(pattern) ?? fail

fn countPattern(pattern str, sequence str) i64:
	re = compiled(pattern)
	re.count(sequence)

# the length of the text after the substitutions, each over the previous one's text
fn substitutedLength(sequence str):
	first = compiled(substitutions[0].pattern)
	text = first.replace(sequence, substitutions[0].by)
	for s in substitutions[1..]:
		re = compiled(s.pattern)
		text = re.replace(text, s.by)
	text.len

# the input without its headers and newlines, and the input's length
type Stripped:
	sequence str
	originalLength i64

fn stripped():
	original = stdin.all()
	re = compiled(">.*\n|\n")
	Stripped(re.replace(original, ""), original.len)

input = stripped()
sequence = input.sequence
# the substitutions are one task and each variant's count another, side by side on the processors
results = (0..variants.len + 1).parallel().map(k:
	substitutedLength(sequence) if k == 0 else countPattern(variants[k - 1], sequence)
)
for i, pattern in variants:
	print("{pattern} {results[i + 1]}")
print("\n{input.originalLength}\n{sequence.len}\n{results[0]}")

test "the C, C++, Rust and Python programs print the same bytes, the variants' counts and the substituted lengths the reference's":
	expect problems.agree("regexRedux")
	problems.feedFasta()
	main()
	prints problems.expectedOf("regexRedux")
