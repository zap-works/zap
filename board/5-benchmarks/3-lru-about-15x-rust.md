---
needs: [runtime-5]
size: M
---
# lru about 1.5x (Rust)

(needs runtime-5): findCell's 56 instructions a miss against
Rust's 20, list headers and locals spilled (compiler-7), the map's probes.
