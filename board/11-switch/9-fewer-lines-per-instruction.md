---
size: L
priority: P0
---
# Fewer lines per guest instruction

Fewer lines per guest instruction (1.8 now): a compare fused with its branch where the flags
are dead; direct calls between parts in place of a search by address.
