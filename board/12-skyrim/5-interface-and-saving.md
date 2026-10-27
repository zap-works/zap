---
size: XL
---
# Skyrim's menus, interface sounds and saves match the game's (milestone 9)

The interface code is `projects/skyrim/interface`, its tests `interfaceTests.zap`, `saveTests.zap`
and `uiSoundTests.zap`; the menus are compared with captures of the game's menus. The executable's
addresses below are in the export at `C:/tools/skyrim-decomp` (`projects/recomp/tools/decompInfo.zap`
prints a function).

- [ ] the scene is blurred under menus: measure the blur's radius in a capture of a menu over the
  scene (the menu captures hold the menus alone, so capture one over the scene) and use it
- [ ] interface sounds that nothing asks for yet, because the menu or game they belong to is not
  modelled: lockpicking (`UILockpicking*`), the stats menu's constellation (`UISkillsFocus`,
  `Forward`, `Backward`, `Stop`, `Glow`, `PerkSelect2D`), crafting (`UISmithing*`, `UIAlchemy*`,
  `UIEnchanting*`), `UISelectOn` and `Off`, `UIShoutLearn*`, `UISpellLearned` (a spell tome
  learned), `UIQuest*` and the discovery music, `UISneakAttack`, `ITMPoisonUse` and
  `ITMTorchHeldEquip`; play each at its event and test it in `uiSoundTests.zap`
- [ ] the lockpicking menu and its sounds (`UILockpicking*`, executable 0x14094f000..0x1409502f0),
  which no lock of the inn opens, and the container's own unlock notice
  (`TESObjectCONT::Activate`, 0x140281c10)
- [ ] the book menu: the game lays the pages on its animated book model (render targets on
  `Book01.nif`, the open and turn animations); do the same
- [ ] the journal's help list: the game's own subset and order are not read from anywhere, so the
  list is a guess; find them in the executable or the interface files and use them
- [ ] the journal's system page: its settings values (the executable's compiled defaults are not
  readable) and its controls list (`RequestInputMappings`, from `controlmap.txt`)
- [ ] text taller than its field is clipped (`scroll` and `maxscroll` are fixed): scroll it; and
  add Scaleform's edge anti-aliasing of shapes and glyphs, glows and blurs of placed objects, and
  `MovieClip.createTextField` to `engine/swf`
- [ ] the dialogue's topics show smaller glyphs in the game than the 24 pixels their field gives at
  the list's 0.8, for a reason not found yet; find it and match the capture
- [ ] the `InventoryMenu`'s list filling (0x1409452b0, 0x1409451e0, 0x140945050, 0x140945e20) and
  the item card's 0x1409472c0 (5,167 bytes): read which fields each item kind sets (`infoValue`,
  `effects`, `potionType` and others). The field names and the entry's six members are known; the
  per-kind logic is not. `interface/itemMenu.zap` already matches the captures, which is why this
  waited; it is done when its logic follows the executable's and the captures still match
- [ ] the HUD's `ProcessMessage` (0x140933180) is read only for its Invoke names and message kinds;
  read the rest of it
- [ ] saves do not carry the sounds playing; save and restore them (`save/`, `saveTests.zap`)
