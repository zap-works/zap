---
size: M
priority: P1
branch: language-5
by: aa93b0ad-db23-444a-885a-61929d1c58d3
---
# Skyrim's `Item` as an enum with payloads

(zap-6b): its `kind` and about 8 kind-specific
fields become variants; the conversion is mechanical (`item.weapon` is `item.kind.Weapon`).
