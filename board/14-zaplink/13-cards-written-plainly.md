---
size: L
priority: P0
branch: zaplink-13
by: fa7ba7ba-02b0-4d52-a94c-9ee8ba5d1bc8
---
# Every card written plainly

Many cards are cryptic: their tasks name tricks, past attempts or shorthand that only the agent
who wrote them knew, so the next agent (or the user) cannot tell what to do. Every card under
board/ is rewritten as board/README.md's "Writing a card" says, keeping what it asks for.

- [ ] each card of `board/1-language` to `board/6-tooling` rewritten: title, a short paragraph
  (what is wrong, why, where), the tasks as `- [ ]` bullets each with its file and how to see it
  worked; ticked items, `needs`, `size`, `priority`, `blocked`, `branch` and `by` kept as they are
- [ ] the same for `board/10-recomp` to `board/16-paused` (this card and zaplink-12 left as they
  are)
- [ ] a card whose aim is unclear even after reading its code gets `blocked:` saying what to ask
  the user, rather than a guess
- [ ] `build/zaplink.exe board check` passes
