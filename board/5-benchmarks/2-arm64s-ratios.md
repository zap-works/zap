---
needs: [compiler-7]
size: XL
priority: P3
---
# arm64's ratios

(arm64 host, `--full`), worst first: revComp 5.64, httpJson 5.35, kNucleotide
2.82, fasta 2.80, havlak 2.35, fannkuchRedux 2.28, nbody 2.15, regexRedux 1.93, lru 1.83,
binaryTrees 1.53, sudoku 1.42, mandelbrot 1.31, base64 1.26, strSort 1.25, jsonRecords 1.20,
pidigits 1.20, exprTree 1.19, brainfudge 1.07, spectralNorm 1.06, nsieve 1.04, raytrace 1.01;
under 1.00: wordFreq 0.65, matMul 0.79, dijkstra 0.89, coroPrimeSieve 0.95. Needs compiler-7;
httpJson's `parseHead` is 21% of its samples, havlak's Finder_collapse 33% and numbering 25%.
