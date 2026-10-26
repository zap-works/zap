---
needs: [runtime-2]
size: L
priority: P3
---
# regexRedux

(needs runtime-2): 0.89x time against Rust, 1.02x memory, 1.66x cycles.
The counts scan at 1.4 ns a byte on every core, Rust's Teddy at 0.6; the substitutions are the
critical path, one core: about 55 ns a match, the call chain of a locate (skip, anchored scan,
two builder appends). Left: a vector scan for the pattern's first bytes or longest literal before
the automaton, a byte shift on `Simd<32, u8>` for a nibble-table prefilter, the five
substitutions in one pass.
