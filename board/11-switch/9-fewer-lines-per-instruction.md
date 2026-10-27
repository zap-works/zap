---
size: L
priority: P0
branch: switch-9
by: 13167c61-39f8-4f4f-b338-1b27cc284038
---
# Fewer lines per guest instruction

Fewer lines per guest instruction (1.8 now): a compare fused with its branch where the flags
are dead; direct calls between parts in place of a search by address.
