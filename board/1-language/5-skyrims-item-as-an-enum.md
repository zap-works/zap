---
size: M
---
# Skyrim's `Item` as an enum with payloads

(zap-6b): its `kind` and about 8 kind-specific
fields become variants; the conversion is mechanical (`item.weapon` is `item.kind.Weapon`).
