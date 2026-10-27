---
size: L
blocked: set aside: needs the decomp's symbol map, which comes only from building pokefirered with agbcc
priority: P3
---
# FireRed: the assets are split into graphics, maps, text, music and tables

The FireRed port (`projects/firered`) uses the ROM as one blob. Splitting it into kinds of assets
(graphics, maps, text, music, tables) needs the symbol map of the pokefirered decompilation, which
only comes from building pokefirered with agbcc (the decomp's old C compiler).

- [ ] build pokefirered with agbcc (outside the repository) and keep its symbol map as input
- [ ] split the player's ROM at the map's symbols into those kinds (`projects/firered/prepare.zap`),
  never committing any of it; a tool lists each kind's files and sizes, and the game still runs from
  them with the same frame hashes
