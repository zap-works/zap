---
size: L
branch: interned
---
# Names interned as numbers

(Zig's InternPool, Go's symbols): each identifier numbered once by
the lexer, the checker's and the lowering's lookups by number (an array, not a map of texts).
Texts' compares, hashes and copies are 10 to 15% of each phase now (firstIndexed alone 3% of a
cold recompshape build; strEq, bytesHash and findCell_str on top of every profile).
