---
size: XL
---
# The interface and saving (milestone 9)

- [ ] The scene blurred under menus: its radius is unmeasured, the menu captures hold the menus alone.
- [ ] The interface sounds that are not asked, for the menu or game they belong to is not modelled: the
  lockpicking menu (UILockpicking*), the stats menu's constellation (UISkillsFocus, Forward,
  Backward, Stop, Glow, PerkSelect2D), crafting (UISmithing*, UIAlchemy*, UIEnchanting*), UISelectOn
  and Off, UIShoutLearn*, UISpellLearned (a spell tome learned), UIQuest* and the discovery music,
  UISneakAttack, ITMPoisonUse, ITMTorchHeldEquip.
- [ ] The lockpicking menu and its sounds (UILockpicking*, 0x14094f000..0x1409502f0), which no lock of
  the inn opens, and the container's own unlock notice (TESObjectCONT::Activate 0x140281c10).
- [ ] The book menu: the game lays the pages on its animated book model (render targets on Book01.nif,
  the open and turn animations).
- [ ] The journal's help list: the game's own subset and order are not read from anywhere, so the list
  is a guess.
- [ ] The journal's system page: its settings values (the executable's compiled defaults are not
  readable) and its controls list (RequestInputMappings, from controlmap.txt).
- [ ] The scroll of a text taller than its field (it is clipped; `scroll` and `maxscroll` are fixed),
  Scaleform's edge anti-aliasing of shapes and glyphs, glows and blurs of placed objects,
  MovieClip.createTextField.
- [ ] The dialogue's topics show smaller glyphs in the game than the 24 pixels their field gives at the
  list's 0.8, for a reason not found yet.
- [ ] The InventoryMenu's list filling (0x1409452b0, 0x1409451e0, 0x140945050, 0x140945e20) and the item
  card's 0x1409472c0 (5,167 bytes): which fields each item kind sets (`infoValue`, `effects`,
  `potionType`...). The field names and the entry's six members are known; the per-kind logic is
  not. `itemMenu.zap` already matches the captures, which is why it waited.
- [ ] The HUD's `ProcessMessage` (0x140933180), read only for its Invoke names and message kinds.
- [ ] Saves do not carry the sounds playing.
