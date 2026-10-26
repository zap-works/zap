---
size: L
branch: interned
by: 05c1402a-077b-4bef-a22a-b65dbb8e7ce8
---
# Names interned as numbers

(Zig's InternPool, Go's symbols): each identifier numbered once by
the lexer, the checker's and the lowering's lookups by number (an array, not a map of texts).
Texts' compares, hashes and copies are 10 to 15% of each phase now (firstIndexed alone 3% of a
cold recompshape build; strEq, bytesHash and findCell_str on top of every profile).

- [x] each name numbered once where its file is parsed (numberNames, in the parse jobs), renumbered
  by the program's table as the file is appended (interned, appendParsed); Node.name, reset by
  setText
- [x] declarations by number (declsByName, declsByLocal, firstIndexed); the hot lookups pass the
  node's number (lookupDecl, normalizeQualified, calleeDecl, callChangesName, findFunc)
- [x] a bare name's declaration looked up once a module and file by its number (bareFound): 5.5
  million declaration lookups in a cold recompshape build, most of them the same few names
- [x] a block's mentions (mutability), the runtime's reads (readsAt) and unsigned quantities'
  reads (one walk) by number
- [ ] scopes by number: the checker's vars and the lowering's names (NameIndex)
- [ ] the lowering's module variables by number (globalOffs, globalsNamed)
- [ ] a kept stage's nodes numbered as read (a warm build looks names up by text)
- [ ] Node is 8 bytes larger (name): a cold build's peak 4 to 6% higher, to win back
