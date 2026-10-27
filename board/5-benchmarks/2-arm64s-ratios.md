---
needs: [compiler-7]
size: XL
priority: P3
---
# Every benchmark is under 1.00x on arm64

On the arm64 host at `--full`, the ratios of Zap's cycles to the best rival's, worst first:
revComp 5.64, httpJson 5.35, kNucleotide 2.82, fasta 2.80, havlak 2.35, fannkuchRedux 2.28, nbody
2.15, regexRedux 1.93, lru 1.83, binaryTrees 1.53, sudoku 1.42, mandelbrot 1.31, base64 1.26, strSort
1.25, jsonRecords 1.20, pidigits 1.20, exprTree 1.19, brainfudge 1.07, spectralNorm 1.06, nsieve
1.04, raytrace 1.01. Under 1.00: wordFreq 0.65, matMul 0.79, dijkstra 0.89, coroPrimeSieve 0.95.
The code-generation part is compiler-7. What the profiles show: `httpJson`'s `parseHead` is 21% of its
samples, havlak's `Finder_collapse` 33% and `numbering` 25%.

- [ ] after compiler-7, measure on the arm64 host (`zap test --only bench --full`) and take the
  worst problem still above 1.00x: profile it, change the compiler or the problem's Zap code, and
  its ratio falls; repeat for the next
- [ ] stop when every problem listed above is under 1.00x, and record `bench.baseline` (see
  benchmarks-11)
