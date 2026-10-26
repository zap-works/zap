---
size: M
branch: interned
by: 05c1402a-077b-4bef-a22a-b65dbb8e7ce8
---
# Names interned as numbers

Each name is numbered once where its file is parsed (interned, Node.name) and the declarations,
a block's mentions and the runtime's reads are looked up by number; a cold recompshape build's
load fell about 25% and its check 17%. What is left are the smaller lookups by text and the
memory the number costs:

- [ ] Node is 8 bytes larger (name): a cold build's peak 3 to 6% higher, to win back
- [ ] scopes by number: the checker's vars and the lowering's names (NameIndex)
- [ ] the lowering's module variables by number (globalOffs, globalsNamed, irGlobal)
- [ ] the runtime's method functions of a method name (rtMethodDecls, methodIsMutating) found
  once by its number, not by texts made for each call
- [ ] a kept stage's nodes numbered as read (a warm build looks names up by text)
