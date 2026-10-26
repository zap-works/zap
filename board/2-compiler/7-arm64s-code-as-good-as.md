---
size: L
---
# arm64's code as good as x64's

(benchmarks-2 lists the ratios it moves). Left: havlak's
`numbering` and `predecessors` still spill with AArch64's own set (x0..x7 only for vregs no call
or scratch-using instruction meets, so what lives across a call has x19..x28 alone); loops
around an inner loop are not split; fasta's drawRounds loop makes its constants at each turn (its
multiplier and addend, a `mov` each since AArch64's mul and add take no such immediate; `% im`'s
magic number and divisor, a `mov` and a `movk` each, a64DivByConstant) and writeRandom's
`draws[at..]` window is written to its frame slot and read back each round.
