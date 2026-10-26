---
size: M
priority: P1
branch: language-5
by: 698f72d1-962c-4d7d-9f72-e4e46c468f15
---
# Skyrim's `Item` as an enum with payloads

(zap-6b): its `kind` and about 8 kind-specific
fields become variants; the conversion is mechanical (`item.weapon` is `item.kind.Weapon`).
